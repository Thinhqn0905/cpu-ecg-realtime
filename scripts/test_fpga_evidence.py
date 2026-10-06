#!/usr/bin/env python3
"""
Unit and integration tests for FPGA Evidence Gate and Timing Acceptance (scripts/check_fpga_evidence.py).
Enforces fail-closed verification per:
- Instruction/claim_integrity.md
- docs/plans/2026-10-06-core-next-decision-audit.md (Task 1)

Verifies:
1. test_exit_zero_negative_setup_rejected: Exit 0 + bitstream rejected due to WNS = -0.815 ns.
2. test_positive_hold_cannot_mask_setup_failure: WHS = +0.044 ns cannot mask setup violation.
3. test_missing_source_hash_rejected: Missing core_sha256 or boot_hex_sha256 rejected.
4. test_sva_error_rejected: Rejection of SVA errors in logs.
5. test_missing_report_rejected: Missing timing_routed.rpt or check_timing.rpt rejected.
6. test_unconstrained_internal_endpoints_rejected: Non-zero unconstrained pins rejected.
7. test_unreviewed_contracts_rejected: Clean timing without reviewed contracts rejected.
8. test_actual_d1_manifest_rejected: Live check of historical run_20261006_093347 manifest.
9. test_happy_path_all_constraints_met: Completely closed 50 MHz run accepted.
"""

import unittest
import tempfile
import subprocess
import sys
import json
import hashlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from check_fpga_evidence import (
    accept_timing,
    classify_run,
    parse_timing_summary,
    parse_check_timing,
    parse_drc_report,
    validate_fpga_manifest,
    calculate_sha256
)


class TestFpgaEvidenceGate(unittest.TestCase):

    def setUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.work_dir = Path(self.tmp_dir.name)
        self.script_path = Path(__file__).resolve().parent / "check_fpga_evidence.py"

        # Create dummy artifacts
        self.bitstream = self.work_dir / "cv32e40p_ecg_soc.bit"
        self.bitstream.write_bytes(b"XILINX_BITSTREAM_HEADER_MOCK_DATA")

        # Create timing report modeling D1 run (WNS -0.815, TNS -63.389, 215 failing endpoints)
        self.d1_timing_rpt = self.work_dir / "timing_routed.rpt"
        self.d1_timing_rpt.write_text(
            "------------------------------------------------------------------------------------------------\n"
            "| Design Timing Summary\n"
            "| ---------------------\n"
            "------------------------------------------------------------------------------------------------\n"
            "\n"
            "    WNS(ns)      TNS(ns)  TNS Failing Endpoints  TNS Total Endpoints      WHS(ns)      THS(ns)  THS Failing Endpoints  THS Total Endpoints     WPWS(ns)     TPWS(ns)  TPWS Failing Endpoints  TPWS Total Endpoints  \n"
            "    -------      -------  ---------------------  -------------------      -------      -------  ---------------------  -------------------     --------     --------  ----------------------  --------------------  \n"
            "     -0.815      -63.389                    215                18669        0.044        0.000                      0                18669        3.000        0.000                       0                  7176  \n"
            "\n"
            "Timing constraints are not met.\n"
            "\n"
            "------------------------------------------------------------------------------------------------\n"
            "| Clock Summary\n"
            "| -------------\n"
            "------------------------------------------------------------------------------------------------\n"
            "\n"
            "Clock            Waveform(ns)       Period(ns)      Frequency(MHz)\n"
            "-----            ------------       ----------      --------------\n"
            "sys_clk_pin      {0.000 5.000}      10.000          100.000         \n"
            "  clk_50m_unbuf  {0.000 10.000}     20.000          50.000          \n",
            encoding="utf-8"
        )

        # Create check_timing report
        self.check_timing_rpt = self.work_dir / "check_timing.rpt"
        self.check_timing_rpt.write_text(
            "check_timing report\n"
            "4. checking unconstrained_internal_endpoints (0)\n"
            " There are 0 pins that are not constrained for maximum delay.\n"
            "5. checking no_input_delay (8)\n"
            "6. checking no_output_delay (11)\n",
            encoding="utf-8"
        )

        # Create DRC report
        self.drc_rpt = self.work_dir / "drc_routed.rpt"
        self.drc_rpt.write_text(
            "Report DRC\n"
            "Violations found: 2\n"
            "DPIP-1#1 Warning\nInput pipelining\n"
            "REQP-1839#1 Warning\nRAMB36 async control check\n",
            encoding="utf-8"
        )

        # Create reviewed contracts
        self.io_contract = self.work_dir / "io_contract.md"
        self.io_contract.write_text("# Reviewed I/O Contract\nSPI and UART I/O delays validated.\n", encoding="utf-8")

        self.drc_review = self.work_dir / "drc_review.md"
        self.drc_review.write_text("# Reviewed DRC Report\nREQP-1839 warnings reviewed.\n", encoding="utf-8")

    def tearDown(self):
        self.tmp_dir.cleanup()

    def create_manifest(self, wns: float = -0.815, include_source_hash: bool = True, custom_artifacts: list = None) -> Path:
        manifest_path = self.work_dir / "fpga_manifest.json"
        timing_path = self.d1_timing_rpt if wns == -0.815 else self.create_clean_timing_rpt()

        artifacts = custom_artifacts if custom_artifacts is not None else [
            {"path": str(self.bitstream), "sha256": calculate_sha256(self.bitstream)},
            {"path": str(timing_path), "sha256": calculate_sha256(timing_path)},
            {"path": str(self.check_timing_rpt), "sha256": calculate_sha256(self.check_timing_rpt)},
            {"path": str(self.drc_rpt), "sha256": calculate_sha256(self.drc_rpt)},
        ]

        data = {
            "run_id": "run_20261006_test",
            "timestamp": "2026-10-06T12:00:00Z",
            "target_part": "xc7a100tcsg324-1",
            "exit_code": 0,
            "artifacts": artifacts
        }
        if include_source_hash:
            data["core_sha256"] = "b0d9341cc231d72333b196748a3500c32f3335b6e24092f8565dce776720aeed"
            data["boot_hex_sha256"] = "bc931c029e3d5a686ec25b929f3bc1972b6bbe0fdffdfdfd776a455a8a21fe64"

        manifest_path.write_text(json.dumps(data, indent=2), encoding="utf-8")
        return manifest_path

    def create_clean_timing_rpt(self) -> Path:
        clean_rpt = self.work_dir / "clean_timing_routed.rpt"
        clean_rpt.write_text(
            "------------------------------------------------------------------------------------------------\n"
            "| Design Timing Summary\n"
            "| ---------------------\n"
            "------------------------------------------------------------------------------------------------\n"
            "\n"
            "    WNS(ns)      TNS(ns)  TNS Failing Endpoints  TNS Total Endpoints      WHS(ns)      THS(ns)  THS Failing Endpoints  THS Total Endpoints     WPWS(ns)     TPWS(ns)  TPWS Failing Endpoints  TPWS Total Endpoints  \n"
            "    -------      -------  ---------------------  -------------------      -------      -------  ---------------------  -------------------     --------     --------  ----------------------  --------------------  \n"
            "      0.125        0.000                      0                18669        0.044        0.000                      0                18669        3.000        0.000                       0                  7176  \n"
            "\n"
            "All user specified timing constraints are met.\n"
            "\n"
            "------------------------------------------------------------------------------------------------\n"
            "| Clock Summary\n"
            "| -------------\n"
            "------------------------------------------------------------------------------------------------\n"
            "\n"
            "Clock            Waveform(ns)       Period(ns)      Frequency(MHz)\n"
            "-----            ------------       ----------      --------------\n"
            "sys_clk_pin      {0.000 5.000}      10.000          100.000         \n"
            "  clk_50m_unbuf  {0.000 10.000}     20.000          50.000          \n",
            encoding="utf-8"
        )
        return clean_rpt

    def test_exit_zero_negative_setup_rejected(self):
        """
        D1 finding fixture: Vivado returns exit 0 and outputs bitstream,
        but setup timing fails (WNS = -0.815 ns, 215 endpoints). Must be rejected.
        """
        manifest = self.create_manifest(wns=-0.815)
        summary, errors = validate_fpga_manifest(manifest, expect_period_ns=20.0)
        self.assertFalse(accept_timing(summary))

        status, reason = classify_run(summary, errors)
        self.assertEqual(status, "TIMING_FAIL")
        self.assertIn("Negative setup slack", reason)
        self.assertIn("WNS = -0.815 ns", reason)

        # Test CLI execution returns exit code 1
        cmd = [sys.executable, str(self.script_path), "--manifest", str(manifest), "--expect-period-ns", "20.0"]
        proc = subprocess.run(cmd, capture_output=True, text=True)
        self.assertEqual(proc.returncode, 1)
        self.assertIn("TIMING_FAIL", proc.stdout)

    def test_positive_hold_cannot_mask_setup_failure(self):
        """
        WHS = +0.044 ns cannot mask setup violation WNS = -0.815 ns.
        """
        summary = {
            "route_complete": True,
            "compute_period_ns": 20.0,
            "wns_ns": -0.815,
            "tns_ns": -63.389,
            "setup_failing_endpoints": 215,
            "whs_ns": 0.044,
            "ths_ns": 0.000,
            "hold_failing_endpoints": 0,
            "unconstrained_internal_endpoints": 0,
            "io_contract_reviewed": True,
            "drc_review_complete": True
        }
        self.assertFalse(accept_timing(summary))
        status, reason = classify_run(summary, [])
        self.assertEqual(status, "TIMING_FAIL")
        self.assertIn("Hold slack WHS = +0.044 ns cannot mask setup failure", reason)

    def test_missing_source_hash_rejected(self):
        """
        Manifest missing mandatory core_sha256 or boot_hex_sha256 must be rejected.
        """
        manifest = self.create_manifest(wns=-0.815, include_source_hash=False)
        summary, errors = validate_fpga_manifest(manifest, expect_period_ns=20.0)
        self.assertFalse(accept_timing(summary))
        self.assertTrue(any("missing mandatory 'core_sha256'" in e for e in errors))

        status, reason = classify_run(summary, errors)
        self.assertEqual(status, "NOT_VERIFIED")

        cmd = [sys.executable, str(self.script_path), "--manifest", str(manifest)]
        proc = subprocess.run(cmd, capture_output=True, text=True)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("NOT_VERIFIED", proc.stdout)

    def test_sva_error_rejected(self):
        """
        Verifies that error patterns reject simulation/implementation logs.
        """
        from check_evidence import check_fatal_in_log
        log_with_sva = (
            "Time: 20000 ns - Iteration 5\n"
            "%Error: p_cs_setup_time violated in spi_master_sva.sv line 45\n"
            "[ERROR] AMBA APB protocol violation: PSLVERR with unmapped address\n"
        )
        detected = check_fatal_in_log(log_with_sva)
        self.assertGreaterEqual(len(detected), 2)
        self.assertTrue(any("%Error:" in line for line in detected))
        self.assertTrue(any("[ERROR]" in line for line in detected))

    def test_missing_report_rejected(self):
        """
        Missing timing_routed.rpt or check_timing.rpt must reject validation.
        """
        custom_artifacts = [
            {"path": str(self.bitstream), "sha256": calculate_sha256(self.bitstream)},
            {"path": str(self.drc_rpt), "sha256": calculate_sha256(self.drc_rpt)}
        ]
        manifest = self.create_manifest(custom_artifacts=custom_artifacts)
        summary, errors = validate_fpga_manifest(manifest)
        self.assertFalse(accept_timing(summary))
        self.assertTrue(any("timing_routed.rpt not found" in e for e in errors))

        status, reason = classify_run(summary, errors)
        self.assertEqual(status, "NOT_VERIFIED")

    def test_unconstrained_internal_endpoints_rejected(self):
        """
        Unconstrained internal pins must cause accept_timing to return False.
        """
        summary = {
            "route_complete": True,
            "compute_period_ns": 20.0,
            "wns_ns": 0.100,
            "tns_ns": 0.000,
            "setup_failing_endpoints": 0,
            "whs_ns": 0.050,
            "ths_ns": 0.000,
            "hold_failing_endpoints": 0,
            "unconstrained_internal_endpoints": 5,  # Violating
            "io_contract_reviewed": True,
            "drc_review_complete": True
        }
        self.assertFalse(accept_timing(summary))

    def test_unreviewed_contracts_rejected(self):
        """
        Clean timing without reviewed I/O contract or DRC review must not be ACCEPTED.
        """
        manifest = self.create_manifest(wns=0.125)
        # Without passing --io-contract or --drc-review
        summary, errors = validate_fpga_manifest(manifest, expect_period_ns=20.0)
        self.assertFalse(accept_timing(summary))
        status, reason = classify_run(summary, errors)
        self.assertEqual(status, "ROUTED_COMPLETE")

    def test_actual_d1_manifest_rejected(self):
        """
        Directly checks the actual historical run_20261006_093347 manifest in repo.
        Must classify as TIMING_FAIL with nonzero exit.
        """
        repo_manifest = Path("Synthesis/fpga/ecg_artix7/reports/run_20261006_093347/fpga_manifest.json")
        if not repo_manifest.is_file():
            self.skipTest(f"Repository manifest not found at {repo_manifest}")

        summary, errors = validate_fpga_manifest(repo_manifest, expect_period_ns=20.0)
        self.assertFalse(accept_timing(summary))
        status, reason = classify_run(summary, errors)
        self.assertEqual(status, "TIMING_FAIL")
        self.assertEqual(summary["wns_ns"], -0.815)
        self.assertEqual(summary["setup_failing_endpoints"], 215)

        cmd = [sys.executable, str(self.script_path), "--manifest", str(repo_manifest), "--expect-period-ns", "20.0"]
        proc = subprocess.run(cmd, capture_output=True, text=True)
        self.assertEqual(proc.returncode, 1)
        self.assertIn("TIMING_FAIL", proc.stdout)

    def test_happy_path_all_constraints_met(self):
        """
        A cleanly closed run with reviewed contracts and WNS >= 0 must be ACCEPTED.
        """
        clean_timing = self.create_clean_timing_rpt()
        manifest = self.create_manifest(wns=0.125)

        summary, errors = validate_fpga_manifest(
            manifest,
            expect_period_ns=20.0,
            io_contract_path=self.io_contract,
            drc_review_path=self.drc_review
        )
        self.assertTrue(accept_timing(summary))
        status, reason = classify_run(summary, errors)
        self.assertEqual(status, "ACCEPTED")

        cmd = [
            sys.executable, str(self.script_path),
            "--manifest", str(manifest),
            "--expect-period-ns", "20.0",
            "--io-contract", str(self.io_contract),
            "--drc-review", str(self.drc_review)
        ]
        proc = subprocess.run(cmd, capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0)
        self.assertIn("ACCEPTED", proc.stdout)


if __name__ == '__main__':
    unittest.main()
