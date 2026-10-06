# Architectural Decision Record: CV32E40P Core as Candidate Controller

**Date:** 2026-10-06  
**Status:** PROPOSED CANDIDATE (In Integration / Evaluation)  
**Context & Scope:** Real-Time ECG Biopotential Acquisition SoC on Xilinx Artix-7 100T (`xc7a100tcsg324-1`)  
**References:**  
- `Instruction/research_analysis.md` (LeapSpace research analysis & core trade-offs)  
- `Instruction/architecture.md` (Baseline CVA6 system architecture & memory map)  
- `spec/ecg_soc_spec.md` (CV32E40P integration specification & register map)  
- `reports/review/2026-10-06-gemini-recovery-audit/audit.md` (Findings R1–R10)  

---

## 1. Decision Context

The baseline repository specification (`Instruction/architecture.md`, `CLAUDE.md`) originally designated OpenHW CVA6 (formerly Ariane, RV32IMA/RV64GC, 6-stage in-order pipeline with Sv32 MMU and AXI4 interconnect) as the processor core.

Subsequent architectural analysis (`Instruction/research_analysis.md`) identified that:
1. Real-time ECG acquisition (250–1000 Hz sample rate, 24-bit samples) is an I/O-bound and interrupt-latency-critical workload rather than a high-IPC compute workload.
2. CVA6 consumes an estimated ~15,000 LUTs and ~20 BRAMs on Artix-7, leaving constrained headroom if combined with dense neural network accelerators (such as the 128-MAC CNN-MAMBA sidecar requiring ~20,000 LUTs and 108 BRAMs).
3. The OpenHW Group **CV32E40P** (RV32IMC + CORE-V `Xpulpv2` extensions, 4-stage in-order pipeline, OBI bus) was cloned at commit `97086e9565f8145522ad6d62852123c0e5537529` as an active candidate to evaluate deterministic fast interrupts (`irq_fast_i[14:0]`) and compact DSP instructions (hardware loops, packed 16-bit SIMD, post-increment addressing).

---

## 2. Candidate Status & Limitations

1. **Candidate, Not Closed Architectural Decision:** CV32E40P is currently treated as an **integration candidate**. A formal, measured post-route resource and timing comparison between CVA6 and CV32E40P on the identical Artix-7 target has **not yet been executed**. Therefore, no claim of final PPA superiority or replacement of the upstream CVA6 baseline is made.
2. **Upstream Immutability:** The upstream `cva6/` repository remains intact and uncorrupted. The cloned `cv32e40p/` repository is kept as the candidate core directory.
3. **Bus Protocol Differences:**
   - CVA6 uses AXI4 / AXI4-Lite with PLIC/CLINT.
   - CV32E40P uses Open Bus Interface (OBI) request-grant protocols (`instr_*`, `data_*`) with direct fast vectored interrupts (`irq_i[30:16]`).
   - The SoC bridges OBI to APB3 via `RTL/ecg_soc/obi_to_apb.sv` to drive the peripheral subsystem (`uart`, `spi_master`, `timer`, `gpio`, `ecg_dma`).

---

## 3. Bus & Interrupt Interface Summary

### 3.1 Memory Mapping
- **Instruction TCM (I-TCM):** `0x0000_0000 – 0x0000_7FFF` (32 KB, Dual-port: Port A for instruction fetch, Port B for rodata / data load read).
- **Data TCM (D-TCM):** `0x0001_0000 – 0x0001_7FFF` (32 KB, Single-port data read/write with byte enables).
- **APB3 Peripherals:** `0x1000_0000 – 0x1FFF_FFFF` (UART, SPI, Timer, GPIO, DMA).
- **Coprocessor Region (Deferred):** `0x2000_0000 – 0x2FFF_FFFF` (MAMBA bridge disabled in baseline).

### 3.2 Fast Interrupt Allocation (`irq_fast_i[14:0]` -> `irq_i[30:16]`)
- `irq_fast[0]` (irq 16): UART RX
- `irq_fast[1]` (irq 17): UART TX Empty
- `irq_fast[2]` (irq 18): ADS1292R DRDY# (Highest priority biosignal interrupt)
- `irq_fast[3]` (irq 19): DMA Buffer Ready (32 samples captured)
- `irq_fast[4]` (irq 20): System Timer Tick
- `irq_fast[5]` (irq 21): GPIO Button / Lead-Off Event
- `irq_fast[6]` (irq 22): Coprocessor Event (Deferred)
- `irq_fast[14:7]`: Tied to 0

---

## 4. Verification & Evidence Contract

- **Compiler Provenance:** CV32E40P code must be compiled with a verified toolchain (`riscv32-unknown-elf-gcc`). Handwritten binary fallback images are strictly rejected.
- **Gate Requirement:** Real CPU instruction fetch, `.data` initialization from I-TCM to D-TCM, timer interrupt triggering, context preservation, and clean `mret` execution must be proven in simulation before any higher-level acquisition or DSP claims are advanced.
