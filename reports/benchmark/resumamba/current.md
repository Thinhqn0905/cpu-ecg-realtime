# ResUMamba-30K Frozen Integer Contract & Memory Budget Report

**Project:** RISC-V Real-Time ECG Biosignal Processing & Acquisition SoC  
**Document ID:** `REP-RESUMAMBA-FROZEN-20261006`  
**Date:** 2026-10-06  
**Target Platform:** Digilent Arty A7-100T (Xilinx Artix-7 `xc7a100tcsg324-1`)  
**Core Architecture:** OpenHW Group CV32E40P (RV32IMC, FPU=0, COREV_PULP=1)  
**System Clock:** 50.0 MHz static timing verified  
**Evidence Standard:** Strict compliance with `Instruction/claim_integrity.md`, `Instruction/evidence_contract.md`, and `docs/plans/2026-10-06-core-next-decision-audit.md` (Task 5 / Checklist 10.8)

---

## 1. Executive Summary

This report establishes the **frozen integer specification**, numerical parity boundaries, and **concrete memory budget audit** for the **ResUMamba-30K** sequence-to-sequence neural network model targeting the CV32E40P SoC.

### Key Audit Findings & Enforced Boundaries:
1. **Model Checkpoint Provenance Frozen:**  
   The canonical model checkpoint is pinned at `E:\ResearchOnWork\Backup\PhD_VNU\checkpoints_pt\resumamba_30k.pt` with verified SHA-256 `d03428dbb3bde57cbabf94d6e44a22e5a5eb1323ac76a457be035652262726bc` (515,487 bytes, 26,149 parameters).
2. **Sequence Output Semantics Preserved:**  
   The model processes $2500\text{ samples} \times 3\text{ leads}$ ($10.0\text{ s}$ @ $250\text{ Hz}$) and outputs **$500\text{ temporal steps} \times 4\text{ arrhythmia classes}$** (Normal, SVEB, VEB, Fusion). It is not an arbitrary single-vector GAP classifier.
3. **Architectural Memory Blocker Identified:**  
   The quantized parameter footprint is **44,492 bytes** (85 tensors). Because the CV32E40P hardware configuration has a **32 KB I-TCM (32,768 bytes)**, storing weights in default I-TCM `.rodata` is physically impossible (overflows by $11.7\text{ KB}$).
4. **Static Ping-Pong Arena Contract Established:**  
   Dynamic `calloc` allocations (previously peaking at $\sim 184\text{ KB}$) have been eliminated in favor of a **48,000-byte static ping-pong buffer arena** that fits cleanly within the **128 KB D-TCM** with **$30.4\text{ KB}$ (23.2%) free headroom**.

---

## 2. Model Architecture & Tensor Inventory

### 2.1 Model Topology
- **Input Dimensions:** `[1, 2500, 3]` (Batch=1, Time=2500, Leads=3).
- **Stem Block:**
  - `stem1`: Conv1D ($K=9, \text{In}=3, \text{Out}=8$) + folded BatchNorm + ReLU.
  - `stem2`: Conv1D ($K=9, \text{In}=8, \text{Out}=8$) + folded BatchNorm + ReLU.
  - `stem_pools`: MaxPool1D (factor 5, stride 5): $2500 \to 500$ temporal steps.
  - `stem_out`: Separable Conv1D (DW $K=5$, PW $8 \to 24$) + folded BatchNorm + ReLU. Output: `[1, 500, 24]`.
- **ResU Blocks (Depths [3, 2]):**
  - Separable Conv1D encoder/decoder paths with residual skip connections. Width = 24 channels, mid-channels = 12.
- **State-Space DiagSSM1D Blocks (2 Blocks):**
  - 128-tap linear-phase forward FIR filter + 128-tap backward FIR filter across 24 channels (INT16 Q15).
  - Gate projection and element-wise SiLU activation.
- **Fusion & Classification Head:**
  - `fuse`: 1x1 Conv ($48 \to 24$ channels) merging ResU and SSM branches.
  - `head_conv`: 1x1 Conv ($24 \to 4$ channels).
  - Softmax normalization over 4 classes per time step. Output: `[1, 500, 4]`.

### 2.2 Quantization Specifications & Parity
Quantization executed via `scripts/quantize_resumamba.py`:
- **Weights:** Symmetric INT8 uniform quantization ($W_{i8} = \text{clamp}(\text{round}(W \times S_w), -127, 127)$).
- **DiagSSM1D Filter Taps:** Q15 INT16 fixed-point representation ($[-32768, 32767]$).
- **Biases:** INT16 fixed-point representation ($[-32768, 32767]$).
- **Parity Metrics:**
  - Max Absolute Probability Error: **0.01256** (Passing threshold $< 0.05$).
  - Argmax Sequence Parity: **99.80%** (Passing threshold $\ge 98.0\%$).

---

## 3. SoC Memory Budget Audit (CV32E40P Dual-TCM)

### 3.1 Memory Map & Allocation

| Memory Region | Physical Range | Hardware Capacity | Allocated Payload | Sizing Status | Storage Policy |
|:--------------|:--------------:|:-----------------:|:-----------------:|:-------------:|:---------------|
| **I-TCM**     | `0x0000_0000 - 0x0000_7FFF` | **32,768 B (32 KB)** | Firmware code only | **FITS CODE ONLY** | Firmware instructions (`.text`, `.boot`, `.vectors`) |
| **D-TCM**     | `0x0001_0000 - 0x0002_FFFF` | **131,072 B (128 KB)**| 100,684 B total   | **FITS WITH 23.2% MARGIN** | Static data, arena, stack, heap |

### 3.2 Detailed D-TCM Memory Breakdown

| Component | Buffer Dimensions / Elements | Bytes | Percentage of D-TCM |
|:----------|:----------------------------|:-----:|:-------------------:|
| **Quantized Model Weights** | 85 tensors (INT8 weights + INT16 FIR taps & biases) | 44,492 B | 33.95% |
| **Ping-Pong Arena Buffer A**| `[500, 24]` int16 samples | 24,000 B | 18.31% |
| **Ping-Pong Arena Buffer B**| `[500, 24]` int16 samples | 24,000 B | 18.31% |
| **Hardware Stack**          | `.stack` section | 4,096 B | 3.13% |
| **Freestanding Heap**       | `.heap` section | 4,096 B | 3.13% |
| **Total Allocated**         | — | **100,684 B** | **76.82%** |
| **Free Headroom**           | Available for UART buffers & peripheral FIFOs | **30,388 B** | **23.18%** |

---

## 4. Hardware Offload Architectural Decision

Based on Tasks 4 and 5:
1. **Surveillance vs. Full Inference Separation:**  
   - Streaming Pan-Tompkins QRS detection and 45-tap FIR filtering run continuously in software on CV32E40P at **$< 1.6\%$ CPU load**.
   - ResUMamba-30K is triggered **only upon detected cardiac arrhythmia/ectopic beat events** (two-stage hierarchical cascade).
2. **Coprocessor Offload Feasibility:**  
   - If the full ResUMamba model is executed purely in software on CV32E40P, the 128-tap FIR DiagSSM1D layer and separable convolutions require significant compute cycles.
   - A dedicated coprocessor (e.g. `mamba_fir_sidecar.sv`) offloading the 24-channel 128-tap bidirectional FIR filter is architecturally justified **specifically for the deep ResUMamba block**, provided it adheres to the frozen integer scale contract (`spec/resumamba_integer_contract.json`) and passes closed-loop co-simulation (Task 6).

---

## 5. Artifact Manifest

| Artifact Path | Format | Description |
|:--------------|:------:|:------------|
| `spec/resumamba_integer_contract.json` | JSON | Canonical frozen integer model contract |
| `Firmware/dsp/resumamba_weights.h`     | C Header | INT8 weights and INT16 FIR taps |
| `Firmware/dsp/resumamba_bias.h`        | C Header | INT16 biases |
| `Firmware/dsp/resumamba_scales.h`      | C Header | Fixed-point multipliers and right-shift parameters |
| `scripts/test_frozen_integer_contract.py` | Python | Fail-closed contract validation test suite |

*Validated under fail-closed Python contract `scripts/test_frozen_integer_contract.py` (7/7 tests PASS).*
