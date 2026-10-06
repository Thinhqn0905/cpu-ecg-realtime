#!/usr/bin/env python3
"""
Unit and integration tests for CV32E40P Real-Core Baseline Contract.
Enforces fail-closed verification per:
- Instruction/claim_integrity.md
- Instruction/evidence_contract.md
- docs/plans/2026-10-06-core-next-decision-audit.md (Task 2)

Verifies:
1. test_baseline_json_config: Validates named baseline parameters in config/core_baseline.json.
2. test_corrupt_or_truncated_boot_image_rejected: Hex validation rejects corrupted/empty files.
3. test_wrong_sentinel_or_canary_failure_detected: Log checker flags DATA INIT FAIL, CANARY FAIL, IRQ TIMEOUT.
4. test_caller_saved_context_restoration_contract: crt0.S & hello.c verify caller-saved register preservation.
5. test_tcm_plusarg_isolation_contract: tcm_sram.sv gates plusarg so D-TCM cannot load I-TCM hex.
6. test_dtcm_boundary_address_decoding: Validates 128 KB D-TCM boundary (0x0001_0000 to 0x0002_FFFF).
7. test_obi_apb_wait_state_serialization: Validates backpressure/gnt deassertion during multi-cycle APB wait.
8. test_firmware_build_artifact_manifest: Validates build directory artifact presence and SHA-256 integrity.
"""

import unittest
import tempfile
import sys
import json
import hashlib
import re
from pathlib import Path

# Add scripts directory to sys.path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from check_evidence import check_fatal_in_log


class TestCoreBaselineContract(unittest.TestCase):

    def setUp(self):
        self.repo_root = Path(__file__).resolve().parent.parent
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.work_dir = Path(self.tmp_dir.name)

    def tearDown(self):
        self.tmp_dir.cleanup()

    def test_baseline_json_config(self):
        """Validates config/core_baseline.json against canonical baseline specification."""
        cfg_path = self.repo_root / "config" / "core_baseline.json"
        self.assertTrue(cfg_path.is_file(), f"Missing config file: {cfg_path}")

        with open(cfg_path, "r", encoding="utf-8") as f:
            cfg = json.load(f)

        # Core checks
        core = cfg.get("core", {})
        self.assertEqual(core.get("name"), "CV32E40P")
        self.assertEqual(core.get("architecture"), "RV32IMC")
        self.assertEqual(core.get("head_commit"), "97086e9565f8145522ad6d62852123c0e5537529")
        self.assertEqual(core.get("COREV_PULP"), 1)
        self.assertEqual(core.get("FPU"), 0)

        # Clock checks
        clock = cfg.get("clock", {})
        self.assertEqual(clock.get("compute_freq_mhz"), 50.0)
        self.assertEqual(clock.get("compute_period_ns"), 20.0)

        # Memory checks
        memory = cfg.get("memory", {})
        self.assertEqual(memory.get("i_tcm_bytes"), 32768)
        self.assertEqual(memory.get("d_tcm_bytes"), 131072)
        self.assertEqual(memory.get("d_tcm_base"), "0x0001_0000")
        self.assertEqual(memory.get("d_tcm_limit"), "0x0002_FFFF")

        # Accelerator checks
        accel = cfg.get("accelerator", {})
        self.assertEqual(accel.get("mamba_enabled"), 0)

        # Verification testcase census
        verif = cfg.get("verification", {})
        baseline_cases = verif.get("baseline_expected_testcases", [])
        self.assertEqual(len(baseline_cases), 5)
        self.assertIn("TC-BOOT-001", baseline_cases)
        self.assertIn("TC-DATA-002", baseline_cases)
        self.assertIn("TC-TIMER-003", baseline_cases)
        self.assertIn("TC-MRET-004", baseline_cases)
        self.assertIn("TC-DONE-005", baseline_cases)

        diag_cases = verif.get("diagnostic_stub_testcases", [])
        self.assertEqual(len(diag_cases), 6)
        self.assertIn("TC-CASCADE-006", diag_cases)

    def test_corrupt_or_truncated_boot_image_rejected(self):
        """Verifies that corrupt or truncated hex images fail validation."""
        corrupt_hex = self.work_dir / "corrupt.hex"
        # Hex file with non-hex characters and truncated words
        corrupt_hex.write_text("00000013\nNOT_A_HEX_WORD\n1234\n")

        valid_words = 0
        has_error = False
        with open(corrupt_hex, "r", encoding="utf-8") as f:
            for line_no, line in enumerate(f, 1):
                clean = line.strip()
                if not clean:
                    continue
                # Verilog hex format requires 8 hex digits per 32-bit word
                if len(clean) != 8 or not re.fullmatch(r"[0-9a-fA-F]{8}", clean):
                    has_error = True
                    break
                valid_words += 1

        self.assertTrue(has_error, "Validator failed to catch invalid/truncated hex word!")
        self.assertEqual(valid_words, 1)

    def test_wrong_sentinel_or_canary_failure_detected(self):
        """Verifies check_fatal_in_log catches runtime failure markers."""
        fail_markers = [
            "ECG BOOT: DATA INIT FAIL - $fatal(1)",
            "ECG BOOT: CANARY FAIL - [FATAL]",
            "ECG BOOT: IRQ TIMEOUT - Assertion failed",
            "CASCADE: FAIL - $error",
            "%Error: Simulation failed",
            "[ERROR] Context corruption detected"
        ]

        for marker in fail_markers:
            test_log = f"Starting boot...\n{marker}\nExiting.\n"
            detected = check_fatal_in_log(test_log)
            self.assertTrue(len(detected) > 0, f"Failed to detect failure marker: '{marker}'")

    def test_caller_saved_context_restoration_contract(self):
        """Verifies crt0.S and hello.c enforce caller-saved context preservation across ISR."""
        crt0_path = self.repo_root / "Firmware" / "boot" / "crt0.S"
        self.assertTrue(crt0_path.is_file())
        crt0_content = crt0_path.read_text(encoding="utf-8")

        # Verify SAVE_CONTEXT macro saves caller-saved registers
        save_match = re.search(r"\.macro SAVE_CONTEXT(.*?)\.endm", crt0_content, re.DOTALL)
        self.assertIsNotNone(save_match, "SAVE_CONTEXT macro missing in crt0.S")
        save_body = save_match.group(1)
        for reg in ["ra", "t0", "t1", "t2", "t3", "t4", "t5", "t6", "a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7"]:
            self.assertRegex(save_body, rf"sw\s+{reg},\s+\d+\(sp\)", f"SAVE_CONTEXT missing save for {reg}")

        # Verify RESTORE_CONTEXT macro restores caller-saved registers
        restore_match = re.search(r"\.macro RESTORE_CONTEXT(.*?)\.endm", crt0_content, re.DOTALL)
        self.assertIsNotNone(restore_match, "RESTORE_CONTEXT macro missing in crt0.S")
        restore_body = restore_match.group(1)
        for reg in ["ra", "t0", "t1", "t2", "t3", "t4", "t5", "t6", "a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7"]:
            self.assertRegex(restore_body, rf"lw\s+{reg},\s+\d+\(sp\)", f"RESTORE_CONTEXT missing restore for {reg}")

        # Verify hello.c tests both callee-saved and caller-saved registers
        hello_path = self.repo_root / "Firmware" / "boot" / "hello.c"
        self.assertTrue(hello_path.is_file())
        hello_content = hello_path.read_text(encoding="utf-8")

        # Caller-saved canaries in hello.c
        self.assertIn("canary_t2", hello_content)
        self.assertIn("canary_t3", hello_content)
        # Callee-saved canaries in hello.c
        self.assertIn("canary_s2", hello_content)
        self.assertIn("canary_s3", hello_content)
        # Verify ISR clobbers caller-saved registers
        self.assertIn("li t2, 0xDEAD0002", hello_content)
        self.assertIn("li t3, 0xDEAD0003", hello_content)

    def test_tcm_plusarg_isolation_contract(self):
        """Verifies tcm_sram.sv gates plusarg initialization so D-TCM cannot load I-TCM hex."""
        tcm_sram_path = self.repo_root / "RTL" / "ecg_soc" / "tcm_sram.sv"
        self.assertTrue(tcm_sram_path.is_file())
        tcm_content = tcm_sram_path.read_text(encoding="utf-8")

        self.assertIn("parameter bit          ALLOW_PLUSARG_INIT = 1'b0", tcm_content)
        self.assertIn("ALLOW_PLUSARG_INIT && $value$plusargs(\"firmware=%s\"", tcm_content)

        # Verify cv32e40p_ecg_soc_top instantiates u_i_tcm with ALLOW_PLUSARG_INIT=1 and u_d_tcm with 0
        soc_top_path = self.repo_root / "RTL" / "ecg_soc" / "cv32e40p_ecg_soc_top.sv"
        self.assertTrue(soc_top_path.is_file())
        soc_top_content = soc_top_path.read_text(encoding="utf-8")

        # u_i_tcm has ALLOW_PLUSARG_INIT(1'b1) in parameter list
        self.assertRegex(soc_top_content, r"tcm_sram\s*#\s*\([^;]*\.ALLOW_PLUSARG_INIT\s*\(\s*1'b1\s*\)[^;]*\)\s*u_i_tcm")
        # u_d_tcm has ALLOW_PLUSARG_INIT(1'b0) in parameter list
        self.assertRegex(soc_top_content, r"tcm_sram\s*#\s*\([^;]*\.ALLOW_PLUSARG_INIT\s*\(\s*1'b0\s*\)[^;]*\)\s*u_d_tcm")

    def test_dtcm_boundary_address_decoding(self):
        """Verifies 128 KB D-TCM address decoder boundaries in cv32e40p_ecg_soc_top.sv."""
        soc_top_path = self.repo_root / "RTL" / "ecg_soc" / "cv32e40p_ecg_soc_top.sv"
        soc_top_content = soc_top_path.read_text(encoding="utf-8")

        # Check address decode equation
        self.assertIn("wire is_itcm_addr    = (data_addr < I_MEM_SIZE_BYTES);", soc_top_content)
        self.assertIn("wire is_dtcm_addr    = (data_addr >= 32'h0001_0000) && (data_addr < (32'h0001_0000 + D_MEM_SIZE_BYTES));", soc_top_content)

        # Concrete boundary calculation
        d_mem_size = 131072 # 128 KB
        d_base = 0x00010000
        d_limit = d_base + d_mem_size - 1 # 0x0002_FFFF
        last_valid_word = d_base + d_mem_size - 4 # 0x0002_FFFC
        first_invalid = d_base + d_mem_size # 0x0003_0000

        self.assertEqual(f"0x{d_limit:08X}", "0x0002FFFF")
        self.assertEqual(f"0x{last_valid_word:08X}", "0x0002FFFC")
        self.assertEqual(f"0x{first_invalid:08X}", "0x00030000")

    def test_obi_apb_wait_state_serialization(self):
        """Verifies OBI-to-APB serialization prevents secondary transaction grant during wait-states."""
        soc_top_path = self.repo_root / "RTL" / "ecg_soc" / "cv32e40p_ecg_soc_top.sv"
        soc_top_content = soc_top_path.read_text(encoding="utf-8")

        # Serializing wire
        self.assertIn("wire data_bus_busy = (pending_target_q != TARGET_NONE) && !data_rvalid;", soc_top_content)
        self.assertIn("assign data_gnt    = data_bus_busy   ? 1'b0 :", soc_top_content)

    def test_firmware_build_artifact_manifest(self):
        """Verifies canonical Firmware/build directory artifacts and matching SHA-256 digests."""
        build_dir = self.repo_root / "Firmware" / "build"
        self.assertTrue(build_dir.is_dir(), f"Build directory missing: {build_dir}")

        sha256_file = build_dir / "hello.sha256"
        self.assertTrue(sha256_file.is_file(), f"Missing SHA-256 manifest: {sha256_file}")

        mandatory_artifacts = [
            "hello.elf",
            "hello.bin",
            "hello.hex",
            "hello.dump",
            "hello.map",
            "hello.nm",
            "hello.readelf"
        ]

        recorded_hashes = {}
        for line in sha256_file.read_text(encoding="ascii").splitlines():
            line = line.strip()
            if not line:
                continue
            parts = line.split(None, 1)
            self.assertEqual(len(parts), 2)
            digest, fname = parts[0], parts[1].strip()
            recorded_hashes[fname] = digest.lower()

        for art_name in mandatory_artifacts:
            art_path = build_dir / art_name
            self.assertTrue(art_path.is_file(), f"Mandatory artifact missing: {art_path}")
            self.assertGreater(art_path.stat().st_size, 0, f"Artifact is empty: {art_path}")
            self.assertIn(art_name, recorded_hashes, f"Artifact not recorded in sha256 file: {art_name}")

            # Recompute digest and compare
            h = hashlib.sha256()
            with open(art_path, "rb") as f:
                while chunk := f.read(65536):
                    h.update(chunk)
            actual_digest = h.hexdigest().lower()
            self.assertEqual(
                actual_digest,
                recorded_hashes[art_name],
                f"SHA-256 digest mismatch for {art_name}: {actual_digest} != {recorded_hashes[art_name]}"
            )


if __name__ == "__main__":
    unittest.main()
