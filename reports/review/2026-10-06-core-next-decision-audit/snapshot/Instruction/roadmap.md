# RISC-V ECG DAQ — Project Roadmap

## Research Position

The CVA6 RISC-V processor is the platform controller for a real-time ECG data
acquisition SoC on Artix-7 FPGA. The project proceeds in phases from core
bring-up through complete clinical-grade ECG streaming, with each phase
gated by verifiable evidence.

This is not a project to build a new RISC-V core. It is a system integration
project that assembles a proven open-source processor with custom peripherals
and firmware for a specific biomedical application.

## Phase 0: Repository Setup and CVA6 Evaluation

Deliverables:
```
Instruction/ — complete contract and checklist system
cva6/ — initialized submodules, clean elaboration
reports/baseline/artix7_resource_estimate.md
```

Tasks:
- initialize CVA6 submodules (riscv-dbg, rv_plic, apb_uart, apb_timer, gpio)
- evaluate cv32a6_ima_sv32_fpga_config_pkg resource usage on Artix-7
- document baseline resource budget and available headroom
- verify RISC-V GCC cross-compiler toolchain setup
- create project directory structure

Gate: clean elaboration of CVA6 with all required submodules; documented
resource estimate showing Artix-7 100T has sufficient headroom.

## Phase 1: CVA6 Core Boot on Artix-7

Deliverables:
```
Synthesis/fpga/ecg_artix7/arty_a7_100t.xdc
Synthesis/fpga/ecg_artix7/run_synth.tcl
Firmware/boot/boot.c
reports/evidence/phase1_core_boot.md
```

Tasks:
- create Arty A7-100T constraint file (clock, UART, LEDs, reset)
- create Vivado synthesis Tcl script
- write bare-metal boot firmware (UART hello world)
- synthesize, implement, generate bitstream
- program board, verify UART output

Gate: CVA6 boots on Arty A7-100T, prints to UART, toggles LEDs. Post-route
timing met at target frequency. Resource utilization documented.

## Phase 2: SPI Master Peripheral

Deliverables:
```
RTL/ecg_soc/spi_master.sv
RTL/ecg_soc/spi_master_apb.sv
Simulation/spi_master_tb.sv
Simulation/ads1292r_model.sv (behavioral SPI slave)
Firmware/drivers/spi_driver.c
reports/evidence/phase2_spi_master.md
```

Tasks:
- design SPI master with configurable clock, mode, and transfer width
- create testbench with behavioral ADS1292R model
- verify all SPI modes, timing compliance, interrupt generation
- integrate into SoC APB bus
- write firmware SPI driver with interrupt support
- board test: SPI loopback → ADS1292R device ID read

Gate: SPI master verified in simulation; reads ADS1292R device ID on board.
SPI timing compliant with ADS1292R datasheet.

## Phase 3: ECG Data Streaming

Deliverables:
```
Firmware/ecg/ecg_acquisition.c
Firmware/ecg/ecg_packet.c
Firmware/ecg/circular_buffer.c
reports/evidence/phase3_ecg_streaming.md
```

Tasks:
- implement DRDY interrupt handler + SPI data read ISR
- implement circular buffer in SRAM
- implement UART packetization with timestamp and CRC
- continuous streaming test: 500 Hz × 60 seconds, zero drops
- measure end-to-end latency (ADC to UART)
- host-side receiver script (Python) for data capture

Gate: continuous 500 Hz, 2-channel ECG streaming for 60+ seconds with zero
dropped samples. End-to-end latency < 10 ms measured.

## Phase 4: Signal Quality and Processing

Deliverables:
```
Firmware/ecg/ecg_filter.c
Firmware/ecg/rpeak_detect.c
Host/ecg_viewer.py (real-time visualization)
reports/evidence/phase4_signal_quality.md
```

Tasks:
- implement firmware IIR bandpass filter (0.5–40 Hz)
- implement firmware 50/60 Hz notch filter
- implement Pan-Tompkins R-peak detection in firmware
- measure CPU utilization during processing
- host-side real-time ECG viewer
- signal quality assessment: P-QRS-T visibility, SNR

Gate: identifiable P-QRS-T complex in captured data. R-peak detection
matches reference within 5 ms tolerance. CPU utilization < 50%.

## Phase 5: Multi-Channel and ADS1298 Support

Deliverables:
```
RTL/ecg_soc/spi_mux.sv (optional SPI multiplexer)
Firmware/drivers/ads1298_driver.c
reports/evidence/phase5_multi_channel.md
```

Tasks:
- extend SPI driver for ADS1298 (8-channel, different register map)
- multi-channel simultaneous acquisition
- increase UART throughput or switch to USB
- verify no cross-talk between channels
- 12-lead ECG demonstration

Gate: 8-channel simultaneous streaming, all channels clean.

## Phase 6: Optional Hardware Accelerators

Only if firmware profiling shows real-time violations:

Deliverables:
```
RTL/ecg_processing/fir_filter.sv
RTL/ecg_processing/rpeak_hw.sv
reports/evidence/phase6_hw_accel.md
```

Tasks:
- profile firmware bottlenecks
- implement FIR filter engine (DSP48E1 inference)
- implement R-peak detection accelerator
- compare firmware vs hardware latency/throughput
- re-verify resource utilization

Gate: hardware accelerator meets latency requirement that firmware could not.
Resource usage within Artix-7 budget.

## Phase 7: Documentation and Publication

Deliverables:
```
reports/final/system_architecture.md
reports/final/measurement_results.md
reports/final/comparison_table.md
```

Required evidence:
- complete resource utilization table (measured)
- timing closure report (post-route)
- streaming performance (measured throughput, latency)
- signal quality assessment
- comparison with MCU-based designs (STM32, ESP32, etc.)
- power consumption (board-level)
- limitations and future work

## Current Status

Phase 0: in_progress — repository setup, instruction system created,
CVA6 cloned but submodules not initialized.
