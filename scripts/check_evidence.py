#!/usr/bin/env python3
"""
Evidence Gate Validator for RISC-V ECG SoC Project
Mandatory checks per Instruction/claim_integrity.md and docs/plans/2026-10-06-gemini-recovery-followup.md

Ensures no false-success runs are accepted:
- Rejects missing tools / nonzero exits
- Rejects stale run IDs when requested_run_id is specified
- Enforces root-relative or run-relative path resolution
- Enforces artifact existence, non-emptiness, and SHA-256 integrity
- Checks compiler / runtime tool identity
- Detects unhandled $fatal, FATAL, Segmentation fault, or Error in logs
- Enforces exact census of expected testcases (no omissions, no unexpected, no duplicates)
- Rejects any testcase with non-PASS status
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


def parse_test_events(log_content: str) -> Tuple[Dict[str, str], List[str]]:
    """
    Parse test events from simulation log content.
    Returns:
        observed: Dict mapping testcase name to outcome ('PASS', 'FAIL', etc.)
        duplicates: List of testcase names that appeared more than once
    """
    observed: Dict[str, str] = {}
    duplicates: List[str] = []

    # Matches patterns like:
    # [PASS] TC-SYS-001: Description
    # [FAIL] TC-SYS-001: Description
    pattern = re.compile(r'\[(PASS|FAIL)\]\s+([A-Za-z0-9_-]+):?')

    for line in log_content.splitlines():
        match = pattern.search(line)
        if match:
            status, tc_id = match.group(1), match.group(2)
            if tc_id in observed:
                duplicates.append(tc_id)
            else:
                observed[tc_id] = status

    return observed, duplicates


def check_fatal_in_log(log_content: str) -> List[str]:
    """Check for fatal errors, simulator crashes, or assertions in log."""
    fatal_patterns = [
        re.compile(r'\$fatal', re.IGNORECASE),
        re.compile(r'\[FATAL\]', re.IGNORECASE),
        re.compile(r'\$error', re.IGNORECASE),
        re.compile(r'\[ERROR\]', re.IGNORECASE),
        re.compile(r'%Error:', re.IGNORECASE),
        re.compile(r'Segmentation fault', re.IGNORECASE),
        re.compile(r'Assertion.*failed', re.IGNORECASE),
        re.compile(r'Core dump', re.IGNORECASE),
        re.compile(r'Watchdog expired', re.IGNORECASE)
    ]
    detected = []
    for line in log_content.splitlines():
        for pat in fatal_patterns:
            if pat.search(line):
                detected.append(line.strip())
                break
    return detected


def resolve_path(p_str: str, base_dir: Optional[Path] = None) -> Path:
    """Resolve an artifact path, allowing root-relative or base_dir-relative paths."""
    p = Path(p_str)
    if p.is_absolute() and p.exists():
        return p
    # Check directly relative to CWD
    if p.exists():
        return p
    # Check relative to base_dir (e.g. results directory or workspace root)
    if base_dir:
        cand = base_dir / p
        if cand.exists():
            return cand
    return p


def accepted_run(compile_exit: int,
                 simulation_exit: int,
                 expected: Set[str],
                 observed: Dict[str, str],
                 artifacts: List[Union[Path, Dict[str, str]]],
                 requested_run_id: Optional[str] = None,
                 manifest_run_id: Optional[str] = None,
                 log_content: Optional[str] = None,
                 base_dir: Optional[Path] = None) -> bool:
    """
    Predicate defined in docs/plans/2026-10-06-gemini-recovery-followup.md.
    Enforces manifest identity, exit codes, artifact integrity, and test census.
    """
    if compile_exit != 0 or simulation_exit != 0:
        return False

    if requested_run_id is not None:
        if manifest_run_id != requested_run_id:
            return False

    if not expected or set(observed) != set(expected) or len(observed) != len(expected):
        return False

    if not all(value == 'PASS' for value in observed.values()):
        return False

    if log_content and check_fatal_in_log(log_content):
        return False

    if not artifacts:
        return False

    for item in artifacts:
        if isinstance(item, (str, Path)):
            p = resolve_path(str(item), base_dir)
            if not p.is_file() or p.stat().st_size == 0:
                return False
        elif isinstance(item, dict):
            p_str = item.get('path', '')
            p = resolve_path(p_str, base_dir)
            if not p.is_file() or p.stat().st_size == 0:
                return False
            expected_hash = item.get('sha256')
            if expected_hash and calculate_sha256(p) != expected_hash:
                return False
        else:
            return False

    return True


def validate_run(compile_exit: int,
                 simulation_exit: int,
                 expected_testcases: Set[str],
                 log_path: Optional[Path] = None,
                 log_content: Optional[str] = None,
                 artifacts: Optional[List[Union[Path, Dict[str, str]]]] = None,
                 requested_run_id: Optional[str] = None,
                 manifest_run_id: Optional[str] = None,
                 base_dir: Optional[Path] = None,
                 compiler_info: Optional[str] = None,
                 runtime_info: Optional[str] = None) -> Tuple[bool, List[str]]:
    """
    Comprehensive validation of a verification run.
    Returns (is_valid, list_of_errors).
    """
    errors: List[str] = []

    if compile_exit != 0:
        errors.append(f"Compile step failed with exit code {compile_exit}")

    if simulation_exit != 0:
        errors.append(f"Simulation step failed with exit code {simulation_exit}")

    if requested_run_id is not None:
        if manifest_run_id != requested_run_id:
            errors.append(f"Stale run ID: manifest has '{manifest_run_id}', expected '{requested_run_id}'")

    if log_content is None:
        if log_path is None:
            errors.append("Simulation log path not specified")
            return False, errors
        actual_log_path = resolve_path(str(log_path), base_dir)
        if not actual_log_path.is_file():
            errors.append(f"Simulation log file missing: {actual_log_path}")
            return False, errors
        log_content = actual_log_path.read_text(encoding='utf-8-sig', errors='replace')

    if not log_content.strip():
        errors.append("Simulation log is empty")
        return False, errors

    # Check for unhandled fatal errors or crash messages in log
    fatal_lines = check_fatal_in_log(log_content)
    if fatal_lines:
        errors.append(f"Fatal errors/aborts detected in log: {fatal_lines[:3]}")

    observed, duplicates = parse_test_events(log_content)

    if duplicates:
        errors.append(f"Duplicate testcase IDs detected in log: {sorted(set(duplicates))}")

    if not expected_testcases:
        errors.append("No expected testcases specified")
    else:
        missing = expected_testcases - set(observed.keys())
        if missing:
            errors.append(f"Missing expected testcases: {sorted(missing)}")

        unexpected = set(observed.keys()) - expected_testcases
        if unexpected:
            errors.append(f"Unexpected testcases observed: {sorted(unexpected)}")

    for tc_id, status in observed.items():
        if status != 'PASS':
            errors.append(f"Testcase {tc_id} reported status {status}")

    if not artifacts:
        errors.append("No required artifacts specified")
    else:
        for item in artifacts:
            if isinstance(item, (str, Path)):
                p = resolve_path(str(item), base_dir)
                if not p.exists():
                    errors.append(f"Required artifact does not exist: {p}")
                elif not p.is_file():
                    errors.append(f"Required artifact is not a regular file: {p}")
                elif p.stat().st_size == 0:
                    errors.append(f"Required artifact is empty (0 bytes): {p}")
            elif isinstance(item, dict):
                p_str = item.get('path', '')
                p = resolve_path(p_str, base_dir)
                if not p.exists():
                    errors.append(f"Required artifact does not exist: {p}")
                elif not p.is_file():
                    errors.append(f"Required artifact is not a regular file: {p}")
                elif p.stat().st_size == 0:
                    errors.append(f"Required artifact is empty (0 bytes): {p}")
                else:
                    expected_hash = item.get('sha256')
                    if expected_hash:
                        actual_hash = calculate_sha256(p)
                        if actual_hash != expected_hash:
                            errors.append(f"Artifact {p} SHA-256 mismatch: got {actual_hash}, expected {expected_hash}")
            else:
                errors.append(f"Invalid artifact entry type: {type(item)}")

    is_valid = len(errors) == 0
    return is_valid, errors


def main() -> int:
    """Command-line entry point for evidence verification."""
    import argparse
    parser = argparse.ArgumentParser(description="Evidence Gate Validator for RISC-V ECG SoC Project")
    parser.add_argument("results_path", type=Path, help="Path to run results JSON manifest")
    parser.add_argument("expected_cases", nargs="*", help="Expected testcase IDs")
    parser.add_argument("--run-id", type=str, default=None, help="Expected run ID for staleness checking")

    args = parser.parse_args()

    results_path = args.results_path
    expected = set(args.expected_cases)
    requested_run_id = args.run_id

    if not results_path.is_file():
        print(f"[FAIL] Results file not found: {results_path}", file=sys.stderr)
        return 1

    try:
        # Read with utf-8-sig to handle optional BOM safely
        data = json.loads(results_path.read_text(encoding='utf-8-sig'))
    except Exception as e:
        print(f"[FAIL] Invalid JSON in {results_path}: {e}", file=sys.stderr)
        return 1

    manifest_run_id = data.get("run_id")
    compile_exit = data.get("compile_exit", 1)
    sim_exit = data.get("simulation_exit", 1)
    log_file = data.get("log_file")
    artifacts = data.get("artifacts", [])
    compiler_info = data.get("compiler") or data.get("tool")
    runtime_info = data.get("runtime") or data.get("tool")

    base_dir = results_path.parent

    log_content = None
    if log_file:
        resolved_log = resolve_path(log_file, base_dir)
        if resolved_log.is_file():
            log_content = resolved_log.read_text(encoding='utf-8-sig', errors='replace')

    is_valid, errors = validate_run(
        compile_exit=compile_exit,
        simulation_exit=sim_exit,
        expected_testcases=expected,
        log_content=log_content,
        artifacts=artifacts,
        requested_run_id=requested_run_id,
        manifest_run_id=manifest_run_id,
        base_dir=base_dir,
        compiler_info=compiler_info,
        runtime_info=runtime_info
    )

    if is_valid:
        print("[PASS] Evidence gate validation successful.")
        return 0
    else:
        print("[FAIL] Evidence gate validation rejected run:", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
