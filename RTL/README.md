# RTL Directory: Synthesizable SystemVerilog Architecture

This directory contains the synthesizable Register-Transfer Level (RTL) SystemVerilog source code for the CV32E40P RISC-V Real-Time ECG SoC, targeting both Xilinx Artix-7 FPGA and SkyWater 130nm ASIC technologies.

---

## Directory Hierarchy

```
RTL/
├── ecg_soc/                         # Core SoC architecture & peripheral subsystem
│   ├── ecg_soc_pkg.sv               # Global parameter packages, APB definitions & types
│   ├── cv32e40p_ecg_soc_top.sv      # SoC integration top-level wrapping the CV32E40P core
│   ├── ecg_soc_top.sv               # Generic reference SoC top-level
│   ├── tcm_sram.sv                  # Dual-port zero-wait-state Harvard TCM (I-TCM & D-TCM)
│   ├── obi_to_apb.sv                # Open Bus Interface to AMBA APB3 bridge
│   ├── apb_interconnect.sv          # 1-to-N APB3 multi-slave address decoder
│   ├── spi_master.sv                # 72-bit continuous-CS ADS1292R SPI engine with Auto-DRDY
│   ├── spi_master_apb.sv            # APB3 bus wrapper for spi_master.sv
│   ├── ecg_dma.sv                   # Split-plane ping-pong frame unpacking DMA controller
│   ├── uart_controller.sv           # 16550-compatible UART core (115200 baud, 8N1)
│   ├── uart_apb.sv                  # APB3 bus wrapper for uart_controller.sv
│   ├── timer_apb.sv                 # 64-bit real-time counter & compare timer
│   ├── gpio_apb.sv                  # Multi-bit GPIO controller with edge/level interrupts
│   ├── sync_fifo.sv                 # Generic synchronous circular FIFO buffer
│   ├── mamba_bridge.sv              # Hardware coprocessor streaming FIFO bridge
│   ├── fpga/
│   │   └── ecg_arty_top.sv          # Digilent Arty A7-100T board top with Xilinx MMCM
│   └── sva/                         # SystemVerilog Assertions (SVA) & formal property checkers
│       ├── obi_to_apb_sva.sv        # Formal protocol assertions for OBI-APB bridge
│       ├── obi_to_apb_bind.sv       # Bind directive for bridge assertions
│       ├── spi_master_sva.sv        # Formal timing assertions for 72-bit continuous CS#
│       └── spi_master_bind.sv       # Bind directive for SPI master assertions
```

---

## Module Descriptions

### 1. `cv32e40p_ecg_soc_top.sv`
- **Role**: Top-level SoC harness integrating the OpenHW CV32E40P processor core.
- **Interfaces**:
  - Connects core Instruction OBI (`instr_*`) to I-TCM port A.
  - Connects core Data OBI (`data_*`) to OBI demultiplexer routing to D-TCM or `obi_to_apb` bridge.
  - Direct-vectors peripheral interrupts into core IRQ lines:
    - `irq_i[7]`  <= `timer_irq` (MTIP)
    - `irq_i[16]` <= `uart_irq` (Fast IRQ 16)
    - `irq_i[17]` <= `spi_irq`  (Fast IRQ 17)
    - `irq_i[18]` <= `dma_irq`  (Fast IRQ 18)
    - `irq_i[19]` <= `gpio_irq` (Fast IRQ 19)

### 2. `tcm_sram.sv`
- **Role**: Dual-port zero-wait-state Tightly-Coupled Memory.
- **Capacity**:
  - I-TCM: 32 KB (`0x0000_0000` - `0x0000_7FFF`), initialized with firmware `.hex`.
  - D-TCM: 32 KB (`0x0001_0000` - `0x0001_7FFF`), runtime data and stack (`sp = 0x0001_7FF0`).
- **Features**: Byte-enable masking (`be[3:0]`) for byte and halfword store operations (`sb`, `sh`).

### 3. `obi_to_apb.sv`
- **Role**: High-speed protocol bridge converting non-blocking OBI transactions to registered AMBA APB3.
- **Protocol Translation**: Translates OBI `req`/`gnt` handshakes into APB3 `SETUP` and `ACCESS` phases with zero dead-cycles on consecutive transfers.
- **Backpressure Handling**: Holds OBI `rvalid` low until APB slave asserts `PREADY`.

### 4. `spi_master.sv` & `spi_master_apb.sv`
- **Role**: Dedicated SPI controller for the Texas Instruments ADS1292R 24-bit 2-channel analog front-end.
- **Critical Requirements**:
  - **72-bit continuous CS#**: Asserts `spi_cs_n = 0` continuously for all 72 SCLK cycles without deassertion.
  - **Autonomous DRDY# Capture**: Edge detector on `drdy_n` automatically initiates serial shift.
  - **Clock Divider**: Generates exact 1.0 MHz SCLK from 50 MHz system clock ($div = 50$).

### 5. `ecg_dma.sv`
- **Role**: Autonomous direct memory access engine for streaming ECG samples.
- **Features**:
  - Unpacks 72-bit raw SPI ingress into standardized 12-byte frames (Status + sign-extended CH1 + sign-extended CH2).
  - Ping-pong double buffering between Buffer A (`0x2000_0000`) and Buffer B (`0x2000_1000`).
  - Generates Fast IRQ 18 upon buffer boundary crossing.

### 6. `uart_controller.sv` & `uart_apb.sv`
- **Role**: Serial communication interface for telemetry transmission to host PC.
- **Configuration**: 115200 baud, 8 data bits, no parity, 1 stop bit (8N1).
- **Buffering**: 16-deep synchronous FIFO for both TX and RX.

### 7. `timer_apb.sv`
- **Role**: 64-bit real-time counter and compare unit.
- **Function**: Produces periodic system ticks for RTOS or sample timestamping.

### 8. `gpio_apb.sv`
- **Role**: General-purpose I/O controller managing AFE power-down, reset, lead-off detection, and board LEDs.

### 9. `fpga/ecg_arty_top.sv`
- **Role**: Physical top-level wrapper for the Digilent Arty A7-100T evaluation board.
- **Components**: Instantiates Xilinx MMCM primitive to synthesize 50 MHz system clock from 100 MHz oscillator.

---

## Design Guidelines & SVA Verification
- All synthesizable modules follow strict IEEE 1800-2012 SystemVerilog rules.
- Floating-point (`real`, `shortreal`) and DPI calls are strictly prohibited in synthesizable code.
- Formal assertions (`obi_to_apb_sva.sv`, `spi_master_sva.sv`) verify bus protocols and continuous CS# framing.
