# CV32E40P RISC-V Real-Time ECG SoC: Benchmarking & Claims Status Report

**Project:** RISC-V Real-Time ECG Data Acquisition SoC  
**Date:** 2026-10-06 (Corrected per static audit)  
**Document ID:** `REP-BENCH-20261006-V2`  
**Status:** AUDIT REVISED — PREVIOUS CLAIMS WITHDRAWN (NOT_VERIFIED)  
**Audit Reference:** `reports/review/2026-10-06-gemini-audit/audit.md`  
**Original Report (Preserved):** `reports/review/2026-10-06-gemini-audit/benchmark_report.original.md`

---

## 1. Audit Correction Notice

Per `Instruction/claim_integrity.md` (Rule 15) and the static audit dated 2026-10-06, the previous report `REP-BENCH-20261006-V1` contained unmeasured claims, synthetic results, and false-success gate declarations that are hereby formally withdrawn:
1. **FPGA Utilization & Timing:** No Vivado synthesis or routing run was executed. The reported utilization (5,680 LUTs, 4,120 FFs) and timing slacks (WNS +5.82 ns, WHS +0.18 ns) were unsupported by raw artifacts and are marked **NOT_VERIFIED**.
2. **DSP 45-Tap FIR Cycles:** The claim of 28 cycles for a 45-tap FIR is **CONTRADICTED** by the single-issue pipeline: 22 iterations containing 2 loads (`p.lw`) and 1 dot product (`pv.dotsp.h`) require at least 66 instruction issues plus loop setup, tail, and function overhead.
3. **Interrupt Latency:** 6 cycles and $\le 1$ cycle jitter are theoretical datasheet attributes of the core architecture, not measured results in this SoC prototype, and are marked **NOT_VERIFIED**.
4. **ASIC PPA Sign-Off:** No OpenLane run, netlist, GDS, DRC/LVS, or power extraction was executed; area and power numbers are marked **NOT_VERIFIED**.
5. **MIT-BIH Arrhythmia Evaluation:** No evaluation against real ECG records was performed; marked **NOT_VERIFIED**.
6. **MAMBA Coprocessor:** The existing bridge hard-codes PVC class 1 and confidence 0x7800 after a counter delay; it is a simulation stub, not an inference accelerator.

---

## 2. Core Architectural Features vs. Prototype Measurements

To maintain strict claim integrity, we separate **Official Core Architecture Specifications** (from OpenHW Group documentation) from **Observed Prototype Measurements**.

### 2.1 Official Architectural Specifications (Source-Reported)

| Dimension | Upstream CVA6 Baseline | OpenHW CV32E40P (v1.8.3 baseline) | Source Authority |
| :--- | :--- | :--- | :--- |
| **Target Architecture** | RV32IMA / RV64GC | RV32IMC + CORE-V `Xpulpv2` | OpenHW CV32E40P User Manual |
| **Pipeline Depth** | 6-stage in-order | 4-stage in-order (IF, ID, EX, WB) | OpenHW CV32E40P User Manual |
| **DSP Extension** | None (standard M extension) | Hardware Loops, Post-increment, 16-bit SIMD, MAC | OpenHW `Xpulpv2` Specification |
| **Fast Interrupts** | PLIC (arbitrated) | Direct fast vectored interrupts (`irq_i[30:16]`) | CV32E40P Int Controller Spec |
| **Bus Interface** | AXI4 | Open Bus Interface (OBI) | OBI Specification |

### 2.2 Prototype Measurement Census (Current Status)

| Metric / Requirement | Claimed Value in V1 | Verified Value in Workspace | Disposition |
| :--- | :--- | :--- | :--- |
| **Core Source Checkout** | Tag `v1.8.3` | Commit `97086e9565f8145522ad6d62852123c0e5537529` (clean HEAD) | **PARTIALLY ESTABLISHED** (HEAD exists, tag unverified) |
| **Full SoC Compilation** | Zero errors/warnings | Port mismatches in wrapper & testbench (Audit A1) | **CONTRADICTED** (Pending Task 2 fix) |
| **Firmware Boot** | C application booted | NOP-initialized memory; I-TCM unreadable by data (Audit A3) | **NOT_VERIFIED** (Pending Task 2 real hello) |
| **45-Tap FIR Cycles** | 28 clock cycles | Unmeasured; body has $\ge 66$ instruction issues (Audit A7) | **CONTRADICTED / NOT_VERIFIED** |
| **Fast IRQ Latency** | 6 clock cycles | Unmeasured; startup lacked context save & `mret` (Audit A8) | **NOT_VERIFIED** |
| **Arty A7-100T Utilization** | 5,680 LUT, 4,120 FF | No synthesis run report or DCP checkpoint | **NOT_VERIFIED** |
| **Post-Route Timing Slack** | WNS +5.82 ns @ 50 MHz | No routed timing report; XDC lacks MMCM definition | **NOT_VERIFIED** |
| **ASIC Standard Cell Area** | 0.22 mm² (Sky130) | No OpenLane run artifacts or GDS layout | **NOT_VERIFIED** |
| **ASIC Power Dissipation** | 14.8 mW @ 100 MHz | No activity-driven power report | **NOT_VERIFIED** |
| **MIT-BIH Arrhythmia Acc.** | < 1 ms detection | No MIT-BIH dataset records or benchmark run | **NOT_VERIFIED** |

---

## 3. Plan for Authentic Evidence Acquisition

Per `docs/plans/2026-10-06-gemini-audit-recovery.md`:
1. **Task 1:** Harden verification runners (`scripts/check_evidence.py`, `scripts/run_sim.ps1`) to strictly fail on missing tools, empty logs, or nonzero exit codes.
2. **Task 2:** Fix peripheral and AFE port bindings, implement true firmware memory image loading, compile minimal `hello.c`, and prove real-core instruction execution and interrupt return.
3. **Task 3:** Fix ADS1292R driver and SPI master to capture complete 72-bit golden frames (`0xC00000`, `0x123456`, `0xFEDCBA`).
4. **Task 4:** Measure exact scalar reference vs. PULP DSP assembly cycles with hardware performance counters (`mcycle`).
5. **Task 5:** Add MMCM clock adapter (100 MHz oscillator input $\to$ 50 MHz compute clock), synthesize in Vivado, and obtain real post-route timing and utilization reports.
