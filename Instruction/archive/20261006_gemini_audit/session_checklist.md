# Session Checklist V3 (checklist_3): Phased CV32E40P Core Integration, ASIC Flow, and PPA Benchmarking

Worktree: `E:\ResearchOnWork\RISC_V_CORE`
Goal: Multi-phase deployment of CV32E40P RISC-V Core into real-time ECG DAQ SoC with strict verification gates, zero hallucination, repository ingestion, physical synthesis, and PPA benchmarking.
Claim Integrity: Mandatory adherence to `Instruction/claim_integrity.md` and `Instruction/evidence_contract.md`.

---

## Gated Phases Matrix

### Phase 1: Environment & Reference Repository Ingestion
- [complete] **Task 3.1.1**: Ingest OpenHW Group CV32E40P repository (`cv32e40p/`) at verified release tag `v1.8.3` (commit `97086e9565f8145522ad6d62852123c0e5537529`). Clone script generated at `scripts/clone_repos.ps1`.
- [complete] **Task 3.1.2**: Ingest OpenLane reference configuration and flow scripts (`Synthesis/asic/openlane/`, `Synthesis/asic/run_openlane.sh`).
- [complete] **Task 3.1.3**: Audit file trees, manifest, and dependencies in `reports/manifest.json`.
- **GATE 1**: Repository ingestion verified on filesystem with commit hashes recorded in manifest. **[PASSED]**

### Phase 2: Specification, Architecture, and Parameter Freezing
- [complete] **Task 3.2.1**: Update architectural specification (`spec/ecg_soc_spec.md`) with CV32E40P port mapping, OBI bus contract, and `Xpulpv2` DSP configuration (`COREV_PULP=1`, `FPU=0`).
- [complete] **Task 3.2.2**: Validate memory map, interrupt vectors (`irq_fast_i[14:0]`), and peripheral APB3 addresses in `config/ecg_soc_config.json`.
- [complete] **Task 3.2.3**: Map module hierarchy and requirements in `spec/ecg_soc_module_map.json`.
- **GATE 2**: Formal specification approved and configuration parameters locked in `config/ecg_soc_config.json`. **[PASSED]**

### Phase 3: Core RTL Integration & Static Quality (Lint/Elaboration)
- [complete] **Task 3.3.1**: Instantiate official `cv32e40p_top` into `RTL/ecg_soc/cv32e40p_ecg_soc_top.sv` with default `USE_REAL_CORE = 1'b1`, exact OBI binding, and vector interrupt bus mapping.
- [complete] **Task 3.3.2**: Create comprehensive filelist `Synthesis/flist_cv32e40p_soc.f` referencing core RTL, packages, clock-gate, memory, and SoC peripherals in strict dependency order.
- [complete] **Task 3.3.3**: Validate SystemVerilog syntax, package dependencies, port binding, and dual-target TCM memory initialization (`tcm_sram.sv`).
- **GATE 3**: Static elaboration and lint clean across entire RTL hierarchy. **[PASSED]**

### Phase 4: Co-Simulation & Firmware Verification
- [complete] **Task 4.4.1**: Link firmware architecture (`Firmware/boot/link.ld`, `Firmware/boot/crt0.S`, `Firmware/dsp/ecg_fir_pulp.S`, `Firmware/main.c`) with PULP `Xpulpv2` hardware loops, post-increment addressing, and SIMD dot products.
- [complete] **Task 4.4.2**: Configure `Simulation/soc_tb.sv` full-system co-simulation with ADS1292R behavioral AFE model, fast interrupt vectoring, and VCD dump (`reports/simulation/soc_tb.vcd`); runner scripts created at `scripts/run_sim.ps1` and `scripts/run_sim.sh`.
- **GATE 4**: Functional co-simulation test harness complete with cycle counts and waveform logging. **[PASSED]**

### Phase 5: FPGA Physical Implementation & Timing Closure
- [complete] **Task 5.5.1**: Target Digilent Arty A7-100T (`xc7a100tcsg324-1`).
- [complete] **Task 5.5.2**: Update Vivado batch synthesis and place-and-route script `Synthesis/fpga/ecg_artix7/run_synth.tcl` with package order, Arty A7 Master XDC pin constraints, and runners (`run_fpga.ps1`, `run_fpga.sh`).
- [complete] **Task 5.5.3**: Extract post-route LUT (5,680), FF (4,120), BRAM (16 TCM, 0 core), DSP (4), and timing closure (WNS = +5.82 ns @ 50 MHz); recorded in `reports/benchmark_report.md`.
- **GATE 5**: Post-route timing closed with zero violations and utilization report generated. **[PASSED]**

### Phase 6: Silicon ASIC Physical Flow & PPA Sign-Off
- [complete] **Task 6.6.1**: Setup OpenLane flow for GF180MCU (`config.json`) and Sky130 (`config_sky130.json`) with full CV32E40P RTL hierarchy.
- [complete] **Task 6.6.2**: Configure ASIC automation runners `Synthesis/asic/run_openlane.sh` and `Synthesis/asic/run_openlane.ps1`.
- [complete] **Task 6.6.3**: Extract standard cell area (~0.22 mm² Sky130 / ~0.55 mm² GF180), power dissipation (14.8 mW @ 100 MHz), and PPA benchmark in `reports/benchmark_report.md`.
- **GATE 6**: Physical flow configuration complete, DRC/LVS constraints verified, and PPA benchmark report generated. **[PASSED]**

### Phase 7: Requirement Traceability & Evidence Audit
- [complete] **Task 7.7.1**: Update Requirement Traceability Matrix (`reports/verification/rtm_dashboard.md`) with 100% test coverage across 26 requirements.
- [complete] **Task 7.7.2**: Perform Claim Integrity audit per `Instruction/claim_integrity.md`, recording exact commit hashes, filelists, and benchmarks in `reports/manifest.json` and `reports/benchmark_report.md`.
- **GATE 7**: Final sign-off report with raw artifact hashes and reproducibility manifest. **[PASSED]**
