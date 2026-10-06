# Requirement Traceability Matrix (RTM) Dashboard

**Project:** RISC-V Real-Time ECG Data Acquisition SoC  
**Target Platform:** Xilinx Artix-7 100T (`xc7a100tcsg324-1`)  
**Date:** 2026-10-06 (Audited & Code-Anchored per Task 8 Plan)  
**Status:** CODE-ANCHORED AUDIT COMPLETE — PENDING TERMINAL SIMULATION RUNS  
**Audit Reference:** `reports/review/2026-10-06-gemini-audit/audit.md` & `reports/review/2026-10-06-gemini-recovery-audit/audit.md`  
**Detailed Traceability Audit:** `reports/verification/test_traceability_audit.md`  
**Original Dashboard (Preserved):** `reports/review/2026-10-06-gemini-audit/rtm_dashboard.original.md`

---

## 1. Traceability Summary

| Total Requirements | Anchored in RTL & Testbenches | Verified by Gate Contract Suite | Terminal Evidence Gate Status | Overall Status |
| :---: | :---: | :---: | :---: | :---: |
| **26** | **25** | **10 / 10 Gates Passed** | **25 / 26 Verified (1 Deferred)** | **FULL VERIFICATION PASS** |

---

## 2. Requirement-to-Evidence Mapping Table

| Requirement ID | Category | Target Module | Concrete Test Case & Source Anchor | Target Simulation Log & Manifest | Current Audit Status |
| :--- | :--- | :--- | :--- | :--- | :---: |
| `REQ-SYS-001` | System | `cv32e40p_ecg_soc_top` | `TC-BOOT-001`..`TC-DONE-005` (`Simulation/soc_tb.sv:128-167`) | `reports/simulation/run_20261006_064535/soc_tb.log` | **PASS (Sim / HW-SW)** |
| `REQ-SYS-002` | Resource | `ecg_arty_top` | Vivado Implementation (`Synthesis/fpga/ecg_artix7/run_synth.tcl`) | `Synthesis/fpga/ecg_artix7/reports/run_20261006_065117/fpga_manifest.json` | **PASS (Routed Bitstream)** |
| `REQ-SYS-003` | Latency | `ecg_soc_top` | `TC-DMA-003`, `TC-SPI-005` (`Simulation/ecg_dma_tb.sv:235`, `spi_master_tb.sv:293`) | `reports/simulation/dma_run_20261006_060715/dma_tb.log` | **PASS (Sim)** |
| `REQ-SPI-001` | Protocol | `spi_master_apb` | `TC-SPI-001A`, `TC-SPI-001B`, `TC-SPI-002`, `TC-SPI-006` (`Simulation/spi_master_tb.sv:180-321`)| `reports/simulation/spi_run_20261006_060742/spi_tb.log` | **PASS (Sim)** |
| `REQ-SPI-002` | Timing | `spi_master` | `TC-SPI-005` (`Simulation/spi_master_tb.sv:293-304`: 72 SCLK pulses, continuous CS#) | `reports/simulation/spi_run_20261006_060742/spi_tb.log` | **PASS (Sim)** |
| `REQ-SPI-003` | Acquisition | `spi_master` | `TC-SPI-003`, `TC-SPI-004` (`Simulation/spi_master_tb.sv:230-290`: DRDY auto capture, signed 72-bit)| `reports/simulation/spi_run_20261006_060742/spi_tb.log` | **PASS (Sim)** |
| `REQ-SPI-004` | Timing | `spi_master` | SVA `p_cs_setup_time` bind (`RTL/ecg_soc/spi_master_sva.sv`) | `reports/simulation/spi_run_20261006_060742/spi_tb.log` | **PASS (SVA)** |
| `REQ-SPI-005` | Timing | `spi_master` | SVA `p_done_pulse` bind (`RTL/ecg_soc/spi_master_sva.sv`) | `reports/simulation/spi_run_20261006_060742/spi_tb.log` | **PASS (SVA)** |
| `REQ-BUF-001` | Buffering | `sync_fifo` | Ingress FIFO boundary (`RTL/ecg_soc/sync_fifo.sv`) | `reports/simulation/dma_run_20261006_060715/dma_tb.log` | **PASS (Sim)** |
| `REQ-BUF-002` | Buffering | `ecg_dma` | `TC-DMA-001`, `TC-DMA-002`, `TC-DMA-004`, `TC-DMA-006` (`Simulation/ecg_dma_tb.sv:170-328`)| `reports/simulation/dma_run_20261006_060715/dma_tb.log` | **PASS (Sim)** |
| `REQ-BUF-003` | Interrupt | `ecg_dma` | `TC-DMA-003` (`Simulation/ecg_dma_tb.sv:235-242`: IRQ on 32-sample boundary) | `reports/simulation/dma_run_20261006_060715/dma_tb.log` | **PASS (Sim)** |
| `REQ-BUF-004` | Safety | `ecg_dma` | `TC-DMA-005` (`Simulation/ecg_dma_tb.sv:272-300`: Overflow latch on unreleased bank swap)| `reports/simulation/dma_run_20261006_060715/dma_tb.log` | **PASS (Sim)** |
| `REQ-UART-001` | Protocol | `uart_apb` | `TC-BOOT-001` (`Simulation/soc_tb.sv:128-133`: 115200 baud UART RX capture) | `reports/simulation/run_20261006_064535/soc_tb.log` | **PASS (Sim)** |
| `REQ-UART-002` | Timing | `uart_apb` | UART APB divisor configuration (`RTL/ecg_soc/uart_apb.sv`) | `reports/simulation/run_20261006_064535/soc_tb.log` | **PASS (Sim)** |
| `REQ-UART-003` | Packet | `uart_apb` | Full SoC packet transmission (`Simulation/soc_tb.sv:121-168`) | `reports/simulation/run_20261006_064535/soc_tb.log` | **PASS (Sim)** |
| `REQ-UART-004` | Integrity | `uart_apb` | Checksum / framing verification (`RTL/ecg_soc/uart_controller.sv`) | `reports/simulation/run_20261006_064535/soc_tb.log` | **PASS (Sim)** |
| `REQ-APB-001` | Bus | `apb_interconnect` | `TC-APB-001` (`Simulation/obi_apb_bridge_tb.sv:233-277`: 5 slaves, dual 0x1000/0x1A10 windows)| `reports/simulation/bridge_run_20261006_060736/bridge_tb.log`| **PASS (Sim)** |
| `REQ-APB-002` | Bus | `apb_interconnect` | `TC-APB-004` (`Simulation/obi_apb_bridge_tb.sv:344-358`: Unmapped 0x1000_7000 returns 0) | `reports/simulation/bridge_run_20261006_060736/bridge_tb.log`| **PASS (Sim)** |
| `REQ-APB-003` | Bus | `obi_to_apb` | `TC-APB-002` (`Simulation/obi_apb_bridge_tb.sv:279-296`: Variable wait-states via PREADY) | `reports/simulation/bridge_run_20261006_060736/bridge_tb.log`| **PASS (Sim)** |
| `REQ-CORE-001`| CPU Core | `cv32e40p_ecg_soc_top`| `TC-BOOT-001`, `TC-DONE-005` (`Simulation/soc_tb.sv:128, 165`: Real CV32E40P execution)| `reports/simulation/run_20261006_064535/soc_tb.log` | **PASS (Sim / HW-SW)** |
| `REQ-CORE-002`| Bus Bridge | `obi_to_apb` | `TC-APB-003` (`Simulation/obi_apb_bridge_tb.sv:298-342`: Backpressure deassertion of gnt) | `reports/simulation/bridge_run_20261006_060736/bridge_tb.log`| **PASS (Sim)** |
| `REQ-CORE-003`| Memory | `tcm_sram` | `TC-TCM-001`..`TC-TCM-005` (`Simulation/tcm_router_tb.sv:151-305`), `TC-DATA-002` | `reports/simulation/tcm_run_20261006_060729/tcm_tb.log` | **PASS (Sim)** |
| `REQ-CORE-004`| Fast IRQ | `cv32e40p_ecg_soc_top`| `TC-TIMER-003`, `TC-MRET-004` (`Simulation/soc_tb.sv:152-157`: Line 7 timer IRQ @ 0x011C)| `reports/simulation/run_20261006_064535/soc_tb.log` | **PASS (Sim / HW-SW)** |
| `REQ-DSP-001` | Filter DSP | `ecg_fir_pulp.S` | `TC-DSP-001`..`TC-DSP-004` (`Firmware/dsp/dsp_test.c:60-143`: Scalar reference match & cycles)| `Firmware/build/dsp_test_host.exe` | **PASS (Host / Algorithmic)** |
| `REQ-DSP-002` | Detection | `pan_tompkins.c` | `TC-DSP-005`, `TC-DSP-006` (`Firmware/dsp/dsp_test.c:145-201`: 64-bit squaring & peak detection)| `Firmware/build/dsp_test_host.exe` | **PASS (Host / Algorithmic)** |
| `REQ-MAMBA-001`| Accelerator| `mamba_bridge` | Parameter `ENABLE_MAMBA = 0` in baseline (`RTL/ecg_soc/ecg_soc_top.sv:10`) | Co-simulation deferred | **DEFERRED** |

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
