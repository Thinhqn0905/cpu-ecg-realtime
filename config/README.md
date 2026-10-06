# Configuration Directory: System Parameters & Architectural Options

This directory contains the machine-readable configuration files defining architectural parameters, memory dimensions, peripheral base addresses, and clock frequencies for the CV32E40P RISC-V Real-Time ECG SoC.

---

## Directory Hierarchy

```
config/
└── ecg_soc_config.json          # Master architectural configuration definition
```

---

## 1. Master Configuration File (`ecg_soc_config.json`)

Defines the hardware parameters and memory boundaries consumed by synthesis scripts, firmware headers, and simulation testbenches:

### Key Configuration Parameters:
- **Processor Settings**:
  - `core`: `"cv32e40p"`
  - `isa`: `"rv32imc_xpulpv2"`
  - `clock_frequency_hz`: `50000000` (50 MHz)
- **Memory Dimensions**:
  - `i_tcm_size_bytes`: `32768` (32 KB @ `0x0000_0000`)
  - `d_tcm_size_bytes`: `32768` (32 KB @ `0x0001_0000`)
  - `dma_buf_a_addr`: `"0x20000000"` (4 KB)
  - `dma_buf_b_addr`: `"0x20001000"` (4 KB)
- **Peripheral Configuration**:
  - `spi_sclk_hz`: `1000000` (1.0 MHz, divisor = 50)
  - `spi_frame_bits`: `72`
  - `uart_baudrate`: `115200`
  - `dma_frame_len_bytes`: `12`
  - `dma_default_capacity_frames`: `256`
- **Target FPGA Constraints**:
  - `fpga_part`: `"xc7a100tcsg324-1"`
  - `fpga_board`: `"digilent_arty_a7_100t"`
  - `board_oscillator_hz`: `100000000` (100 MHz)
