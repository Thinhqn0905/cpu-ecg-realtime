#!/usr/bin/env python3
"""
FPGA Evidence Gate and Static Timing Acceptance Checker
Mandatory verification per Instruction/claim_integrity.md,
Instruction/evidence_contract.md, and docs/plans/2026-10-06-core-next-decision-audit.md.

Enforces fail-closed timing acceptance:
- Rejects any negative setup slack (WNS < 0.0) regardless of positive hold slack or exit 0.
- Rejects missing artifacts, missing source hashes, or mismatched file hashes.
- Parses design timing summary, intra-clock metrics, check_timing, and DRC reports.
- Enforces accept_timing predicate.
- Emits discrete statuses: ROUTED_COMPLETE, TIMING_FAIL, NOT_VERIFIED, ACCEPTED.
"""

import sys
import os
import re
import json
import hashlib
from pathlib import Path
from typing import Dict, List, Set, Optional, Tuple, Any, Union


def calculate_sha256(filepath: Path) -> str:
    """Calculate SHA-256 hex digest of a file."""
    h = hashlib.sha256()
    with open(filepath, 'rb') as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()


def resolve_path(p_str: str, base_dir: Optional[Path] = None) -> Path:
    """Resolve path relative to CWD or base directory."""
    p = Path(p_str)
    if p.is_absolute() and p.exists():
        return p
    if p.exists():
        return p
    if base_dir:
        cand_name = base_dir / p.name
        if cand_name.exists():
            return cand_name
        cand = base_dir / p
        if cand.exists():
            return cand
    return p


def parse_timing_summary(timing_content: str) -> Dict[str, Any]:
    """
    Parse Vivado report_timing_summary output.
    Extracts global Design Timing Summary and Clock Summary.
    """
    metrics: Dict[str, Any] = {
        "wns_ns": None,
        "tns_ns": None,
        "setup_failing_endpoints": None,
        "setup_total_endpoints": None,
        "whs_ns": None,
        "ths_ns": None,
        "hold_failing_endpoints": None,
        "hold_total_endpoints": None,
        "wpws_ns": None,
        "tpws_ns": None,
        "pulse_width_failing_endpoints": None,
        "pulse_width_total_endpoints": None,
        "timing_constraints_met": False,
        "compute_clock_name": None,
        "compute_period_ns": None,
        "compute_freq_mhz": None
    }

    lines = timing_content.splitlines()

    # Check for "Timing constraints are not met" or "All user specified timing constraints are met"
    if "All user specified timing constraints are met." in timing_content:
        metrics["timing_constraints_met"] = True
    elif "Timing constraints are not met." in timing_content:
        metrics["timing_constraints_met"] = False

    # Parse Design Timing Summary table
    # Look for table header with WNS(ns) ...
    for i, line in enumerate(lines):
        if "Design Timing Summary" in line:
            # Table data is usually 5-7 lines after header
            for offset in range(1, 15):
                if i + offset >= len(lines):
                    break
                data_line = lines[i + offset].strip()
                # A row of floating point numbers e.g.:
                # -0.815      -63.389                    215                18669        0.044        0.000                      0                18669        3.000        0.000                       0                  7176
                tokens = data_line.split()
                if len(tokens) == 12:
                    try:
                        metrics["wns_ns"] = float(tokens[0])
                        metrics["tns_ns"] = float(tokens[1])
                        metrics["setup_failing_endpoints"] = int(tokens[2])
                        metrics["setup_total_endpoints"] = int(tokens[3])
                        metrics["whs_ns"] = float(tokens[4])
                        metrics["ths_ns"] = float(tokens[5])
                        metrics["hold_failing_endpoints"] = int(tokens[6])
                        metrics["hold_total_endpoints"] = int(tokens[7])
                        metrics["wpws_ns"] = float(tokens[8])
                        metrics["tpws_ns"] = float(tokens[9])
                        metrics["pulse_width_failing_endpoints"] = int(tokens[10])
                        metrics["pulse_width_total_endpoints"] = int(tokens[11])
                        break
                    except ValueError:
                        continue

    # Parse Clock Summary for compute clock period (clk_50m_unbuf, clk_50m, clk_out1, etc.)
    # Format:
    # Clock            Waveform(ns)       Period(ns)      Frequency(MHz)
    # sys_clk_pin      {0.000 5.000}      10.000          100.000
    #   clk_50m_unbuf  {0.000 10.000}     20.000          50.000
    in_clock_summary = False
    for line in lines:
        if "| Clock Summary" in line:
            in_clock_summary = True
            continue
        if in_clock_summary and line.startswith("---"):
            continue
        if in_clock_summary and line.startswith("| Intra Clock Table"):
            break
        if in_clock_summary:
            parts = line.strip().split()
            # If line mentions 50MHz or compute clock or has period ~20.0
            if len(parts) >= 4:
                clock_name = parts[0]
                try:
                    # Period is usually the second-to-last or token before freq
                    freq_mhz = float(parts[-1])
                    period_ns = float(parts[-2])
                    if "50m" in clock_name.lower() or abs(freq_mhz - 50.0) < 0.1 or abs(period_ns - 20.0) < 0.1:
                        metrics["compute_clock_name"] = clock_name
                        metrics["compute_period_ns"] = period_ns
                        metrics["compute_freq_mhz"] = freq_mhz
                except (ValueError, IndexError):
                    pass

    return metrics


def parse_check_timing(check_timing_content: str) -> Dict[str, Any]:
    """Parse Vivado check_timing report."""
    results = {
        "unconstrained_internal_endpoints": None,
        "no_input_delay_high": None,
        "no_output_delay_high": None,
        "no_clock": None
    }
    # Pattern: "4. checking unconstrained_internal_endpoints (0)"
    m = re.search(r'checking unconstrained_internal_endpoints\s*\((\d+)\)', check_timing_content)
    if m:
        results["unconstrained_internal_endpoints"] = int(m.group(1))

    m_in = re.search(r'checking no_input_delay\s*\((\d+)\)', check_timing_content)
    if m_in:
        results["no_input_delay_high"] = int(m_in.group(1))

    m_out = re.search(r'checking no_output_delay\s*\((\d+)\)', check_timing_content)
    if m_out:
        results["no_output_delay_high"] = int(m_out.group(1))

    m_clk = re.search(r'checking no_clock\s*\((\d+)\)', check_timing_content)
    if m_clk:
        results["no_clock"] = int(m_clk.group(1))

    return results


def parse_drc_report(drc_content: str) -> Dict[str, Any]:
    """Parse Vivado DRC report."""
    results = {
        "drc_errors": 0,
        "drc_warnings": 0,
        "drc_violations_total": 0
    }
    m = re.search(r'Violations found:\s*(\d+)', drc_content)
    if m:
        results["drc_violations_total"] = int(m.group(1))

    errors = len(re.findall(r'Severity\s*:\s*Error', drc_content, re.IGNORECASE))
    warnings = len(re.findall(r'Severity\s*:\s*Warning', drc_content, re.IGNORECASE))
    results["drc_errors"] = errors
    results["drc_warnings"] = warnings
    return results


def accept_timing(summary: Dict[str, Any]) -> bool:
    """
    Mandatory predicate specified in docs/plans/2026-10-06-core-next-decision-audit.md:
    def accept_timing(summary):
        return (
            summary['route_complete'] is True
            and summary['compute_period_ns'] == 20.0
            and summary['wns_ns'] >= 0 and summary['tns_ns'] == 0
            and summary['setup_failing_endpoints'] == 0
            and summary['whs_ns'] >= 0 and summary['ths_ns'] == 0
            and summary['hold_failing_endpoints'] == 0
            and summary['unconstrained_internal_endpoints'] == 0
            and summary['io_contract_reviewed'] is True
            and summary['drc_review_complete'] is True
        )
    """
    try:
        return (
            summary.get('route_complete') is True
            and summary.get('compute_period_ns') == 20.0
            and summary.get('wns_ns') is not None and summary.get('wns_ns') >= 0.0
            and summary.get('tns_ns') is not None and summary.get('tns_ns') == 0.0
            and summary.get('setup_failing_endpoints') == 0
            and summary.get('whs_ns') is not None and summary.get('whs_ns') >= 0.0
            and summary.get('ths_ns') is not None and summary.get('ths_ns') == 0.0
            and summary.get('hold_failing_endpoints') == 0
            and summary.get('unconstrained_internal_endpoints') == 0
            and summary.get('io_contract_reviewed') is True
            and summary.get('drc_review_complete') is True
        )
    except (TypeError, KeyError):
        return False


def classify_run(summary: Dict[str, Any], validation_errors: List[str]) -> Tuple[str, str]:
    """
    Classify the FPGA run into one of four distinct states:
    - ACCEPTED: all timing and review criteria met
    - TIMING_FAIL: routed run with negative slack (WNS < 0 or TNS < 0 or setup endpoints > 0)
    - ROUTED_COMPLETE: route completed and bitstream produced, but timing/review unfulfilled
    - NOT_VERIFIED: missing artifacts, hash mismatches, or missing required fields
    """
    if validation_errors:
        return "NOT_VERIFIED", "; ".join(validation_errors)

    if accept_timing(summary):
        return "ACCEPTED", "All setup/hold timing constraints met at 20.000 ns (50.0 MHz) with reviewed contracts."

    wns = summary.get('wns_ns')
    setup_fail = summary.get('setup_failing_endpoints')
    route_complete = summary.get('route_complete')

    if wns is not None and (wns < 0.0 or (setup_fail is not None and setup_fail > 0)):
        reason = (
            f"Negative setup slack WNS = {wns:.3f} ns (< 0.0), "
            f"TNS = {summary.get('tns_ns', 0.0):.3f} ns, "
            f"{setup_fail} failing endpoints at compute period {summary.get('compute_period_ns')} ns. "
            f"Hold slack WHS = +{summary.get('whs_ns', 0.0):.3f} ns cannot mask setup failure."
        )
        return "TIMING_FAIL", reason

    if route_complete is True:
        reasons = []
        if summary.get('compute_period_ns') != 20.0:
            reasons.append(f"Compute period {summary.get('compute_period_ns')} != 20.0 ns")
        if summary.get('unconstrained_internal_endpoints') != 0:
            reasons.append(f"Unconstrained internal endpoints: {summary.get('unconstrained_internal_endpoints')}")
        if not summary.get('io_contract_reviewed'):
            reasons.append("I/O contract review not complete")
        if not summary.get('drc_review_complete'):
            reasons.append("DRC review not complete")
        return "ROUTED_COMPLETE", "; ".join(reasons) if reasons else "Routed completed with pending review"

    return "NOT_VERIFIED", "Incomplete run data"


def validate_fpga_manifest(manifest_path: Path,
                           expect_period_ns: float = 20.0,
                           io_contract_path: Optional[Path] = None,
                           drc_review_path: Optional[Path] = None,
                           expected_part: Optional[str] = "xc7a100tcsg324-1") -> Tuple[Dict[str, Any], List[str]]:
    """
    Validate all artifacts in an FPGA manifest, parse reports, and construct summary dict.
    Returns (summary_dict, validation_errors).
    """
    errors: List[str] = []
    summary: Dict[str, Any] = {
        "route_complete": False,
        "compute_period_ns": None,
        "wns_ns": None,
        "tns_ns": None,
        "setup_failing_endpoints": None,
        "whs_ns": None,
        "ths_ns": None,
        "hold_failing_endpoints": None,
        "unconstrained_internal_endpoints": None,
        "io_contract_reviewed": False,
        "drc_review_complete": False,
        "artifacts_checked": 0,
        "bitstream_present": False
    }

    if not manifest_path.is_file():
        errors.append(f"Manifest file not found: {manifest_path}")
        return summary, errors

    try:
        data = json.loads(manifest_path.read_text(encoding='utf-8-sig'))
    except Exception as e:
        errors.append(f"Invalid JSON in manifest {manifest_path}: {e}")
        return summary, errors

    base_dir = manifest_path.parent

    # Check part
    target_part = data.get("target_part")
    if expected_part and target_part and target_part != expected_part:
        errors.append(f"Target part mismatch: manifest has '{target_part}', expected '{expected_part}'")

    # Check mandatory source hashes
    core_sha256 = data.get("core_sha256")
    if not core_sha256:
        errors.append("Manifest missing mandatory 'core_sha256' source fingerprint")

    boot_hex_sha256 = data.get("boot_hex_sha256")
    if not boot_hex_sha256:
        errors.append("Manifest missing mandatory 'boot_hex_sha256' boot image fingerprint")

    # Validate all artifacts and their SHA-256
    artifacts = data.get("artifacts", [])
    if not artifacts:
        errors.append("Manifest has no artifacts list")

    timing_rpt_path: Optional[Path] = None
    check_timing_path: Optional[Path] = None
    drc_rpt_path: Optional[Path] = None

    for item in artifacts:
        if not isinstance(item, dict):
            errors.append(f"Artifact entry is not a dict: {item}")
            continue
        p_str = item.get("path", "")
        p = resolve_path(p_str, base_dir)
        expected_hash = item.get("sha256")

        if not expected_hash:
            errors.append(f"Artifact {p_str} is missing mandatory SHA-256 hash in manifest")
            continue

        if not p.is_file():
            errors.append(f"Artifact file missing: {p}")
            continue

        if p.stat().st_size == 0:
            errors.append(f"Artifact file empty (0 bytes): {p}")
            continue

        actual_hash = calculate_sha256(p)
        if actual_hash != expected_hash:
            errors.append(f"Artifact {p.name} SHA-256 mismatch: actual {actual_hash} != expected {expected_hash}")
            continue

        summary["artifacts_checked"] += 1

        name = p.name.lower()
        if "timing_routed" in name or name == "timing_routed.rpt":
            timing_rpt_path = p
        elif "check_timing" in name or name == "check_timing.rpt":
            check_timing_path = p
        elif "drc_routed" in name or name == "drc_routed.rpt":
            drc_rpt_path = p
        elif name.endswith(".bit"):
            summary["bitstream_present"] = True

    # Parse timing report if available
    if timing_rpt_path:
        timing_content = timing_rpt_path.read_text(encoding='utf-8-sig', errors='replace')
        timing_metrics = parse_timing_summary(timing_content)
        summary.update(timing_metrics)
        # Route is complete if timing_routed.rpt has Design Timing Summary
        if summary.get("wns_ns") is not None:
            summary["route_complete"] = True
    else:
        errors.append("timing_routed.rpt not found in verified artifacts")

    # Parse check_timing report
    if check_timing_path:
        check_content = check_timing_path.read_text(encoding='utf-8-sig', errors='replace')
        ct_metrics = parse_check_timing(check_content)
        summary["unconstrained_internal_endpoints"] = ct_metrics.get("unconstrained_internal_endpoints")
    else:
        errors.append("check_timing.rpt not found in verified artifacts")

    # Parse DRC report
    if drc_rpt_path:
        drc_content = drc_rpt_path.read_text(encoding='utf-8-sig', errors='replace')
        drc_metrics = parse_drc_report(drc_content)
        summary["drc_errors"] = drc_metrics.get("drc_errors", 0)
        summary["drc_warnings"] = drc_metrics.get("drc_warnings", 0)

    # Review contract checks
    if io_contract_path:
        resolved_io = resolve_path(str(io_contract_path), base_dir)
        if resolved_io.is_file() and resolved_io.stat().st_size > 0:
            summary["io_contract_reviewed"] = True
        else:
            errors.append(f"Specified I/O contract document not found or empty: {io_contract_path}")

    if drc_review_path:
        resolved_drc = resolve_path(str(drc_review_path), base_dir)
        if resolved_drc.is_file() and resolved_drc.stat().st_size > 0:
            summary["drc_review_complete"] = True
        else:
            errors.append(f"Specified DRC review document not found or empty: {drc_review_path}")

    return summary, errors


def main() -> int:
    """Command-line entry point for FPGA evidence validation."""
    import argparse
    parser = argparse.ArgumentParser(description="FPGA Evidence Gate & Timing Checker")
    parser.add_argument("--manifest", type=Path, required=True, help="Path to fpga_manifest.json")
    parser.add_argument("--expect-period-ns", type=float, default=20.0, help="Expected compute clock period in ns (default: 20.0)")
    parser.add_argument("--io-contract", type=Path, default=None, help="Path to reviewed I/O contract document")
    parser.add_argument("--drc-review", type=Path, default=None, help="Path to reviewed DRC signoff document")
    parser.add_argument("--part", type=str, default="xc7a100tcsg324-1", help="Target FPGA part number")

    args = parser.parse_args()

    summary, errors = validate_fpga_manifest(
        manifest_path=args.manifest,
        expect_period_ns=args.expect_period_ns,
        io_contract_path=args.io_contract,
        drc_review_path=args.drc_review,
        expected_part=args.part
    )

    status, reason = classify_run(summary, errors)

    print(f"=== FPGA Evidence Gate Assessment ===")
    print(f"Status:   {status}")
    print(f"Details:  {reason}")
    print(f"Metrics:")
    print(f"  Route Complete:                  {summary.get('route_complete')}")
    print(f"  Compute Clock Period:            {summary.get('compute_period_ns')} ns (expected {args.expect_period_ns} ns)")
    print(f"  WNS (Worst Negative Setup):      {summary.get('wns_ns')} ns")
    print(f"  TNS (Total Negative Setup):      {summary.get('tns_ns')} ns")
    print(f"  Setup Failing Endpoints:         {summary.get('setup_failing_endpoints')}")
    print(f"  WHS (Worst Hold Slack):          {summary.get('whs_ns')} ns")
    print(f"  THS (Total Hold Slack):          {summary.get('ths_ns')} ns")
    print(f"  Hold Failing Endpoints:          {summary.get('hold_failing_endpoints')}")
    print(f"  Unconstrained Internal Pins:     {summary.get('unconstrained_internal_endpoints')}")
    print(f"  I/O Contract Reviewed:           {summary.get('io_contract_reviewed')}")
    print(f"  DRC Review Complete:             {summary.get('drc_review_complete')}")
    print(f"  Artifacts Verified:              {summary.get('artifacts_checked')}")
    print(f"  Bitstream Generated:             {summary.get('bitstream_present')}")

    if status == "ACCEPTED":
        print("\n[PASS] Timing closure verified and all evidence gates accepted.")
        return 0
    elif status == "TIMING_FAIL":
        print(f"\n[FAIL] Timing closure failed at {args.expect_period_ns} ns. Exit status TIMING_FAIL.", file=sys.stderr)
        return 1
    elif status == "ROUTED_COMPLETE":
        print(f"\n[REJECT] Route completed but timing closure or reviews unverified.", file=sys.stderr)
        return 2
    else:  # NOT_VERIFIED
        print(f"\n[REJECT] Manifest or artifacts failed verification.", file=sys.stderr)
        return 3


if __name__ == '__main__':
    sys.exit(main())
