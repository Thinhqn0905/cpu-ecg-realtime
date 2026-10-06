#!/usr/bin/env python3
"""
Unit tests for evidence gate validation (scripts/check_evidence.py).
Enforces rejection of false-success runs per Tasks 1-2 in docs/plans/2026-10-06-gemini-recovery-followup.md:
- empty log
- missing tool / nonzero compile exit
- child nonzero exit despite PASS text in log
- missing expected testcase (e.g. missing IRQ)
- COMPLETE-only log missing intermediate testcases
- fatal/crash/assert outside testcase events
- duplicate testcase in log
- missing or empty artifacts
- corrupted SHA-256 hash
- stale / mismatched run-id
- happy path accepted run with verified hash
"""

import unittest
import tempfile
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from check_evidence import accepted_run, validate_run, parse_test_events, calculate_sha256


class TestEvidenceGate(unittest.TestCase):

    def setUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.tmp_dir.name)

        # Create dummy artifacts
        self.valid_artifact = self.tmp_path / "valid.vcd"
        self.valid_artifact.write_bytes(b"VCD_HEADER_DATA_12345")
        self.valid_hash = calculate_sha256(self.valid_artifact)

        self.empty_artifact = self.tmp_path / "empty.vcd"
        self.empty_artifact.write_bytes(b"")

    def tearDown(self):
        self.tmp_dir.cleanup()

    def test_accepted_run_happy_path(self):
        expected = {"TC-001", "TC-002"}
        observed = {"TC-001": "PASS", "TC-002": "PASS"}
        self.assertTrue(accepted_run(0, 0, expected, observed, [self.valid_artifact]))

    def test_accepted_run_with_hash_and_run_id(self):
        expected = {"TC-001"}
        observed = {"TC-001": "PASS"}
        artifacts = [{"path": str(self.valid_artifact), "sha256": self.valid_hash}]
        self.assertTrue(accepted_run(
            0, 0, expected, observed, artifacts,
            requested_run_id="20261006_120000",
            manifest_run_id="20261006_120000"
        ))

    def test_rejected_nonzero_compile_exit(self):
        expected = {"TC-001"}
        observed = {"TC-001": "PASS"}
        self.assertFalse(accepted_run(1, 0, expected, observed, [self.valid_artifact]))

        is_valid, errors = validate_run(
            compile_exit=1, simulation_exit=0,
            expected_testcases=expected,
            log_content="[PASS] TC-001: Sample text",
            artifacts=[self.valid_artifact]
        )
        self.assertFalse(is_valid)
        self.assertTrue(any("Compile step failed" in e for e in errors))

    def test_rejected_nonzero_simulation_exit_despite_pass_text(self):
        expected = {"TC-001"}
        observed = {"TC-001": "PASS"}
        self.assertFalse(accepted_run(0, 134, expected, observed, [self.valid_artifact]))

        is_valid, errors = validate_run(
            compile_exit=0, simulation_exit=134,
            expected_testcases=expected,
            log_content="[PASS] TC-001: Success before crash",
            artifacts=[self.valid_artifact]
        )
        self.assertFalse(is_valid)
        self.assertTrue(any("Simulation step failed" in e for e in errors))

    def test_rejected_empty_log(self):
        expected = {"TC-001"}
        is_valid, errors = validate_run(
            compile_exit=0, simulation_exit=0,
            expected_testcases=expected,
            log_content="   \n\t  \n",
            artifacts=[self.valid_artifact]
        )
        self.assertFalse(is_valid)
        self.assertTrue(any("empty" in e for e in errors))

    def test_rejected_missing_irq_case(self):
        # Has BOOT and COMPLETE, but missing TIMER IRQ and MRET cases
        expected = {"TC-BOOT-001", "TC-DATA-002", "TC-TIMER-003", "TC-MRET-004", "TC-DONE-005"}
        observed = {"TC-BOOT-001": "PASS", "TC-DATA-002": "PASS", "TC-DONE-005": "PASS"}
        self.assertFalse(accepted_run(0, 0, expected, observed, [self.valid_artifact]))

        log_content = (
            "[PASS] TC-BOOT-001: Core Alive\n"
            "[PASS] TC-DATA-002: Data Init\n"
            "[PASS] TC-DONE-005: Complete\n"
        )
        is_valid, errors = validate_run(
            compile_exit=0, simulation_exit=0,
            expected_testcases=expected,
            log_content=log_content,
            artifacts=[self.valid_artifact]
        )
        self.assertFalse(is_valid)
        self.assertTrue(any("Missing expected testcases" in e for e in errors))

    def test_rejected_complete_only_log(self):
        # A log that only prints complete without performing intermediate verifications
        expected = {"TC-BOOT-001", "TC-DATA-002", "TC-TIMER-003", "TC-MRET-004", "TC-DONE-005"}
        log_content = "[PASS] TC-DONE-005: Full Real Boot and IRQ Verification Complete\n"
        is_valid, errors = validate_run(
            compile_exit=0, simulation_exit=0,
            expected_testcases=expected,
            log_content=log_content,
            artifacts=[self.valid_artifact]
        )
        self.assertFalse(is_valid)
        self.assertTrue(any("Missing expected testcases" in e for e in errors))

    def test_rejected_fatal_outside_tc_event(self):
        # Log has PASS but also encountered a $fatal or abort
        expected = {"TC-001"}
        log_content = (
            "[PASS] TC-001: Initial check passed\n"
            "$fatal(1, \"Incomplete boot testcase census\")\n"
        )
        observed, _ = parse_test_events(log_content)
        self.assertFalse(accepted_run(
            0, 0, expected, observed, [self.valid_artifact],
            log_content=log_content
        ))

        is_valid, errors = validate_run(
            compile_exit=0, simulation_exit=0,
            expected_testcases=expected,
            log_content=log_content,
            artifacts=[self.valid_artifact]
        )
        self.assertFalse(is_valid)
        self.assertTrue(any("Fatal errors/aborts" in e for e in errors))

    def test_sva_error_rejected(self):
        # Simulation log has PASS marker but also contains SVA $error, %Error:, or [ERROR]
        expected = {"TC-001"}
        log_content = (
            "[PASS] TC-001: Intermediate step\n"
            "%Error: p_cs_setup_time SVA assertion violated at time 45000\n"
            "$error(\"CS hold violation\");\n"
        )
        observed, _ = parse_test_events(log_content)
        self.assertFalse(accepted_run(
            0, 0, expected, observed, [self.valid_artifact],
            log_content=log_content
        ))

        is_valid, errors = validate_run(
            compile_exit=0, simulation_exit=0,
            expected_testcases=expected,
            log_content=log_content,
            artifacts=[self.valid_artifact]
        )
        self.assertFalse(is_valid)
        self.assertTrue(any("Fatal errors/aborts detected" in e for e in errors))

    def test_rejected_corrupted_artifact_hash(self):
        expected = {"TC-001"}
        observed = {"TC-001": "PASS"}
        corrupted_artifacts = [{"path": str(self.valid_artifact), "sha256": "badbeef000000000000000000000000000000000000000000000000000000000"}]
        self.assertFalse(accepted_run(0, 0, expected, observed, corrupted_artifacts))

        is_valid, errors = validate_run(
            compile_exit=0, simulation_exit=0,
            expected_testcases=expected,
            log_content="[PASS] TC-001: Success\n",
            artifacts=corrupted_artifacts
        )
        self.assertFalse(is_valid)
        self.assertTrue(any("SHA-256 mismatch" in e for e in errors))

    def test_rejected_stale_run_id(self):
        expected = {"TC-001"}
        observed = {"TC-001": "PASS"}
        self.assertFalse(accepted_run(
            0, 0, expected, observed, [self.valid_artifact],
            requested_run_id="run_20261006_120000",
            manifest_run_id="run_20261006_090000"
        ))

        is_valid, errors = validate_run(
            compile_exit=0, simulation_exit=0,
            expected_testcases=expected,
            log_content="[PASS] TC-001: Success\n",
            artifacts=[self.valid_artifact],
            requested_run_id="run_20261006_120000",
            manifest_run_id="run_20261006_090000"
        )
        self.assertFalse(is_valid)
        self.assertTrue(any("Stale run ID" in e for e in errors))

    def test_rejected_duplicate_testcase(self):
        log_content = (
            "[PASS] TC-001: First execution\n"
            "[PASS] TC-001: Duplicate execution\n"
        )
        observed, duplicates = parse_test_events(log_content)
        self.assertIn("TC-001", duplicates)

        is_valid, errors = validate_run(
            compile_exit=0, simulation_exit=0,
            expected_testcases={"TC-001"},
            log_content=log_content,
            artifacts=[self.valid_artifact]
        )
        self.assertFalse(is_valid)
        self.assertTrue(any("Duplicate testcase IDs" in e for e in errors))

    def test_rejected_testcase_failure(self):
        expected = {"TC-001"}
        observed = {"TC-001": "FAIL"}
        self.assertFalse(accepted_run(0, 0, expected, observed, [self.valid_artifact]))

        is_valid, errors = validate_run(
            compile_exit=0, simulation_exit=0,
            expected_testcases=expected,
            log_content="[FAIL] TC-001: Value mismatch",
            artifacts=[self.valid_artifact]
        )
        self.assertFalse(is_valid)
        self.assertTrue(any("reported status FAIL" in e for e in errors))

    def test_rejected_missing_or_empty_artifact(self):
        nonexistent = self.tmp_path / "does_not_exist.vcd"
        expected = {"TC-001"}
        observed = {"TC-001": "PASS"}

        # Missing artifact
        self.assertFalse(accepted_run(0, 0, expected, observed, [nonexistent]))
        is_valid, errors = validate_run(
            compile_exit=0, simulation_exit=0,
            expected_testcases=expected,
            log_content="[PASS] TC-001: OK",
            artifacts=[nonexistent]
        )
        self.assertFalse(is_valid)
        self.assertTrue(any("does not exist" in e for e in errors))

        # Empty artifact (0 bytes)
        self.assertFalse(accepted_run(0, 0, expected, observed, [self.empty_artifact]))
        is_valid, errors = validate_run(
            compile_exit=0, simulation_exit=0,
            expected_testcases=expected,
            log_content="[PASS] TC-001: OK",
            artifacts=[self.empty_artifact]
        )
        self.assertFalse(is_valid)
        self.assertTrue(any("empty" in e for e in errors))


if __name__ == '__main__':
    unittest.main()
