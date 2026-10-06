# RISC-V ECG DAQ — Evidence Contract

Version: 1.0
Date: 2026-10-05

## Purpose

This contract prevents simulation results, firmware tests, synthesis reports,
and board measurements from being merged into one unsupported claim. Every
quantitative statement must name its evidence level, source revision,
workload, and boundary.

## Evidence Levels

| Level | Name | Minimum Evidence | Permitted Wording |
|---:|---|---|---|
| E0 | Hypothesis | Architecture/specification only | proposed, planned, hypothesized |
| E1 | Simulation | RTL simulation with testbench vectors | simulated, verified in simulation |
| E2 | Synthesis | Vivado synthesis report (resource, timing) | synthesized area/timing |
| E3 | Place & Route | Post-route timing with complete setup/hold | routed timing/utilization |
| E4 | Board Boot | FPGA programmed, basic function (UART, LED) | board boots, UART functional |
| E5 | SPI Communication | SPI master communicates with AFE chip | AFE responds, device ID read |
| E6 | ECG Streaming | Continuous data stream, no drops | streaming at X Hz for Y seconds |
| E7 | Signal Quality | Identifiable cardiac waveform in data | P-QRS-T visible, SNR measured |
| E8 | Real-Time Processing | On-chip R-peak/QRS detection functional | firmware detection matches reference |
| E9 | Clinical Validation | Extended recording, accuracy vs reference | clinical-grade, validated against standard |

An E1 simulation is never called board-proven. E2 synthesis timing is never
called routed or measured. E4 boot is never called ECG-functional. E6
streaming is never called clinically validated.

## Required Manifest Fields

Each evidence campaign records:

```
campaign_id
date_utc
git_commit and dirty_status
source_filelist and SHA-256 fingerprint
tool name/version/host (Vivado, GCC, simulator)
top module and hierarchy boundary
FPGA part/board/clock configuration
firmware version and compiler flags
AFE chip type and configuration registers
test workload description
command and exit status
raw artifact paths and SHA-256 hashes
summary metrics with units
known exclusions and claim level
```

## Functional Verification Gates

### RTL Simulation
- SPI master: all CPOL/CPHA modes, clock divider values, 8/16/24-bit transfers
- UART: baud rate accuracy, FIFO overflow handling, flow control
- Timer: period accuracy, interrupt generation, prescaler
- GPIO: direction control, interrupt on edge/level
- SoC integration: concurrent peripheral access, interrupt priority

### Firmware Verification
- Boot sequence: ROM → firmware entry → peripheral init → main loop
- ISR latency: cycles from interrupt assertion to first SPI clock
- Buffer management: circular buffer wrap, overflow detection
- UART packetization: frame format, checksum, timestamp accuracy
- Digital filter: coefficient loading, step response, group delay

### Board Verification
- UART echo test at target baud rate
- SPI loopback (MOSI→MISO on PMOD)
- SPI to ADS1292R: read device ID register (0x01 → expect 0x73)
- Continuous acquisition: 500 Hz × 60 seconds, zero dropped samples
- Latency measurement: GPIO toggle at ISR entry + scope measurement

## Performance Metrics

Report at least:

```
FPGA resource utilization (LUT, FF, BRAM, DSP)
Maximum achieved clock frequency (post-route)
Interrupt latency (cycles and microseconds)
SPI transaction time (microseconds per sample)
UART throughput (bytes/second actual)
End-to-end latency (ADC sample to UART byte)
Buffer occupancy (average, peak)
CPU utilization (ISR time / sample period)
Power consumption (board-level, if measured)
```

## Boundary Wording

- `simulation`: observed in RTL simulation with specified testbench
- `synthesis`: Vivado synthesis report for specified part and constraints
- `routed`: post-route with complete timing analysis
- `board`: programmed FPGA with measured I/O and external equipment
- `NOT_VERIFIED`: absent or incompatible required evidence
- `FAIL`: observed violation
