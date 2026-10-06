# RISC-V ECG Data Acquisition System — Workspace Operating Rules

## Project Identity

This workspace develops a **RISC-V-based real-time ECG data acquisition system**
on FPGA. The CVA6 (formerly Ariane) 6-stage in-order RISC-V processor core
serves as the central controller: managing the analog front-end (AFE) chip via
SPI, streaming digitized cardiac signals through on-chip FIFOs, and outputting
data over UART/USB to a host PC. The target is a complete SoC-on-FPGA for
continuous, clinical-grade ECG monitoring.

## Mandatory Session Start

Before answering, planning, editing, or running a tool in this worktree:

1. Read `Instruction/session_checklist.md` and continue any item marked
   `in_progress`.
2. Read `Instruction/research_spec.md`,
   `Instruction/evidence_contract.md`,
   `Instruction/claim_integrity.md`,
   `Instruction/design_rules.md`, and
   `Instruction/todo.md`.
3. Before editing or running a script under `Synthesis/`, `simulation/`, or
   `reports/evidence/`, also read `Instruction/eda_script_style.md`.
4. For architecture or research changes, also read
   `Instruction/architecture.md` and `Instruction/roadmap.md`.
5. Inspect `git status --short` before editing. Never revert unrelated work.

Repeat these steps after context compaction, a resumed turn, or a new chat. If
a required contract is absent, recreate it before modifying RTL.

## Branch Purpose

This worktree develops:

> A RISC-V SoC for real-time ECG data acquisition: CVA6 (RV32IMA) processor
> core with SPI master (AFE interface), interrupt controller (PLIC/CLINT),
> timer, UART, GPIO, DMA controller, and on-chip FIFO buffering — targeting
> Xilinx Artix-7 FPGA for continuous biosignal streaming and processing.

The upstream `cva6/` repository is the immutable reference baseline. Custom
ECG-specific work belongs under:
- `RTL/ecg_soc/` — SoC integration, peripherals, AFE interface
- `RTL/ecg_processing/` — on-chip signal processing (R-peak, QRS detection)
- `Firmware/` — RISC-V C/assembly firmware for ECG acquisition
- `Simulation/` — testbenches and verification
- `Synthesis/fpga/ecg_artix7/` — Vivado project, XDC, Tcl scripts

Do not modify files inside `cva6/` without explicit justification.

## FPGA Target

- **Device:** Xilinx Artix-7 (xc7a100tcsg324-1 or xc7a35tcpg236-1)
- **Board:** Digilent Arty A7-100T (primary) or Arty A7-35T (constrained)
- **System clock:** 100 MHz oscillator → MMCM-generated compute clock
- **Target frequency:** 50–100 MHz for the SoC (ECG does not require 200 MHz)
- Every Vivado campaign uses an explicit top, filelist, part, constraint,
  source hash, immutable run directory, and separate reports for synthesis,
  placement, routing, timing, utilization, DSP/BRAM, and DRC.
- The deployment board uses the official Arty-A7 Master XDC. Verify board
  revision and pin mapping for SPI/UART/GPIO connections to the AFE board.

## ECG System Constraints

- **Sampling rate:** 250–1000 Hz per channel (configurable)
- **Resolution:** 24-bit ADC (ADS1292R) or 16-bit (AD8232 + external ADC)
- **Channels:** 1–3 lead (expandable to 12-lead with ADS1298)
- **AFE interface:** SPI master at 1–4 MHz SCLK
- **Data output:** UART at 115200–921600 baud to host PC
- **Latency budget:** < 10 ms from ADC sample to UART output
- **Interrupt-driven:** DRDY pin from AFE triggers interrupt → SPI read → FIFO → UART

## Checklist Protocol

- Every implementation goal has one current checklist in
  `Instruction/session_checklist.md`.
- Start a new numbered checklist for a materially new goal. Mark steps only as
  `pending`, `in_progress`, or `complete`.
- Archive the replaced checklist under `Instruction/archive/YYYYMMDD_HHMM/`.
  Preserve historical evidence. Do not use automatic retention or pruning to
  remove versions containing unique evidence.
- A checklist is not evidence. Link completion to an exact command, report,
  source revision, or test log.

## Claim Integrity — Mandatory

Before reporting a result or marking an evidence gate complete:

- Read `Instruction/claim_integrity.md` at session start, before issuing a
  report, updating a checklist, or declaring a gate complete.
- Identify the exact source revision, workload, implementation boundary and
  measurement interval.
- Verify raw artifacts, terminal exit status and required result census.
- Report missing or incompatible evidence as NOT_VERIFIED.
- Never substitute mock data, golden replay, or estimated frequency
  conversion for measurement.
- Preserve failed and rejected evidence; record dated corrections.
- Do not claim peripheral integration from filelist inclusion alone.
- Do not claim real-time ECG performance from simulation without matched
  timing and throughput analysis.

## Architecture Boundary

- CVA6 core configuration: `cv32a6_ima_sv32_fpga_config_pkg` (RV32IMA, Sv32,
  FPGA-optimized) is the starting point. Extensions (C, F) added only after
  resource analysis.
- SoC peripherals are AXI/APB-attached. Use the existing `corev_apu/`
  infrastructure (CLINT, PLIC, AXI interconnect) where possible.
- SPI master for AFE is a new peripheral — implement as APB slave with
  interrupt support and configurable clock divider.
- DMA controller is optional — implement only after measuring whether
  interrupt-driven SPI+UART meets latency requirements.
- On-chip processing (R-peak detection, QRS morphology) is firmware-first.
  Hardware accelerators only after profiling shows firmware cannot meet
  real-time deadlines.

## RTL And Verification Boundary

- Candidate SoC RTL under `RTL/ecg_soc/` must cleanly integrate with CVA6
  via AXI/APB interfaces.
- No `real`, `shortreal`, or DPI math in synthesizable RTL.
- Unit verification precedes composition: SPI master → UART → interrupt
  controller → timer → integrated SoC → firmware test.
- Simulation must include realistic SPI transaction timing with AFE chip
  models (behavioral SPI slave testbench).

## Firmware Boundary

- Bare-metal C firmware (no OS initially). FreeRTOS only after bare-metal
  proves insufficient for multi-channel management.
- Firmware responsibilities: AFE initialization, SPI DMA/interrupt handling,
  circular buffer management, UART packetization, optional digital filtering.
- Use RISC-V GCC cross-compiler (riscv32-unknown-elf-gcc).
- Boot from on-chip ROM or SPI flash.

## Verification And Tool Order

1. CVA6 core standalone synthesis and simulation on Artix-7.
2. Individual peripheral RTL verification (SPI, UART, timer, GPIO).
3. SoC integration with AXI/APB interconnect.
4. Firmware compilation and bare-metal test on simulator.
5. FPGA synthesis, place & route, timing closure.
6. Board bring-up: UART echo → SPI loopback → AFE communication.
7. ECG signal acquisition and real-time streaming validation.
8. Signal quality and latency measurement.

Do not launch Vivado synthesis after each small edit. Aggregate a coherent
block, pass simulation, then run the next expensive gate.
