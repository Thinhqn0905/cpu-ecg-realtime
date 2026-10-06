# Simulation Directory: Verification Environments & Behavioral Models

This directory contains the verification testbenches, behavioral analog front-end models, and automated execution scripts for the CV32E40P RISC-V ECG SoC.

---

## Directory Hierarchy

```
Simulation/
├── ads1292r_model.sv            # Behavioral simulation model of Texas Instruments ADS1292R AFE
├── tcm_router_tb.sv             # Unit testbench for Dual-Port TCM SRAM (TC-TCM-001..005)
├── obi_apb_bridge_tb.sv         # Unit testbench for OBI-to-APB3 Bridge (TC-BRG-001..004)
├── spi_master_tb.sv             # Unit testbench for 72-bit Continuous-CS SPI Master (TC-SPI-001A..007)
├── ecg_dma_tb.sv                # Unit testbench for Ping-Pong Frame Unpacking DMA (TC-DMA-001..006)
├── soc_tb.sv                    # Full-SoC co-simulation testbench with CV32E40P core (TC-SYS-001..017)
├── run_tcm.ps1                  # PowerShell automated runner for TCM verification
├── run_bridge.ps1               # PowerShell automated runner for Bridge verification
├── run_spi.ps1                  # PowerShell automated runner for SPI verification
└── run_dma.ps1                  # PowerShell automated runner for DMA verification
```

---

## 1. Testbenches & Test Case Mapping

### A. TCM SRAM Testbench (`tcm_router_tb.sv`)
- **Focus**: Verifies simultaneous instruction fetch and data read/write without arbitration collisions, zero-wait-state bus response, and byte-enable masking.
- **Test Cases**:
  - `TC-TCM-001`: Concurrent I-fetch and D-read in the same clock cycle.
  - `TC-TCM-002`: Read access from read-only data section (`.rodata`).
  - `TC-TCM-003`: Byte-enable masking composite write/read verification (`be[3:0]`).
  - `TC-TCM-004`: Memory boundary wrap and address decoding check (`0x0000_7FFC`).
  - `TC-TCM-005`: Single-cycle zero-wait response verification (`gnt` and `rvalid` timing).

### B. OBI-to-APB3 Bridge Testbench (`obi_apb_bridge_tb.sv`)
- **Focus**: Verifies OBI request to APB setup/access protocol translation, backpressure wait states, and dual-window address decoding.
- **Test Cases**:
  - `TC-BRG-001`: Basic single-cycle APB write and read transaction.
  - `TC-BRG-002`: Backpressure wait-state insertion via slave `PREADY = 0`.
  - `TC-BRG-003`: Dual-window address decoding (`0x1000_xxxx` legacy vs `0x1A10_xxxx` OpenHW standard).
  - `TC-BRG-004`: Back-to-back streaming transactions without dead cycles.

### C. ADS1292R SPI Master Testbench (`spi_master_tb.sv`)
- **Focus**: Verifies the strict timing contract of the Texas Instruments ADS1292R AFE chip.
- **Test Cases**:
  - `TC-SPI-001A`: Continuous CS# assertion across all 72 SCLK pulses (no mid-frame deassertion).
  - `TC-SPI-001B`: SCLK frequency verification ($50\text{ MHz} / 50 = 1.0\text{ MHz} \pm 0.1\%$).
  - `TC-SPI-002`: Autonomous DRDY# falling-edge capture and automatic acquisition start.
  - `TC-SPI-003`: Exact 72-bit unpacking into Status, Channel 1, and Channel 2 registers.
  - `TC-SPI-003B`: SPI Mode 1 timing verification (CPOL = 0, CPHA = 1).
  - `TC-SPI-004`: Acquisition complete interrupt generation (Fast IRQ 17).
  - `TC-SPI-005`: Overrun detection when new DRDY# arrives before prior frame read.
  - `TC-SPI-006`: Manual SPI transfer mode for ADS1292R command configuration.
  - `TC-SPI-007`: Programmable clock divider functionality verification.

### D. Ping-Pong DMA Testbench (`ecg_dma_tb.sv`)
- **Focus**: Verifies autonomous split-plane buffering and standardized 12-byte frame assembly.
- **Test Cases**:
  - `TC-DMA-001`: Correct 12-byte frame unpacking (Word 0: Status, Word 1: sign-extended CH1, Word 2: sign-extended CH2).
  - `TC-DMA-002`: Buffer A filling and pointer increment verification.
  - `TC-DMA-003`: Buffer boundary crossing and atomic buffer swap (Buffer A to Buffer B).
  - `TC-DMA-004`: Fast IRQ 18 generation upon buffer swap.
  - `TC-DMA-005`: Continuous ping-pong operation without frame dropping.
  - `TC-DMA-006`: CPU read access to inactive buffer while DMA writes to active buffer.

### E. Full-SoC Co-Simulation Testbench (`soc_tb.sv`)
- **Focus**: Full system co-simulation with CV32E40P core executing compiled firmware.
- **Test Cases (`TC-SYS-001` to `017`)**:
  - Reset vector fetch, CRT0 startup execution, BSS zeroing.
  - `mtvec` direct-vectored trap table initialization at `0x0000_0100`.
  - Machine Timer Interrupt (MTIP) generation and handler entry.
  - APB peripheral read/write access from C code.
  - Real-time ADS1292R streaming and UART telemetry output.

---

## 2. Behavioral ADS1292R Model (`ads1292r_model.sv`)
- Emulates the analog front-end chip's internal state machine:
  - Generates periodic active-low `drdy_n` pulses at configurable sampling rates (250 SPS, 500 SPS, 1000 SPS).
  - Generates synthetic cardiac waveforms (normal sinus rhythm, tachycardia, bradycardia, lead-off impedance).
  - Shifts 72-bit output frames on SCLK falling edges per SPI Mode 1 specification.
  - Implements internal command decoder for register read/write (`SDATAC`, `RDATAC`, `WREG`, `RREG`).

---

## 3. Automated Execution Commands

Each runner script compiles the testbench via Icarus Verilog (`iverilog`), executes the simulation binary (`vvp`), checks for `$fatal` assertions, parses test verdict lines, and generates a signed evidence directory under `reports/simulation/`:

```powershell
# Run TCM verification
powershell -File Simulation/run_tcm.ps1

# Run OBI-to-APB3 Bridge verification
powershell -File Simulation/run_bridge.ps1

# Run ADS1292R SPI Master verification
powershell -File Simulation/run_spi.ps1

# Run ECG DMA verification
powershell -File Simulation/run_dma.ps1
```

Each run outputs:
- `<run_dir>/compile.log`: Icarus Verilog compilation output and exit code.
- `<run_dir>/<module>_tb.log`: Raw stdout with individual `[PASS]` / `[FAIL]` tags.
- `<run_dir>/sim_results.json`: Machine-readable results manifest with SHA-256 hashes.
