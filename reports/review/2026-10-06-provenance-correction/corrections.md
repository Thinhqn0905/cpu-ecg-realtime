# Dated Correction Report: Provenance and Evidence Integrity Rectification

**Date:** 2026-10-06  
**Document ID:** `REP-CORR-20261006-01`  
**Scope:** Rectification of GCC compilation, SPI testbench promotion, and DSP cycle claims  
**Audit Reference:** `reports/review/2026-10-06-gemini-recovery-audit/audit.md` (Findings R1–R10)  
**Governance:** `Instruction/claim_integrity.md` (Rules 1, 2, 3, 5, 10, 15)  

---

## 1. Summary of Corrected Claims

Pursuant to the static recovery audit dated 2026-10-06, the following claims made in previous checklist iterations (V4/V5) are formally withdrawn and corrected:

### 1.1 GCC Compilation & Firmware Build Provenance (Findings R1, R2)
- **Previous Claim:** "Task 5.2.5: Compile hello firmware with RISC-V GCC into ELF, map, disassembly, and Verilog hex image complete."
- **Audit Reality:** `Firmware/build/` lacked an actual ELF executable, binary, or object files. The file `hello.sha256` recorded hash `e3b0c442...` (empty file) for `hello.map`, which is actually 1,260 bytes. The dump file `hello.dump` conflicted with opcode jump targets at PC `0x4` (`0740006f` decodes to target `0x78`, not `0x130`). The build script `Firmware/build_boot_image.py` contained a silent fallback that generated hand-assembled hex words when GCC was absent or failed.
- **Corrected Status:** **`NOT_VERIFIED`**. The existing `Firmware/build/` artifacts are marked as an **artifact-integrity violation**. They are retained strictly as historical failed evidence and must not be cited as compiler outputs.

### 1.2 SPI Master Simulation Promotion (Finding R8)
- **Previous Status:** `REQ-SPI-001`, `REQ-SPI-002`, `REQ-SPI-003` marked as `PASS (Sim)` in `reports/verification/rtm_dashboard.md` citing `reports/review/2026-10-06-source-audit/spi_run.json`.
- **Audit Reality:** The source-audit run executed an older, isolated 24-bit testbench with testcase IDs `TC-001`, `TC-002`, `TC-007`. The current RTL implements continuous-CS 72-bit acquisition with new testcase IDs `TC-SPI-*`. Borrowing evidence from an older, incompatible testbench revision violates Claim Integrity Rule 5.
- **Corrected Status:** **`NOT_VERIFIED`** for the current 72-bit continuous-CS SPI master. The historical smoke simulation is preserved under its original revision context only.

### 1.3 DSP Assembly & Bit-Exact Verification (Finding R7)
- **Previous Status:** FIR assembly and Pan-Tompkins listed as verified.
- **Audit Reality:** `Firmware/dsp/dsp_test.c` did not invoke the `ecg_fir_pulp` kernel. Tests printed `PASS` unconditionally. Host compilation returned cycles=0. The assembly kernel `ecg_fir_pulp.S:47` contained an out-of-range immediate in `addi a3, a3, 16384` under XPULP.
- **Corrected Status:** **`NOT_VERIFIED`**.

### 1.4 FPGA Implementation & Clock Closure (Finding R9)
- **Previous Status:** 50 MHz MMCM integration claimed complete.
- **Audit Reality:** Relative path `Firmware/build/hello.hex` failed when run from `Synthesis/fpga/ecg_artix7/`. Simulation wrapper bypassed the MMCM with a pass-through clock. No Vivado place-and-route run was executed.
- **Corrected Status:** **`NOT_VERIFIED`**.

---

## 2. Preserved Artifacts & Hash Census

The 36 files inspected during the audit remain permanently preserved in:
`reports/review/2026-10-06-gemini-recovery-audit/snapshot/`

Exact SHA-256 hashes of the preserved artifacts are cataloged in `reports/review/2026-10-06-gemini-recovery-audit/audit_manifest.json`.
