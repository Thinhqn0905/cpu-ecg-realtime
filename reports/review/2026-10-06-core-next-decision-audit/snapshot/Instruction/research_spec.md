# RISC-V ECG DAQ — Research Specification

Version: 1.0
Date: 2026-10-05

## System Overview

This project implements a real-time electrocardiogram (ECG) data acquisition
system built around the CVA6 RISC-V processor core on Xilinx Artix-7 FPGA.
The system replaces traditional microcontroller-based ECG designs with an
integrated SoC-on-FPGA that provides deterministic timing, custom peripheral
integration, and optional hardware acceleration for biosignal processing.

## Target Application

- Continuous ECG monitoring (ambulatory, clinical, research)
- 1-lead to 12-lead acquisition capability
- Real-time R-peak detection and QRS morphology analysis
- Data streaming to host PC for visualization and storage
- Future: on-chip inference using lightweight ML models

## System Architecture

```
┌─────────────────────────────────────────────────────┐
│  Artix-7 FPGA (xc7a100tcsg324-1)                   │
│                                                     │
│  ┌──────────┐    ┌─────────┐    ┌──────────┐       │
│  │  CVA6    │◄──►│  AXI    │◄──►│  CLINT   │       │
│  │ RV32IMA  │    │ Xbar    │    │  PLIC    │       │
│  │ 6-stage  │    │         │    └──────────┘       │
│  └──────────┘    │         │                       │
│                  │         │◄──►┌──────────┐       │
│  ┌──────────┐    │         │    │ Boot ROM │       │
│  │ I-Cache  │◄──►│         │    └──────────┘       │
│  │ D-Cache  │    │         │                       │
│  └──────────┘    │         │◄──►┌──────────┐       │
│                  │         │    │  SRAM    │       │
│                  │         │    │ (BRAM)   │       │
│                  └────┬────┘    └──────────┘       │
│                       │                            │
│              ┌────────┴────────┐                   │
│              │   APB Bridge    │                   │
│              └────────┬────────┘                   │
│     ┌────────┬────────┼────────┬────────┐         │
│     ▼        ▼        ▼        ▼        ▼         │
│  ┌──────┐┌──────┐┌──────┐┌──────┐┌──────┐       │
│  │ UART ││ SPI  ││Timer ││ GPIO ││ DMA  │       │
│  │      ││Master││      ││      ││(opt) │       │
│  └──┬───┘└──┬───┘└──────┘└──┬───┘└──────┘       │
│     │       │               │                    │
└─────┼───────┼───────────────┼────────────────────┘
      │       │               │
      ▼       ▼               ▼
   Host PC  ADS1292R        LEDs/
   (USB/    (ECG AFE)       Debug
    UART)
```

## Hardware Components

### CVA6 Processor Core
- Configuration: cv32a6_ima_sv32_fpga_config_pkg
- ISA: RV32IMA (32-bit, integer, multiply, atomic)
- Pipeline: 6-stage, single-issue, in-order
- Cache: 8KB I-Cache, 8KB D-Cache (2-way, 128-bit lines)
- MMU: Sv32 (can be disabled for bare-metal)
- Privilege: M-mode + optional S/U modes

### ECG Analog Front-End Interface
- Primary: Texas Instruments ADS1292R (2-channel, 24-bit, SPI)
- Alternative: ADS1298 (8-channel, 24-bit, SPI) for 12-lead
- Fallback: AD8232 + external ADC for single-lead prototype
- Interface: SPI master with DRDY interrupt

### SoC Peripherals
| Peripheral | Interface | Purpose |
|---|---|---|
| SPI Master | APB slave | AFE chip communication |
| UART | APB slave | Host PC data streaming |
| Timer | APB slave | Sampling rate control, watchdog |
| GPIO | APB slave | LEDs, debug, AFE reset/power |
| PLIC | AXI slave | Platform interrupt controller |
| CLINT | AXI slave | Core timer, software interrupt |
| DMA (optional) | AXI master | High-throughput SPI→memory transfer |

## Sampling and Timing Budget

For 500 Hz, 2-channel, 24-bit acquisition (ADS1292R):

```
Sample period:     2.0 ms (500 Hz)
SPI read time:     ~50 µs (72 bits at 2 MHz SCLK + overhead)
Interrupt latency: ~1 µs (CVA6 at 50 MHz, ~50 cycles)
Firmware process:  ~10 µs (buffer management, optional filter)
UART transmit:     ~100 µs (6 bytes at 921600 baud)
Total per sample:  ~162 µs
Margin:            1838 µs (91.9% idle — ample headroom)
```

## Data Flow

1. ADS1292R asserts DRDY (falling edge) when new sample ready
2. PLIC routes interrupt to CVA6 → firmware ISR executes
3. ISR triggers SPI read: 24-bit status + 2×24-bit data (72 bits)
4. Firmware stores sample in circular buffer (BRAM-backed)
5. Main loop: read buffer → optional digital filter → UART packetize
6. UART transmits timestamped sample packet to host PC
7. Host PC: receive → display → store → analyze

## Acceptance Gates

| Gate | Criterion | Evidence Level |
|---|---|---|
| G1: Core boot | CVA6 boots, UART prints, GPIOs toggle | Board transcript |
| G2: SPI comm | SPI master reads ADS1292R device ID correctly | Board + scope |
| G3: ECG stream | Continuous 500 Hz data stream, no drops for 60s | Board + host log |
| G4: Latency | ADC-to-UART < 10 ms measured | Counter + scope |
| G5: Signal quality | Identifiable P-QRS-T complex in captured data | Host visualization |
| G6: Multi-channel | 2+ channels simultaneous, no cross-talk | Board + analysis |
| G7: R-peak detect | Firmware R-peak detection matches reference | Comparison report |
| G8: 12-lead ready | ADS1298 integration, all channels streaming | Board + host log |
