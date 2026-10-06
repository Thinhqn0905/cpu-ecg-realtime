# Master Orchestrator — /autoflow
# Target: CV32E40P Real-Time ECG SoC & CNN-MAMBA Coprocessor
# ASIC & FPGA Dual-Track Implementation Flow

This engine orchestrates the end-to-end ASIC and FPGA design flow for the CV32E40P-based ECG SoC:
1. Phase 0: Specification definition (`spec/ecg_soc_spec.md`)
2. Phase 1: Requirements parsing & module mapping (`spec/ecg_soc_reqs.json`, `spec/ecg_soc_module_map.json`)
3. Phase 2: Configuration & constraint validation (`config/ecg_soc_config.json`)
4. Phase 3a: SystemVerilog RTL generation & linting (`RTL/ecg_soc/`)
5. Phase 3b: SVA formal assertions (`RTL/ecg_soc/sva/`)
6. Phase 4: Self-checking testbench generation (`Simulation/`)
7. Phase 5: Verification & Requirement Traceability Matrix (`reports/verification/rtm_dashboard.md`)
8. Phase 6: Final specification & tapeout documentation (`docs/`)
9. Firmware: Bare-metal drivers & Xpulpv2 DSP assembly kernels (`Firmware/`)
10. Synthesis: Dual-track FPGA (Vivado) and ASIC (OpenLane GF180/Sky130) flows (`Synthesis/`)
