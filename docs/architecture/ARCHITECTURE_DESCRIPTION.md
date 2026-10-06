# CV32E40P Real-Time ECG SoC — Microarchitecture Reference Manual

**Document Version:** 3.0.0 (Frozen Architecture Baseline)  
**Target Core:** OpenHW Group CV32E40P (v1.8.3, RV32IMC + Xpulpv2)  
**Target Device:** Xilinx Artix-7 FPGA (`xc7a100tcsg324-1`)  
**Biosignal AFE:** Texas Instruments ADS1292R (24-bit 2-channel ECG front-end)  

---

## 1. Architectural Overview & Design Principles

The CV32E40P Real-Time ECG SoC is designed to meet strict clinical data acquisition standards:
1. **Zero Sample Loss & Jitter Freedom**: The system guarantees jitter-free biosignal acquisition from 250 Hz to 1000 Hz per channel through autonomous hardware-driven DRDY# falling-edge capture and split-plane ping-pong DMA buffering.
2. **Minimal Interrupt Latency**: The processor employs direct-vectored interrupt dispatch (`mtvec = 0x0000_0101`) with direct vector table execution at `0x0000_0100`, eliminating multi-cycle software dispatch overheads.
3. **Determinism through TCM Harvard Memory**: Both Instruction TCM (32 KB) and Data TCM (32 KB) provide single-cycle, zero-wait-state combinational access, eliminating cache misses and bus contention during critical DSP filtering passes.
4. **Hardware DSP Acceleration**: Employs PULP `Xpulpv2` extension instructions (`p.mac`, `lp.setup`, post-increment loads) for real-time 45-tap FIR filtering and Pan-Tompkins QRS wave detection.

```
                           +-------------------------------------+
                           |            CV32E40P Core            |
                           |   +-----------+     +-----------+   |
                           |   | Instr OBI |     | Data OBI  |   |
                           +---+-----+-----+-----+-----+-----+---+
                                     |                 |
                         Instr Addr  |                 | Data Addr / Wdata
                         Instr Rdata |                 | Data Rdata / We
                                     v                 v
                           +---------+---+       +-----+---------+
                           | 32 KB I-TCM |       |   OBI Demux   |
                           | 0x0000_0000 |       +---+-----+-----+
                           +-------------+           |     |
                                                     |     +-------------------------+
                                                     v                               v
                                              +------+------+                 +------+------+
                                              | 32 KB D-TCM |                 | OBI-to-APB3 |
                                              | 0x0001_0000 |                 |   Bridge    |
                                              +-------------+                 +------+------+
                                                                                     |
                                                                        +------------+------------+
                                                                        |    APB Interconnect     |
                                                                        +---+----+----+----+----+
                                                                            |    |    |    |    |
                                              +-----------------------------+    |    |    |    |
                                              |                                  |    |    |    |
                                              v                                  v    v    v    v
                                       +------+------+                        +----+----+----+----+
                                       |   ECG DMA   |<-----------------------|SPI |UART|TIMR|GPIO|
                                       | 0x1000_4000 |  72-bit packed sample  +----+----+----+----+
                                       +------+------+
                                              |
                                     (D-OBI Direct Port)
                                              v
                                       +------+------+
                                       | Ping-Pong   |
                                       | Buffers A/B |
                                       | 0x2000_0000 |
                                       +-------------+
```

---

## 2. Bus Architecture & Interconnect Protocol

### 2.1 Harvard Open Bus Interface (OBI)

The processor communicates with memories and peripherals over two independent 32-bit Open Bus Interface (OBI) ports:
- **`instr_*`**: Instruction fetch port.
- **`data_*`**: Load/store data port.

#### OBI Protocol Signals:
- `req`: Master assertion indicating a valid transfer request.
- `gnt`: Slave acknowledgment indicating acceptance of request address.
- `addr[31:0]`: 32-bit byte address.
- `we`: Write enable (high = write, low = read).
- `be[3:0]`: Byte enables for byte/half-word masking.
- `wdata[31:0]`: Write data.
- `rvalid`: Slave assertion indicating read data `rdata` or write completion is valid.
- `rdata[31:0]`: Read data from slave.

#### OBI Single-Cycle Zero-Wait Handshake Timing:
```
Clock Cycle:       | 1 | 2 | 3 |
clk:             _/ \_/ \_/ \_
req:             ___/¯¯¯\_____
gnt:             ___/¯¯¯\_____  (combinational ack in cycle 1)
addr:            ---< A1>-----
rvalid:          _______/¯¯¯\_  (data available in cycle 2)
rdata:           -------< D1>-
```

### 2.2 OBI-to-APB3 Protocol Bridge (`obi_to_apb.sv`)

The bridge translates non-blocking OBI transactions into compliant AMBA APB3 transfers:
- **`PCLK`**: Shared system clock (50 MHz).
- **`PRESETn`**: Active-low asynchronous reset with synchronous release.
- **`PSELx`**: Individual peripheral slave select.
- **`PENABLE`**: APB access phase strobed high for the second cycle of an APB transfer.
- **`PWRITE`**: Direction control (1 = Write, 0 = Read).
- **`PWDATA[31:0]`**: APB write data bus.
- **`PRDATA[31:0]`**: APB read data bus.
- **`PREADY`**: Slave wait-state insertion (the bridge holds OBI `rvalid` low until `PREADY` is asserted).

#### Bridge State Machine:
```
           +----------------+
           |   ST_IDLE      |<------------------------------------+
           +-------+--------+                                     |
                   | obi_req && apb_addr_match                    |
                   v                                              |
           +----------------+                                     |
           |   ST_SETUP     | (PSEL = 1, PENABLE = 0)             |
           +-------+--------+                                     |
                   | unconditional next cycle                     |
                   v                                              |
           +----------------+                                     |
           |   ST_ACCESS    | (PSEL = 1, PENABLE = 1)             |
           +-------+--------+                                     |
                   | PREADY == 1 (obi_rvalid = 1, obi_gnt = 1)    |
                   +----------------------------------------------+
```

---

## 3. Peripheral Subsystem Specifications

### 3.1 ADS1292R SPI Master (`spi_master.sv` & `spi_master_apb.sv`)

The SPI Master peripheral interfaces with the Texas Instruments ADS1292R analog front-end chip.

#### Register Map (Base: `0x1000_0000` or `0x1A10_0000`):

| Offset | Register Name | Access | Reset Value | Description |
|--------|---------------|--------|-------------|-------------|
| `0x00` | `SPI_CTRL`    | R/W    | `0x0000_0032`| Control register: Clock divider, CPOL, CPHA, Auto-DRDY enable |
| `0x04` | `SPI_STATUS`  | R/W1C  | `0x0000_0000`| Status register: Busy, Done, DRDY detected, FIFO full/empty |
| `0x08` | `SPI_TXDATA`  | W      | `0x0000_0000`| Transmit command data register (8-bit) |
| `0x0C` | `SPI_RXDATA0` | R      | `0x0000_0000`| Received 24-bit Status word (`{8'h0, status[23:0]}`) |
| `0x10` | `SPI_RXDATA1` | R      | `0x0000_0000`| Received 24-bit Channel 1 ECG voltage sample |
| `0x14` | `SPI_RXDATA2` | R      | `0x0000_0000`| Received 24-bit Channel 2 ECG voltage sample |
| `0x18` | `SPI_CLKDIV`  | R/W    | `0x0000_0032`| Direct clock divider register ($div = 50 \implies 1.0\text{ MHz}$) |

#### `SPI_CTRL` Bitfield Definition:
```
[31:16] - Reserved (read as 0)
[15:8]  - CLK_DIV[7:0]   : Integer clock divider ratio (default = 50)
[7]     - AUTO_DRDY_EN   : 1 = Automatically trigger 72-bit transfer on DRDY# falling edge
[6]     - START_MANUAL   : 1 = Initiate manual SPI transfer (self-clearing)
[5]     - CS_FORCE       : Manual CS# override (0 = auto, 1 = force assert)
[4]     - IRQ_EN         : 1 = Enable interrupt on acquisition completion
[3:2]   - SPI_MODE[1:0]  : Mode select ([1]=CPOL, [0]=CPHA; default = 2'b01 -> Mode 1)
[1]     - WORD_LEN[1:0]  : 00 = 8-bit command, 10 = 72-bit ECG frame
[0]     - SPI_EN         : 1 = Master enabled
```

#### 72-Bit Continuous Chip-Select Sequence:
```
drdy_n:    ¯¯\___________________________________________________________/¯¯
cs_n:      ¯¯¯\_________________________________________________________/¯¯¯
sclk:      _____/\_/\_/\_/\_ ... (72 continuous clock cycles) ... _/\_/\_____
miso:      -----< Status[23:0] ><----- CH1[23:0] ----><----- CH2[23:0] ---->-
irq:       _____________________________________________________________/¯\_
```

---

### 3.2 Split-Plane Ping-Pong DMA Controller (`ecg_dma.sv`)

The DMA controller autonomously unpacks incoming 72-bit SPI frames into memory without core intervention.

#### Register Map (Base: `0x1000_4000` or `0x1A10_4000`):

| Offset | Register Name | Access | Reset Value | Description |
|--------|---------------|--------|-------------|-------------|
| `0x00` | `DMA_CTRL`    | R/W    | `0x0000_0000`| DMA Enable, Ping-Pong Mode Enable, IRQ Enable, Soft Reset |
| `0x04` | `DMA_STATUS`  | R/W1C  | `0x0000_0000`| Active buffer indicator (0 = A, 1 = B), Buffer full flags |
| `0x08` | `DMA_BUFA_PTR`| R/W    | `0x2000_0000`| Base address for Ping-Pong Buffer A |
| `0x0C` | `DMA_BUFB_PTR`| R/W    | `0x2000_1000`| Base address for Ping-Pong Buffer B |
| `0x10` | `DMA_BUF_LEN` | R/W    | `0x0000_0100`| Buffer capacity in number of frames (default = 256 frames) |
| `0x14` | `DMA_CUR_CNT` | R      | `0x0000_0000`| Current write index within active buffer |

#### Standardized 12-Byte Frame Layout:
Each 72-bit ingress transaction from the ADS1292R is packed into three 32-bit words (12 bytes total):
```
Byte Offset   Word      Bits [31:24]       Bits [23:16]       Bits [15:8]        Bits [7:0]
+0x00         Word 0:   [   0x00   ]       [   0x00   ]       [   0x00   ]       [ Status Byte ]
+0x04         Word 1:   [ Sign-Ext ]       [  CH1 [23:16]  ]  [  CH1 [15:8]   ]  [  CH1 [7:0]  ]
+0x08         Word 2:   [ Sign-Ext ]       [  CH2 [23:16]  ]  [  CH2 [15:8]   ]  [  CH2 [7:0]  ]
```
*Note:* Bits `[31:24]` of Words 1 and 2 replicate bit `[23]` of the respective channel data to provide immediate signed 32-bit `int32_t` integer representation for the arithmetic pipeline.

---

### 3.3 UART Controller (`uart_controller.sv` & `uart_apb.sv`)

Provides serial communication to a host workstation or wireless telemetry unit.

#### Register Map (Base: `0x1000_1000` or `0x1A10_1000`):

| Offset | Register Name | Access | Reset Value | Description |
|--------|---------------|--------|-------------|-------------|
| `0x00` | `UART_TXDATA` | W      | `0x0000_0000`| Transmit data register (writes push into TX FIFO) |
| `0x04` | `UART_RXDATA` | R      | `0x0000_0000`| Receive data register (reads pop from RX FIFO) |
| `0x08` | `UART_STATUS` | R      | `0x0000_0002`| Status: TX Full (`[0]`), TX Empty (`[1]`), RX Empty (`[2]`) |
| `0x0C` | `UART_BAUD`   | R/W    | `0x0000_01B2`| Baud divisor register ($50\text{ MHz} / (16 \times 115200) = 27$) |
| `0x10` | `UART_CTRL`   | R/W    | `0x0000_0003`| TX Enable (`[0]`), RX Enable (`[1]`), IRQ Enable (`[2]`) |

---

### 3.4 Timer & Real-Time Counter (`timer_apb.sv`)

Implements a standard 64-bit real-time counter for periodic scheduling and system timestamping.

#### Register Map (Base: `0x1000_2000` or `0x1A10_2000`):

| Offset | Register Name | Access | Reset Value | Description |
|--------|---------------|--------|-------------|-------------|
| `0x00` | `MTIME_LOW`   | R/W    | `0x0000_0000`| Real-time counter lower 32 bits |
| `0x04` | `MTIME_HIGH`  | R/W    | `0x0000_0000`| Real-time counter upper 32 bits |
| `0x08` | `MTIMECMP_LOW`| R/W    | `0xFFFF_FFFF`| Timer compare match lower 32 bits |
| `0x0C` | `MTIMECMP_HIGH`| R/W   | `0xFFFF_FFFF`| Timer compare match upper 32 bits |
| `0x10` | `TIMER_CTRL`  | R/W    | `0x0000_0001`| Timer run enable (`[0]`), Periodic reset enable (`[1]`) |

*Interrupt Generation:* When `{MTIME_HIGH, MTIME_LOW} >= {MTIMECMP_HIGH, MTIMECMP_LOW}`, the timer asserts Machine Timer Interrupt (MTIP) on Core IRQ line 7.

---

### 3.5 GPIO Controller (`gpio_apb.sv`)

Manages external discrete signals including ADS1292R reset, power-down, lead-off status, and on-board status LEDs.

#### Register Map (Base: `0x1000_3000` or `0x1A10_3000`):

| Offset | Register Name | Access | Reset Value | Description |
|--------|---------------|--------|-------------|-------------|
| `0x00` | `GPIO_DATA_IN`| R      | `0x0000_0000`| Direct read of input pin levels |
| `0x04` | `GPIO_DATA_OUT`| R/W   | `0x0000_0000`| Output pin drive states |
| `0x08` | `GPIO_DIR`    | R/W    | `0x0000_0000`| Direction control: 0 = Input, 1 = Output |
| `0x0C` | `GPIO_INT_EN` | R/W    | `0x0000_0000`| Per-pin interrupt enable |
| `0x10` | `GPIO_INT_TYPE`| R/W   | `0x0000_0000`| Trigger type: 0 = Level, 1 = Edge |
| `0x14` | `GPIO_INT_POL`| R/W    | `0x0000_0000`| Polarity: 0 = Low/Falling, 1 = High/Rising |

---

## 4. Hardware-Software Interface & Boot Process

### 4.1 Cold Reset & Vector Initialization
1. Upon power-on reset deassertion, the CV32E40P core begins execution at boot vector `boot_addr_i = 0x0000_0000`.
2. `Firmware/boot/crt0.S` executes:
   - Sets stack pointer: `la sp, __stack_top` (`0x0001_7FF0` in D-TCM).
   - Initializes Machine Trap-Vector:
     ```assembly
     la t0, _vector_table      # Address 0x0000_0100
     ori t0, t0, 1             # Set Mode = 1 (Direct Vectored)
     csrw mtvec, t0
     ```
   - Clears `.bss` section in D-TCM.
   - Enables machine-level global interrupts: `csrsi mstatus, 0x8`.
   - Jumps to C runtime `main()`.

### 4.2 ECG Data Acquisition Pipeline Execution
1. **AFE Setup**:
   - Firmware asserts ADS1292R `RESET` pin via GPIO.
   - Configures ADS1292R internal reference, lead-off comparator, and 250 SPS sampling mode via SPI commands.
   - Configures SPI master `SPI_CTRL` with `AUTO_DRDY_EN = 1` and `CLK_DIV = 50`.
2. **Autonomous Ingress**:
   - The ADS1292R asserts `DRDY#` low.
   - Hardware SPI master pulls `CS#` low, executes 72 SCLK pulses, and latches `{Status, CH1, CH2}`.
   - SPI Master presents sample to DMA; DMA writes 12-byte packed frame to active ping-pong buffer in D-OBI space.
3. **Buffer Completion & Swapping**:
   - When DMA frame count reaches `DMA_BUF_LEN`, DMA flips active buffer and generates Fast IRQ 18.
   - `dma_irq_handler` vectors immediately, notifies DSP worker thread, and starts FIR filtering and Pan-Tompkins analysis on the completed buffer.
   - Zero sample loss occurs because the alternate buffer immediately absorbs ongoing ingress.
