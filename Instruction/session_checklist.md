# Session Checklist V9 (checklist_9): Tri-Modal Real-Time ECG DSP & ResUMamba-30K Implementation

Worktree: E:\ResearchOnWork\RISC_V_CORE
Goal: Implement, verify, and physically synthesize on Artix-7 FPGA a unified tri-modal biosignal processing architecture combining (1) pure in-core CV32E40P Xpulpv2 software DSP execution, (2) dedicated streaming hardware coprocessor offload for heavy 128-tap DiagSSM1D FIR layers, and (3) an energy-efficient hierarchical cascade triggering deep ResUMamba-30K arrhythmia classification upon classical Pan-Tompkins ectopic detection, per `docs/plans/2026-10-06-tri-modal-dsp-resumamba-plan.md`.
Claim contract: Instruction/claim_integrity.md and Instruction/evidence_contract.md.
Previous checklist preserved: Instruction/archive/20261006_1600/session_checklist.md.

---

## Task 9.1: Memory Architecture Expansion & Quantization Pipeline
- [in_progress] **Task 9.1.1**: Expand D-TCM to 128 KB (`0x0001_0000` - `0x0002_FFFF`) in `RTL/ecg_soc/tcm_sram.sv`, `cv32e40p_ecg_soc_top.sv`, and `Firmware/boot/link.ld`; add `TC-TCM-006` in `Simulation/tcm_router_tb.sv` and verify with `Simulation/run_tcm.ps1`.
- [pending] **Task 9.1.2**: Extract ResUMamba-30K (`resumamba_30k.pt`) parameters, quantize to INT8 weights and INT16 FIR taps via `scripts/quantize_resumamba.py`, generate `Firmware/dsp/resumamba_weights.h`, and verify numerical parity ($> 98\%$ accuracy, MAE $< 0.05$) via `scripts/test_quantization_parity.py`.

## Task 9.2: Method 1 — In-Core Software ResUMamba-30K Implementation
- [pending] **Task 9.2.1**: Implement fixed-point biosignal conditioning library (`signal_ops.h`, `signal_ops.c`) supporting 0.5–30 Hz bandpass filtering and per-lead Z-score normalization; verify parity via `Firmware/dsp/test_signal_ops.c`.
- [pending] **Task 9.2.2**: Implement in-core quantized ResUMamba-30K inference engine (`resumamba_infer.h`, `resumamba_infer.c`, `resumamba_kernels_pulp.S`); verify layer parity and $< 20,000,000$ cycle latency ($< 400\text{ ms}$ @ 50 MHz) via `Firmware/dsp/test_resumamba_infer.c`.

## Task 9.3: Method 2 — Hardware Coprocessor Offload Bridge
- [pending] **Task 9.3.1**: Upgrade `RTL/ecg_soc/mamba_bridge.sv` with APB register control and streaming DMA FIFO; verify via `Simulation/mamba_bridge_tb.sv`.
- [pending] **Task 9.3.2**: Implement 128-tap DiagSSM1D FIR sidecar accelerator (`RTL/ecg_soc/mamba_fir_sidecar.sv`); verify latency ($< 80\text{ ms}$) and output match via `Simulation/mamba_fir_tb.sv`.

## Task 9.4: Method 3 — Hierarchical Two-Stage Cascade Integration
- [pending] **Task 9.4.1**: Implement hierarchical state machine in firmware (`Firmware/src/main.c`); verify Stage 1 Pan-Tompkins anomaly detection triggering Stage 2 ResUMamba inference in `Simulation/soc_tb.sv`.

## Task 9.5: Physical FPGA Implementation & Timing Closure on Artix-7
- [pending] **Task 9.5.1**: Update Vivado filelist `Synthesis/flist_cv32e40p_soc.f` and run physical synthesis/implementation via `Synthesis/fpga/ecg_artix7/run_fpga.ps1`.
- [pending] **Task 9.5.2**: Verify routed timing closure ($WNS \ge 0$, $WHS \ge 0$), utilization, and bitstream generation.
- [pending] **Task 9.5.3**: Update Requirements Traceability Matrix (`reports/verification/rtm_dashboard.md`), benchmark report, and `reports/manifest.json`.
