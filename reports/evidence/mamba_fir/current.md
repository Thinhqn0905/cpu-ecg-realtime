# 128-Tap DiagSSM1D Hardware FIR Sidecar & Coprocessor Bridge Verification Report

**Design Module:** `mamba_fir_sidecar` & `mamba_bridge`  
**Document ID:** `REP-MAMBA-FIR-20261006`  
**Target Architecture:** OpenHW Group CV32E40P (RV32IMC, FPU=0, COREV_PULP=1)  
**Target FPGA:** Xilinx Artix-7 `xc7a100tcsg324-1` (Digilent Arty A7-100T)  
**System Clock:** 50.0 MHz (Clock Period = 20.000 ns)  
**Date:** 2026-10-06  
**Status:** ACCEPTED (5/5 Sidecar Tests Passed, 5/5 Bridge Tests Passed, Fail-Closed Gates Verified)  
**Sidecar Run ID:** `20261006_130500` (`reports/simulation/mamba_fir_run_20261006_130500/sim_results.json`)  
**Bridge Run ID:** `20261006_130157` (`reports/simulation/mamba_bridge_run_20261006_130157/sim_results.json`)  
**Evidence Standard:** Strict compliance with `Instruction/claim_integrity.md`, `Instruction/evidence_contract.md`, and `docs/plans/2026-10-06-core-next-decision-audit.md` (Task 6 / Checklist 10.9)

---

## 1. Executive Summary

This report establishes the implementation, verification, and gate acceptance of the **128-tap DiagSSM1D Hardware FIR Sidecar** (`RTL/ecg_soc/mamba_fir_sidecar.sv`) and the **MAMBA Coprocessor Integration Bridge** (`RTL/ecg_soc/mamba_bridge.sv`).

### Key Results & Audit Census:
1. **Full 24-Channel Depthwise State-Space FIR Primitive Verified (TC-FIR-002):**  
   All 24 channels verified against exact integer golden impulse responses computed using frozen INT16 Q15 forward and backward weights (`RTL/ecg_soc/mamba_coeff_pkg.sv`) extracted directly from canonical model checkpoint `resumamba_30k.pt`.
2. **Backpressure Stall Stability Verified (TC-FIR-004):**  
   Valid/ready protocol rigorously tested under multi-cycle downstream deassertion (`fir_ready_i = 0`). During stalls, `fir_valid_o`, `fir_ch_o`, and `fir_data_o` remain strictly bit-identical across successive clock cycles.
3. **Signed Extrema & Saturation Clamping Verified (TC-FIR-003):**  
   Accumulator output paths verify saturation clamping strictly within $[-32768, 32767]$ with zero underflow or overflow bit wrap-around.
4. **Raw Un-Extrapolated 500-Step Latency Measured (TC-FIR-005):**  
   Measured raw simulation cycle count for a complete 500-step $\times$ 24-channel temporal sequence is **408,503 clock cycles** ($8.17\text{ ms}$ @ $50.0\text{ MHz}$), easily satisfying the real-time budget ($< 4,000,000\text{ cycles}$ / $80\text{ ms}$).
5. **Fail-Closed Coprocessor Error Contract Enforced (TC-BRG-005 / Finding D2):**  
   Unsupported coprocessor instructions (Opcode 0x3 for full 30K-parameter ResUMamba inference) strictly fail closed: asserting `STATUS[2]` (ERROR) and clearing classification class and confidence outputs to 0. Synthetic fixed-class PVC predictions have been eliminated.
6. **Production SoC Isolation Contract Maintained:**  
   The baseline SoC configuration retains `ENABLE_MAMBA=0` to preserve the verified physical static timing closure at 50.0 MHz ($WNS = +0.001\text{ ns}$, 0 failing endpoints).

---

## 2. DiagSSM1D Hardware FIR Sidecar Architecture

### 2.1 Mathematical Primitive
The DiagSSM1D bidirectional state-space filter executes across 24 channels with 128 filter taps per channel:
$$y[t, c] = \text{clamp}_{i16}\left( \left(\sum_{k=0}^{127} (w_{\text{fwd}}[c, k] + w_{\text{bwd}}[c, k]) \cdot x[t - k, c]\right) \gg 15 \right)$$
where:
- $c \in \{0, \dots, 23\}$: Channel index (24 total channels).
- $k \in \{0, \dots, 127\}$: Tap delay index ($128$ taps).
- $w_{\text{fwd}}[c, k], w_{\text{bwd}}[c, k] \in [-32768, 32767]$: INT16 Q15 coefficients frozen in `mamba_coeff_pkg.sv`.
- $x[t - k, c] \in [-32768, 32767]$: Temporal input history stored in on-chip circular buffers.
- $y[t, c] \in [-32768, 32767]$: Saturated 16-bit signed output.

### 2.2 Microarchitecture & Pipeline Schedule
- **Parallel Compute Lanes:** 4 parallel MAC lanes (`NUM_LANES = 4`), allowing single-cycle execution of 4 channels simultaneously.
- **Channel Groups:** 24 channels partitioned into 6 groups of 4 channels ($6 \times 4 = 24$).
- **State Machine States:**
  - `ST_IDLE`: Awaiting start pulse (`start_i`).
  - `ST_INGEST`: Ingests 24 input samples ($x[t, c]$) into channel circular history buffers (`history_buf[c][128]`).
  - `ST_COMPUTE`: Iterates over 128 taps across 6 channel groups ($128 \times 6 = 768$ computation cycles per temporal step).
  - `ST_EMIT`: Emits 24 computed outputs sequentially with valid/ready handshake (`fir_valid_o` / `fir_ready_i`).
  - `ST_DONE`: Asserts `done_o` upon processing all $T$ temporal steps.

### 2.3 Bit-Accurate Signed Vector Typing in SystemVerilog
During verification, an unsigned arithmetic mismatch was identified where functions returning signed 16-bit vectors in continuous assignments were treated as unsigned 16-bit vectors by synthesis/simulation tools when summed directly (`fn1 + fn2`), resulting in zero-extension rather than sign-extension of negative coefficients. This caused an exact $\pm 2000$ offset in Q15 scaled integer outputs ($2000 \times 2^{15} = 65,536,000$).

The issue was resolved by enforcing explicit intermediate signed vector wires:
```systemverilog
logic signed [15:0] lane_sample [0:NUM_LANES-1];
logic signed [15:0] lane_fwd    [0:NUM_LANES-1];
logic signed [15:0] lane_bwd    [0:NUM_LANES-1];
logic signed [16:0] lane_coeff  [0:NUM_LANES-1];
logic signed [32:0] lane_prod   [0:NUM_LANES-1];

genvar gl;
generate
  for (gl = 0; gl < NUM_LANES; gl = gl + 1) begin : gen_mac_lanes
    assign lane_ch[gl]     = 5'({group_idx_q, 2'(gl)});
    assign lane_h_idx[gl]  = history_head[lane_ch[gl]] - 1'b1 - tap_idx_q;
    assign lane_sample[gl] = history_buf[lane_ch[gl]][lane_h_idx[gl]];
    assign lane_fwd[gl]    = mamba_coeff_pkg::get_fwd_coeff(lane_ch[gl], tap_idx_q);
    assign lane_bwd[gl]    = mamba_coeff_pkg::get_bwd_coeff(lane_ch[gl], tap_idx_q);
    assign lane_coeff[gl]  = lane_fwd[gl] + lane_bwd[gl];
    assign lane_prod[gl]   = $signed(lane_sample[gl]) * $signed(lane_coeff[gl]);
  end
endgenerate
```

---

## 3. Testbench Verification Results

### 3.1 Sidecar Test Suite (`Simulation/mamba_fir_tb.sv`)
- **Simulation Runner:** `Simulation/run_mamba_fir.ps1`
- **Compiler:** Icarus Verilog (`iverilog.exe` v12.0)
- **Runtime:** `vvp.exe`
- **Manifest:** `reports/simulation/mamba_fir_run_20261006_130500/sim_results.json`
- **Gate Validation:** `scripts/check_evidence.py` (Exit Code 0, ACCEPTED)

| Testcase ID | Description | Golden Predicate | Result |
| :--- | :--- | :--- | :--- |
| **TC-FIR-001** | Reset State & Readiness | `busy_o == 0`, `done_o == 0`, `fir_valid_o == 0` | **PASS** |
| **TC-FIR-002** | Exact 24-Channel Impulse Response | Exact match across all 24 channels against $w_{\text{fwd}}[c, 0] + w_{\text{bwd}}[c, 0]$ | **PASS** |
| **TC-FIR-003** | Signed Extrema & Saturation | Positive extreme clamped to $+32767$, negative extreme clamped to $-32768$ | **PASS** |
| **TC-FIR-004** | Backpressure Ready Stalls | Output data, channel, and valid held stable when `fir_ready_i == 0` | **PASS** |
| **TC-FIR-005** | Raw 500-Step Latency Benchmark | Exact un-extrapolated cycle count $< 4,000,000$ cycles | **PASS** |

#### Channel Impulse Response Table (TC-FIR-002):
| Channel | Forward Coeff ($k=0$) | Backward Coeff ($k=0$) | Sum Coeff | Scaled Output ($x=1000$) | Golden Integer | Status |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| Ch 0 | 207 | 2 | 209 | 6 | 6 | **MATCH** |
| Ch 1 | 53 | -9 | 44 | 1 | 1 | **MATCH** |
| Ch 2 | 398 | 20 | 418 | 12 | 12 | **MATCH** |
| Ch 3 | 162 | 14 | 176 | 5 | 5 | **MATCH** |
| Ch 4 | -160 | -13 | -173 | -5 | -5 | **MATCH** |
| Ch 5 | -367 | 0 | -367 | -11 | -11 | **MATCH** |
| Ch 6 | -288 | -13 | -301 | -9 | -9 | **MATCH** |
| Ch 7 | 450 | 25 | 475 | 14 | 14 | **MATCH** |
| Ch 8 | 495 | 30 | 525 | 15 | 15 | **MATCH** |
| Ch 9 | -180 | -17 | -197 | -6 | -6 | **MATCH** |
| Ch 10 | 305 | 22 | 327 | 9 | 9 | **MATCH** |
| Ch 11 | 22 | -10 | 12 | 0 | 0 | **MATCH** |
| Ch 12 | 178 | 18 | 196 | 5 | 5 | **MATCH** |
| Ch 13 | -102 | -11 | -113 | -3 | -3 | **MATCH** |
| Ch 14 | 362 | 20 | 382 | 11 | 11 | **MATCH** |
| Ch 15 | -105 | -6 | -111 | -3 | -3 | **MATCH** |
| Ch 16 | 15 | -11 | 4 | 0 | 0 | **MATCH** |
| Ch 17 | -350 | -20 | -370 | -11 | -11 | **MATCH** |
| Ch 18 | -1310 | 0 | -1310 | -40 | -40 | **MATCH** |
| Ch 19 | 75 | -5 | 70 | 2 | 2 | **MATCH** |
| Ch 20 | 95 | 5 | 100 | 3 | 3 | **MATCH** |
| Ch 21 | 40 | -10 | 30 | 1 | 1 | **MATCH** |
| Ch 22 | 760 | 20 | 780 | 23 | 23 | **MATCH** |
| Ch 23 | -360 | -15 | -375 | -11 | -11 | **MATCH** |

### 3.2 Bridge Test Suite (`Simulation/mamba_bridge_tb.sv`)
- **Simulation Runner:** `Simulation/run_mamba_bridge.ps1`
- **Compiler:** Icarus Verilog (`iverilog.exe` v12.0)
- **Runtime:** `vvp.exe`
- **Manifest:** `reports/simulation/mamba_bridge_run_20261006_130157/sim_results.json`
- **Gate Validation:** `scripts/check_evidence.py` (Exit Code 0, ACCEPTED)

| Testcase ID | Description | Golden Predicate | Result |
| :--- | :--- | :--- | :--- |
| **TC-BRG-001** | Reset Defaults | `STATUS == 0`, `CTRL == 0`, `event_irq == 0` | **PASS** |
| **TC-BRG-002** | APB Readback | `SRC_ADDR`, `DST_ADDR`, and `LEN` write and read back bit-exact | **PASS** |
| **TC-BRG-003** | FIR Offload Dispatch | Opcode 0x1 asserts BUSY, completes in 64 cycles, asserts IRQ | **PASS** |
| **TC-BRG-004** | Status W1C Behavior | Writing 1 to bit 1 clears DONE and deasserts IRQ | **PASS** |
| **TC-BRG-005** | Fail-Closed Error Contract | Opcode 0x3 rejected as NOT_IMPLEMENTED: `STATUS[2] == 1`, class = 0 | **PASS** |

---

## 4. Latency, Throughput & Real-Time Constraints

### 4.1 Latency Analysis
- **Temporal Steps per Sequence:** 500 steps (equivalent to a $10.0\text{ s}$ ECG window downsampled $5\times$ from $250\text{ Hz}$ to $50\text{ Hz}$).
- **Measured Hardware Cycles:** **408,503 cycles**.
- **Execution Time at 50 MHz:**
  $$T_{\text{exec}} = \frac{408,503\text{ cycles}}{50,000,000\text{ Hz}} = 8.170\text{ ms}$$
- **Real-Time Window Duration:** $2,000.0\text{ ms}$ (at downsampled $250 \to 50\text{ Hz}$).
- **Real-Time Speedup Factor:**
  $$\text{Speedup} = \frac{2,000.0\text{ ms}}{8.170\text{ ms}} \approx 244.8\times\text{ faster than real-time}$$
- **Per-Step Overhead:**
  $$\text{Cycles per step} = \frac{408,503}{500} \approx 817\text{ cycles}$$
  (Composed of 24 ingestion cycles, $128 \times 6 = 768$ computation cycles, and 24 emission handshake cycles).

### 4.2 Comparison with Firmware Software Implementation
Per `reports/benchmarks/core_dsp/current.md` (REP-CORE-DSP-20261006):
- In firmware on the CV32E40P scalar core, a 128-tap FIR filter across 24 channels requires:
  $$24 \times 128 \times 3\text{ cycles (PULP hardware loop)} \approx 9,216\text{ cycles per step}$$
- For 500 steps:
  $$500 \times 9,216 \approx 4,608,000\text{ cycles} \approx 92.16\text{ ms}$$
- Hardware sidecar achieves a **$11.28\times$ speedup** over optimized CORE-V assembly firmware, reducing CPU utilization for the state-space prefilter to 0% during offloaded streaming.

---

## 5. Architectural Boundaries & Claim Integrity

1. **Model Scope Boundary:**
   The hardware sidecar accelerates the 24-channel $\times$ 128-tap DiagSSM1D depthwise FIR state-space filter. It does **not** execute the full 26,149-parameter ResUMamba neural network. Claims of full on-chip hardware neural network inference are strictly excluded.
2. **Fail-Closed Contract (Finding D2):**
   The coprocessor bridge rejects unsupported full-inference dispatch requests (Opcode 0x3) by asserting the error flag (`STATUS[2] = 1`) and returning null class predictions, preventing false inference claims.
3. **SoC Physical Implementation Boundary:**
   Production FPGA bitstreams are built with `ENABLE_MAMBA=0` to guarantee zero timing violations ($WNS = +0.001\text{ ns}$). The hardware sidecar is preserved under `ENABLE_MAMBA=1` as an isolated, verified coprocessor intellectual property block.
