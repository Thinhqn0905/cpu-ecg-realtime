#!/usr/bin/env python3
"""
Unit tests for evidence gate validation (scripts/check_evidence.py).
Enforces rejection of false-success runs per Task 1 in docs/plans/2026-10-06-gemini-audit-recovery.md:
- empty log
- missing tool / nonzero compile exit
- child nonzero exit despite PASS text in log
- missing expected testcase
- duplicate testcase in log
- missing or empty artifacts
- happy path accepted run
"""

import unittest
import tempfile
import os
from pathlib import Path

from check_evidence import accepted_run, validate_run, parse_test_events


class TestEvidenceGate(unittest.TestCase):

    def setUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.tmp_dir.name)

        # Create dummy artifacts
        self.valid_artifact = self.tmp_path / "valid.vcd"
        self.valid_artifact.write_bytes(b"VCD_HEADER_DATA")

        self.empty_artifact = self.tmp_path / "empty.vcd"
        self.empty_artifact.write_bytes(b"")

    def tearDown(self):
        self.tmp_dir.cleanup()

    def test_accepted_run_happy_path(self):
        expected = {"TC-001", "TC-002"}
        observed = {"TC-001": "PASS", "TC-002": "PASS"}
        self.assertTrue(accepted_run(0, 0, expected, observed, [self.valid_artifact]))

    def test_rejected_nonzero_compile_exit(self):
        expected = {"TC-001"}
        observed = {"TC-001": "PASS"}
        # compile_exit is nonzero (e.g. 1 or 127)
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
        # A testbench might print [PASS] before crashing or failing with $fatal
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

    def test_rejected_missing_expected_testcase(self):
        expected = {"TC-001", "TC-002", "TC-003"}
        observed = {"TC-001": "PASS", "TC-002": "PASS"}
        self.assertFalse(accepted_run(0, 0, expected, observed, [self.valid_artifact]))

        log_content = "[PASS] TC-001: OK\n[PASS] TC-002: OK\n"
        is_valid, errors = validate_run(
            compile_exit=0, simulation_exit=0,
            expected_testcases=expected,
            log_content=log_content,
            artifacts=[self.valid_artifact]
        )
        self.assertFalse(is_valid)
        self.assertTrue(any("Missing expected testcases" in e for e in errors))

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
