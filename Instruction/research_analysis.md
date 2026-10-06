# Research Analysis: RISC-V Core Selection & Architecture for FPGA-based ECG SoC

**Date:** 2026-10-06  
**Reference Document:** `user_analyze/RISC-V_core_selection_for_FPGA-based_ECG_SoC_LeapSpace.pdf` (LeapSpace Deep Research Report)  
**Sister Project Reference:** `E:\ResearchOnWork\Backup\FPGA_MAMBA_ARTIX7_layers_support` (CNN-MAMBA Fold-SIMD Accelerator)  
**Target Platform:** Xilinx Artix-7 100T (`xc7a100tcsg324-1` on Digilent Arty A7-100T)

---

## 1. Executive Summary & Core Finding

The LeapSpace research document reveals a critical paradigm shift for this project:

> **An ECG SoC on Artix-7 is not primarily a compute-throughput problem; it is a deterministic acquisition and data-movement problem.**

Biomedical signal acquisition (ECG @ 250–1000 Hz, 24-bit samples) operates at sub-kHz to low-kHz sample rates. Raw CPU compute demand for data acquisition is minimal (< 5% CPU utilization even on low-end RV32 cores). The actual operational bottlenecks are:
1. **Deterministic interrupt service & jitter** (handling AFE `DRDY` transitions without losing frames).
2. **Buffer management** (absorbing burstiness and clock-domain crossing between SPI SCLK, SoC bus, and UART/host).
3. **Autonomous data movement** (DMA / ping-pong BRAM buffering) to decouple real-time capture from compute/communication.
4. **FPGA Resource Budgeting** for future on-chip neural acceleration (CNN-MAMBA inference engine).

---

## 2. In-Depth RISC-V Core Comparison for Artix-7

| Core | Architecture / Pipeline | ISA | Estimated Artix-7 LUTs | Artix-7 FFs | BRAM (Core overhead) | Pros for ECG SoC | Cons / Risk Factors | Recommendation Rank |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Ibex** (lowRISC) | 2-stage (in-order) | RV32IMC / EMC | **~3,841** | ~2,030 | 0–2 | • Verified Artix-7 & Zynq data<br>• Highly compact<br>• Deterministic 2-stage pipeline<br>• Leaves 94% LUTs for accelerators | • Limited IPC for heavy software DSP (requires HW offload) | **#1 (Recommended for pure Control Plane)** |
| **CV32E40P** (OpenHW) | 4-stage (in-order) | RV32IMFC / Xpulp | **~5,500 – 6,500** | ~3,200 | 0–2 | • Fast interrupt / CLIC (down to 6 cycles)<br>• Hardware loops & DSP extensions<br>• High embedded efficiency | • Slightly higher LUT usage<br>• Artix-7 evidence less widespread than Ibex | **#2 (Strong contender if fast IRQ needed)** |
| **VexRiscv** (SpinalHDL) | 2–5 stages (configurable) | RV32IMAFDC | **~2,000 – 4,500** | ~1,800 | 0–4 | • Highly optimized for Xilinx LUTs<br>• Custom instruction & plugin support<br>• Excellent Fmax on Artix-7 | • SpinalHDL/Scala source complicates SystemVerilog toolchains | **#3 (Great alternative if toolchain permits)** |
| **NEORV32** | 2-stage (folded) | RV32IMAC | **~2,500 – 3,500** | ~1,500 | 0–2 | • Extremely complete SoC ecosystem included<br>• Very clean VHDL/SV integration | • Moderate Fmax; less ASIC portability | **#4** |
| **CVA6** (OpenHW, current baseline) | 6-stage (single-issue) | RV32IMA / RV64GC | **~15,000** | ~8,000 | ~20 (Caches/BTB) | • Full MMU (Sv32) for Linux<br>• Standardized CV-X-IF coprocessor interface<br>• Rich AXI interconnect infrastructure | • **Heavy resource footprint** (~24% of Artix-7 100T LUTs)<br>• High BRAM consumption for caches<br>• Over-engineered for 500 Hz acquisition | **#5 (Over-scaled for pure DAQ; viable if Linux or heavy C-stack required)** |

### Resource Allocation Trade-Off with CNN-MAMBA Accelerator

On the **Artix-7 100T** (`xc7a100tcsg324-1`):
- Total LUTs: **63,400**
- Total BRAM36k: **135** (or 270 BRAM18k)
- Total DSP48E1: **240**

| Component | With CVA6 (Current) | With Ibex / CV32E40P (Recommended) |
| :--- | :--- | :--- |
| **CPU Core + Interconnect** | ~15,000 LUT, 20 BRAM | ~4,500 LUT, 2 BRAM |
| **SoC Peripherals (SPI, UART, Timer, DMA)** | ~4,000 LUT, 4 BRAM | ~3,500 LUT, 4 BRAM |
| **CNN-MAMBA Accelerator** (from backup repo) | ~20,000 LUT, 108 BRAM, 25 DSP | ~20,000 LUT, 108 BRAM, 25 DSP |
| **Total System Footprint** | **~39,000 LUT (61.5%)**, **132 BRAM (97.8%)** | **~28,000 LUT (44.2%)**, **114 BRAM (84.4%)** |
| **Margin / Feasibility on Artix-7 100T** | **Extremely Dangerous**: 98% BRAM utilization causes severe routing congestion. | **Safe & Balanced**: 84% BRAM and 44% LUT leaves comfortable headroom for timing closure. |

---

## 3. Gap Analysis: Current Architecture vs. Literature Best Practices

| Domain | Current Architecture (`Instruction/architecture.md`) | Literature / LeapSpace Best Practice | Identified Gap & Action Plan |
| :--- | :--- | :--- | :--- |
| **CPU Role** | CVA6 performing interrupt service + firmware filtering + UART streaming | Dedicated MCU control plane (Ibex/CV32E40P) orchestrating hardware pipelines | **Gap:** CVA6 is over-scaled. Refactor to allow modular core replacement (maintain AXI/APB boundaries so either CVA6 or Ibex can slot in). |
| **Data Capture** | Pure ISR-driven SPI read (CPU bit-bangs or reads SPI RX FIFO in interrupt) | Autonomous SPI capture into asynchronous FIFO + Ping-Pong BRAM buffer | **Gap:** Software ISR for every 72-bit sample creates jitter. Implement hardware auto-capture on `DRDY#` into double-buffer. |
| **Buffering** | Simple circular buffer in general SRAM | Hardware Ping-Pong BRAM buffer + optional lightweight scatter-gather DMA | **Gap:** Add hardware ping-pong buffer with half/full block interrupt. CPU only wakes once per block (e.g., every 32 samples = 64 ms). |
| **UART Telemetry** | Raw continuous sample streaming over UART (14 bytes @ 500 Hz = 7 kB/s) | Layered telemetry: Debug/raw export vs. Feature/classification event export | **Gap:** Align UART packet format with CNN-MAMBA event streaming (streaming arrhythmia alerts vs. continuous raw trace). |

---

## 4. Matching to CNN-MAMBA Reference Architecture

The sister project (`FPGA_MAMBA_ARTIX7_layers_support`) defines:
- **Compute Unit:** 16x8 Fold-SIMD Processing Element (PE) array (128 MACs) for 1D temporal convolution + Mamba SSM state updates.
- **Sidecar:** Narrow state-stationary selective-SSM sidecar (4 lanes).
- **Interface:** Custom streaming interface / AXI4-Stream slave with control registers mapped via AXI-Lite/APB.

### Unified Chip Architecture
```
+-----------------------------------------------------------------------------------+
|                              Artix-7 100T FPGA Top                                |
|                                                                                   |
|  +--------------------+       +----------------------+      +------------------+  |
|  |   ADS1292R AFE     |       |   Hardware Engine    |      |  Host Interface  |  |
|  |  (Off-Chip PMOD)   |       |                      |      |                  |  |
|  |                    |       |  [Auto-SPI Capture]  |      |   [UART Core]    |  |
|  |  DRDY# ----------->|------>|          |           |      |   115.2k-921.6k  |  |
|  |  SPI (MISO/MOSI/   |<======|   [Async FIFO]       |      |                  |  |
|  |       SCLK/CS#)    |       |          |           |      +--------^---------+  |
|  +--------------------+       |  [Ping-Pong BRAM]    |               |            |
|                               +----------+-----------+               |            |
|                                          | AXI-Stream                | APB3       |
|                                          v                           |            |
|                               +----------------------+               |            |
|                               |  CNN-MAMBA Coprocessor|               |            |
|                               |  (128 MAC PE Array + |               |            |
|                               |   SSM State Sidecar) |               |            |
|                               +----------+-----------+               |            |
|                                          | Output Events / Features  |            |
|                                          v                           |            |
|  +---------------------------------------+---------------------------+---------+  |
|  |                     Control Plane CPU (Ibex / CVA6)                         |  |
|  |  - Supervises AFE startup & calibration sequence                            |  |
|  |  - Configures CNN-MAMBA layer weights & thresholds                          |  |
|  |  - Handles packetization, timestamps, error detection                       |  |
|  +-----------------------------------------------------------------------------+  |
+-----------------------------------------------------------------------------------+
```

---

## 5. Recommended Workflow & Verification Requirements

Following the proven 6-phase gated design pattern from the backup repository:

1. **Phase 0 & 1 (Spec & Parsing):** Formalize the peripheral registers and timing constraints in `spec/` with unique `REQ-ID` tags.
2. **Phase 2 (Configuration):** Parameterize SPI dividers, FIFO depths, and memory mappings (`config_ui`).
3. **Phase 3 (RTL & SVA Generation):**
   - Synthesizable SystemVerilog matching CVA6 / OpenHW design standards (`always_ff`, `always_comb`, ANSI ports).
   - Formal SVA properties binding to SPI protocol compliance (`tCSSC`, `tSCCS`, `CPOL=0/CPHA=1`).
4. **Phase 4 & 5 (Testbench & Verification):**
   - Self-checking testbench with behavioral `ADS1292R` slave model.
   - Simulation using Icarus Verilog (`iverilog`) or Verilator.
   - Requirement Traceability Matrix (RTM) verifying 100% of REQ-IDs before physical synthesis.
5. **Phase 6 (Documentation & Synthesis Gate):**
   - Automated synthesis report generation with Vivado.
   - Verification of timing closure at 50–100 MHz on Artix-7.
