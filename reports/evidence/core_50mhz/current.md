# CV32E40P ECG SoC 50 MHz Timing Closure Status Report

**Design:** `ecg_arty_top`  
**Target Device:** Xilinx Artix-7 `xc7a100tcsg324-1`  
**Target Frequency:** 50.000 MHz (Clock Period = 20.000 ns)  
**Reference Clock:** 100.000 MHz (Digilent Arty A7-100T Pin E3)  
**Core Baseline:** OpenHW CV32E40P (`97086e9565f8145522ad6d62852123c0e5537529`), `COREV_PULP=1`, `FPU=0`  
**SoC Configuration:** 32 KB I-TCM, 128 KB D-TCM, `ENABLE_MAMBA=0` (Clean Production Baseline)  
**Date:** 2026-10-06  
**Status:** ACCEPTED (Physical Timing Closure Achieved at 50.0 MHz, All Evidence Gates Passed)  
**Accepted Run ID:** `run_20261006_110810`  

---

## 1. Static Timing Acceptance Criteria (Fail-Closed)

Per `Instruction/claim_integrity.md`, `Instruction/evidence_contract.md`, and `docs/plans/2026-10-06-core-next-decision-audit.md` (Task 1 & Task 3):
- **WNS (Worst Negative Slack):** $\ge 0.000\text{ ns}$ (Strictly required for setup timing closure) — **Result: +0.001 ns (MET)**
- **TNS (Total Negative Slack):** $= 0.000\text{ ns}$ — **Result: 0.000 ns (MET)**
- **Setup Failing Endpoints:** Exactly 0 — **Result: 0 / 18,167 (MET)**
- **WHS (Worst Hold Slack):** $\ge 0.000\text{ ns}$ — **Result: +0.119 ns (MET)**
- **THS (Total Hold Slack):** $= 0.000\text{ ns}$ — **Result: 0.000 ns (MET)**
- **Hold Failing Endpoints:** Exactly 0 — **Result: 0 / 18,167 (MET)**
- **Unconstrained Internal Endpoints:** Exactly 0 — **Result: 0 (MET)**
- **I/O Contract:** Formal review complete (`reports/evidence/core_50mhz/io_contract.md`) — **Reviewed**
- **DRC Review:** 0 errors, 47 audited advisory warnings (`reports/evidence/core_50mhz/drc_review.md`) — **Reviewed**
- **Bitstream Generated:** `cv32e40p_ecg_soc.bit` (SHA256: `030ada0486eac7b5592296c2f017f663e3970c247c185339b9882bcb8ac886e8`) — **Verified**

---

## 2. Critical Path Family Analysis (Historical Rejected Run `run_20261006_093347`)

The historical D1 candidate produced a bitstream under native Vivado exit 0, but failed static timing analysis:
- **WNS:** $-0.815\text{ ns}$
- **TNS:** $-63.389\text{ ns}$
- **Failing Endpoints:** 215 / 15,454
- **Critical Path:**
  - Source: `u_soc_top/gen_cv32e40p_core.u_core/core_i/id_stage_i/alu_operator_ex_o_reg[5]/C`
  - Destination: `u_soc_top/gen_cv32e40p_core.u_core/core_i/id_stage_i/mult_operand_b_ex_o_reg[26]/D`
  - Total Delay: $20.576\text{ ns}$ (Logic: $5.753\text{ ns}$ [28.0%], Route: $14.823\text{ ns}$ [72.0%])
  - Logic Levels: 27 (CARRY4=5, LUT3=2, LUT5=4, LUT6=14, MUXF7=2)
- **Root Cause:**
  1. Deep ALU datapath forwarding: EX stage ALU results feed back through multiplexers into ID stage multiplier operand registers for back-to-back dependent arithmetic instructions.
  2. High-fanout nets: Internal signals (`i___160_i_5_n_0` with fanout 96, `extract_sign` with fanout 64, `shift_right_result126_out` with fanout 61, `alu_operator_ex_o_reg[5]` with fanout 59) caused $14.823\text{ ns}$ of interconnect routing delay across multiple Artix-7 SLICE columns.
  3. Pre-route-only physical optimization: The previous script ran `phys_opt_design` prior to routing, but omitted post-route physical optimization and swallowed re-routing errors in a Tcl `catch` block.

---

## 3. Implementation Optimization Strategy

1. **Decoupled Baseline:** Set `ENABLE_MAMBA=0` to eliminate synthetic coprocessor interconnect congestion from the physical routing graph.
2. **Timing-Driven Synthesis:** Run `synth_design` with `-directive PerformanceOptimized` and `-flatten_hierarchy rebuilt` to prevent unwanted arithmetic resource sharing and deep LUT mux trees.
3. **Multi-Stage Physical Optimization:**
   - Pre-route: `opt_design -directive Explore` -> `place_design -directive Explore` -> `phys_opt_design -directive AggressiveExplore`
   - Initial Route: `route_design -directive Explore`
   - Post-route (conditional on slack < 0): `phys_opt_design -directive AggressiveExplore` followed by `route_design -directive MoreGlobalIterations -tns_cleanup` with strict error trapping (no hidden `catch`).
4. **Fail-Closed Evidence Gate:** Automatically invoked via `scripts/check_fpga_evidence.py`. Any run with $WNS < 0.000\text{ ns}$ is immediately tagged `TIMING_FAIL` and rejected.

---

## 4. Implementation Results & Metrics Comparison

| Metric | Historical Rejected (`run_20261006_093347`) | Baseline Control (`run_20261006_105354`) | Production Accepted (`run_20261006_110810`) |
| :--- | :--- | :--- | :--- |
| **Status** | `TIMING_FAIL` | `REJECTED_OOM` | **`ACCEPTED`** |
| **Clock Period** | 20.000 ns (50.0 MHz) | 20.000 ns (50.0 MHz) | **20.000 ns (50.0 MHz)** |
| **WNS (Setup)** | -0.815 ns (VIOLATED) | N/A (aborted) | **+0.001 ns (MET)** |
| **TNS (Setup)** | -63.389 ns | N/A (aborted) | **0.000 ns (MET)** |
| **Failing Endpoints (Setup)** | 215 / 15,454 | N/A | **0 / 18,167** |
| **WHS (Hold)** | +0.044 ns | N/A | **+0.119 ns (MET)** |
| **THS (Hold)** | 0.000 ns | N/A | **0.000 ns (MET)** |
| **Failing Endpoints (Hold)** | 0 | N/A | **0 / 18,167** |
| **Unconstrained Endpoints** | 0 | N/A | **0** |
| **Slice LUTs** | 10,798 (17.03%) | N/A | **10,397 (16.40%)** |
| **Slice Registers** | 7,046 (5.56%) | N/A | **6,942 (5.47%)** |
| **Block RAM (RAMB36E1)** | 40 (29.63%) | N/A | **40 (29.63%)** |
| **DSPs (DSP48E1)** | 7 (2.92%) | N/A | **7 (2.92%)** |
| **Total On-Chip Power** | 0.252 W | N/A | **0.250 W** |
| **Router Concurrency** | 8 threads | 8 threads (OOM) | **2 threads (maxThreads 2)** |
| **Bitstream Generated** | Yes (invalid timing) | No | **Yes (`cv32e40p_ecg_soc.bit`)** |

