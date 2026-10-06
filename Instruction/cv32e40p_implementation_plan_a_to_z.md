# CV32E40P Full Implementation Plan (Phase A to Z)
## Real-Time ECG SoC & CNN-MAMBA Coprocessor Platform

**Document Version:** 1.0  
**Target Architecture:** OpenHW Group CV32E40P (RV32IMC + `Xpulpv2` DSP Extensions)  
**Target Deployment:** Dual-Track (FPGA Prototyping on Artix-7/Gowin + Silicon ASIC on GF180MCU/Sky130)  
**Sensor Front-End:** Texas Instruments ADS1292R (2-Channel, 24-bit Biopotential AFE)  
**Neural Accelerator:** 16x8 Fold-SIMD PE Array + 4-lane Selective-SSM Sidecar (CNN-MAMBA)

---

## 1. Architectural Positioning & System Blueprint

The SoC architecture replaces the heavy CVA6 application core with the optimized **CV32E40P** microcontroller core. This achieves an optimal balance between low silicon area, deterministic sub-microsecond interrupt handling, and high DSP efficiency for biosignal conditioning.

```
+---------------------------------------------------------------------------------------------------+
|                                   CV32E40P ECG SoC Architecture                                   |
|                                                                                                   |
|  +---------------------------------------------------------------------------------------------+  |
|  |                                  CV32E40P Processor Core                                    |  |
|  |  - 4-Stage In-Order Pipeline (IF -> ID -> EX -> WB)                                         |  |
|  |  - RV32IMC + CORE-V PULP DSP Extensions (Hardware Loops, Post-Inc Load/Store, SIMD Dot-Prod)|  |
|  |  - Fast Interrupt Controller (irq_fast_i[14:0], 6-cycle deterministic vectoring)            |  |
|  +------------------------------+-------------------------------+------------------------------+  |
|                                 |                               |                                 |
|                       Instruction OBI Bus                  Data OBI Bus                           |
|                                 |                               |                                 |
|                                 v                               v                                 |
|                 +-------------------------------+   +---------------------------+                 |
|                 | Tightly Coupled I-SRAM (32KB) |   | Tightly Coupled D-SRAM    |                 |
|                 | (Zero-wait-state BRAM/Macro)  |   | (32KB BRAM/Macro)         |                 |
|                 +-------------------------------+   +-------------+-------------+                 |
|                                                                   |                               |
|                                                                   v                               |
|                                                     +---------------------------+                 |
|                                                     |   OBI-to-APB3 Bridge      |                 |
|                                                     +-------------+-------------+                 |
|                                                                   |                               |
|            +------------------+-------------------+---------------+-------------------+           |
|            |                  |                   |               |                   |           |
|            v                  v                   v               v                   v           |
|     +--------------+   +--------------+    +--------------+ +--------------+   +--------------+   |
|     |  UART (8N1)  |   |  SPI Master  |    |  Timer (32b) | |  GPIO (8b)   |   |  Ping-Pong   |   |
|     |  115k-921k   |   |  ADS1292R AFE|    |  Watchdog/Sys| |  AFE Reset/  |   |  BRAM DMA    |   |
|     |  0x1000_0000 |   |  0x1000_1000 |    |  0x1000_2000 | |  0x1000_3000 |   |  0x1000_4000 |   |
|     +-------+------+   +-------+------+    +-------+------+ +-------+------+   +-------+------+   |
|             |                  |                   |                |                  |          |
|             |                  | DRDY# (IRQ 3)     | (IRQ 5)        | (IRQ 6)          | (IRQ 4)  |
|             |                  +-------------------+----------------+------------------+          |
|             |                                      |                                              |
|             |                                      v                                              |
|             |                        CV32E40P irq_fast_i Bundle                                   |
|             |                                                                                     |
|             |        +--------------------------------------------------------------------+       |
|             |        |                 CNN-MAMBA Coprocessor Accelerator                  |       |
|             +------->| - Control Plane: AXI4-Lite Slave mapped at 0x2000_0000             |       |
|                      | - Data Plane: Direct AXI4-Stream from Ping-Pong Buffer             |       |
|                      | - Compute: 16x8 Fold-SIMD PE Array (128 MACs) + 4-lane SSM Sidecar |       |
|                      | - Event Output: Arrhythmia / QRS event interrupt to Core (IRQ 7)   |       |
|                      +--------------------------------------------------------------------+       |
+---------------------------------------------------------------------------------------------------+
```

---

## 2. Phase-by-Phase Implementation Blueprint (A to Z)

### Phase A: Core RTL Packaging & Parameter Configuration
- **Objective:** Integrate the upstream OpenHW Group CV32E40P SystemVerilog core with target parameters.
- **Top Module:** `cv32e40p_core.sv` / `cv32e40p_top.sv`
- **Parameter Matrix:**
  ```verilog
  cv32e40p_top #(
    .COREV_PULP       ( 1'b1 ), // Enable CORE-V / PULP DSP extensions
    .COREV_CLUSTER    ( 1'b0 ), // Standalone microcontroller mode
    .FPU              ( 1'b0 ), // No FPU (saves ~15k gates / 2,000 LUTs)
    .ZFINX            ( 1'b0 ),
    .NUM_MHPMCOUNTERS ( 1    )  // Minimal performance counters
  ) u_core ( ... );
  ```
- **Register File Selection:**
  - *FPGA Target:* Use `cv32e40p_register_file_fpga.sv` (maps cleanly to dual-port Distributed RAM or BRAM slices).
  - *ASIC Target:* Use standard D-flip-flop register file `cv32e40p_register_file.sv` or foundry-compiled multi-port register file macro.

---

### Phase B: Bus Protocol Bridges (OBI to APB3 & AXI4-Lite)
- **Objective:** Translate the high-throughput, low-latency Open Bus Interface (OBI) to standard peripheral buses.
- **Protocol Handshake Translation:**
  - `data_req_o` asserts with address and write enable.
  - Slave returns `data_gnt_i` immediately (1 cycle).
  - In the subsequent cycle, `data_rvalid_i` returns data or acknowledges write.
- **OBI-to-APB3 Bridge RTL (`obi_to_apb.sv`):**
  ```verilog
  // FSM translating OBI pipeline to 2-cycle APB3 Setup/Access phases
  typedef enum logic [1:0] { OBI_IDLE, APB_SETUP, APB_ACCESS } obi_apb_state_e;
  ```
  - Eliminates wait states on peripheral registers while providing bus error trapping (`PSLVERR -> data_err_i`).

---

### Phase C: Dual-Target Memory Subsystem Architecture
- **Objective:** Provide zero-wait-state Harvard memory access for instruction fetch and data read/write.
- **1. Instruction Tightly Coupled Memory (I-TCM) (32 KB):**
  - Mapped at `0x0000_0000` – `0x0000_7FFF`.
  - Single-cycle read latency. Dedicated instruction OBI port.
  - Supports pre-loading boot firmware via `.hex` file.
- **2. Data Tightly Coupled Memory (D-TCM) (32 KB):**
  - Mapped at `0x0001_0000` – `0x0001_7FFF`.
  - Byte-enable support (`data_be_o[3:0]`). Dedicated data OBI port.
- **Target Abstraction Layer:**
  - **FPGA:** Pure synthesizable SystemVerilog array inferring Xilinx `RAMB36E1` / Gowin `BSRAM` blocks.
  - **ASIC:** SRAM wrapper selecting OpenRAM or Foundry memory compiler macros (`GF180MCU_SRAM_512x32` / `Sky130_SRAM_1024x32`).

---

### Phase D: ECG Biosignal Ingress & Peripheral Subsystem
- **Objective:** Connect Texas Instruments ADS1292R AFE and host telemetry peripherals.
- **Peripheral Suite (already verified in `RTL/ecg_soc/`):**
  1. `spi_master_apb.sv`: ADS1292R SPI Mode 1 controller with 24-bit word sizing.
  2. `ecg_dma.sv`: Autonomous Ping-Pong buffer (Bank A / Bank B, 32 samples per bank).
  3. `uart_apb.sv`: 8N1 serial telemetry (115,200 baud for continuous monitoring; 921,600 baud for burst raw EEG/ECG traces).
  4. `timer_apb.sv`: 32-bit periodic tick & watchdog supervisor.
  5. `gpio_apb.sv`: AFE reset, start, and status LEDs.
- **Interrupt Routing Table (CV32E40P `irq_fast_i`):**
  - `irq_fast_i[0]` : UART RX character available
  - `irq_fast_i[1]` : UART TX FIFO empty
  - `irq_fast_i[2]` : **ADS1292R `DRDY#` Data Ready (Highest Priority)**
  - `irq_fast_i[3]` : **Ping-Pong Buffer Block Ready (32 samples ready)**
  - `irq_fast_i[4]` : System Timer Tick / Watchdog
  - `irq_fast_i[5]` : GPIO Button / Lead-Off Alert
  - `irq_fast_i[6]` : **CNN-MAMBA Arrhythmia Classification Event**

---

### Phase E: CNN-MAMBA Neural Accelerator Coupling
- **Objective:** High-bandwidth, low-overhead co-processor integration with the sister accelerator.
- **Coupling Mechanism:**
  1. **Control / Register Plane (APB3 / AXI4-Lite @ `0x2000_0000`):**
     - CV32E40P writes network layer dimensions, quantization scale factors, and detection thresholds.
     - Controls inference start, resets internal state registers of the selective-SSM sidecar.
  2. **Data Streaming Channel (AXI4-Stream):**
     - Directly streams conditioned 32-sample blocks from the Ping-Pong BRAM buffer into the 16x8 Fold-SIMD PE Array.
     - Bypasses core registers entirely, preserving 100% of CPU cycles during matrix operations.
  3. **Event Notification:**
     - Accelerator asserts `irq_fast_i[6]` on detecting ventricular ectopic beats or anomalous QRS morphologies.
     - CPU wakes from low-power wait-for-interrupt (`wfi`) and immediately frames the alert telemetry packet.

---

### Phase F: Firmware & DSP Kernels with `Xpulp` Acceleration
- **Objective:** Implement high-precision clinical ECG signal processing in bare-metal C using CV32E40P assembly intrinsics.
- **Firmware Directory Structure:**
  ```
  Firmware/
  ├── boot/
  │   ├── crt0.S            # Vector table, stack initialization, fast-irq handlers
  │   └── link.ld           # Memory map linker script (32KB I-TCM, 32KB D-TCM)
  ├── drivers/
  │   ├── ads1292r.c        # AFE initialization, gain, and mode configuration
  │   ├── uart.c            # Telemetry packetizer with hardware CRC-8
  │   └── dma.c             # Ping-pong bank buffer manager
  ├── dsp/
  │   ├── ecg_fir_pulp.S    # 45-tap FIR lowpass using Hardware Loops & SIMD
  │   ├── ecg_iir_pulp.S    # 2nd-order Biquad notch & baseline filter
  │   └── pan_tompkins.c    # Real-time QRS detector & RR-interval estimator
  └── main.c                # Event loop & telemetry dispatcher
  ```
- **Key Kernel 1: 45-Tap FIR with Hardware Loops (`ecg_fir_pulp.S`):**
  ```assembly
  // CV32E40P Zero-Overhead Hardware Loop FIR Kernel
  // a0 = input buffer ptr (post-increment), a1 = coeff ptr, a2 = num_taps/2, a3 = accumulator
  lp.setup   0, a2, fir_loop_end
    p.lw     t0, 4(a0!)          // Load 2 packed 16-bit samples, post-increment pointer
    p.lw     t1, 4(a1!)          // Load 2 packed 16-bit coefficients
    pv.dotsp.h a3, t0, t1        // Dual 16-bit multiply and 32-bit accumulate in 1 cycle
  fir_loop_end:
  ```
- **Execution Cost:** 23 loop iterations + 2 setup cycles = **25 clock cycles** (0.50 µs @ 50 MHz).

---

### Phase G: Verification, Co-Simulation & SVA Sign-Off
- **Tooling:** Icarus Verilog (`iverilog`), Verilator 5.x, Questa / ModelSim.
- **Verification Gates:**
  - `Gate 1 (Spec Approval)`: Formal sign-off on memory map and pinout.
  - `Gate 2 (Lint & Static Analysis)`: Verilator `--lint-only -Wall` with zero warnings.
  - `Gate 3 (SVA Assertions)`: SVA formal checks for OBI handshaking and ADS1292R SPI timing.
  - `Gate 4 (Behavioral Co-Simulation)`: Full SoC simulation reading simulated MIT-BIH Arrhythmia database waveforms through `ads1292r_model.sv`.
  - `Gate 5 (RTM Coverage)`: 100% trace of requirements in `reports/verification/rtm_dashboard.md`.

---

### Phase H: Physical Implementation: Dual FPGA & ASIC Tapeout

#### Flow 1: FPGA Implementation (Portable Across Vendors)
- **Primary Board:** Digilent Arty A7-100T (Xilinx Artix-7 `xc7a100tcsg324-1`).
- **Secondary Targets:** Gowin GW2A-55 (Tang Primer), Intel Cyclone V, Lattice ECP5.
- **FPGA Steps:**
  1. Run automated Vivado synthesis and implementation scripts (`Synthesis/fpga/run_synth.tcl`).
  2. Verify timing closure at **50 MHz (target) to 100 MHz (maximum)**.
  3. Generate `.bit` file and verify on-board with Digilent PMOD ADS1292R daughterboard.

#### Flow 2: Silicon ASIC Tapeout (GF180MCU / Sky130)
- **EDA Flow:** OpenLane / OpenROAD or Commercial Synopsys/Cadence toolchain.
- **ASIC Implementation Steps:**
  1. **Synthesis (Yosys):** Map RTL to standard cell library (e.g. `gf180mcu_fd_sc_mcu7t5v0`).
  2. **Floorplanning:** Core area ~1.2 mm x 1.2 mm (including SRAM macros and pad ring).
  3. **Power Distribution Network (PDN):** Robust dual VDD/VSS mesh to prevent IR drop during SIMD peak switching.
  4. **Placement & Clock Tree Synthesis (TritonCTS):** Target clock skew < 150 ps across all core registers.
  5. **Routing & Parasitic Extraction (SPEF):** Detailed routing via FastRoute/TritonRoute.
  6. **DRC / LVS & Sign-Off:** Magic / KLayout DRC and Netgen LVS check clean. Generate GDSII.

---

## 3. Implementation Checklist & Gate Tracking Matrix

| Phase | Milestone Task | Deliverable Artifact | Status |
| :---: | :--- | :--- | :---: |
| **A** | Package CV32E40P RTL & Core Configuration | `RTL/cv32e40p/` | PENDING |
| **B** | Implement OBI-to-APB3 Bridge | `RTL/ecg_soc/obi_to_apb.sv` | PENDING |
| **C** | Dual-Target Harvard SRAM Wrappers (32KB+32KB)| `RTL/ecg_soc/tcm_sram.sv` | PENDING |
| **D** | Integrate ECG Peripherals & Interrupt Table | `RTL/ecg_soc/ecg_soc_top.sv` | COMPLETE |
| **E** | Connect CNN-MAMBA Coprocessor Interfaces | `RTL/ecg_soc/mamba_bridge.sv` | PENDING |
| **F** | Compile Bare-Metal Firmware with Xpulp DSP | `Firmware/dsp/ecg_fir_pulp.S`| PENDING |
| **G** | Run Full-System Simulation with AFE Model | `Simulation/soc_tb.sv` | PENDING |
| **H1**| FPGA Bitstream Generation & Hardware Validation| `Synthesis/fpga/bitstream.bit`| PENDING |
| **H2**| ASIC OpenLane Flow Run & GDSII Sign-Off | `Synthesis/asic/runs/top.gds` | PENDING |
