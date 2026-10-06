# RISC-V ECG DAQ — Architecture Document

Version: 1.0
Date: 2026-10-05

## 1. System Purpose

A complete ECG data acquisition system on FPGA using the CVA6 RISC-V processor
as the central controller. The system acquires analog cardiac signals through
a dedicated analog front-end (AFE) chip, digitizes them, optionally processes
them on-chip, and streams the data to a host PC for visualization, storage,
and clinical analysis.

## 2. CVA6 Core Selection Rationale

The CVA6 (formerly Ariane) is selected for:

- **Open-source:** OpenHW Group maintained, Apache 2.0 license
- **RV32IMA:** Integer + multiply + atomic — sufficient for embedded control
- **6-stage pipeline:** Good IPC for firmware-heavy workloads
- **Sv32 MMU:** Enables future Linux support if needed
- **FPGA-proven:** Existing Xilinx constraint files and synthesis reports
- **Configurable:** FPGA-optimized config reduces cache/BTB for smaller devices
- **Ecosystem:** CLINT, PLIC, AXI interconnect, APB peripherals already exist

### FPGA Configuration

Using `cv32a6_ima_sv32_fpga_config_pkg`:
- 8 KB I-Cache, 8 KB D-Cache (2-way, 128-bit lines)
- 32 BTB entries, 128 BHT entries, RAS depth 2
- 4 scoreboard entries
- No FPU (saves significant resources)
- No vector extension

### Resource Estimate (Artix-7 100T)

| Resource | Available | CVA6 Estimate | SoC Peripherals | Total Budget |
|---|---|---|---|---|
| LUT | 63,400 | ~15,000 | ~5,000 | ~20,000 (32%) |
| FF | 126,800 | ~8,000 | ~3,000 | ~11,000 (9%) |
| BRAM (36Kb) | 135 | ~20 | ~10 | ~30 (22%) |
| DSP48E1 | 240 | ~4 | 0 | ~4 (2%) |

Note: These are estimates. Actual numbers from synthesis (E2 evidence) will
replace these.

## 3. ECG Analog Front-End

### Primary: ADS1292R
- 2-channel, 24-bit delta-sigma ADC
- Programmable gain amplifier (PGA): 1, 2, 3, 4, 6, 8, 12×
- Sample rates: 125, 250, 500, 1000, 2000, 4000, 8000 SPS
- Built-in right-leg drive (RLD), lead-off detection
- SPI interface: CPOL=0, CPHA=1 (SPI Mode 1)
- DRDY: active-low, asserts when new data ready
- Supply: 2.7–5.25V analog, 1.8V digital
- Package: TQFP-32

### SPI Protocol (ADS1292R)
```
Register Read:  CS↓ → RREG(addr,count) → read bytes → CS↑
Register Write: CS↓ → WREG(addr,count) → write bytes → CS↑
Data Read:      DRDY↓ → CS↓ → RDATA → 3+6 bytes → CS↑
Continuous:     START → DRDY↓ → read 9 bytes → repeat
```

### Data Format (per DRDY cycle)
```
Byte 0-2: 24-bit status (GPIO, lead-off, fault)
Byte 3-5: 24-bit Channel 1 data (signed, 2's complement)
Byte 6-8: 24-bit Channel 2 data (signed, 2's complement)
Total: 72 bits per DRDY cycle
```

## 4. SoC Memory Map

```
0x0000_0000 — 0x0000_FFFF : Boot ROM (64 KB)
0x0100_0000 — 0x0100_FFFF : On-chip SRAM (64 KB, BRAM-backed)
0x0200_0000 — 0x0200_FFFF : CLINT (core-local interruptor)
0x0C00_0000 — 0x0FFF_FFFF : PLIC (interrupt controller)
0x1000_0000 — 0x1000_0FFF : UART (APB, 4 KB)
0x1000_1000 — 0x1000_1FFF : SPI Master (APB, 4 KB)
0x1000_2000 — 0x1000_2FFF : Timer (APB, 4 KB)
0x1000_3000 — 0x1000_3FFF : GPIO (APB, 4 KB)
0x1000_4000 — 0x1000_4FFF : DMA Controller (APB, 4 KB, optional)
0x8000_0000 — 0x8FFF_FFFF : External memory (SPI Flash, optional)
```

## 5. Interrupt Map

| IRQ ID | Source | Priority | Description |
|---|---|---|---|
| 1 | UART RX | Medium | UART receive data available |
| 2 | UART TX | Low | UART transmit buffer empty |
| 3 | SPI DRDY | High | AFE data ready (from ADS1292R DRDY pin) |
| 4 | SPI Done | Medium | SPI transfer complete |
| 5 | Timer 0 | Medium | Timer compare match |
| 6 | Timer 1 | Low | Watchdog timeout |
| 7 | GPIO | Low | GPIO edge/level interrupt |

DRDY (IRQ 3) has highest priority — ECG sample must not be missed.

## 6. Data Pipeline

### Acquisition Path (Interrupt-Driven)
```
AFE DRDY↓ → PLIC IRQ 3 → CVA6 ISR entry (~50 cycles)
  → SPI CS↓ + clock out 72 bits (~36 µs at 2 MHz SCLK)
  → Store 9 bytes in circular buffer (SRAM)
  → Increment write pointer, check overflow
  → Clear interrupt, return from ISR
```

### Processing Path (Main Loop)
```
While (read_ptr != write_ptr):
  → Read sample from circular buffer
  → Optional: IIR bandpass filter (0.5–40 Hz)
  → Optional: 50/60 Hz notch filter
  → Optional: R-peak detection (Pan-Tompkins firmware)
  → Packetize: [SYNC][TIMESTAMP][CH1_24b][CH2_24b][STATUS][CRC]
  → Write to UART TX FIFO
```

### UART Packet Format
```
Byte 0:    0xAA (sync byte)
Byte 1:    Packet type (0x01=ECG data, 0x02=R-peak event, 0x03=status)
Byte 2-5:  32-bit timestamp (sample counter)
Byte 6-8:  24-bit Channel 1
Byte 9-11: 24-bit Channel 2
Byte 12:   Status flags
Byte 13:   CRC-8
Total: 14 bytes per sample
```

At 500 Hz: 14 × 500 = 7000 bytes/s → requires ≥ 70 kbaud
At 921600 baud: 92160 bytes/s → 13× headroom

## 7. Firmware Architecture

### Boot Sequence
1. Boot ROM initializes stack, clears BSS
2. Clock configuration (MMCM already locked by FPGA bitstream)
3. UART init (baud rate, FIFOs)
4. SPI init (clock divider, mode)
5. GPIO init (LEDs, AFE reset pin)
6. Timer init (optional sampling rate timer)
7. ADS1292R init (register configuration sequence)
8. PLIC init (enable DRDY interrupt, set priorities)
9. Enable global interrupts (mstatus.MIE)
10. Enter main processing loop

### Real-Time Requirements
- ISR must complete before next DRDY (2 ms at 500 Hz)
- ISR execution budget: < 200 µs (10% of sample period)
- Main loop must drain buffer faster than ISR fills it
- Watchdog timer resets system if main loop stalls > 10 ms

## 8. Board Interface (Arty A7-100T)

### Pin Assignments (via PMOD connectors)
```
PMOD JA (SPI to ADS1292R):
  JA1: SPI_SCLK
  JA2: SPI_MOSI (DIN)
  JA3: SPI_MISO (DOUT)
  JA4: SPI_CS_N
  JA7: AFE_DRDY_N
  JA8: AFE_RESET_N
  JA9: AFE_START
  JA10: AFE_PWDN_N

PMOD JB (Debug/Extension):
  JB1-4: Debug GPIO / logic analyzer

Built-in:
  UART: USB-UART bridge (pin E/D)
  LEDs: LD0-LD3 (heartbeat, data, error, status)
  Buttons: BTN0 (reset), BTN1-3 (user)
  Switches: SW0-3 (configuration)
  RGB LEDs: LD4-5 (system status)
```

## 9. Future Extensions

- **Hardware filter accelerator:** FIR/IIR filter engine if firmware is
  insufficient for high channel counts
- **R-peak hardware detector:** Pan-Tompkins in RTL for deterministic latency
- **USB interface:** Replace UART with USB 2.0 for higher throughput
- **Wi-Fi/BLE module:** Wireless ECG streaming via PMOD ESP32
- **SD card logging:** On-board storage for ambulatory monitoring
- **Linux SoC:** Enable Sv32 MMU, boot Linux for complex applications
- **Multi-AFE:** SPI multiplexing for 12-lead (ADS1298 × 2)
- **ML inference:** Lightweight CNN/Mamba model for on-chip arrhythmia detection
