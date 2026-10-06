# Hardware Specification: Real-Time ECG Acquisition RISC-V SoC & Coprocessor Platform

**Document Version:** 1.0  
**Status:** DRAFT - PENDING GATE 1 REVIEW  
**Author:** spec_writer (Automated ASIC/FPGA Flow)  
**Target Platform:** Xilinx Artix-7 100T (`xc7a100tcsg324-1`) on Digilent Arty A7-100T  
**Primary Sensor Target:** Texas Instruments ADS1292R (2-Channel, 24-bit Low-Power AFE)  
**Co-Processor Target:** 16x8 Fold-SIMD PE Array + 4-lane Selective-SSM (CNN-MAMBA sidecar)

---

## 1. System Overview & Architecture

### 1.1 Purpose
The system provides real-time, deterministic electrocardiogram (ECG) biopotential acquisition, autonomous buffer management, on-chip arrhythmia feature extraction/inference, and clinical-grade packetized telemetry to a host PC.

### 1.2 Top-Level Block Diagram
```
                     +---------------------------------------+
                     |         Artix-7 FPGA Top-Level        |
                     |                                       |
+-----------------+  |  +---------------------------------+  |
|  ADS1292R AFE   |  |  |     Autonomous Capture Path     |  |
| (2-Ch, 24-bit)  |  |  |                                 |  |
|                 |  |  |  [DRDY Edge Detector]           |  |
| DRDY# ---------->-->--|           |                     |  |
| SPI_SCLK <------<--<--|--[SPI Master Engine (2.0 MHz)]  |  |
| SPI_MOSI <------<--<--|           |                     |  |
| SPI_MISO ------->-->--|--[Async Dual-Clock FIFO (8x24b)]|  |
+-----------------+  |  +-----------|---------------------+  |
                     |              | AXI-Stream / DMA       |
                     |              v                        |
                     |  +---------------------------------+  |
                     |  |     Ping-Pong BRAM Buffer       |  |
                     |  |   (Bank A: 32s / Bank B: 32s)   |  |
                     |  +-----------+---------------------+  |
                     |              |                        |
                     |              +-------------------+    |
                     |              |                   |    |
                     |              v                   v    |
+-----------------+  |  +--------------------+  +---------+  |
| Host PC Link    |  |  | Control Plane CPU  |  |CNN-MAMBA|  |
|                 |  |  | (RV32IMC Core)     |  |Fold-SIMD|  |
| UART_TX <-------<--<--|  - Register config |  |PE Array |  |
| UART_RX ------->-->-->|  - Telemetry frame |  |(128 MAC)|  |
+-----------------+  |  +--------------------+  +---------+  |
                     +---------------------------------------+
```

---

## 2. Core Specification & Selection

### 2.1 Microarchitecture Parameters
- **Selected Processor Core:** OpenHW Group **CV32E40P** (RV32IMC with CORE-V `Xpulpv2` DSP Extensions).
- **Pipeline Architecture:** 4-stage in-order pipeline (IF, ID, EX, WB) with single-issue execution.
- **ISA Extensions:** `RV32IMC` + `Xpulpv2` (Hardware Loops `HWLP`, Post-Increment Load/Store, Packed 16-bit SIMD Dot-Product).
- **Core Parameters:**
  - `COREV_PULP = 1`: Enable hardware loops, post-increment addressing, and SIMD MAC.
  - `COREV_CLUSTER = 0`: Standalone SoC configuration.
  - `FPU = 0`: Fixed-point Q1.15 arithmetic for biosignal processing (saves ~2,500 LUTs).
  - `NUM_MHPMCOUNTERS = 1`: Minimal performance counters for cycle profiling.
- **Bus Interfaces:**
  - Instruction Port: 32-bit Open Bus Interface (OBI) request-grant protocol (`instr_*`).
  - Data Port: 32-bit Open Bus Interface (OBI) request-grant protocol (`data_*`).
- **Accelerator Coupling:**
  - Control Plane: APB3 slave register interface mapped at `0x2000_0000` (`mamba_bridge.sv`).
  - Data Plane: Direct AXI4-Stream channel from Ping-Pong DMA buffer to CNN-MAMBA input buffer.

---

## 3. SoC Memory Map

The memory map uses a Harvard configuration for Tightly-Coupled Memories (TCM) and unified APB3 peripheral addressing:

| Base Address | Size | Device / Subsystem | Bus Type | Description |
| :--- | :--- | :--- | :--- | :--- |
| `0x0000_0000` | 32 KB | Instruction TCM (I-TCM) | OBI (Instr) | Vector table, crt0 startup, firmware code |
| `0x0001_0000` | 32 KB | Data TCM (D-TCM) | OBI (Data) | Stack, heap, .data, .bss, circular buffers |
| `0x1000_0000` | 4 KB  | UART Controller | APB3 | 8N1 serial transceiver with TX/RX FIFOs |
| `0x1000_1000` | 4 KB  | SPI Master (AFE) | APB3 | ADS1292R SPI controller & auto-capture |
| `0x1000_2000` | 4 KB  | System Timer | APB3 | Periodic system ticks & watchdog |
| `0x1000_3000` | 4 KB  | GPIO Controller | APB3 | LEDs, buttons, AFE reset & power control |
| `0x1000_4000` | 4 KB  | Ping-Pong Buffer DMA| APB3 | Buffer management & block interrupt generation |
| `0x2000_0000` | 64 KB | CNN-MAMBA Accelerator| APB3 | Control & status registers for neural engine |

---

## 4. Interrupt Hierarchy & Mapping

The CV32E40P fast vectored interrupt interface (`irq_fast_i[14:0]`) guarantees 6-cycle (120 ns at 50 MHz) deterministic interrupt dispatch with zero PLIC arbitration overhead:

| Fast IRQ Pin | Interrupt Source | Priority | Latency Budget | Trigger Type | Description |
| :---: | :--- | :---: | :---: | :---: | :--- |
| `irq_fast_i[2]` | `AFE_DRDY` | **Highest (7)** | $< 20\ \mu\text{s}$ | Falling Edge | ADS1292R biopotential sample ready |
| `irq_fast_i[3]` | `BUFFER_READY` | **High (6)** | $< 100\ \mu\text{s}$ | Level | Ping-pong bank (32 samples) filled |
| `irq_fast_i[6]` | `MAMBA_EVENT` | **High (6)** | $< 100\ \mu\text{s}$ | Pulse | Arrhythmia classification event |
| `irq_fast_i[0]` | `UART_RX_AVAIL` | **Medium (4)** | $< 500\ \mu\text{s}$ | Level | Host command byte available |
| `irq_fast_i[1]` | `UART_TX_EMPTY` | **Medium (3)** | $< 1\ \text{ms}$ | Level | UART TX buffer ready |
| `irq_fast_i[4]` | `TIMER_TICK` | **Low (2)** | $< 2\ \text{ms}$ | Level | Periodic system tick |
| `irq_fast_i[5]` | `GPIO_EVENT` | **Lowest (1)** | $< 5\ \text{ms}$ | Edge | Pushbutton or lead-off detection |

---

## 5. Formal Functional Requirements (REQ-IDs)

### 5.1 System & Timing (`REQ-SYS`)
- `REQ-SYS-001`: The system clock shall operate at a nominal frequency of $50.0\text{ MHz} \pm 50\text{ ppm}$ derived from the onboard 100 MHz oscillator via an MMCM.
- `REQ-SYS-002`: Total peripheral logic (excluding CPU core and CNN-MAMBA accelerator) shall consume $\le 5,000\text{ LUTs}$, $\le 3,000\text{ FFs}$, and $\le 10\text{ BRAM36k}$ blocks on the Artix-7 100T.
- `REQ-SYS-003`: End-to-end sample acquisition latency from AFE `DRDY#` assertion to UART transmission start shall be strictly $\le 10.0\text{ ms}$.

### 5.2 SPI Master & AFE Interface (`REQ-SPI`)
- `REQ-SPI-001`: The SPI master shall implement SPI Mode 1 ($\text{CPOL}=0$, $\text{CPHA}=1$).
- `REQ-SPI-002`: SCLK frequency shall be configurable via register division; default division ratio shall be 25 ($50\text{ MHz} / 25 = 2.0\text{ MHz}$).
- `REQ-SPI-003`: The SPI master shall support autonomous 72-bit burst reading (24-bit status + 24-bit CH1 + 24-bit CH2) upon detecting the falling edge of `DRDY#`.
- `REQ-SPI-004`: CS# setup time ($t_{\text{CSSC}}$) prior to the first SCLK edge shall be $\ge 4$ SCLK cycles ($2.0\ \mu\text{s}$).
- `REQ-SPI-005`: CS# hold time ($t_{\text{SCCS}}$) following the final SCLK edge shall be $\ge 4$ SCLK cycles ($2.0\ \mu\text{s}$).

### 5.3 Buffering & Data Integrity (`REQ-BUF`)
- `REQ-BUF-001`: An asynchronous capture FIFO (depth $\ge 8$ words $\times 24$-bit) shall isolate the SPI SCLK domain from the system bus domain.
- `REQ-BUF-002`: A Ping-Pong dual-bank BRAM buffer shall hold two alternating frames of 32 samples each ($32 \times 9\text{ bytes} = 288\text{ bytes}$ per bank).
- `REQ-BUF-003`: The buffer controller shall assert `BUFFER_HALF_FULL` interrupt when Bank A fills, seamlessly switching write ingress to Bank B without dropping samples.
- `REQ-BUF-004`: If write ingress attempts to overwrite an unread buffer bank, an `OVERFLOW_FAULT` status bit shall assert and log the dropped sample count.

### 5.4 UART Telemetry (`REQ-UART`)
- `REQ-UART-001`: The UART shall support 8 data bits, 1 stop bit, no parity (8N1).
- `REQ-UART-002`: Baud rate generator shall support standard rates: 115200 (divisor 434 @ 50 MHz) and 921600 (divisor 54 @ 50 MHz).
- `REQ-UART-003`: Standard data packets shall use a 14-byte frame structure:
  `[0xAA][TYPE][TIMESTAMP_32b][CH1_24b][CH2_24b][STATUS_8b][CRC8]`.
- `REQ-UART-004`: CRC-8 shall be computed over bytes 1 through 12 using polynomial $x^8 + x^2 + x + 1$ (`0x07`).

### 5.5 APB3 Slave Compliance (`REQ-APB`)
- `REQ-APB-001`: All peripheral register read/write accesses shall adhere to the AMBA 3 APB protocol without generating protocol deadlocks.
- `REQ-APB-002`: Unmapped address reads shall return `0x0000_0000` with `PSLVERR = 0`.
- `REQ-APB-003`: Back-to-back writes with zero wait states (`PREADY = 1`) shall complete deterministically in 2 clock cycles.

---

## 6. Verification Acceptance Gates

- **Gate 1 (Human Review):** User reviews and approves this specification document.
- **Gate 2 (Auto Check):** Configuration tool confirms all clock dividers, FIFO depths, and memory mappings are structurally sound.
- **Gate 3 (Human Review):** SVA assertions reviewed against ADS1292R datasheet timing figures.
- **Gate 4 (Auto Check):** Verilator lint clean (`--lint-only -Wall`) and iverilog testbench compilation pass.
- **Gate 5 (Human Sign-off):** 100% of `REQ-xxx` IDs mapped and passing across all 12 testcases with mutation kill rate $\ge 80\%$.
