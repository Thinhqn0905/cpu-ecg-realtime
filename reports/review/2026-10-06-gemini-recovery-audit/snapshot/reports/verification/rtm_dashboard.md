# Requirement Traceability Matrix (RTM) Dashboard

**Project:** RISC-V Real-Time ECG Data Acquisition SoC  
**Target Platform:** Xilinx Artix-7 100T (`xc7a100tcsg324-1`)  
**Date:** 2026-10-06 (Corrected per static audit)  
**Status:** AUDIT REVISED — EVIDENCE AUDIT IN PROGRESS  
**Audit Reference:** `reports/review/2026-10-06-gemini-audit/audit.md`  
**Original Dashboard (Preserved):** `reports/review/2026-10-06-gemini-audit/rtm_dashboard.original.md`

---

## 1. Traceability Summary

| Total Requirements | Verified with Raw Evidence | Pending Verification | Deferred / Stub | Overall Status |
| :---: | :---: | :---: | :---: | :---: |
| **26** | **3 (SPI smoke sim)** | **22** | **1 (MAMBA)** | **In Recovery (Task 1-5)** |

---

## 2. Requirement-to-Evidence Mapping Table

| Requirement ID | Category | Target Module | Stated Method | Current Verification Evidence & Status | Audit Disposition |
| :--- | :--- | :--- | :--- | :--- | :---: |
| `REQ-SYS-001` | System | `ecg_soc_top` | Full-system sim | Unverified full-system scenario | **NOT_VERIFIED** |
| `REQ-SYS-002` | Resource | `ecg_soc_top` | Vivado synth | No Vivado synthesis report or DCP | **NOT_VERIFIED** |
| `REQ-SYS-003` | Latency | `ecg_soc_top` | End-to-end sim | No measured timing trace | **NOT_VERIFIED** |
| `REQ-SPI-001` | Protocol | `spi_master` | Simulation | Passed in `Simulation/spi_master_tb.sv` (TC-002) | **PASS (Sim)** |
| `REQ-SPI-002` | Timing | `spi_master` | Simulation | Passed in `Simulation/spi_master_tb.sv` (TC-001) | **PASS (Sim)** |
| `REQ-SPI-003` | Acquisition | `spi_master` | AFE model sim | Passed in `Simulation/spi_master_tb.sv` (TC-007) | **PASS (Sim)** |
| `REQ-SPI-004` | Timing | `spi_master` | SVA Assertion | SVA `p_cs_setup_time` bind uncompiled | **NOT_VERIFIED** |
| `REQ-SPI-005` | Timing | `spi_master` | SVA Assertion | SVA `p_done_pulse` bind uncompiled | **NOT_VERIFIED** |
| `REQ-BUF-001` | Buffering | `sync_fifo` | Boundary sim | No test log for standalone FIFO | **NOT_VERIFIED** |
| `REQ-BUF-002` | Buffering | `ecg_dma` | Simulation | Hardware has channels hardcoded to 0 | **NOT_VERIFIED** |
| `REQ-BUF-003` | Interrupt | `ecg_dma` | Simulation | Interrupt generation unverified | **NOT_VERIFIED** |
| `REQ-BUF-004` | Safety | `ecg_dma` | Error injection | Overflow flag latch unverified | **NOT_VERIFIED** |
| `REQ-UART-001` | Protocol | `uart_controller` | Loopback sim | Standalone UART test log missing | **NOT_VERIFIED** |
| `REQ-UART-002` | Timing | `uart_controller` | Baud sweep | Standalone baud sweep missing | **NOT_VERIFIED** |
| `REQ-UART-003` | Packet | `uart_controller` | Packet sim | Framing unverified with real data | **NOT_VERIFIED** |
| `REQ-UART-004` | Integrity | `uart_controller` | Golden CRC | Packet CRC unverified | **NOT_VERIFIED** |
| `REQ-APB-001` | Bus | `apb_interconnect` | APB check | APB interconnect has slave decode issues | **NOT_VERIFIED** |
| `REQ-APB-002` | Bus | `apb_interconnect` | Unmapped sweep | Unmapped read returns unverified | **NOT_VERIFIED** |
| `REQ-APB-003` | Bus | `apb_interconnect` | Waveform inspect | Zero wait-state unverified | **NOT_VERIFIED** |
| `REQ-CORE-001`| CPU Core | `cv32e40p_ecg_soc_top`| Arch check | Core instantiated; wrapper ports broken (A1) | **NOT_VERIFIED** |
| `REQ-CORE-002`| Bus Bridge | `obi_to_apb` | SVA Assertions | `obi_to_apb_sva.sv` does not exist on disk | **NOT_VERIFIED** |
| `REQ-CORE-003`| Memory | `tcm_sram` | Memory check | NOP initialized; I-TCM unreadable by data (A3)| **NOT_VERIFIED** |
| `REQ-CORE-004`| Fast IRQ | `cv32e40p_ecg_soc_top`| Vectoring sim | Startup lacked context save/mret (A8) | **NOT_VERIFIED** |
| `REQ-DSP-001` | Filter DSP | `ecg_fir_pulp.S` | Assembly bench | 28 cycles contradicted by single-issue core | **NOT_VERIFIED** |
| `REQ-DSP-002` | Detection | `pan_tompkins.c` | Algorithmic test | Deriv overflow bug (A7); no MIT-BIH run | **NOT_VERIFIED** |
| `REQ-MAMBA-001`| Accelerator| `mamba_bridge` | Co-simulation | Hard-coded counter delay stub (A2) | **DEFERRED** |

---

## 3. Verified Artifact Reference

1. **`reports/review/2026-10-06-source-audit/spi_run.json`**:
   - Tool: Icarus Verilog 12.0 devel (`vvp`)
   - Exit Code: 0
   - Verified Tests: TC-001 (Register RW), TC-002 (Manual SPI Transfer), TC-007 (Auto DRDY Capture)
   - Scope: Isolated `Simulation/spi_master_tb.sv` only
2. **`reports/review/2026-10-06-gemini-audit/audit.md`**:
   - Identifies specific root causes for unverified items (A1 through A11).
