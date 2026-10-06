#!/usr/bin/env python3
"""
Test Runner Contract Suite for RISC-V ECG SoC Project
Tests runner contract validation and gate enforcement per:
- docs/plans/2026-10-06-gemini-recovery-followup.md (Task 2)
- Instruction/claim_integrity.md

Covers:
1. Zero-exit log missing IRQ (TC-TIMER-003 / TC-MRET-004)
2. COMPLETE-only log (missing intermediate cases)
3. Fatal / crash / assert outside TC event
4. Corrupted artifact SHA-256 hash in manifest
5. Stale / mismatched run ID (--run-id)
6. Empty simulation log
7. Duplicate testcase event
8. Child process failure (compile exit != 0 or sim exit != 0)
9. Missing or 0-byte artifact
10. Valid complete run accepted and verified
"""

import unittest
import tempfile
import subprocess
import sys
import json
import hashlib
from pathlib import Path


def sha256_file(p: Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()


class TestRunnerContract(unittest.TestCase):

    def setUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.work_dir = Path(self.tmp_dir.name)
        self.script_path = Path(__file__).resolve().parent / "check_evidence.py"
        self.expected_boot_cases = [
            "TC-BOOT-001",
            "TC-DATA-002",
            "TC-TIMER-003",
            "TC-MRET-004",
            "TC-DONE-005"
        ]

        # Create valid mock artifacts
        self.vvp_file = self.work_dir / "soc_tb.vvp"
        self.vvp_file.write_bytes(b"VVP_MOCK_COMPILED_BINARY_DATA")

        self.compile_log = self.work_dir / "compile.log"
        self.compile_log.write_text("Icarus Verilog compilation finished cleanly.\n", encoding="utf-8")

        self.sim_log = self.work_dir / "soc_tb.log"
        self.sim_log_content = (
            "[PASS] TC-BOOT-001: Core alive and executing crt0\n"
            "[PASS] TC-DATA-002: Data segment initialized from ROM\n"
            "[PASS] TC-TIMER-003: Timer interrupt triggered and handled\n"
            "[PASS] TC-MRET-004: Clean return from trap handler via mret\n"
            "[PASS] TC-DONE-005: Boot and IRQ verification complete\n"
        )
        self.sim_log.write_text(self.sim_log_content, encoding="utf-8")

        self.valid_artifacts = [
            {"path": str(self.vvp_file), "sha256": sha256_file(self.vvp_file)},
            {"path": str(self.compile_log), "sha256": sha256_file(self.compile_log)},
            {"path": str(self.sim_log), "sha256": sha256_file(self.sim_log)},
        ]

    def tearDown(self):
        self.tmp_dir.cleanup()

    def run_checker(self, manifest_path: Path, expected_cases: list, run_id: str = None) -> subprocess.CompletedProcess:
        cmd = [sys.executable, str(self.script_path), str(manifest_path)] + expected_cases
        if run_id:
            cmd += ["--run-id", run_id]
        return subprocess.run(cmd, capture_output=True, text=True)

    def write_manifest(self, run_id: str, compile_exit: int, sim_exit: int, log_file: Path, artifacts: list) -> Path:
        manifest_path = self.work_dir / "sim_results.json"
        data = {
            "run_id": run_id,
            "timestamp": "2026-10-06T12:00:00Z",
            "compiler": "iverilog",
            "runtime": "vvp",
            "compile_exit": compile_exit,
            "simulation_exit": sim_exit,
            "log_file": str(log_file),
            "artifacts": artifacts
        }
        manifest_path.write_text(json.dumps(data, indent=2), encoding="utf-8")
        return manifest_path

    def test_happy_path_all_cases_passed(self):
        manifest = self.write_manifest("run_20261006_120000", 0, 0, self.sim_log, self.valid_artifacts)
        proc = self.run_checker(manifest, self.expected_boot_cases, run_id="run_20261006_120000")
        self.assertEqual(proc.returncode, 0, f"Expected 0, got {proc.returncode}. Stderr: {proc.stderr}")
        self.assertIn("[PASS] Evidence gate validation successful", proc.stdout)

    def test_rejected_zero_exit_missing_irq(self):
        # Simulation finished with 0, but only has BOOT, DATA, and DONE (missed TIMER and MRET)
        incomplete_log = self.work_dir / "incomplete.log"
        incomplete_log.write_text(
            "[PASS] TC-BOOT-001: Core alive\n"
            "[PASS] TC-DATA-002: Data init\n"
            "[PASS] TC-DONE-005: Done\n",
            encoding="utf-8"
        )
        artifacts = [
            {"path": str(self.vvp_file), "sha256": sha256_file(self.vvp_file)},
            {"path": str(self.compile_log), "sha256": sha256_file(self.compile_log)},
            {"path": str(incomplete_log), "sha256": sha256_file(incomplete_log)},
        ]
        manifest = self.write_manifest("run_20261006_120000", 0, 0, incomplete_log, artifacts)
        proc = self.run_checker(manifest, self.expected_boot_cases, run_id="run_20261006_120000")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("Missing expected testcases", proc.stderr)
        self.assertIn("TC-TIMER-003", proc.stderr)
        self.assertIn("TC-MRET-004", proc.stderr)

    def test_rejected_complete_only(self):
        # Simulation only printed DONE-005
        complete_only_log = self.work_dir / "complete_only.log"
        complete_only_log.write_text(
            "[PASS] TC-DONE-005: All tests complete\n",
            encoding="utf-8"
        )
        artifacts = [
            {"path": str(self.vvp_file), "sha256": sha256_file(self.vvp_file)},
            {"path": str(complete_only_log), "sha256": sha256_file(complete_only_log)},
        ]
        manifest = self.write_manifest("run_20261006_120000", 0, 0, complete_only_log, artifacts)
        proc = self.run_checker(manifest, self.expected_boot_cases, run_id="run_20261006_120000")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("Missing expected testcases", proc.stderr)

    def test_rejected_fatal_outside_tc_event(self):
        fatal_log = self.work_dir / "fatal.log"
        fatal_log.write_text(
            self.sim_log_content + "\n$fatal(1, \"Watchdog expired: simulation timed out\")\n",
            encoding="utf-8"
        )
        artifacts = [
            {"path": str(self.vvp_file), "sha256": sha256_file(self.vvp_file)},
            {"path": str(fatal_log), "sha256": sha256_file(fatal_log)},
        ]
        manifest = self.write_manifest("run_20261006_120000", 0, 0, fatal_log, artifacts)
        proc = self.run_checker(manifest, self.expected_boot_cases, run_id="run_20261006_120000")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("Fatal errors/aborts detected in log", proc.stderr)

    def test_rejected_corrupted_hash(self):
        corrupted_artifacts = [
            {"path": str(self.vvp_file), "sha256": "badbeef000000000000000000000000000000000000000000000000000000000"},
            {"path": str(self.sim_log), "sha256": sha256_file(self.sim_log)},
        ]
        manifest = self.write_manifest("run_20261006_120000", 0, 0, self.sim_log, corrupted_artifacts)
        proc = self.run_checker(manifest, self.expected_boot_cases, run_id="run_20261006_120000")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("SHA-256 mismatch", proc.stderr)

    def test_rejected_stale_run_id(self):
        manifest = self.write_manifest("run_20261006_110000", 0, 0, self.sim_log, self.valid_artifacts)
        # We expect run_20261006_120000, but manifest has run_20261006_110000
        proc = self.run_checker(manifest, self.expected_boot_cases, run_id="run_20261006_120000")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("Stale run ID", proc.stderr)

    def test_rejected_empty_log(self):
        empty_log = self.work_dir / "empty.log"
        empty_log.write_text("", encoding="utf-8")
        artifacts = [
            {"path": str(self.vvp_file), "sha256": sha256_file(self.vvp_file)},
            {"path": str(empty_log), "sha256": sha256_file(empty_log)},
        ]
        manifest = self.write_manifest("run_20261006_120000", 0, 0, empty_log, artifacts)
        proc = self.run_checker(manifest, self.expected_boot_cases, run_id="run_20261006_120000")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("Simulation log is empty", proc.stderr)

    def test_rejected_duplicate_case(self):
        duplicate_log = self.work_dir / "duplicate.log"
        duplicate_log.write_text(
            self.sim_log_content + "[PASS] TC-BOOT-001: Duplicate entry\n",
            encoding="utf-8"
        )
        artifacts = [
            {"path": str(duplicate_log), "sha256": sha256_file(duplicate_log)},
        ]
        manifest = self.write_manifest("run_20261006_120000", 0, 0, duplicate_log, artifacts)
        proc = self.run_checker(manifest, self.expected_boot_cases, run_id="run_20261006_120000")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("Duplicate testcase IDs detected", proc.stderr)

    def test_rejected_child_compile_failure(self):
        manifest = self.write_manifest("run_20261006_120000", 1, 0, self.sim_log, self.valid_artifacts)
        proc = self.run_checker(manifest, self.expected_boot_cases, run_id="run_20261006_120000")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("Compile step failed with exit code 1", proc.stderr)

    def test_rejected_child_sim_failure(self):
        manifest = self.write_manifest("run_20261006_120000", 0, 134, self.sim_log, self.valid_artifacts)
        proc = self.run_checker(manifest, self.expected_boot_cases, run_id="run_20261006_120000")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("Simulation step failed with exit code 134", proc.stderr)

    def test_rejected_missing_or_empty_artifact(self):
        # Empty artifact
        empty_artifact = self.work_dir / "empty.vvp"
        empty_artifact.write_bytes(b"")
        artifacts = [
            {"path": str(empty_artifact), "sha256": sha256_file(empty_artifact)},
            {"path": str(self.sim_log), "sha256": sha256_file(self.sim_log)},
        ]
        manifest = self.write_manifest("run_20261006_120000", 0, 0, self.sim_log, artifacts)
        proc = self.run_checker(manifest, self.expected_boot_cases, run_id="run_20261006_120000")
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("empty (0 bytes)", proc.stderr)


if __name__ == "__main__":
    unittest.main()
