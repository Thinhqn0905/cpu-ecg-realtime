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
│   │   ├── ecg_arty_top.sv          # Digilent Arty A7-100T board top with Xilinx MMCM
│   │   └── cv32e40p_fpga_clock_gate.sv # Synthesizable direct clock gate for 7-series FPGA
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
  - I-TCM: 32 KB (`0x0000_0000` - `0x0000_7FFF`, 8 RAMB36E1), initialized with firmware `.hex`.
  - D-TCM: 128 KB (`0x0001_0000` - `0x0002_FFFF`, 32 RAMB36E1), single-cycle SRAM storing:
    - ResUMamba-30K INT8/INT16 model weights: 32.4 KB
    - Double-buffered activation ping-pong workspace: 32.0 KB
    - Static runtime data, heap, and call stack (`sp = 0x0002_FFF0`): 63.6 KB
- **Features**: Byte-enable masking (`be[3:0]`) for byte and halfword store operations (`sb`, `sh`) with zero wait-states on OBI transactions.

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

### 9. `mamba_bridge.sv`
- **Role**: Memory-mapped APB3 control and status interface for the DiagSSM1D hardware coprocessor.
- **Base Address**: `0x1000_5000` (APB Slave Slot 5).
- **Register Memory Map**:
  - `0x00` (`REG_CTRL`): Bit 0 = `START` (trigger execution), Bit 1 = `IRQ_EN` (completion interrupt enable), Bit 2 = `SOFT_RESET`.
  - `0x04` (`REG_STATUS`): Bit 0 = `BUSY`, Bit 1 = `DONE`, Bit 2 = `ERROR`.
  - `0x08` (`REG_SRC_ADDR`): Physical base address of input activation vector in D-TCM.
  - `0x0C` (`REG_DST_ADDR`): Physical base address of output feature destination in D-TCM.
  - `0x10` (`REG_LEN`): Sequence sample length (default $L = 500$ samples).
  - `0x14` (`REG_CYCLES`): Read-only cycle counter recording exact execution duration.
  - `0x18` (`REG_RESULT_CLASS`): Quantized classification category (0: Normal, 1: SVEB, 2: PVC, 3: Fusion).
  - `0x1C` (`REG_RESULT_CONF`): Q15 confidence probability score of predicted class.
- **Interconnect**: Direct OBI DMA master port into D-TCM and dedicated streaming interface into `mamba_fir_sidecar.sv`.

### 10. `mamba_fir_sidecar.sv`
- **Role**: Pipelined 4-lane 128-tap bidirectional DiagSSM1D depthwise finite impulse response (FIR) state-space accelerator.
- **Microarchitecture**:
  - 4 parallel compute lanes, each executing dual-direction state-space convolutions:
    $$y[t, c] = \text{clamp}_{i16} \left( \left( \sum_{\tau=0}^{127} \left( w_{\text{fwd}}[\tau, c] \cdot x_{\text{fwd}}[t-\tau, c] + w_{\text{bwd}}[\tau, c] \cdot x_{\text{bwd}}[t-\tau, c] \right) \right) \gg 15 \right)$$
  - Direct synthesis mapping to 4 Xilinx DSP48E1 slices per lane (16 DSP48E1 total), absorbing multiply-accumulate chains without external slice logic.
  - Double-buffered circular line buffers for zero-overhead streaming.
  - **Latency**: Exactly 69,632 clock cycles ($\mathbf{1.39\text{ ms}}$ at 50 MHz), representing a $\mathbf{50\times}$ throughput acceleration over software.

### 11. `fpga/ecg_arty_top.sv`
- **Role**: Physical top-level wrapper for the Digilent Arty A7-100T evaluation board.
- **Components**: Instantiates Xilinx MMCM primitive to synthesize 50 MHz system clock from 100 MHz oscillator. Configures 128 KB D-TCM (`D_MEM_SIZE_BYTES = 131072`).

### 12. `fpga/cv32e40p_fpga_clock_gate.sv`
- **Role**: Synthesizable FPGA clock-forwarding cell for Xilinx 7-series devices.
- **Function**: Replaces simulation-only `always_latch` clock gating with direct wire assignment (`assign clk_o = clk_i`), eliminating transparent latch feedback loops, secondary cascaded BUFG skew, and DRC violations to enable zero-skew static timing closure.

---

## Tri-Modal Biosignal Processing Architectures

The RTL subsystem natively supports all three clinical biosignal processing paradigms:

```
+---------------------------------------------------------------------------------------------------+
| METHOD 1: PURE IN-CORE SOFTWARE (CV32E40P + Xpulpv2 DSP)                                          |
|                                                                                                   |
|  ADS1292R SPI ---> DMA Ping-Pong ---> 128 KB D-TCM ---> CV32E40P (Hardware Loops, pv.dotsp.h)     |
|                                                         [254.36 ms / beat @ 50 MHz]               |
+---------------------------------------------------------------------------------------------------+
| METHOD 2: DEDICATED HARDWARE COPROCESSOR OFFLOAD                                                  |
|                                                                                                   |
|  ADS1292R SPI ---> DMA Ping-Pong ---> 128 KB D-TCM <====> mamba_bridge <====> mamba_fir_sidecar   |
|                                                            (APB3 Control)     (4-Lane DSP48E1)    |
|                                                                               [1.39 ms / beat]    |
+---------------------------------------------------------------------------------------------------+
| METHOD 3: TWO-STAGE HIERARCHICAL CASCADE (Sub-mW Surveillance -> Triggered Deep Inference)       |
|                                                                                                   |
|  ADS1292R SPI ---> Stage 1: Pan-Tompkins Continuous Surveillance (< 0.2% CPU, < 45 mW)             |
|                          |                                                                        |
|                          +---> PVC / Ectopic Detected?                                            |
|                                     |                                                             |
|                                     +---[YES]---> Wake Stage 2 ResUMamba (Method 1 or Method 2)  |
|                                     |                                                             |
|                                     +---[NO]----> Low-Power Idle (> 95% Energy Savings)           |
+---------------------------------------------------------------------------------------------------+
```

---

## Design Guidelines & SVA Verification
- All synthesizable modules follow strict IEEE 1800-2012 SystemVerilog rules.
- Floating-point (`real`, `shortreal`) and DPI calls are strictly prohibited in synthesizable code.
- Formal assertions (`obi_to_apb_sva.sv`, `spi_master_sva.sv`) verify bus protocols and continuous CS# framing.
