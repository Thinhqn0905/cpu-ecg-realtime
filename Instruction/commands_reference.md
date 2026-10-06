# ECG SoC RTL Generation Commands & Workflow Architecture

This document adapts the 9 ASIC command workflows from the CNN-MAMBA reference project (`FPGA_MAMBA_ARTIX7_layers_support/asic/.claude/commands`) for the **RISC-V ECG Data Acquisition SoC** on Xilinx Artix-7 FPGA (Arty A7-100T).

---

## Command 1: `/autoflow` (Master Gated Pipeline Orchestrator)

**Target:** ECG SoC Peripherals (SPI Master, UART, Timer, GPIO, FIFO, DMA, APB Interconnect, SoC Top)  
**FPGA Device:** Xilinx Artix-7 `xc7a100tcsg324-1` (Arty A7-100T)  
**EDA Tools:** Vivado 2023.2+ (Synthesis/P&R), Verilator 5.x (Lint), Icarus Verilog `iverilog` (Simulation)

```
Phase 0: spec_writer       --> Interactive specification definition
  | [Gate 1: HUMAN REVIEW] -> Approve spec & register map
Phase 1: spec_parser       --> Extraction of REQ-IDs & module dependency mapping
Phase 2: config_ui         --> Parameter configuration & constraint validation
  | [Gate 2: AUTO]         --> Constraint check (SCLK <= Fsys/2, BRAM/LUT budget)
Phase 3a: rtl_generator    --> SystemVerilog module generation (11 modules)
Phase 3b: sva_generator    --> SVA protocol & interface assertions
  | [Gate 3: HUMAN REVIEW] -> Verify SVA properties match ADS1292R & APB specs
Phase 4: tb_generator      --> Self-checking testbenches (12 testcases)
  | [Gate 4: AUTO]         --> Verilator lint clean & iverilog compile pass
Phase 5: verification      --> Simulation run, mutation testing & RTM matrix
  | [Gate 5: HUMAN REVIEW] -> Verification sign-off (100% REQ-ID coverage)
Phase 6: spec_pdf_generator -> Final verification & implementation report
```

---

## Command 2: `/spec_writer` (Phase 0: Interactive Spec Generator)

**Purpose:** Guides the user through defining architectural parameters for the ECG SoC peripherals.  
**Interactive Prompts:**
1. **Sampling Rates:** Support 250, 500, 1000 Hz (default: 500 Hz).
2. **AFE Model:** Texas Instruments ADS1292R (2-channel 24-bit delta-sigma ADC, SPI Mode 1, DRDY# interrupt).
3. **SPI Clock:** System clock 50 MHz divided by 25 = 2.0 MHz SCLK.
4. **Host Communication:** UART 8N1, default 115200 baud, up to 921600 baud for burst raw streaming.
5. **Buffer Policy:** Dual-clock Async FIFO (capture) + Ping-Pong BRAM (block framing).
6. **Interrupt Policy:** DRDY# assigned highest PLIC priority (IRQ 3).
**Output:** Generates `spec/ecg_soc_spec.md`.

---

## Command 3: `/spec_parser` (Phase 1: Requirements Extraction & Mapping)

**Purpose:** Ingests `spec/ecg_soc_spec.md`, assigns standardized `REQ-ID` tags, and establishes module mappings.
- `REQ-SYS-xxx`: System-level timing, clocking, and memory mapping.
- `REQ-SPI-xxx`: ADS1292R SPI timing (`tCSSC`, `tSCCS`, `CPOL=0`, `CPHA=1`, 72-bit frame).
- `REQ-APB-xxx`: APB3 bus protocol compliance (`PSEL`, `PENABLE`, `PREADY`, `PSLVERR`).
- `REQ-FIFO-xxx`: FIFO watermarks, overflow drop, underflow guard.
- `REQ-UART-xxx`: Baud division, framing error detection, TX/RX buffers.
- `REQ-IRQ-xxx`: Priority resolution and latency bounds.
**Output:** Generates `spec/ecg_soc_reqs.json` and `spec/ecg_soc_module_map.json`.

---

## Command 4: `/config_ui` (Phase 2: Parameter Configuration)

**Configurable Parameters:**
- `PR_SYS_CLK_FREQ_MHZ`: Default `50` (50 MHz system clock).
- `PR_SPI_CLK_DIV`: Default `25` (2 MHz SCLK for ADS1292R).
- `PR_SPI_CPOL`: `0`, `PR_SPI_CPHA`: `1` (SPI Mode 1).
- `PR_SPI_WORD_LEN`: Default `24` (24-bit words).
- `PR_SPI_FIFO_DEPTH`: Default `8` (8 entries of 24-bit).
- `PR_UART_BAUD_DIV`: Default `434` (50 MHz / 115200 baud).
- `PR_UART_FIFO_DEPTH`: Default `16` (16 bytes).
- `PR_TIMER_WIDTH`: Default `32` (32-bit counter).
- `PR_GPIO_WIDTH`: Default `8` (8-bit bidirectional I/O).
- `PR_DMA_EN`: Default `0` (0: interrupt-driven, 1: autonomous BRAM DMA).
**Gate 2 Checks:**
- Validates `PR_SPI_CLK_DIV >= 2`.
- Validates peripheral resource estimate <= 5,000 LUTs, <= 10 BRAMs on Artix-7.
**Output:** Generates `config/ecg_soc_config.json`.

---

## Command 5: `/rtl_generator` (Phase 3a: SystemVerilog RTL Generation)

**Coding Standard:** SystemVerilog IEEE 1800-2017 conforming to `Instruction/design_rules.md`.
- `always_ff @(posedge clk_i or negedge rst_ni)` for sequential blocks.
- `always_comb` for combinational blocks.
- Strict `_i`, `_o`, `_n`, `_q`, `_d` naming suffixes.
- No behavioral delays (`#`), no `initial` blocks in synthesizable RTL.

**Module Delivery List (11 Modules):**
1. `ecg_soc_pkg.sv`: Register offsets, peripheral base addresses, status encodings.
2. `sync_fifo.sv`: Parameterized synchronous FIFO with status and watermarks.
3. `spi_master.sv`: 24-bit SPI master engine with programmable clock divider and Mode 1 support.
4. `spi_master_apb.sv`: APB3 slave wrapper with register bank (CTRL, STATUS, TX_DATA, RX_DATA, CLK_DIV).
5. `uart_controller.sv`: 8N1 UART transmitter/receiver with baud generator and FIFOs.
6. `uart_apb.sv`: APB3 slave wrapper for UART.
7. `timer_apb.sv`: 32-bit programmable countdown/up timer with interrupt output.
8. `gpio_apb.sv`: 8-bit GPIO controller with edge/level interrupt generation.
9. `apb_interconnect.sv`: 1-to-6 APB address decoder and read multiplexer.
10. `ecg_dma.sv`: Autonomous sample mover (SPI RX FIFO -> Ping-Pong BRAM).
11. `ecg_soc_top.sv`: Top-level integration uniting all peripherals with APB and interrupt lines.

**Lint Check:** Ran automatically via `verilator --lint-only -Wall`.

---

## Command 6: `/sva_generator` (Phase 3b: SVA Formal Assertion Generation)

**Purpose:** Generates SystemVerilog Assertions (SVA) and bind files for formal and simulation checking.
- `spi_master_sva.sv`:
  * CS# assertion timing: `assert property (@(posedge clk) $fell(cs_n) |-> ##[1:$] $fell(sclk))`.
  * SCLK frequency validation: `assert property (@(posedge clk) sclk_period >= MIN_SCLK_CYCLES)`.
  * Data stability: MISO sampled on falling edge, MOSI changed on rising edge (Mode 1).
- `apb_protocol_sva.sv`:
  * PSEL setup before PENABLE.
  * PADDR/PWRITE/PWDATA stability while PSEL && !PREADY.
- `sync_fifo_sva.sv`:
  * No push when `full_o` without `overflow_err_o`.
  * No pop when `empty_o` without `underflow_err_o`.
**Output:** Files placed in `RTL/ecg_soc/sva/` with corresponding `_bind.sv` files.

---

## Command 7: `/tb_generator` (Phase 4: Self-Checking Testbenches)

**Purpose:** Generates comprehensive testbenches with golden checking and ADS1292R behavioral model.
**Standard Test Cases (12 Test Cases):**
- `TC-001`: APB register read/write integrity across all peripheral registers.
- `TC-002`: SPI loopback (MOSI connected to MISO) with random 24-bit words.
- `TC-003`: ADS1292R device ID read sequence (0x20 0x00 command returning 0x73).
- `TC-004`: UART loopback transmission at 115200 and 921600 baud.
- `TC-005`: Timer periodic compare interrupt generation.
- `TC-006`: GPIO direction, output toggling, and input edge interrupt.
- `TC-007`: Continuous 500 Hz 3-byte status + 2x3-byte channel data capture.
- `TC-008`: UART packet formatting (14-byte standard packet with CRC-8).
- `TC-009`: Interrupt priority arbitration (DRDY# IRQ 3 preempts UART IRQ 1).
- `TC-010`: FIFO full, empty, almost-full, and almost-empty boundary checks.
- `TC-011`: DMA block transfer to Ping-Pong BRAM (if PR_DMA_EN=1).
- `TC-012`: End-to-end integration: ADS1292R DRDY# -> SPI Read -> Buffer -> UART TX.

---

## Command 8: `/verification` (Phase 5: Simulation, Mutation & RTM Dashboard)

**Simulation Engine:** `iverilog -g2012` + `vvp` or `verilator --binary`.
**Quality Metrics:**
1. **Pass Rate:** 12/12 Test Cases must PASS.
2. **RTM Dashboard:** Every `REQ-ID` mapped to >= 1 passing test case.
3. **Mutation Testing:** Fault injection in state machines and counter limits using Yosys/Python mutation scripts (Target: >= 80% mutation kill rate).
**Gate 5 Artifact:** Generates `reports/verification/rtm_dashboard.md`.

---

## Command 9: `/spec_pdf_generator` (Phase 6: Specification & Report Generation)

**Deliverables Generated:**
1. Complete register map with bitfield definitions.
2. Vivado synthesis resource utilization summary (LUT, FF, BRAM, DSP on Artix-7).
3. Timing closure report (Worst Negative Slack, Fmax >= 50 MHz).
4. Power estimation report (board-level dynamic & static power).
5. RTM sign-off matrix.
