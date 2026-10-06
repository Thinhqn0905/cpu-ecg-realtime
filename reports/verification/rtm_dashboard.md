# Requirement Traceability Matrix (RTM) Dashboard

**Project:** RISC-V Real-Time ECG Data Acquisition SoC  
**Target Platform:** Xilinx Artix-7 100T (`xc7a100tcsg324-1`)  
**Date:** 2026-10-06 (Reconciled & Corrected per Audit & Census v1.0.0)
**Status:** AUDITED CENSUS RECONCILED — TASKS 1-3 EXECUTION IN PROGRESS
**Audit Reference:** `reports/review/2026-10-06-core-next-decision-audit/audit.md`
**Execution Plan:** `docs/plans/2026-10-06-core-next-decision-audit.md`
**Census Data:** `reports/verification/current_requirement_census.json`

---

## 1. Traceability Summary

| Canonical Reqs (`spec/ecg_soc_reqs.json`) | Extended Architecture Reqs | Total Reqs in Census | PASS (Sim / Host / Routed) | Diagnostic Stub | Timing Fail (50 MHz) | NOT_VERIFIED |
| :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **19** | **10** | **29** | **16** | **2** | **2** | **9** |

*Note: Historical designation "29/29 Verified" is explicitly superseded. In accordance with `Instruction/claim_integrity.md`, unmeasured streaming latency, unverified 14-byte packet CRCs, unbound SVA checkers, fixed diagnostic stubs, and failed static timing ($WNS = -0.815\text{ ns}$) are correctly classified below.*

---

## 2. Requirement-to-Evidence Mapping Table

| Requirement ID | Canonical Spec Source | Category | Target Module & Concrete Check | Observed Assertion & Run ID | Current Reconciled Status |
| :--- | :--- | :--- | :--- | :--- | :---: |
| `REQ-SYS-001` | `spec/ecg_soc_reqs.json` | System Timing | 50.0 MHz static timing closure on Artix-7 | WNS = -0.815 ns, TNS = -63.389 ns (`run_20261006_093347`) | **TIMING_FAIL** |
| `REQ-SYS-002` | `spec/ecg_soc_reqs.json` | Resource | Artix-7 resource utilization footprint | 10516 LUTs, 7090 FFs, 40 RAMB36, 7 DSP (`run_20261006_093347`) | **PASS (Routed)** |
| `REQ-SYS-003` | `spec/ecg_soc_reqs.json` | Latency | Acquisition to UART latency <= 10.0 ms | End-to-end streaming measurement requires board bring-up | **NOT_VERIFIED** |
| `REQ-SPI-001` | `spec/ecg_soc_reqs.json` | Protocol | SPI Mode 1, continuous 72-bit CS# | TC-SPI-001A / TC-SPI-001B (`spi_run_20261006_060742`) | **PASS (Sim)** |
| `REQ-SPI-002` | `spec/ecg_soc_reqs.json` | Timing | Programmable clock divider (1.0 MHz default) | TC-SPI-007 divider check (`spi_run_20261006_060742`) | **PASS (Sim)** |
| `REQ-SPI-003` | `spec/ecg_soc_reqs.json` | Acquisition | Autonomous 72-bit burst read on DRDY# | TC-SPI-003 / TC-SPI-004 (`spi_run_20261006_060742`) | **PASS (Sim)** |
| `REQ-SPI-004` | `spec/ecg_soc_reqs.json` | Timing | SVA CS setup time verification | SVA bind omitted in simulation filelist; formally unbound | **NOT_VERIFIED** |
| `REQ-SPI-005` | `spec/ecg_soc_reqs.json` | Timing | SVA CS hold time verification | SVA bind omitted in simulation filelist; formally unbound | **NOT_VERIFIED** |
| `REQ-BUF-001` | `spec/ecg_soc_reqs.json` | Buffering | Ingress FIFO decoupling SPI from memory | TC-DMA-001 frame unpacking (`dma_run_20261006_060715`) | **PASS (Sim)** |
| `REQ-BUF-002` | `spec/ecg_soc_reqs.json` | Buffering | Ping-pong buffer swap (256 frames/bank) | TC-DMA-002 / TC-DMA-003 (`dma_run_20261006_060715`) | **PASS (Sim)** |
| `REQ-BUF-003` | `spec/ecg_soc_reqs.json` | Interrupt | Fast IRQ 18 assertion on buffer boundary | TC-DMA-004 boundary IRQ (`dma_run_20261006_060715`) | **PASS (Sim)** |
| `REQ-BUF-004` | `spec/ecg_soc_reqs.json` | Safety | Overflow detection without frame drop | TC-DMA-005 continuous swap (`dma_run_20261006_060715`) | **PASS (Sim)** |
| `REQ-UART-001` | `spec/ecg_soc_reqs.json` | Protocol | 115200 baud UART transmission | TC-BOOT-001 'ECG BOOT: ALIVE' (`run_20261006_064535`) | **PASS (Sim)** |
| `REQ-UART-002` | `spec/ecg_soc_reqs.json` | Timing | Baud rate divisor 434 at 50 MHz | Divisor matches 115200 baud (`run_20261006_064535`) | **PASS (Sim)** |
| `REQ-UART-003` | `spec/ecg_soc_reqs.json` | Packet | 14-byte binary ECG frame packet | Current firmware outputs ASCII status; packet pipeline deferred | **NOT_VERIFIED** |
| `REQ-UART-004` | `spec/ecg_soc_reqs.json` | Integrity | CRC-8 checksum verification over packet | Binary frame CRC-8 calculation deferred | **NOT_VERIFIED** |
| `REQ-APB-001` | `spec/ecg_soc_reqs.json` | Bus | AMBA APB3 single-cycle read/write | TC-BRG-001 protocol access (`bridge_run_20261006_060736`) | **PASS (Sim)** |
| `REQ-APB-002` | `spec/ecg_soc_reqs.json` | Bus | Dual-window address decoding (0x1000/0x1A10) | TC-BRG-003 decoding check (`bridge_run_20261006_060736`) | **PASS (Sim)** |
| `REQ-APB-003` | `spec/ecg_soc_reqs.json` | Bus | Variable wait-states & backpressure via PREADY| TC-BRG-002 / TC-BRG-004 (`bridge_run_20261006_060736`) | **PASS (Sim)** |
| `REQ-CORE-001`| Extended Architecture | CPU Core | Real CV32E40P execution from I-TCM | TC-BOOT-001..005 real crt0 binary (`run_20261006_064535`)| **PASS (Sim)** |
| `REQ-CORE-002`| Extended Architecture | Bus Bridge | OBI-to-APB bridge backpressure (gnt deassert) | TC-BRG-002 backpressure grant (`bridge_run_20261006_060736`)| **PASS (Sim)** |
| `REQ-CORE-003`| Extended Architecture | Memory | Dual-port TCM zero-wait-state access | TC-TCM-001..005 concurrent access (`tcm_run_20261006_080029`)| **PASS (Sim)** |
| `REQ-CORE-004`| Extended Architecture | Fast IRQ | Vectored interrupt dispatch & mret return | TC-TIMER-003 / TC-MRET-004 (`run_20261006_064535`) | **PASS (Sim)** |
| `REQ-DSP-001` | Extended Architecture | Filter DSP | 45-tap linear-phase bandpass filter | TC-DSP-001..004 scalar reference (`host_dsp_test`) | **PASS (Host Ref)** |
| `REQ-DSP-002` | Extended Architecture | Detection | Pan-Tompkins QRS peak detection | TC-DSP-005..006 64-bit squaring (`host_dsp_test`) | **PASS (Host Ref)** |
| `REQ-MAMBA-001`| Extended Architecture | Accelerator | ResUMamba DiagSSM1D offload bridge | 64-cycle timer returns fixed class 2 (`run_20261006_090915`) | **DIAGNOSTIC_STUB** |
| `REQ-TCM-128K` | Extended Architecture | Memory | Expanded 128 KB Data TCM addressing | TC-TCM-006 high address access (`tcm_run_20261006_080148`) | **PASS (Sim)** |
| `REQ-CASCADE-001`| Extended Architecture | Cascade DSP | Pan-Tompkins anomaly triggers ResUMamba | Synthetic RR vector {800,800,480} (`run_20261006_091539`) | **DIAGNOSTIC_STUB** |
| `REQ-FPGA-001` | Extended Architecture | Physical FPGA | 50.0 MHz static timing closure on Artix-7 | Bitstream generated, but WNS = -0.815 ns (`run_20261006_093347`)| **TIMING_FAIL** |

---

## 3. Verified Artifact Reference

1. **`reports/review/2026-10-06-source-audit/spi_run.json` (Historical Archive Only)**:
   - Tool: Icarus Verilog 12.0 devel (`vvp`)
   - Exit Code: 0
   - Verified Tests (Historical 24-bit Smoke Only): TC-001 (Register RW), TC-002 (Manual SPI Transfer), TC-007 (Auto DRDY Capture)
   - Scope: Isolated older `Simulation/spi_master_tb.sv` only; does NOT apply to current continuous-CS 72-bit RTL.
2. **`reports/review/2026-10-06-gemini-audit/audit.md`**:
   - Identifies specific root causes for unverified items (A1 through A11).
3. **`reports/review/2026-10-06-gemini-recovery-audit/audit.md`**:
   - Follow-up audit identifying findings R1 through R10. All requirements currently remain in recovery.
