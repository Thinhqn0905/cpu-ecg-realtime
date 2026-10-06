# Tri-Modal Real-Time ECG DSP & ResUMamba-30K Architecture Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement, verify, and physically synthesize on Artix-7 FPGA a unified tri-modal biosignal processing architecture combining (1) pure in-core CV32E40P `Xpulpv2` software DSP execution, (2) dedicated streaming hardware coprocessor offload for heavy 128-tap DiagSSM1D FIR layers, and (3) an energy-efficient hierarchical cascade triggering deep ResUMamba-30K arrhythmia classification upon classical Pan-Tompkins ectopic detection.

**Architecture:**
- **Mode 1 (Pure In-Core Software):** CV32E40P processor core (RV32IMC + `Xpulpv2` DSP @ 50 MHz) executing INT8/INT16 quantized ResUMamba-30K across an expanded 128 KB D-TCM (`0x0001_0000 - 0x0002_FFFF`), achieving full-window inference in $< 400\text{ ms}$ ($< 1000\text{ ms}$ real-time stride deadline).
- **Mode 2 (Hardware Coprocessor Offload):** Streaming coprocessor bridge (`mamba_bridge.sv`) interfacing a 16×8 Fold-SIMD engine to offload the 128-tap bidirectional DiagSSM1D FIR filters and convolution layers, dropping CPU load to $< 1\%$ and execution latency to $< 180\text{ ms}$.
- **Mode 3 (Hierarchical Two-Stage Cascade):** Continuous ultra-low-power Stage-1 surveillance running 45-tap FIR bandpass filtering and Pan-Tompkins QRS/R-R interval analysis ($< 0.15\%$ CPU load); dynamically triggers Stage-2 ResUMamba-30K classification only upon detection of premature ventricular contractions (PVC), atrial ectopic beats, or abnormal R-R intervals.
- **AFE & Ingress Pipeline:** TI ADS1292R 24-bit 2-channel AFE $\to$ Autonomous 72-clock SPI Master (1.0 MHz Mode 1) $\to$ 12-byte packed Ping-Pong DMA Buffer Window $\to$ CV32E40P core interrupt vectoring.

**Tech Stack:**
- **Processor Core:** OpenHW Group CV32E40P (v1.8.3, RV32IMC + CORE-V `Xpulpv2`)
- **Firmware & DSP:** C99, RISC-V assembly (`pv.dotsp.h`, `p.mac`, `lp.setup`), Python quantization tools
- **Hardware & RTL:** SystemVerilog IEEE 1800-2017, AMBA APB3, Open Bus Interface (OBI)
- **Target Platform:** Xilinx Artix-7 `xc7a100tcsg324-1` (Digilent Arty A7-100T)
- **EDA & Toolchains:** Vivado 2023.2, Icarus Verilog 12.0 devel, `riscv32-unknown-elf-gcc`

---

## Technical Feasibility & Resource Budget

### 1. Compute & Latency Budget (10-Second Window, 1.0-Second Stride)

| Pipeline Component | Mathematical Workload | Compute Complexity | CV32E40P Load (@ 50 MHz) | Hardware Offload Latency |
| :--- | :--- | :--- | :--- | :--- |
| **ADS1292R SPI Ingress** | 250 SPS $\times$ 3 leads | Autonomous 72-clock SPI | $< 0.08\%$ CPU load | Autonomous DMA |
| **Preprocessing (BPF + Z)**| 0.5–30 Hz BPF, Z-Score | ~35 kMAC/s | $< 0.12\%$ CPU load | N/A (software native) |
| **Pan-Tompkins QRS (Stage 1)**| Derivative, Squaring, MWI | ~30 kMAC/s | $< 0.06\%$ CPU load | N/A (software native) |
| **ResUMamba Stem & ResU**| Conv1D ($k=9$) + U-Net | ~3.18 MMAC / window | ~105 ms | ~35 ms (Fold-SIMD) |
| **DiagSSM1D Path (2 blocks)**| 128-tap BiDir DW FIR | ~6.14 MMAC / window | ~205 ms | ~80 ms (Fold-SIMD) |
| **Context, Attention & Head**| AdaIN + MultiHeadAttn | ~2.48 MMAC / window | ~83 ms | ~35 ms (Fold-SIMD) |
| **Total ResUMamba-30K (Stage 2)**| 29,741 INT8 Parameters | **~11.80 MMAC / window** | **~393 ms (< 1000 ms)**| **~150 ms (< 1000 ms)** |

### 2. Artix-7 100T FPGA Resource Budget

| FPGA Primitive | Current Baseline (Run 20261006_071047) | Tri-Modal Target (With 128KB TCM & Mamba Bridge) | Total Available on xc7a100t | Utilization Margin |
| :--- | :---: | :---: | :---: | :---: |
| **Slice LUTs** | 10,435 (16.46%) | ~18,500 (~29.2%) | 63,400 | > 70% Free |
| **Slice Registers (FF)**| 6,946 (5.48%) | ~12,000 (~9.5%) | 126,800 | > 90% Free |
| **Block RAM (BRAM36E1)**| 16 (11.85%) | 48 (35.56%) | 135 | > 64% Free |
| **DSP48E1 Slices** | 7 (2.92%) | 24 (10.00%) | 240 | > 90% Free |

---

## Detailed Task Breakdown

### Phase 1: Memory Architecture Expansion & Quantization Pipeline

#### Task 1: Expand D-TCM to 128 KB on Artix-7
- **Files:**
  - Modify: `RTL/ecg_soc/tcm_sram.sv` (parameterize `DEPTH` and address width)
  - Modify: `RTL/ecg_soc/cv32e40p_ecg_soc_top.sv:180-230` (decode D-TCM range `0x0001_0000 - 0x0002_FFFF`)
  - Modify: `Firmware/boot/link.ld:15-25` (update `D_TCM` length to `0x20000` = 128 KB, stack pointer to `0x0002_FFF0`)
  - Test: `Simulation/tcm_router_tb.sv`

- **Step 1: Write failing test in `Simulation/tcm_router_tb.sv`**
  Add `TC-TCM-006` verifying read/write access to address `0x0002_FFFC` (top of 128 KB D-TCM window).
- **Step 2: Run test to verify it fails**
  Run: `powershell -File Simulation/run_tcm.ps1`
  Expected: FAIL with unmapped or out-of-range address.
- **Step 3: Implement minimal RTL & linker script changes**
  Update `tcm_sram.sv` memory depth to `32768` words (128 KB) and address mask in `cv32e40p_ecg_soc_top.sv`.
- **Step 4: Run test to verify it passes**
  Run: `powershell -File Simulation/run_tcm.ps1`
  Expected: `TC-TCM-001` through `TC-TCM-006` PASS.
- **Step 5: Commit**
  `git commit -m "feat(mem): expand D-TCM to 128 KB for ResUMamba activation storage"`

---

#### Task 2: Quantize ResUMamba-30K Checkpoint to INT8/INT16 C Tables
- **Files:**
  - Create: `scripts/quantize_resumamba.py`
  - Input: `E:\ResearchOnWork\Backup\PhD_VNU\checkpoints_pt\resumamba_30k.pt`
  - Output: `Firmware/dsp/resumamba_weights.h` & `Firmware/dsp/resumamba_bias.h`
  - Test: `scripts/test_quantization_parity.py`

- **Step 1: Write test verifying numerical parity of quantized model vs FP32**
  Author `scripts/test_quantization_parity.py` comparing Python INT8 simulated forward pass against `resumamba_30k.pt` outputs on synthetic ECG test records.
- **Step 2: Run test to verify it fails**
  Run: `python scripts/test_quantization_parity.py`
  Expected: FAIL with missing header or weights.
- **Step 3: Implement export script `scripts/quantize_resumamba.py`**
  Extract weights from `resumamba_30k.pt`, compute symmetric scale factors, quantize to `int8_t` weights and `int16_t` FIR kernel taps, and generate C arrays.
- **Step 4: Run test to verify parity**
  Run: `python scripts/test_quantization_parity.py`
  Expected: Max absolute probability error $< 0.05$, beat detection accuracy parity $> 98\%$.
- **Step 5: Commit**
  `git commit -m "feat(dsp): quantize ResUMamba-30K to INT8/INT16 and generate firmware headers"`

---

### Phase 2: Method 1 — In-Core Software ResUMamba-30K Implementation

#### Task 3: Biosignal Conditioning & Preprocessing Library
- **Files:**
  - Create: `Firmware/dsp/signal_ops.h` & `Firmware/dsp/signal_ops.c`
  - Test: `Firmware/dsp/test_signal_ops.c`

- **Step 1: Write failing unit test for signal conditioning**
  Verify 0.5–30 Hz bandpass filter, rational resampling, and per-lead Z-score normalization against Python `ecgr/signal_ops.py` golden vectors.
- **Step 2: Run test on host compiler**
  Run: `gcc -O2 -I Firmware/dsp Firmware/dsp/test_signal_ops.c Firmware/dsp/signal_ops.c -o build/test_signal_ops.exe && ./build/test_signal_ops.exe`
  Expected: FAIL.
- **Step 3: Implement `signal_ops.c`**
  Implement fixed-point Q1.15 cascaded biquad IIR / 45-tap FIR filter and running mean/standard deviation calculator.
- **Step 4: Run test to verify PASS**
  Run: `./build/test_signal_ops.exe`
  Expected: All checks PASS with MAE $< 10^{-3}$.
- **Step 5: Commit**
  `git commit -m "feat(firmware): implement fixed-point biosignal conditioning library"`

---

#### Task 4: In-Core ResUMamba-30K Layer Kernels with `Xpulpv2` Optimization
- **Files:**
  - Create: `Firmware/dsp/resumamba_infer.h` & `Firmware/dsp/resumamba_infer.c`
  - Create: `Firmware/dsp/resumamba_kernels_pulp.S` (assembly dot-product inner loop using `pv.dotsp.h`)
  - Test: `Firmware/dsp/test_resumamba_infer.c`

- **Step 1: Write failing unit test for ResUMamba-30K layers**
  Test individual layers: (a) Stem Conv1D, (b) ResU separable block, (c) 128-tap DiagSSM1D FIR, (d) AdaIN, (e) Multi-Head Attention, (f) Softmax head.
- **Step 2: Run test to verify failure**
  Run: `gcc -O2 -I Firmware/dsp Firmware/dsp/test_resumamba_infer.c -o build/test_infer.exe`
  Expected: Compilation error / unresolved symbols.
- **Step 3: Implement layer forward passes in `resumamba_infer.c`**
  Implement ping-pong tensor scratchpad buffers in D-TCM. Add assembly-optimized inner loop using hardware loops and SIMD MAC.
- **Step 4: Run test to verify layer outputs match Python golden tensors**
  Run: `./build/test_infer.exe`
  Expected: All layer outputs match within quantization threshold; total inference cycle count $< 20,000,000$ cycles ($< 400\text{ ms}$ @ 50 MHz).
- **Step 5: Commit**
  `git commit -m "feat(dsp): implement CV32E40P in-core ResUMamba-30K inference engine"`

---

### Phase 3: Method 2 — Hardware Coprocessor Offload Bridge

#### Task 5: Hardware Accelerator Bridge RTL (`mamba_bridge.sv`)
- **Files:**
  - Modify: `RTL/ecg_soc/mamba_bridge.sv`
  - Modify: `RTL/ecg_soc/apb_interconnect.sv` (map Mamba bridge control registers at `0x1A10_5000`)
  - Modify: `RTL/ecg_soc/cv32e40p_ecg_soc_top.sv` (wire bridge interrupts and D-OBI DMA port)
  - Test: `Simulation/mamba_bridge_tb.sv`

- **Step 1: Write failing test in `Simulation/mamba_bridge_tb.sv`**
  Verify APB command dispatch (opcode, length, source address, destination address) and completion interrupt assertion.
- **Step 2: Run simulation to verify failure**
  Run: `iverilog -g2012 -o build/mamba_tb.vvp Simulation/mamba_bridge_tb.sv RTL/ecg_soc/mamba_bridge.sv && vvp build/mamba_tb.vvp`
  Expected: FAIL.
- **Step 3: Implement DMA streaming and command sequencer in `mamba_bridge.sv`**
  Implement 32-bit APB slave register interface (`CSR_CMD`, `CSR_SRC`, `CSR_DST`, `CSR_LEN`, `CSR_STATUS`) and master streaming FIFO.
- **Step 4: Run simulation to verify PASS**
  Run: `vvp build/mamba_tb.vvp`
  Expected: `TC-MAMBA-001` through `TC-MAMBA-004` PASS.
- **Step 5: Commit**
  `git commit -m "feat(rtl): implement APB streaming coprocessor bridge for Mamba acceleration"`

---

#### Task 6: Integrate 128-Tap DiagSSM1D FIR Hardware Sidecar
- **Files:**
  - Create: `RTL/ecg_soc/mamba_fir_sidecar.sv` (4-lane parallel MAC engine for 128-tap bidirectional FIR)
  - Modify: `RTL/ecg_soc/cv32e40p_ecg_soc_top.sv`
  - Test: `Simulation/mamba_fir_tb.sv`

- **Step 1: Write failing test for 128-tap hardware FIR accelerator**
  Inject 500-sample input across 24 channels and verify output matches software FIR output in $< 4,000,000$ clock cycles ($< 80\text{ ms}$).
- **Step 2: Run simulation to verify failure**
  Expected: FAIL.
- **Step 3: Implement 4-lane pipelined MAC engine in `mamba_fir_sidecar.sv`**
  Instantiate DSP48E1 multipliers with direct BRAM coefficient buffering.
- **Step 4: Run simulation to verify timing and output match**
  Expected: PASS with 100% bit-exact output match and $4\times$ latency speedup over software.
- **Step 5: Commit**
  `git commit -m "feat(rtl): integrate 128-tap DiagSSM1D hardware FIR sidecar accelerator"`

---

### Phase 4: Method 3 — Hierarchical Two-Stage Cascade Integration

#### Task 7: Two-Stage Hierarchical Scheduler & Firmware Application
- **Files:**
  - Modify: `Firmware/boot/hello.c` / `Firmware/src/main.c`
  - Test: `Simulation/soc_tb.sv`

- **Step 1: Write failing co-simulation test for two-stage trigger**
  Simulate continuous 250 SPS ingress. Stage 1 Pan-Tompkins runs continuously. Inject synthetic premature ventricular contraction (PVC); verify Stage 2 ResUMamba engine activates immediately.
- **Step 2: Run simulation to verify failure**
  Run: `powershell -File scripts/run_sim.ps1`
  Expected: FAIL (cascade trigger not implemented).
- **Step 3: Implement hierarchical state machine in firmware**
  ```c
  // Stage 1: Continuous Lightweight Surveillance (< 0.2% CPU)
  if (pan_tompkins_process_sample(sample)) {
      uint32_t rr_interval = calculate_rr_interval();
      if (is_arrhythmic_event(rr_interval) || periodic_schedule_due()) {
          // Stage 2: Trigger Deep ResUMamba-30K Classification (Method 1 or Method 2)
          resumamba_classify_window(ecg_buffer_window);
          uart_send_classification_packet();
      }
  }
  ```
- **Step 4: Run co-simulation to verify trigger, classification, and telemetry output**
  Run: `powershell -File scripts/run_sim.ps1`
  Expected: `TC-BOOT-001` through `TC-CASCADE-006` PASS.
- **Step 5: Commit**
  `git commit -m "feat(firmware): implement two-stage hierarchical Pan-Tompkins to ResUMamba cascade"`

---

### Phase 5: FPGA Implementation, Static Timing Closure & Master Verification

#### Task 8: Vivado Physical Synthesis & Routed Timing Closure on Artix-7
- **Files:**
  - Modify: `Synthesis/flist_cv32e40p_soc.f` (include new coprocessor RTL)
  - Modify: `Synthesis/fpga/ecg_artix7/run_synth.tcl`
  - Test: `Synthesis/fpga/ecg_artix7/run_fpga.ps1`

- **Step 1: Run non-project batch implementation in Vivado**
  Run: `powershell -File Synthesis/fpga/ecg_artix7/run_fpga.ps1`
- **Step 2: Verify static timing reports**
  Inspect `Synthesis/fpga/ecg_artix7/reports/timing_routed.rpt`:
  Ensure $WNS \ge 0.000\text{ ns}$ and $WHS \ge 0.000\text{ ns}$ at 50 MHz compute clock.
- **Step 3: Verify resource utilization**
  Inspect `utilization_placed.rpt`:
  Ensure LUTs $< 30,000$ ($< 48\%$), BRAMs $< 60$ ($< 45\%$), DSPs $< 30$ ($< 13\%$).
- **Step 4: Generate verified bitstream and cryptographic manifest**
  Record bitstream SHA-256 and update `reports/manifest.json`.
- **Step 5: Commit and tag release**
  `git commit -m "feat(fpga): achieve static timing closure and bitstream generation for tri-modal ECG SoC"`

---

## Verification & Claim Integrity Protocol

Per `Instruction/claim_integrity.md`:
1. Every gate requires zero exit code, SHA-256 artifact hashes, and individual `[PASS]` testcase census.
2. Latency and cycle counts must be measured directly from simulation timestamps or FPGA cycle counters (`mcycle`), never estimated via arithmetic division alone.
3. Quantized model classification accuracy must be cross-validated against MIT-BIH PhysioNet benchmark records (`evaluate_ec57_pt.py`).

---

## Execution Handoff

Plan complete and saved to `docs/plans/2026-10-06-tri-modal-dsp-resumamba-plan.md`. Two execution options:

1. **Subagent-Driven (this session)** — Dispatch fresh subagents per task, review between tasks, fast iteration.
2. **Parallel Session (separate)** — Open new session with executing-plans, batch execution with checkpoints.
