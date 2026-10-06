# Synthesis Directory: FPGA & ASIC Physical Implementation Flows

This directory contains the physical implementation scripts, board constraints, tool configurations, and Verilog synthesis filelists for targeting both FPGA and ASIC silicon.

---

## Directory Hierarchy

```
Synthesis/
├── fpga/
│   └── ecg_artix7/              # Xilinx Artix-7 FPGA Implementation Flow
│       ├── arty_a7_100t.xdc     # Board physical pin mapping & timing constraints
│       ├── run_synth.tcl        # Non-project batch mode Vivado synthesis script
│       ├── run_fpga.ps1         # PowerShell wrapper for automated Vivado runs
│       └── run_fpga.sh          # Bash wrapper for automated Vivado runs
├── asic/
│   └── openlane/                # SkyWater 130nm ASIC Flow via OpenLane
│       ├── config.json          # OpenLane flow configuration
│       ├── config_sky130.json   # Sky130 PDK technology parameters & clock targets
│       ├── run_openlane.ps1     # PowerShell wrapper for Docker-based OpenLane runs
│       └── run_openlane.sh      # Bash wrapper for Docker-based OpenLane runs
├── flist_cv32e40p_soc.f         # Complete SoC filelist for synthesis & simulation
├── flist_tcm_router_tb.f        # Filelist for TCM subsystem testbench
├── flist_obi_apb_bridge_tb.f    # Filelist for OBI-APB bridge testbench
├── flist_spi_master_tb.f        # Filelist for ADS1292R SPI master testbench
└── flist_ecg_dma_tb.f           # Filelist for ECG DMA testbench
```

---

## 1. Xilinx Artix-7 FPGA Implementation Flow

### Target Hardware Specifications:
- **Device Family**: Xilinx Artix-7
- **Part Number**: `xc7a100tcsg324-1` (or `xc7a35tcpg236-1` for constrained footprints)
- **Target Evaluation Board**: Digilent Arty A7-100T (rev D/E)
- **Oscillator**: 100.000 MHz board oscillator connected to pin `E3`
- **SoC Core Frequency**: 50.000 MHz (generated via on-chip MMCM)

### Constraints Architecture (`arty_a7_100t.xdc`):
- **Clock Definition**:
  ```tcl
  create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} [get_ports clk_i]
  ```
- **Pin Assignments**:
  - `clk_i` -> Pin `E3` (3.3V LVCMOS)
  - `rst_n_i` -> Pin `C2` (Active-low pushbutton)
  - `uart_tx_o` -> Pin `D10` (USB-UART bridge TX)
  - `uart_rx_i` -> Pin `A9` (USB-UART bridge RX)
  - `spi_sclk_o` -> Pin `G13` (Pmod Header JA pin 1)
  - `spi_cs_n_o` -> Pin `B11` (Pmod Header JA pin 2)
  - `spi_mosi_o` -> Pin `A11` (Pmod Header JA pin 3)
  - `spi_miso_i` -> Pin `D12` (Pmod Header JA pin 4)
  - `drdy_n_i` -> Pin `D13` (Pmod Header JA pin 7)

### Non-Project Batch Flow (`run_synth.tcl`):
The synthesis script runs headlessly in Vivado batch mode to produce reproducible gate-level reports:
```powershell
E:\Vivado\2023.2\bin\vivado.bat -mode batch -source Synthesis/fpga/ecg_artix7/run_synth.tcl
```
Optimizations applied:
- `synth_design -flatten_hierarchy rebuilt -retiming`: Rebalances combinational logic paths across the CV32E40P multiplier/ALU pipelines and DiagSSM1D 4-lane sidecar.
- `opt_design -directive Explore`: Performs deep constant folding, DSP absorption, and logic restructuring.
- `place_design -directive Explore`: Maximizes placement efficiency for dense BRAM and DSP clusters.
- `phys_opt_design -directive AggressiveExplore`: Executes pre-routing register replication, critical cell fanout splitting, and DSP pipeline retiming.
- `route_design -directive Explore` with automatic fallback to `route_design -directive MoreGlobalIterations -tns_cleanup` to guarantee timing closure without triggering Vivado segfaults.

Outputs produced under `Synthesis/fpga/ecg_artix7/reports/run_<timestamp>/`:
- `utilization_synth.rpt`, `utilization_placed.rpt`: LUT, FF, BRAM, and DSP utilization breakdown.
- `timing_routed.rpt`, `timing_min_max.rpt`: Post-route static timing closure (WNS / WHS / TNS / THS).
- `drc_routed.rpt`: Post-route Design Rule Checks (DRC) report.
- `cv32e40p_ecg_soc.bit`: Physical FPGA bitstream ready for hardware programming.

### Verified Architecture Resource Allocation:
- **Target Part**: `xc7a100tcsg324-1` (Digilent Arty A7-100T)
- **Clock Synthesis**: 50.000 MHz compute clock from 100.000 MHz oscillator via MMCM
- **Memory Architecture**:
  - Instruction TCM: 32 KB (8 RAMB36E1 Block RAMs)
  - Data TCM: Expanded 128 KB (32 RAMB36E1 Block RAMs) for ResUMamba-30K weights and ping-pong activations
- **Coprocessor Acceleration**:
  - DiagSSM1D 128-tap 4-lane FIR sidecar (`mamba_fir_sidecar.sv`)
  - Memory-mapped APB3 control bridge (`mamba_bridge.sv`)
  - Direct DSP48E1 MAC absorption (8 to 16 DSP slices)

---

## 2. SkyWater 130nm ASIC Implementation Flow

### Flow Specifications:
- **PDK**: SkyWater 130nm (`sky130_fd_sc_hd`)
- **EDA Framework**: OpenLane / OpenROAD toolchain
- **Target Frequency**: 50 MHz ($T_{clk} = 20\text{ ns}$)
- **Die Area Target**: $1.8\text{ mm} \times 1.8\text{ mm}$
- **Core Utilization Target**: 45% - 55%

### Configuration Parameters (`config_sky130.json`):
- `DESIGN_NAME`: `cv32e40p_ecg_soc_top`
- `VERILOG_FILES`: Includes full SoC synthesizable filelist
- `CLOCK_PERIOD`: 20.0
- `CLOCK_PORT`: `clk_i`
- `FP_CORE_UTIL`: 50
- `PL_TARGET_DENSITY`: 0.55
- `SYNTH_STRATEGY`: "AREA 0"

---

## 3. Verilog Filelists (`.f`)

The `.f` filelists provide ordered compilation manifests used by both Icarus Verilog (`iverilog -f ...`) and Vivado Tcl scripts (`read_verilog ...`):
- `flist_cv32e40p_soc.f`: Lists package definitions, core wrapper, interconnect, memory, peripherals, and board top.
- `flist_spi_master_tb.f`: Compiles SPI master, APB wrapper, ADS1292R model, and testbench.
- `flist_ecg_dma_tb.f`: Compiles DMA controller, memory buffers, and DMA testbench.
- `flist_obi_apb_bridge_tb.f`: Compiles OBI-to-APB bridge and bridge testbench.
- `flist_tcm_router_tb.f`: Compiles TCM SRAM array and TCM router testbench.
