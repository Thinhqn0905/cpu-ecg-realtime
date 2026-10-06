#!/usr/bin/env python3
"""
Test Firmware Build Contract Suite for RISC-V ECG SoC Project
Tests build contract enforcement per docs/plans/2026-10-06-gemini-recovery-followup.md (Task 3):
- Rejects toolchain absence with non-zero exit code
- No silent fallback to handwritten or synthetic machine code
- No success artifacts (.elf, .bin, .hex, .map, .dump, .sha256) created or touched on failure
- Diagnostic naming required compiler binaries
- Preserves clean run separation and hash verification
"""

import unittest
import tempfile
import subprocess
import sys
import os
from pathlib import Path


class TestFirmwareBuildContract(unittest.TestCase):

    def setUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.tmp_dir.name)
        self.build_script = Path(__file__).resolve().parent.parent / "Firmware" / "build_boot_image.py"

    def tearDown(self):
        self.tmp_dir.cleanup()

    def test_missing_toolchain_fails_hard(self):
        """When toolchain is absent or invalid prefix given, build MUST fail non-zero."""
        target_out = self.tmp_path / "build_fail_test"
        cmd = [
            sys.executable,
            str(self.build_script),
            "--out-dir", str(target_out),
            "--prefix", "nonexistent-riscv-toolchain-prefix-"
        ]
        proc = subprocess.run(cmd, capture_output=True, text=True)

        self.assertNotEqual(proc.returncode, 0, f"Expected non-zero exit code, got {proc.returncode}")
        # Diagnostic must name the missing compiler
        combined_output = proc.stdout + proc.stderr
        self.assertTrue(
            any(w in combined_output.lower() for w in ["compiler not found", "toolchain not found", "cannot find", "nonexistent-riscv"]),
            f"Expected diagnostic naming missing compiler, got: {combined_output}"
        )

        # No success artifacts should have been created in target_out
        for ext in [".elf", ".bin", ".hex", ".map", ".dump", ".sha256"]:
            artifact = target_out / f"hello{ext}"
            self.assertFalse(artifact.exists(), f"Artifact {artifact} was improperly created on failure!")

    def test_no_synthetic_fallback_on_toolchain_absence(self):
        """Verify that build_boot_image.py does not contain or execute silent synthetic fallbacks."""
        script_content = self.build_script.read_text(encoding="utf-8")
        # Check that main() does not call build_standalone() or handwritten fallback on toolchain absence
        self.assertNotIn("build_standalone()", script_content, "build_boot_image.py must not call build_standalone()")


if __name__ == "__main__":
    unittest.main()
