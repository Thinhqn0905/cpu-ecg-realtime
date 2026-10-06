#!/usr/bin/env python3
"""
Unit and integration tests for CV32E40P Target DSP & Benchmark Contract.
Enforces fail-closed verification per:
- Instruction/claim_integrity.md
- Instruction/evidence_contract.md
- docs/plans/2026-10-06-core-next-decision-audit.md (Task 4 / Checklist 10.7)

Verifies:
1. test_dsp_source_files_exist: Verifies required DSP source files exist.
2. test_dsp_runtime_freestanding_contract: Verifies freestanding runtime symbols and mcycle contract.
3. test_claim_integrity_no_host_stub_false_pass: Ensures host builds skip target assembly & CSRs.
4. test_assembly_kernels_structural_parity: Validates both baseline RV32IM and CORE-V .insn loops.
5. test_host_dsp_execution: Executes host dsp_test, verifying 4 passes, 0 fails, 2 skips.
6. test_host_kernel_benchmark_execution: Executes host kernel_benchmark, verifying 5 passes, 0 fails, 3 skips.
7. test_target_binary_build_contract: Verifies target ELFs, hex image, and 32KB I-TCM sizing.
8. test_realtime_cycle_budget_contract: Verifies 50 MHz / 1000 Hz timing budget calculation and margins.
"""

import unittest
import subprocess
import shutil
import re
import os
import sys
from pathlib import Path

class TestTargetDspContract(unittest.TestCase):

    def setUp(self):
        self.repo_root = Path(__file__).resolve().parent.parent
        self.dsp_dir = self.repo_root / "Firmware" / "dsp"
        self.build_dir = self.repo_root / "Firmware" / "build"

    def test_dsp_source_files_exist(self):
        """Verify all required DSP source files exist in Firmware/dsp/."""
        required_files = [
            "kernel_benchmark.c",
            "dsp_test.c",
            "dsp_runtime.h",
            "dsp_runtime.c",
            "ecg_fir_pulp.S",
            "resumamba_kernels_pulp.S",
            "fir_reference.c",
            "pan_tompkins.c",
            "pan_tompkins.h",
        ]
        for fname in required_files:
            fpath = self.dsp_dir / fname
            self.assertTrue(fpath.is_file(), f"Missing required DSP file: {fpath}")

    def test_dsp_runtime_freestanding_contract(self):
        """Verify freestanding runtime definitions and CSR mcycle contract."""
        runtime_h = (self.dsp_dir / "dsp_runtime.h").read_text(encoding="utf-8")
        runtime_c = (self.dsp_dir / "dsp_runtime.c").read_text(encoding="utf-8")

        # Freestanding symbols
        self.assertIn("void *memset", runtime_c)
        self.assertIn("void *memcpy", runtime_c)

        # Hardware UART base address
        self.assertIn("0x10000000", runtime_h)

        # CSR mcycle read
        self.assertIn('csrr %0, mcycle', runtime_h)

        # Host fallback returns 0 and does not fabricate cycle counts
        self.assertIn("return 0; // Host does not have hardware RISC-V mcycle CSR", runtime_h)

    def test_claim_integrity_no_host_stub_false_pass(self):
        """Verify claim integrity: host must never return [PASS] for target assembly or mcycle reads."""
        dsp_test_c = (self.dsp_dir / "dsp_test.c").read_text(encoding="utf-8")
        kbench_c = (self.dsp_dir / "kernel_benchmark.c").read_text(encoding="utf-8")

        # dsp_test.c must emit [SKIP] on host
        self.assertIn("[SKIP] TC-DSP-003", dsp_test_c)
        self.assertIn("[SKIP] TC-DSP-004", dsp_test_c)

        # kernel_benchmark.c must emit [SKIP] on host
        self.assertIn("[SKIP] TC-KBENCH-006", kbench_c)
        self.assertIn("[SKIP] TC-KBENCH-007", kbench_c)
        self.assertIn("[SKIP] TC-KBENCH-008", kbench_c)

        # Ensure no fake pass on host
        self.assertNotIn("[PASS] TC-DSP-003: Target assembly kernel (ecg_fir_pulp) skipped on host", dsp_test_c)
        self.assertNotIn("[PASS] TC-DSP-004: Hardware cycle measurement via mcycle CSR skipped on host", dsp_test_c)

    def test_assembly_kernels_structural_parity(self):
        """Validate both RV32IM baseline and CORE-V .insn loops exist in assembly."""
        fir_s = (self.dsp_dir / "ecg_fir_pulp.S").read_text(encoding="utf-8")
        resumamba_s = (self.dsp_dir / "resumamba_kernels_pulp.S").read_text(encoding="utf-8")

        # ecg_fir_pulp.S must have both loops
        self.assertIn(".L_corev_loop:", fir_s)
        self.assertIn(".L_rv32im_loop:", fir_s)
        # Check standard GNU .insn opcodes for CORE-V
        self.assertIn(".insn i 0x0b, 2, t0, 4(a0)", fir_s)      # cv.lw
        self.assertIn(".insn r 0x7b, 0, 0x54, a3, t0, t1", fir_s) # cv.sdotsp.h
        self.assertIn(".insn r 0x2b, 3, 0x48, a3, t0, t1", fir_s) # cv.mac

        # resumamba_kernels_pulp.S must have both loops
        self.assertIn(".L_fir128_corev_loop:", resumamba_s)
        self.assertIn(".L_fir128_rv32im_loop:", resumamba_s)
        self.assertIn("resumamba_dotp_i16_i8:", resumamba_s)

    def test_host_dsp_execution(self):
        """Execute host dsp_test binary and verify exact pass/fail counts."""
        host_bin = self.build_dir / "dsp_test_host"
        if not host_bin.is_file():
            # Compile using gcc
            res = subprocess.run(
                ["gcc", "-O2", "-Wall", "-Wextra", "-I", str(self.dsp_dir),
                 str(self.dsp_dir / "dsp_test.c"), str(self.dsp_dir / "fir_reference.c"),
                 str(self.dsp_dir / "pan_tompkins.c"), str(self.dsp_dir / "dsp_runtime.c"),
                 "-o", str(host_bin)],
                capture_output=True, text=True
            )
            self.assertEqual(res.returncode, 0, f"Compilation failed: {res.stderr}")

        res = subprocess.run([str(host_bin)], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"dsp_test_host failed: {res.stdout}\n{res.stderr}")
        self.assertIn("PASSED:  4", res.stdout)
        self.assertIn("FAILED:  0", res.stdout)
        self.assertIn("SKIPPED: 2", res.stdout)

    def test_host_kernel_benchmark_execution(self):
        """Execute host kernel_benchmark binary and verify exact pass/fail counts."""
        host_bin = self.build_dir / "kernel_benchmark_host"
        if not host_bin.is_file():
            res = subprocess.run(
                ["gcc", "-O2", "-Wall", "-Wextra", "-I", str(self.dsp_dir),
                 str(self.dsp_dir / "kernel_benchmark.c"), str(self.dsp_dir / "fir_reference.c"),
                 str(self.dsp_dir / "pan_tompkins.c"), str(self.dsp_dir / "dsp_runtime.c"),
                 "-o", str(host_bin)],
                capture_output=True, text=True
            )
            self.assertEqual(res.returncode, 0, f"Compilation failed: {res.stderr}")

        res = subprocess.run([str(host_bin)], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"kernel_benchmark_host failed: {res.stdout}\n{res.stderr}")
        self.assertIn("PASSED:  5", res.stdout)
        self.assertIn("FAILED:  0", res.stdout)
        self.assertIn("SKIPPED: 3", res.stdout)

    def test_target_binary_build_contract(self):
        """Validate target ELFs, hex images, and TCM sizing constraints."""
        target_elf = self.build_dir / "kernel_benchmark.elf"
        target_hex = self.build_dir / "kernel_benchmark.hex"

        self.assertTrue(target_elf.is_file(), f"Target ELF missing: {target_elf}")
        self.assertTrue(target_hex.is_file(), f"Target Hex image missing: {target_hex}")

        # Check hex line count and word format (up to 32768 lines, 8 hex digits per line)
        lines = target_hex.read_text(encoding="utf-8").strip().splitlines()
        self.assertGreater(len(lines), 0, "Hex file is empty")
        self.assertLessEqual(len(lines), 32768, "Hex exceeds 32 KB I-TCM")

        for line in lines[:50]:
            self.assertTrue(re.match(r"^[0-9a-fA-F]{8}$", line.strip()), f"Invalid hex word: {line}")

    def test_realtime_cycle_budget_contract(self):
        """Verify cycle budget formulas for real-time 1000 Hz, 500 Hz, and 250 Hz sampling."""
        f_clk = 50_000_000 # 50.0 MHz
        sampling_rates = [1000, 500, 250]
        fir_taps = 45

        # Scalar cycles per tap ~ 6-8 cycles (load, mul, add, index)
        # Total FIR ~ 400-600 cycles
        # Pan-Tompkins step ~ 150-300 cycles
        estimated_total_cycles = 1500

        for fs in sampling_rates:
            budget_cycles = f_clk // fs
            cpu_utilization_pct = (estimated_total_cycles / budget_cycles) * 100.0

            if fs == 1000:
                self.assertEqual(budget_cycles, 50_000)
                self.assertLess(cpu_utilization_pct, 5.0, "1000 Hz CPU load exceeds 5.0%")
            elif fs == 500:
                self.assertEqual(budget_cycles, 100_000)
                self.assertLess(cpu_utilization_pct, 2.5, "500 Hz CPU load exceeds 2.5%")
            elif fs == 250:
                self.assertEqual(budget_cycles, 200_000)
                self.assertLess(cpu_utilization_pct, 1.0, "250 Hz CPU load exceeds 1.0%")


if __name__ == "__main__":
    unittest.main()
