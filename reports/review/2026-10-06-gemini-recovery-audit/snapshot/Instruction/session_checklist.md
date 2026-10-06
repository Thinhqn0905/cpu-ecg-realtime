# Session Checklist V5 (checklist_5): Gemini Audit Recovery Execution (Tasks 1-5)

Worktree: E:\ResearchOnWork\RISC_V_CORE
Goal: Execute recovery plan (docs/plans/2026-10-06-gemini-audit-recovery.md) to withdraw unsupported claims, fix false-success runners, repair bindings, and demonstrate real CV32E40P firmware boot and IRQ proof.
Claim Integrity: Mandatory adherence to `Instruction/claim_integrity.md` and `Instruction/evidence_contract.md`.

---

## Task 1: Withdraw unsupported claims and stop false-success gates
- [complete] **Task 5.1.1**: Preserve and correct reports (`reports/benchmark_report.md`, `reports/manifest.json`, `reports/verification/rtm_dashboard.md`), setting unmeasured timing/PPA/DSP/clinical claims to `NOT_VERIFIED` with dated corrections.
- [complete] **Task 5.1.2**: Author Python evidence gate validation tests (`scripts/test_evidence_gate.py`) verifying rejection of empty logs, missing tools, child nonzero exit codes, missing testcases, and duplicate testcases per `accepted_run` condition.
- [complete] **Task 5.1.3**: Implement evidence validator (`scripts/check_evidence.py`).
- [complete] **Task 5.1.4**: Repair simulation and synthesis runner scripts (`scripts/run_sim.ps1`, `scripts/run_sim.sh`, `Synthesis/fpga/ecg_artix7/run_fpga.ps1`, `run_fpga.sh`, `Synthesis/asic/run_openlane.ps1`) to strictly propagate native exit codes, enforce `set -euo pipefail`, and stop reporting false success when tools are missing or failed.
- [in_progress] **Task 5.1.5**: Execute `python -m unittest discover -s scripts -p 'test_*.py'` and verify evidence gate unit tests pass (pending shell execution environment availability).

## Task 2: Correct bindings and demonstrate real firmware boot
- [complete] **Task 5.2.1**: Audit and repair port and net bindings in `RTL/ecg_soc/cv32e40p_ecg_soc_top.sv`, `ecg_soc_top.sv`, and `Simulation/soc_tb.sv` matching actual peripheral and AFE model declarations; disable MAMBA from baseline bus array.
- [complete] **Task 5.2.2**: Repair memory subsystem in `RTL/ecg_soc/tcm_sram.sv` and data router in `cv32e40p_ecg_soc_top.sv` to support real memory image loading, allow CPU data reads of rodata/data load image from I-TCM address space, remove D-TCM aliasing, and handle OBI byte enables properly.
- [complete] **Task 5.2.3**: Update linker script `Firmware/boot/link.ld` and startup code `Firmware/boot/crt0.S` with fixed-width 4-byte vector slots, interrupt context save/restore with `mret`, and global `mstatus.MIE` enabling.
- [complete] **Task 5.2.4**: Create minimal real firmware (`Firmware/boot/hello.c`) and build infrastructure (`Firmware/Makefile`).
- [complete] **Task 5.2.5**: Compile hello firmware with RISC-V GCC into ELF, map, disassembly, and Verilog hex image (`Firmware/build/hello.hex`).
- [in_progress] **Task 5.2.6**: Run self-checking simulation (`Simulation/soc_tb.sv` via `scripts/run_sim.ps1`) confirming real CPU fetches and executes firmware, emits exact UART boot marker, and handles one IRQ cleanly (pending shell execution environment availability).

## Task 3: Prove one complete AFE frame before DSP
- [complete] **Task 5.3.1**: Repair SPI master hardware (`RTL/ecg_soc/spi_master.sv` and `spi_master_apb.sv`) to maintain continuous CS# low across all 72 bits of biopotential frame.
- [complete] **Task 5.3.2**: Add dedicated Status, CH1, CH2 APB registers and direct streaming outputs to DMA.
- [complete] **Task 5.3.3**: Update behavioral ADS1292R model (`Simulation/ads1292r_model.sv`) with exact golden frame payload (`0xC00000`, `0x123456`, `0xFEDCBA`) and race-free Mode 1 timing.
- [complete] **Task 5.3.4**: Repair firmware driver (`Firmware/drivers/ads1292r.c` and `ads1292r.h`) with 72-bit auto-capture and signed sign extension.
- [complete] **Task 5.3.5**: Author self-checking testbench (`Simulation/spi_master_tb.sv`) verifying continuous CS# and golden frame decoding.

## Task 4: Validate DSP arithmetic and measure cycles honestly
- [complete] **Task 5.4.1**: Repair 45-tap FIR assembly kernel (`Firmware/dsp/ecg_fir_pulp.S`) to use accumulating dot product `pv.sdotsp.h` with portable RV32IM fallback.
- [complete] **Task 5.4.2**: Repair Pan-Tompkins QRS detector (`Firmware/dsp/pan_tompkins.c`) with 64-bit widening to prevent 32-bit squaring overflow.
- [complete] **Task 5.4.3**: Author bit-exact scalar reference (`Firmware/dsp/fir_reference.c`).
- [complete] **Task 5.4.4**: Author verification suite (`Firmware/dsp/dsp_test.c`) measuring honest execution cycles via `mcycle` CSR.

## Task 5: Make the FPGA clock and routed evidence real
- [complete] **Task 5.5.1**: Correct board physical clock constraint in `Synthesis/fpga/ecg_artix7/arty_a7_100t.xdc` to 100 MHz (10.00 ns period) on Pin E3.
- [complete] **Task 5.5.2**: Implement FPGA board top wrapper (`RTL/ecg_soc/fpga/ecg_arty_top.sv`) with 7-Series `MMCME2_BASE` (100 MHz to 50 MHz) and synchronous reset release.
- [complete] **Task 5.5.3**: Update Vivado synthesis script (`Synthesis/fpga/ecg_artix7/run_synth.tcl`) to target `ecg_arty_top` with MMCM sources.
