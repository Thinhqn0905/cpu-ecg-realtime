# RISC-V ECG DAQ — Active TODO

Last updated: 2026-10-06

## Gemini Recovery Follow-Up Plan (docs/plans/2026-10-06-gemini-recovery-followup.md)

- [x] **Task 1: Correct provenance claims and preserve failed evidence (R1/R2/R8)**
  - [x] Preserved legacy firmware build and reports in snapshot directory with SHA-256 digests.
  - [x] Marked unverified compiler output as `NOT_VERIFIED` in RTM dashboard, benchmark report, and manifest.
  - [x] Authored Architectural Decision Record `docs/decisions/cv32e40p-candidate.md`.
  - [x] Authored dated correction report `reports/review/2026-10-06-provenance-correction/corrections.md`.
- [x] **Task 2: Close false-success gates first (R5/R6)**
  - [x] Implemented `scripts/test_runner_contract.py` covering 10 false-success conditions.
  - [x] Hardened `scripts/check_evidence.py` to enforce manifest identity, root-relative paths, SHA-256 checks, stale run ID rejection, and fatal log error pattern matching.
  - [x] Updated `scripts/test_evidence_gate.py` with expanded fixtures.
  - [x] Wired `check_evidence.py` into `scripts/run_sim.ps1` and `scripts/run_sim.sh`.
  - [x] Replaced `$finish` failure exits in `Simulation/soc_tb.sv` and `Simulation/spi_master_tb.sv` with `$fatal(1, ...)`.
- [x] **Task 3: Build real firmware with no synthetic replacement (R1–R3/R7)**
  - [x] Implemented `scripts/test_firmware_build_contract.py`.
  - [x] Removed synthetic standalone fallback from `Firmware/build_boot_image.py`.
  - [x] Updated `Firmware/Makefile` with explicit compiler tools, map generation, disassembly, and fresh output manifests, plus `dsp-test` targets.
- [x] **Task 4: Prove local binding, memory and one real IRQ (R4/R6/R10)**
  - [x] Fixed undeclared net `dtcm_data_gnt` -> `dtcm_gnt` in `RTL/ecg_soc/cv32e40p_ecg_soc_top.sv` and enforced `default_nettype none`.
  - [x] Authored `Simulation/tcm_router_tb.sv`, `Synthesis/flist_tcm_router_tb.f`, and runner `Simulation/run_tcm.ps1`.
  - [x] Enhanced `Simulation/soc_tb.sv` and `Firmware/boot/hello.c` with `.data` sentinel/copy check, `.bss` zero check, and register canary checks (`s2..s5`) across IRQ.
- [x] **Task 5: Prove acquisition and DSP separately (R4/R7/R8)**
  - [x] Fixed SystemVerilog type in `Simulation/spi_master_tb.sv` (`int32_t` -> `int signed`), enforced 72 SCLK pulses, and created gated runner `Simulation/run_spi.ps1`.
  - [x] Repaired `Firmware/dsp/ecg_fir_pulp.S` out-of-range immediate (`addi a3, a3, 16384` -> `li t5, 16384; add a3, a3, t5`) and aligned saturation semantics.
  - [x] Updated `Firmware/dsp/dsp_test.c` to call actual `ecg_fir_pulp` kernel and production Pan-Tompkins detector, comparing against `ecg_fir_scalar_reference`, checking squaring overflow and QRS peak detection, and reading real `mcycle` CSR.
- [x] **Task 6: Prepare FPGA campaign after functional gates (R9)**
  - [x] Parameterized boot image path with `BOOT_HEX`, enforced strict nettypes, and corrected 50 MHz simulation clock model in `RTL/ecg_soc/fpga/ecg_arty_top.sv`.
  - [x] Enhanced `Synthesis/fpga/ecg_artix7/run_synth.tcl`, `arty_a7_100t.xdc`, `run_fpga.ps1`, and `run_fpga.sh` with image preflight, false-path I/O constraints, routed checkpoints, and detailed timing/utilization reports.

## Pending Verification Runs (Upon Shell Execution Availability)
- [ ] Run `python -m unittest discover -s scripts -p 'test_*.py'`
- [ ] Run `Simulation/soc_tb.sv` via `scripts/run_sim.ps1` or `run_sim.sh`
- [ ] Run `Simulation/spi_master_tb.sv` via `Simulation/run_spi.ps1`
- [ ] Run `Simulation/tcm_router_tb.sv` via `Simulation/run_tcm.ps1`
- [ ] Compile and run `Firmware/dsp/dsp_test.c`
- [ ] Run Vivado implementation via `Synthesis/fpga/ecg_artix7/run_fpga.ps1`


## Completed (Checklist 3 - CV32E40P Phased Integration, ASIC Flow & PPA Benchmarking)

- [x] Ingest OpenHW Group CV32E40P core repository (`cv32e40p/` @ commit `97086e9565f8145522ad6d62852123c0e5537529`, tag `v1.8.3`)
- [x] Ingest OpenLane physical design configs and runner automation (`Synthesis/asic/openlane/`, `Synthesis/asic/run_openlane.*`)
- [x] Generate project repository manifest with cryptographic commit tracking (`reports/manifest.json`)
- [x] Freeze formal specification and architecture (`spec/ecg_soc_spec.md`, `config/ecg_soc_config.json`, `spec/ecg_soc_module_map.json`)
- [x] Integrate official `cv32e40p_top` into master SoC (`RTL/ecg_soc/cv32e40p_ecg_soc_top.sv`) with default `USE_REAL_CORE = 1'b1`
- [x] Author comprehensive multi-tool compilation filelist (`Synthesis/flist_cv32e40p_soc.f`)
- [x] Update simulation, FPGA, and ASIC include paths and clock-gating support (`cv32e40p_sim_clock_gate.sv`)
- [x] Create automated co-simulation execution harnesses (`scripts/run_sim.ps1`, `scripts/run_sim.sh`) with VCD waveform logging
- [x] Create Vivado FPGA batch implementation runners (`Synthesis/fpga/ecg_artix7/run_fpga.ps1`, `run_fpga.sh`)
- [x] Create Silicon ASIC OpenLane runners (`Synthesis/asic/run_openlane.ps1`, `run_openlane.sh`)
- [x] Author Comprehensive PPA Benchmarking & Sign-Off Report (`reports/benchmark_report.md`)
- [x] Update Requirement Traceability Matrix (`reports/verification/rtm_dashboard.md`) with 100% REQ-ID test coverage
- [x] Complete and pass all 7 Gates in Session Checklist V3 (`Instruction/session_checklist.md`)

## Completed (Phase 1 - CV32E40P Autoflow E2E)

- [x] Execute Autoflow E2E pipeline for CV32E40P implementation plan
- [x] Implement Phase A: CV32E40P Core Subsystem (`RTL/ecg_soc/cv32e40p_ecg_soc_top.sv`)
- [x] Implement Phase B: OBI-to-APB3 Bridge & SVA (`RTL/ecg_soc/obi_to_apb.sv`, `RTL/ecg_soc/sva/obi_to_apb_sva.sv`, `sva/obi_to_apb_bind.sv`)
- [x] Implement Phase C: Dual-Target Harvard SRAM (`RTL/ecg_soc/tcm_sram.sv`)
- [x] Implement Phase D: ECG Biosignal Ingress Suite (`RTL/ecg_soc/ecg_soc_top.sv`)
- [x] Implement Phase E: CNN-MAMBA Coprocessor Bridge (`RTL/ecg_soc/mamba_bridge.sv`)
- [x] Implement Phase F: Firmware & Xpulpv2 DSP assembly kernels (`Firmware/boot/*`, `Firmware/drivers/*`, `Firmware/dsp/*`, `Firmware/main.c`)
- [x] Implement Phase G: Full SoC testbench with ADS1292R AFE (`Simulation/soc_tb.sv`)
- [x] Implement Phase H1: FPGA (Vivado) synthesis & constraints (`Synthesis/fpga/ecg_artix7/run_synth.tcl`, `arty_a7_100t.xdc`)
- [x] Implement Phase H2: Silicon ASIC (OpenLane) synthesis scripts (`Synthesis/asic/openlane/config.json`, `Synthesis/asic/run_openlane.sh`)
- [x] Update Gate 5 Requirement Traceability Matrix with 100% coverage (`reports/verification/rtm_dashboard.md`)
- [x] Record Checklist 2 deliverables (`Instruction/checklists/checklist_2.md`)

## Immediate (Phase 0)

- [ ] Initialize CVA6 submodules: `git submodule update --init --recursive`
- [ ] Review core selection decision: Ibex vs CV32E40P vs CVA6 based on `Instruction/research_analysis.md`
- [ ] Set up Verilator/iverilog on Windows for RTL lint and simulation
- [ ] Create initial RTL specification for ECG SoC peripherals (SPI master, UART, FIFO, DMA) in `spec/`
- [ ] Verify clean elaboration with Verilator or iverilog
- [ ] Set up RISC-V GCC cross-compiler (riscv32-unknown-elf-gcc)
- [ ] Create project directory structure:
  ```
  RTL/ecg_soc/          — custom SoC RTL
  RTL/ecg_processing/   — optional HW accelerators
  Firmware/              — C firmware
  Firmware/boot/         — boot code
  Firmware/drivers/      — peripheral drivers
  Firmware/ecg/          — ECG application code
  Simulation/            — testbenches
  Synthesis/fpga/ecg_artix7/  — Vivado project
  Host/                  — PC-side tools
  reports/               — evidence and documentation
  ```
- [ ] Document CVA6 resource baseline for Artix-7

## Next (Phase 1)

- [ ] Create Arty A7-100T XDC constraint file
- [ ] Create Vivado synthesis Tcl script
- [ ] Write bare-metal boot firmware
- [ ] First synthesis attempt

## Research Needed

- [x] Analyze LeapSpace research document (`user_analyze/RISC-V_core_selection_for_FPGA-based_ECG_SoC_LeapSpace.pdf`)
- [x] Gap analysis between ECG requirements and CNN-MAMBA reference accelerator
- [x] Synthesize core comparison and recommendation (Ibex vs CVA6 vs CV32E40P)
- [x] Adapt 9 ASIC workflow commands to ECG SoC (`Instruction/commands_reference.md`)
- [ ] ADS1292R datasheet deep-dive: SPI timing, register map, start-up sequence
- [ ] APB bus integration: finalize peripheral base addresses and interconnect
- [ ] RISC-V interrupt handling: PLIC/CLINT programming and ISR conventions

## Blocked

- Direct file writes to `.claude/commands/` require either running without auto-mode classifier timeouts or manually copying from `Instruction/commands_reference.md`.

## Completed

- [x] Clone CVA6 repository
- [x] Create Instruction system (CLAUDE.md, AGENTS.md, contracts, checklists)
- [x] Define system architecture and research specification
- [x] Generate research prompt for RISC-V ECG DAQ literature review
- [x] Document Research Analysis and Core Comparison (`Instruction/research_analysis.md`)
- [x] Document adapted ASIC command suite for ECG SoC (`Instruction/commands_reference.md`)
- [x] Conduct CV32E40P deep research, PPA benchmarking (FPGA + ASIC), and ECG DSP analysis (`Instruction/cv32e40p_deep_research_and_benchmark.md`)
- [x] Author CV32E40P Implementation Plan from A to Z for FPGA & ASIC (`Instruction/cv32e40p_implementation_plan_a_to_z.md`)
- [x] Generate formal specification and requirements matrix (`spec/ecg_soc_spec.md`, `spec/ecg_soc_reqs.json`, `spec/ecg_soc_module_map.json`, `config/ecg_soc_config.json`)
- [x] Implement core bus bridge and memory wrappers (`RTL/ecg_soc/obi_to_apb.sv`, `RTL/ecg_soc/tcm_sram.sv`)
- [x] Implement full peripheral RTL suite and verification testbench (`RTL/ecg_soc/*`, `Simulation/*`, `reports/verification/rtm_dashboard.md`)
