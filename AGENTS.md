# RISC-V ECG DAQ — Agent Operating Rules

## Mandatory Session Start

Before answering, planning, editing, or running a tool in this worktree:

1. Read `Instruction/session_checklist.md` and continue any item marked
   `in_progress`.
2. Read `Instruction/research_spec.md`,
   `Instruction/evidence_contract.md`,
   `Instruction/claim_integrity.md`,
   `Instruction/design_rules.md`, and
   `Instruction/todo.md`.
3. Before editing or running a script under `Synthesis/`, `Simulation/`, or
   `reports/evidence/`, also read `Instruction/eda_script_style.md`.
4. For architecture or research changes, also read
   `Instruction/architecture.md` and `Instruction/roadmap.md`.
5. Inspect `git status --short` before editing. Never revert unrelated work.

Repeat these steps after context compaction, a resumed turn, or a new chat. If
a required contract is absent, recreate it before modifying RTL.

## Branch Purpose

This worktree develops:

> A RISC-V SoC for real-time ECG data acquisition using the CVA6 processor
> core (RV32IMA) on Xilinx Artix-7 FPGA. The system interfaces with analog
> front-end chips (ADS1292R/ADS1298) via SPI, processes biosignals in
> firmware or hardware accelerators, and streams data to a host via UART/USB
> for clinical-grade ECG monitoring.

The upstream `cva6/` repository is the immutable reference baseline. New
ECG-specific RTL belongs under `RTL/ecg_soc/` and `RTL/ecg_processing/`.
Firmware under `Firmware/`. Do not silently modify upstream CVA6 files.

## FPGA Target Override

This project targets Artix-7 deployment with the following constraints:

- **Part:** xc7a100tcsg324-1 (Arty A7-100T) or xc7a35tcpg236-1 (Arty A7-35T)
- **Board:** Digilent Arty A7-100T primary, A7-35T constrained variant
- **Clock:** 100 MHz board oscillator → MMCM/BUFG-generated system clock
  (50–100 MHz). Do not constrain the oscillator as compute frequency.
- **SoC clock budget:** 50 MHz minimum, 100 MHz target for processing headroom
- Use the official Arty-A7-100 Master XDC. Verify board revision and PMOD
  pin mapping for SPI/interrupt connections to ECG AFE breakout board.
- Never add Xilinx attributes, primitives, or XDC assumptions to upstream
  `cva6/` source files. FPGA adaptations use wrapper modules.

## ECG Real-Time Constraints

- Sampling: 250–1000 Hz/channel, 24-bit resolution (ADS1292R SPI)
- SPI SCLK: 1–4 MHz, interrupt-driven via DRDY pin
- End-to-end latency budget: ADC sample → SPI read → processing → UART < 10 ms
- UART output: 115200–921600 baud continuous streaming
- Multi-channel: 1–3 lead minimum, 12-lead with ADS1298 expansion

## Checklist Protocol

- Every implementation goal has one current checklist in
  `Instruction/session_checklist.md`.
- Start a new numbered checklist for a materially new goal. Mark steps only as
  `pending`, `in_progress`, or `complete`.
- Archive the replaced checklist under `Instruction/archive/YYYYMMDD_HHMM/`.
  Preserve historical evidence.
- A checklist is not evidence. Link completion to an exact command, report,
  source revision, or test log.

## Claim Integrity — Mandatory

Before reporting a result or marking an evidence gate complete:

- Read `Instruction/claim_integrity.md` at session start, before issuing a
  report, updating a checklist, or declaring a gate complete.
- Identify the exact source revision, workload, boundary and measurement.
- Report missing evidence as NOT_VERIFIED.
- Never substitute simulation for board measurement, or UART echo for AFE
  communication proof.
- Preserve failed and rejected evidence; record dated corrections.

## Architecture Boundary

- CVA6 RV32IMA is the processor core. Do not switch cores without explicit
  justification and resource comparison.
- Peripheral integration via AXI4/APB bus using CVA6's existing interconnect.
- SPI master is a new custom peripheral (APB slave + interrupt).
- Firmware-first approach: digital filtering, R-peak detection, QRS analysis
  in C firmware before considering hardware accelerators.
- Hardware accelerators only after firmware profiling proves real-time
  violation.

## RTL Coding Rules

- SystemVerilog for all new RTL. Match CVA6's coding style.
- `always_ff` for state, `always_comb` for combinational logic.
- No `real`, `shortreal`, or DPI math in synthesizable RTL.
- Structural module boundaries: one function per module.
- Ready/valid handshake protocol for data interfaces.
- Parameterized designs: configurable SPI clock divider, FIFO depth,
  UART baud rate.

## Verification Order

1. CVA6 standalone synthesis/simulation on Artix-7
2. SPI master RTL unit test (loopback, timing)
3. UART controller unit test
4. Timer/interrupt controller test
5. SoC integration test (CVA6 + peripherals)
6. Firmware compilation and ISS simulation
7. FPGA synthesis + place & route + timing closure
8. Board bring-up sequence: UART → SPI loopback → AFE → ECG stream
9. Signal quality and latency measurement

## EDA Script Boundary

Default XDC/Tcl must expose named ports, units, assumptions, and direct
Vivado commands. Do not hide the top, filelist, clock, or I/O contract behind
environment wrappers or custom Tcl procedures.
