# CPU-ECG: RISC-V Real-Time ECG Data Acquisition & Processing SoC

[![Architecture: CV32E40P](https://img.shields.io/badge/Core-OpenHW_CV32E40P_RV32IMC+Xpulpv2-blue.svg)](https://github.com/openhwgroup/cv32e40p)
[![Bus: Harvard OBI](https://img.shields.io/badge/Bus-Harvard_OBI_to_APB3-orange.svg)]()
[![AFE: ADS1292R](https://img.shields.io/badge/AFE-ADS1292R_24--bit_1MHz_SPI-red.svg)]()
[![FPGA: Artix-7](https://img.shields.io/badge/FPGA-Xilinx_Artix--7_xc7a100t-green.svg)]()
[![ASIC: Sky130](https://img.shields.io/badge/ASIC-OpenLane_SkyWater_130nm-purple.svg)]()
[![Gates: 10 Strict Contracts](https://img.shields.io/badge/Integrity-10_Failure_Rejection_Gates-brightgreen.svg)]()

A complete clinical-grade **System-on-Chip (SoC)** for real-time Electrocardiogram (ECG) acquisition, filtering, and R-peak / QRS morphological detection. Built around the OpenHW Group **CV32E40P** 4-stage in-order RISC-V processor core with PULP DSP extensions (`Xpulpv2`), implemented on Xilinx Artix-7 FPGA (`xc7a100tcsg324-1`) and verified through an ASIC-ready flow (SkyWater 130nm via OpenLane).

---

## Table of Contents

1. [System Architecture Overview](#system-architecture-overview)
2. [Key Microarchitectural Features](#key-microarchitectural-features)
3. [Memory Map & Register Address Space](#memory-map--register-address-space)
4. [Direct-Vectored Interrupt Routing](#direct-vectored-interrupt-routing)
5. [Ingress & Buffering Subsystems](#ingress--buffering-subsystems)
   - [Continuous-CS 72-bit SPI Master](#continuous-cs-72-bit-spi-master)
   - [Split-Plane Autonomous Ping-Pong DMA](#split-plane-autonomous-ping-pong-dma)
6. [DSP Biosignal Processing Engine](#dsp-biosignal-processing-engine)
   - [45-tap Q1.15 Bandpass FIR Filter](#45-tap-q115-bandpass-fir-filter)
   - [Pan-Tompkins QRS Detection Engine](#pan-tompkins-qrs-detection-engine)
7. [Repository Folder Structure](#repository-folder-structure)
8. [Verification Methodology & Gate Integrity](#verification-methodology--gate-integrity)
   - [39 Code-Anchored Test Cases](#39-code-anchored-test-cases)
   - [10 Evidence Rejection Gates](#10-evidence-rejection-gates)
9. [Build, Simulation & Synthesis Guide](#build-simulation--synthesis-guide)

---

## System Architecture Overview

The system features a decoupled Harvard architecture with zero-wait-state Tightly-Coupled Memories (TCM), an Open Bus Interface (OBI) to APB3 bridge, autonomous hardware peripherals for biosignal capture, and dedicated streaming interconnects for coprocessors.

```
                          +-------------------------------------------------------+
                          |                 Xilinx Artix-7 FPGA                   |
                          |                                                       |
                          |  +-------------------------------------------------+  |
                          |  |          CV32E40P RISC-V Core (v1.8.3)          |  |
                          |  |        RV32IMC + PULP Xpulpv2 DSP Engine         |  |
                          |  +-----------------------+-------------------------+  |
                          |                          |                            |
                          |             +------------+------------+               |
                          |             |                         |               |
                          |      Instr OBI (32-bit)        Data OBI (32-bit)      |
                          |             |                         |               |
                          |             v                         v               |
                          |   +-------------------+     +---------------------+   |
                          |   |   32 KB I-TCM     |     |   OBI Demux/Router  |   |
                          |   | (0x0000_0000)     |     +----------+----------+   |
                          |   +-------------------+                |              |
                          |                      +-----------------+-----------+  |
                          |                      |                             |  |
                          |                      v                             v  |
                          |            +-------------------+         +-----------------+
                          |            |    32 KB D-TCM    |         | OBI-to-APB3 Brg |
                          |            |   (0x0001_0000)   |         +--------+--------+
                          |            +-------------------+                  |
                          |                                                   v
                          |                                          +-----------------+
                          |                                          | APB Interconnect|
                          |                                          +---+---+---+---+--+
                          |                                              |   |   |   |
                          |                      +-----------------------+   |   |   +---+
                          |                      v                           v   v       v
                          |             +-----------------+               +----+ +----+ +----+
                          |             | Ping-Pong DMA   |               |UART| |TIMR| |GPIO|
                          |             | Control & Ingress               +----+ +----+ +----+
                          |             +--------+--------+
                          |                      | (D-OBI Port)
                          |                      v
                          |             +-----------------+
                          |             |  Buffer A / B   |
                          |             |  (0x2000_0000)  |
                          |             +--------+--------+
                          |                      ^
+-----------------------+ |                      | 12-byte packed frames
|  Texas Instruments    | |                      |
|  ADS1292R 24-bit ADC  | |             +--------+--------+
|  (2-channel ECG AFE)  | |             | 72-bit SPI Mst  |
|                       | |             | (1.0 MHz SCLK)  |
|  DRDY_N ------------->+-+------------>| Autonomous Ingr |
|  SCLK <---------------+----------------+ (CPOL=0, CPHA=1)|
|  CS_N <---------------+----------------+                |
|  MOSI <---------------+----------------+                |
|  MISO --------------->+----------------+                |
+-----------------------+ +-------------------------------------------------------+
```

---

## Key Microarchitectural Features

- **Core Processor**: OpenHW Group CV32E40P (v1.8.3 release, commit `97086e9565f8145522ad6d62852123c0e5537529`).
  - 4-stage in-order execution pipeline (IF, ID, EX, WB).
  - Standard RV32IMC extensions (Base Integer + Multiply/Divide + Compressed Instructions).
  - PULP `Xpulpv2` hardware extensions: post-increment load/stores, hardware loops (`lp.setup`), and dot-product multiply-accumulate (`p.mac`).
- **Memory Subsystem**:
  - Harvard split: Dedicated Instruction TCM (32 KB, `0x0000_0000`) and Data TCM (32 KB, `0x0001_0000`).
  - True zero-wait-state combinational SRAM interface with byte-enable masking (`be[3:0]`).
  - Dual-port contention routing allowing simultaneous CPU load/stores and DMA buffer writes.
- **Interconnect Architecture**:
  - High-speed Open Bus Interface (OBI) with combinational single-cycle transfers and backpressure stalling (`gnt`/`rvalid`).
  - Multi-window OBI-to-APB3 protocol bridge with registered APB state machine supporting legacy (`0x1000_xxxx`) and OpenHW standard (`0x1A10_xxxx`) address decodes.
- **Clocking & Constraints**:
  - Primary Board Oscillator: 100 MHz on Digilent Arty A7-100T (`E3` pin).
  - Mixed-Mode Clock Manager (MMCM): Derives 50 MHz core/system clock with phase-aligned reset.
  - SPI Clock Generator: Integer divider ($div = 50$) producing deterministic 1.0 MHz SCLK from 50 MHz system clock.

---

## Memory Map & Register Address Space

The SoC decodes a clean, collision-free 32-bit physical address map:

| Subsystem / Peripheral | Base Address | Size | Access Type | Description |
|------------------------|--------------|------|-------------|-------------|
| **Instruction TCM** | `0x0000_0000` | 32 KB | R/W (32-bit) | Zero-wait-state code SRAM, boot vector at `0x0000_0000` |
| **Direct Vector Table** | `0x0000_0100` | 256 B | R/W (32-bit) | Hardware direct-vectored interrupt table (`mtvec = 0x0000_0101`) |
| **Data TCM (D-TCM)** | `0x0001_0000` | 32 KB | R/W (8/16/32) | Zero-wait-state data SRAM, stack top at `0x0001_7FF0` |
| **SPI Master (Legacy)** | `0x1000_0000` | 4 KB | R/W (32-bit) | ADS1292R 72-bit continuous-CS SPI interface registers |
| **UART Controller (Legacy)**| `0x1000_1000` | 4 KB | R/W (32-bit) | 16550-compatible UART, 115200 baud, TX/RX FIFO |
| **Timer / Counter (Legacy)**| `0x1000_2000` | 4 KB | R/W (32-bit) | 64-bit real-time clock counter & compare interrupt register |
| **GPIO APB (Legacy)** | `0x1000_3000` | 4 KB | R/W (32-bit) | General-purpose I/O, AFE control, status LEDs |
| **ECG DMA (Legacy)** | `0x1000_4000` | 4 KB | R/W (32-bit) | Split-plane ping-pong DMA control & status registers |
| **OpenHW Standard APB Window**| `0x1A10_0000` | 64 KB | R/W (32-bit) | Mirrors all APB peripherals per OpenHW interconnect standard |
| **DMA Buffer A Window** | `0x2000_0000` | 4 KB | R/W (32-bit) | Direct D-OBI memory window for Ping-Pong Buffer A |
| **DMA Buffer B Window** | `0x2000_1000` | 4 KB | R/W (32-bit) | Direct D-OBI memory window for Ping-Pong Buffer B |

---

## Direct-Vectored Interrupt Routing

The CV32E40P core operates with Machine Trap-Vector Base-Address Register `mtvec` set to `0x0000_0101` (Direct Vectored Mode, where Base = `0x0000_0100`, Mode = `0x01`):

$$\text{Vector Address} = \text{Base} + (4 \times \text{IRQ Number})$$

```
0x0000_0100: [Entry 0]  Unused / Exception Fallback (j default_exc_handler)
0x0000_010C: [Entry 3]  Machine Software Interrupt (MSIP)
0x0000_011C: [Entry 7]  Machine Timer Interrupt (MTIP) -> timer_irq_handler
0x0000_012C: [Entry 11] Machine External Interrupt (MEIP)
0x0000_0140: [Entry 16] Fast IRQ 16 -> UART Controller Interrupt (uart_irq_handler)
0x0000_0144: [Entry 17] Fast IRQ 17 -> SPI Master Acquisition Complete (spi_irq_handler)
0x0000_0148: [Entry 18] Fast IRQ 18 -> Ping-Pong DMA Buffer Swap (dma_irq_handler)
0x0000_014C: [Entry 19] Fast IRQ 19 -> GPIO Edge Interrupt (AFE Lead-Off / Alarm)
0x0000_0150: [Entry 20] Fast IRQ 20 -> Reserved / Coprocessor Interrupt
```

---

## Ingress & Buffering Subsystems

### Continuous-CS 72-bit SPI Master

The Texas Instruments ADS1292R 24-bit 2-channel analog front-end outputs a continuous 72-bit frame per conversion:
- 24-bit Status word (`1100 + LOFF_STAT + GPIO`)
- 24-bit Channel 1 ECG voltage sample (2's complement)
- 24-bit Channel 2 ECG voltage sample (2's complement)

**Microarchitectural Guarantees (`spi_master.sv`)**:
1. **Autonomous DRDY# Ingress**: An active-low falling edge on `drdy_n` triggers the state machine without software polling.
2. **Continuous CS# Assertion**: Chip-select `spi_cs_n` remains strictly asserted low for all 72 consecutive SCLK cycles (violating CS# mid-frame corrupts ADS1292R serial framing).
3. **SPI Mode 1**: Operates at CPOL = 0, CPHA = 1 (data shifted on falling edge, latched on rising edge).
4. **Deterministic Clock Generation**: 50 MHz core clock divided by 50 delivers precisely 1.000 MHz SCLK.

### Split-Plane Autonomous Ping-Pong DMA

To prevent core pipeline stalls and eliminate sample jitter during DSP filtering, the DMA controller (`ecg_dma.sv`) operates autonomously:
- **Ping-Pong Buffers**: Dual 4 KB buffers (`Buffer A` @ `0x2000_0000`, `Buffer B` @ `0x2000_1000`).
- **Standardized 12-Byte Frame Unpacking**:
  ```
  Word 0: { 24'h000000, status_byte[7:0] }
  Word 1: { {8{ch1[23]}}, ch1[23:0] }  // 32-bit sign-extended 2's complement
  Word 2: { {8{ch2[23]}}, ch2[23:0] }  // 32-bit sign-extended 2's complement
  ```
- **Autonomous Swap & Vectoring**: When Buffer A reaches capacity, DMA atomically switches ingress to Buffer B and fires Fast IRQ 18. The CPU processes Buffer A in background while Buffer B fills.

---

## DSP Biosignal Processing Engine

The firmware DSP library (`Firmware/dsp/`) executes real-time QRS detection and digital filtering within the CV32E40P core:

### 45-tap Q1.15 Bandpass FIR Filter
- Bandwidth: 5 Hz to 15 Hz (isolates QRS electrical complexes, suppresses muscle EMG noise and 50/60 Hz mains interference).
- Coefficients: Quantized to 16-bit signed fixed-point (Q1.15).
- Hardware Acceleration: Implemented in assembly (`ecg_fir_pulp.S`) utilizing PULP `p.mac` (single-cycle multiply-accumulate with 32-bit accumulator) and hardware loop instructions (`lp.setup`), achieving >3.8x throughput acceleration over baseline RV32I.

### Pan-Tompkins QRS Detection Engine
- Five-stage pipelined cardiac analysis:
  1. **Bandpass Filtering**: 45-tap linear-phase FIR.
  2. **Five-Point Numerical Derivative**: $y[n] = \frac{1}{8} (2x[n] + x[n-1] - x[n-3] - 2x[n-4])$ highlights steep QRS slopes.
  3. **Non-linear Squaring**: 64-bit widened intermediate squaring $(y[n])^2$ ensuring positive amplification without integer overflow.
  4. **Moving Window Integrator (MWI)**: 30-sample integration window ($N = 30$ @ 250 Hz) captures QRS wave energy duration.
  5. **Dual-Threshold Adaptive Peak Detection**: Continuously updates Signal Peak ($SPKI$) and Noise Peak ($NPKI$) estimators with dynamic threshold $THR = NPKI + 0.25(SPKI - NPKI)$ and 200 ms physiological refractory lockout.

---

## Repository Folder Structure

```
E:\ResearchOnWork\RISC_V_CORE\
├── RTL/                         # SystemVerilog Synthesizable RTL
│   ├── ecg_soc/                 # Custom SoC modules (Interconnect, Peripherals, Core top)
│   │   ├── cv32e40p_ecg_soc_top.sv # Top-level SoC harness with CV32E40P core
│   │   ├── tcm_sram.sv          # 32 KB I-TCM & 32 KB D-TCM zero-wait SRAM
│   │   ├── obi_to_apb.sv        # Open Bus Interface to APB3 bridge
│   │   ├── apb_interconnect.sv  # Dual-window APB address decoder
│   │   ├── spi_master.sv        # 72-bit continuous CS# ADS1292R SPI engine
│   │   ├── spi_master_apb.sv    # APB wrapper for SPI master
│   │   ├── ecg_dma.sv           # Split-plane ping-pong frame unpacking DMA
│   │   ├── uart_controller.sv   # 16550 UART transmit/receive engine
│   │   ├── uart_apb.sv          # APB wrapper for UART
│   │   ├── timer_apb.sv         # 64-bit real-time counter & compare timer
│   │   ├── gpio_apb.sv          # General-purpose I/O with edge detection
│   │   ├── sync_fifo.sv         # Circular synchronous FIFO
│   │   ├── mamba_bridge.sv      # Coprocessor streaming bridge
│   │   ├── fpga/                # Board top-level implementations
│   │   │   └── ecg_arty_top.sv  # Digilent Arty A7-100T top wrapper with MMCM
│   │   └── sva/                 # SystemVerilog Assertions & formal bindings
│   │       ├── obi_to_apb_sva.sv
│   │       └── spi_master_sva.sv
├── Firmware/                    # RISC-V Bare-Metal C & Assembly Firmware
│   ├── boot/                    # Startup & Linker scripts
│   │   ├── crt0.S               # Reset vector, direct vector table, mtvec config
│   │   ├── link.ld              # Memory layout (I-TCM @ 0x0, D-TCM @ 0x10000)
│   │   └── hello.c              # Core bringup and diagnostic program
│   ├── drivers/                 # Bare-metal peripheral drivers
│   │   ├── ads1292r.c / .h      # SPI initialization, continuous read, register config
│   │   ├── dma.c / .h           # Ping-pong buffer swap, frame unpacking
│   │   └── uart.c / .h          # Baudrate setup, non-blocking string/hex print
│   ├── dsp/                     # Biosignal digital processing algorithms
│   │   ├── ecg_fir_pulp.S       # Hand-optimized PULP Xpulpv2 assembly FIR
│   │   ├── fir_reference.c      # Standard C reference 45-tap FIR
│   │   ├── pan_tompkins.c / .h  # Real-time QRS detection state machine
│   │   └── dsp_test.c           # Synthetic arrhythmia & MIT-BIH test harness
│   ├── Makefile                 # Deterministic build system with SHA256 tracking
│   └── bin_to_hex.py            # Binary to Verilog hexadecimal image converter
├── Simulation/                  # Verification Testbenches & Behavioral Models
│   ├── ads1292r_model.sv        # Behavioral ADS1292R AFE behavioral simulation model
│   ├── tcm_router_tb.sv         # TC-TCM-001..005 testbench
│   ├── obi_apb_bridge_tb.sv     # TC-BRG-001..004 testbench
│   ├── spi_master_tb.sv         # TC-SPI-001A..007 continuous CS# testbench
│   ├── ecg_dma_tb.sv            # TC-DMA-001..006 ping-pong testbench
│   ├── soc_tb.sv                # TC-SYS-001..017 full SoC co-simulation
│   ├── run_tcm.ps1              # TCM automated execution runner
│   ├── run_bridge.ps1           # Bridge automated execution runner
│   ├── run_spi.ps1              # SPI automated execution runner
│   └── run_dma.ps1              # DMA automated execution runner
├── Synthesis/                   # Physical Implementation Flows
│   ├── fpga/ecg_artix7/         # Vivado 2023.2 / 2024.x FPGA Flow
│   │   ├── arty_a7_100t.xdc     # Official Master XDC pin & timing constraints
│   │   ├── run_synth.tcl        # Non-project batch synthesis & implementation script
│   │   └── run_fpga.ps1         # PowerShell Vivado execution wrapper
│   ├── asic/openlane/           # ASIC SkyWater 130nm Physical Flow
│   │   ├── config.json          # OpenLane ASIC configuration
│   │   └── config_sky130.json   # Sky130 technology mapping & density rules
│   └── *.f                      # Icarus Verilog synthesis filelists
├── scripts/                     # Evidence Gate & Test Runner Infrastructure
│   ├── check_evidence.py        # Strict 10-gate cryptographically-signed validator
│   ├── test_evidence_gate.py    # Unit tests for evidence rejection rules
│   ├── test_runner_contract.py  # Unit tests for test runner contracts
│   ├── test_firmware_build_contract.py # Contract tests for toolchain integrity
│   └── run_sim.ps1 / .sh        # Comprehensive automated regression runners
├── reports/                     # Evidence Manifests & Verification Tracking
│   ├── verification/            # RTM dashboards & traceability matrices
│   ├── benchmark_report.md      # Performance & latency characterization
│   └── review/                  # Independent multi-round audit documentation
├── spec/                        # Formal Architectural Specifications
│   ├── ecg_soc_spec.md          # Architectural and interface specification
│   ├── ecg_soc_reqs.json        # Machine-readable requirements list
│   └── ecg_soc_module_map.json  # Module to requirement traceability map
├── config/                      # System Configurations
│   └── ecg_soc_config.json      # SoC parameter definitions (clock, FIFO depth)
└── docs/                        # Project Plans & Architectural Manuals
    ├── architecture/            # Microarchitecture reference manuals
    └── plans/                   # Implementation and verification plans
```

---

## Verification Methodology & Gate Integrity

### 39 Code-Anchored Test Cases

Every requirement maps directly to synthesizable SystemVerilog assertions and verifiable testbench scenarios:

| Category | Suite ID Range | Count | Primary Verification Objective |
|----------|----------------|-------|--------------------------------|
| **TCM Subsystem** | `TC-TCM-001` - `005` | 5 | Concurrent I/D access, zero-wait-state bus response, byte-enable masking. |
| **OBI-APB Bridge** | `TC-BRG-001` - `004` | 4 | Protocol translation, single-cycle response, backpressure handling. |
| **SPI Master** | `TC-SPI-001A` - `007`| 9 | Autonomous DRDY# capture, continuous 72-bit CS#, 1 MHz SCLK divider, CPOL=0/CPHA=1. |
| **ECG DMA** | `TC-DMA-001` - `006` | 6 | 12-byte packed frame unpacking, ping-pong atomic swap, fast IRQ 18 assert. |
| **Full SoC Co-Sim** | `TC-SYS-001` - `017` | 17 | Core reset, boot sequence, peripheral APB read/write, UART transmission, timer tick. |
| **Total** | | **39**| **100% Code-Anchored Coverage** |

### 10 Evidence Rejection Gates

Per `Instruction/claim_integrity.md`, results cannot be reported as `PASS` without surviving the strict automated gate checker (`scripts/check_evidence.py`):

1. **Gate 1**: Non-zero process exit code rejection (compilation or simulation failure).
2. **Gate 2**: Stale `run_id` rejection (enforces newly generated timestamps).
3. **Gate 3**: Manifest SHA-256 artifact hash corruption detection.
4. **Gate 4**: Empty or missing evidence artifact rejection.
5. **Gate 5**: Incomplete census rejection (all expected test cases must report verdict).
6. **Gate 6**: Unsolicited fatal event detection outside test case boundaries.
7. **Gate 7**: Missing interrupt verification case detection.
8. **Gate 8**: Duplicate test case identifier rejection.
9. **Gate 9**: "Complete-only" log rejection (must contain individual `[PASS]` tags).
10. **Gate 10**: Hard compilation failure without fallback.

---

## Build, Simulation & Synthesis Guide

### 1. Prerequisites
- **Simulator**: Icarus Verilog (`iverilog`, `vvp` v12.0+)
- **Cross-Compiler**: GNU RISC-V Toolchain (`riscv32-unknown-elf-gcc` or `riscv-none-elf-gcc`)
- **Host Tools**: Python 3.8+, Make, MinGW GCC
- **Synthesis Tool**: Xilinx Vivado 2023.2+ (for FPGA bitstream generation)

### 2. Verify Gate Infrastructure
Execute the Python test runner contract suite:
```powershell
python -m unittest discover -s scripts -p "test_*.py" -v
```
*Expected: 26 tests passed with exit code 0.*

### 3. Run Subsystem Unit Simulations
Execute automated subsystem simulations:
```powershell
# TCM SRAM Subsystem (5 Test Cases)
powershell -File Simulation/run_tcm.ps1

# OBI-to-APB3 Bridge Subsystem (4 Test Cases)
powershell -File Simulation/run_bridge.ps1

# ADS1292R SPI Master Subsystem (9 Test Cases)
powershell -File Simulation/run_spi.ps1

# ECG Ping-Pong DMA Subsystem (6 Test Cases)
powershell -File Simulation/run_dma.ps1
```

### 4. Build Firmware & DSP Test Harness
Compile host-native DSP verification suite:
```powershell
mingw32-make -C Firmware dsp-test-host
```
Compile RISC-V target ELF and generate Verilog memory image:
```powershell
mingw32-make -C Firmware all
```

### 5. Run Full System-on-Chip Co-Simulation
Execute full SoC simulation with CV32E40P core executing firmware:
```powershell
powershell -File scripts/run_sim.ps1
```

### 6. Xilinx Artix-7 FPGA Implementation
Run non-project batch synthesis and timing closure in Vivado:
```powershell
E:\Vivado\2023.2\bin\vivado.bat -mode batch -source Synthesis/fpga/ecg_artix7/run_synth.tcl
```

---

## License & Attribution

- **Project Core**: [OpenHW Group CV32E40P](https://github.com/openhwgroup/cv32e40p) (Apache 2.0 License).
- **SoC Architecture & Peripherals**: Copyright 2026 RISC-V ECG Project Team. Released under Apache-2.0 License.
- **Reference Baselines**: [CVA6](https://github.com/openhwfoundation/cva6) and [lowRISC Ibex](https://github.com/lowRISC/ibex).
