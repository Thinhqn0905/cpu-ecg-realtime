# Session Checklist V7 (checklist_7): Gemini Recovery Follow-up Execution

Worktree: E:\ResearchOnWork\RISC_V_CORE
Goal: Execute follow-up plan (docs/plans/2026-10-06-gemini-recovery-followup.md) to close false-success gates, produce verified compiler provenance, prove real CPU boot/data/IRQ, and validate 72-bit SPI / DSP / FPGA.
Claim contract: Instruction/claim_integrity.md and Instruction/evidence_contract.md.
Previous checklist preserved: Instruction/archive/20261006_1200/session_checklist.md.

---

## Task 1: Correct provenance claims and preserve failed evidence (R1/R2/R8)
- [complete] **Task 7.1.1**: Preserve current Firmware/build and reports with hashes in `reports/review/2026-10-06-gemini-recovery-audit/snapshot/` and `audit_manifest.json`.
- [complete] **Task 7.1.2**: Record GCC compilation/boot as `NOT_VERIFIED`; record hash mismatch as artifact-integrity violation in `reports/benchmark_report.md` and `reports/manifest.json`.
- [complete] **Task 7.1.3**: Update `reports/verification/rtm_dashboard.md` to remove premature promotion of historical 24-bit SPI smoke test to new 72-bit requirements (`REQ-SPI-001..003` -> `NOT_VERIFIED`).
- [complete] **Task 7.1.4**: Author Architectural Decision Record `docs/decisions/cv32e40p-candidate.md` documenting candidate status, OBI/APB/IRQ map, upstream CVA6 preservation, and missing CVA6 resource comparison.
- [complete] **Task 7.1.5**: Author dated correction report `reports/review/2026-10-06-provenance-correction/corrections.md`.

## Task 2: Close false-success gates first (R5/R6)
- [complete] **Task 7.2.1**: Implement comprehensive test runner contract tests (`scripts/test_runner_contract.py`) covering zero-exit log missing IRQ, COMPLETE-only, FAIL outside TC event, corrupted hash, old run-id, empty log, duplicate case, child failure and timeout.
- [complete] **Task 7.2.2**: Update `scripts/check_evidence.py` to enforce manifest identity, root-relative paths, source/filelist digest, compiler/simulator versions, boot ELF/image digest, and fail on missing/mismatched SHA-256 or stale run_id.
- [complete] **Task 7.2.3**: Update `scripts/test_evidence_gate.py` with expanded fixtures and verify rejection behavior.
- [complete] **Task 7.2.4**: Wire `check_evidence.py` into `scripts/run_sim.ps1` and `scripts/run_sim.sh` before latest/SUCCESS update; propagate exit code and preserve failure manifests.
- [complete] **Task 7.2.5**: Update `Simulation/soc_tb.sv` and `Simulation/spi_master_tb.sv` to invoke `$fatal(1, ...)` on incomplete testcase census or failure count > 0, ensuring simulator process exits non-zero.

## Task 3: Build real firmware with no synthetic replacement (R1–R3/R7)
- [complete] **Task 7.3.1**: Author `scripts/test_firmware_build_contract.py` asserting rejection of missing compiler and failure without emitting success artifacts.
- [complete] **Task 7.3.2**: Remove automatic standalone/handwritten fallback from `Firmware/build_boot_image.py`.
- [complete] **Task 7.3.3**: Update `Firmware/Makefile` with explicit compiler tools, map generation, disassembly, and fresh output manifests, plus `dsp-test` targets.
- [pending] **Task 7.3.4**: Compile real firmware when toolchain is available in terminal; validate ELF segments, vector targets, and SHA-256 digests.

## Task 4: Prove local binding, memory and one real IRQ (R4/R6/R10)
- [complete] **Task 7.4.1**: Fix undeclared `dtcm_data_gnt` to `dtcm_gnt` in `RTL/ecg_soc/cv32e40p_ecg_soc_top.sv` and enforce strict undeclared net rules.
- [complete] **Task 7.4.2**: Author `Simulation/tcm_router_tb.sv`, filelist `Synthesis/flist_tcm_router_tb.f`, and runner `Simulation/run_tcm.ps1` testing dual-port TCM boundaries, byte-enables, and fatal checks on corrupt/missing images.
- [complete] **Task 7.4.3**: Enhance `Simulation/soc_tb.sv` and `Firmware/boot/hello.c` with independent data copy checks (`g_data_array`), `.bss` zero check (`g_bss_zero_check`), register canary checks (`s2..s5`) across IRQ, and clean `mret` verification.
- [pending] **Task 7.4.4**: Execute full SoC simulation when simulator is available in terminal; verify 5-case test census with zero exit.

## Task 5: Prove acquisition and DSP separately (R4/R7/R8)
- [complete] **Task 7.5.1**: Fix SystemVerilog type in `Simulation/spi_master_tb.sv` (`int32_t` -> `int signed`), enforce exact 72 SCLK pulses, and create gated runner `Simulation/run_spi.ps1`.
- [complete] **Task 7.5.2**: Repair `Firmware/dsp/ecg_fir_pulp.S` out-of-range immediate (`addi a3, a3, 16384` -> `li t5, 16384; add a3, a3, t5`) and align saturation semantics with scalar reference.
- [complete] **Task 7.5.3**: Update `Firmware/dsp/dsp_test.c` to call actual `ecg_fir_pulp` kernel and production Pan-Tompkins detector, comparing against `ecg_fir_scalar_reference`, checking squaring overflow and QRS peak detection, and reading real `mcycle` CSR.

## Task 6: Prepare FPGA campaign after functional gates (R9)
- [complete] **Task 7.6.1**: Fix boot image path in `RTL/ecg_soc/fpga/ecg_arty_top.sv` to be parameterized with `BOOT_HEX`, enforce strict nettypes, and correct simulation clock model.
- [complete] **Task 7.6.2**: Enhance `Synthesis/fpga/ecg_artix7/run_synth.tcl`, `arty_a7_100t.xdc`, `run_fpga.ps1`, and `run_fpga.sh` with image preflight, false-path I/O constraints, routed checkpoints, and detailed timing/utilization reports.
- [pending] **Task 7.6.3**: Execute Vivado FPGA implementation when EDA tools are available in terminal; verify timing closure and bitstream generation.
