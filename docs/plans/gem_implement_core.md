# CV32E40P Core Implementation Plan (V4 Audit-Gated Decision)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Establish truthful evidence and routed acceptance for the existing CV32E40P at 50 MHz before advancing DSP inference or hardware offload claims.

**Architecture:** Reuse immutable CV32E40P HEAD `97086e9565f8145522ad6d62852123c0e5537529`, the current local OBI/APB/peripherals and explicit 128 KiB D-TCM control. Separate diagnostic MAMBA behavior from the core baseline. Trained-model and offload work require independent numerical, memory and measured-workload gates.

**Tech Stack:** Existing RISC-V GCC/binutils, compatible CORE-V compiler, SystemVerilog/XSIM and Vivado 2023.2 on Artix-7 100T.

---

## Current decision — 2026-10-06

Use [Core Next Decision Audit Implementation Plan](2026-10-06-core-next-decision-audit.md) as the active execution sequence. Its **Tasks 1–3** are the recommended next scope for `gem_implement_core`; return actual evidence and a new decision before model/offload work. This audit turn did not execute those tasks.

Evidence: [updated source/artifact audit](../../reports/review/2026-10-06-core-next-decision-audit/audit.md), `audit_manifest.json` and `inspection_results.json` beside it.

- **Core choice: KEEP CV32E40P.** Actual clean HEAD is six commits beyond `cv32e40p_v1.8.3`, not the exact release tag. No full core/SoC rewrite is required.
- **Latest 50 MHz routed timing: NO_GO / FAIL.** Run `20261006_093347`: WNS −0.815 ns, TNS −63.389 ns, 215 failing setup endpoints; positive WHS +0.044 ns does not establish closure. Preserve bitstream/DCP as routed artifacts with failed setup acceptance.
- **Boot firmware/artifacts: useful retained evidence.** Seven firmware hashes and ELF→bin→hex bytes match. Existing XSIM boot/IRQ smoke supports that boundary; source/run binding and negative-proof gaps remain.
- **Cascade/model/offload: NOT_VERIFIED.** The current bridge returns fixed class/confidence; the sidecar is not instantiated in the routed SoC. Partial floating-point sensitivity and host-reference tests do not establish integer C or in-core SIMD inference.
- **Next action:** correct claims and fail-closed gates → isolate source-bound real-core baseline → close matched routed timing at 20.000 ns. Then actual target kernel profiling determines the need for offload.

The previous V3 “FULL GO / frozen & verified” decision is superseded. The original document is preserved in `reports/review/2026-10-06-core-next-decision-audit/snapshot/docs/plans/gem_implement_core.md`. Historical task commands below are not current instructions and must not substitute for the active plan or its evidence gates.

<details>
<summary>Historical V3 body — retained for traceability, superseded</summary>

## Contradiction Table: Evolution Across Plan Revisions

| Architectural Dimension | Initial Flaw (V1) | Revision V2 | Frozen V3 Architecture (Final) |
| :--- | :--- | :--- | :--- |
| **CV32E40P Source Pin** | Hardcoded arbitrary commit `97086e95` | Re-used `97086e95` | **Pinned to official release tag `cv32e40p_v1.8.3`. Manifest captures dynamic git rev-parse or source SHA256.** |
| **Trap Vector Base & Timer** | Vector table at `0x0004` | `mtvec = 0x0100`, IRQ 7 at `0x011C` | **`boot_addr = 0x0000_0000`, `mtvec = 0x0000_0100`, Timer IRQ 7 at `0x0000_011C`.** |
| **Interrupt Lines** | Generic IRQ 0..6 bundle | CV32E40P mapped lines | **Strict OpenHW map: Timer on 7, peripherals on 16–20; reserved lines tied low.** |
| **ADS1292R SPI Clock** | Vague $\le 4\,\text{MHz}$ | Retained 4 MHz | **Frozen at 1.0 MHz across all phases (satisfies TI $f_{\text{SCLK}} \le 2 \times f_{\text{CLK}} = 1.024\,\text{MHz}$).** |
| **DRDY Acquisition Load** | CPU IRQ on every sample | CPU IRQ on DRDY | **Hardware FSM captures 72 SCLKs autonomously; CPU interrupted only every 256 frames on DMA `irq_i[19]`.** |
| **DMA Data Interface** | Ambiguous "APB / TCM" | Mixed mention | **Strict Separation: APB control plane (`0x1A10_4000`) + D-OBI memory window (`0x2000_0000/1000`).** |
| **ECG Frame Format** | Undefined bit width | 3 words mentioned | **Standardized 12-byte packed frame: `uint32_t status`, `int32_t ch1`, `int32_t ch2` (3 KB per buffer).** |
| **Bus Bridge Contention** | Global zero-wait assumption | 2-outstanding queue | **TCM has zero-wait grant; APB bridge backpressures 2nd OBI request while APB busy.** |
| **DSP Mnemonic & Fallback** | `pv.sdotsp.h` via generic GCC | Probed `cv.sdotsp.h` | **Probes toolchain for `cv.sdotsp.h`; explicit `CONFIG_COREV_PULP` vs `CONFIG_BASELINE_RV32IMC`.** |
| **Manifest Hashing** | Glob `hello.*` hashed self | Excluded self | **Payload list (`.elf`, `.hex`, `.dump`, `.map`, `.bin`) explicitly hashed into `hello.sha256`.** |
| **Simulation Duration** | `< 100 us wall-clock` | Simulated time | **`< 100 us of simulated target time`.** |
| **FPGA BRAM Metric** | `BRAM < 135` | Ambiguous tile count | **`BRAM36-equivalent < 135` (`RAMB36E1` + `RAMB18E1/2`).** |

---

## Detailed Task Breakdown

### Task 1: Gate Infrastructure & Runner Contract Verification

**Files:**
- Test: `scripts/test_evidence_gate.py`
- Test: `scripts/test_runner_contract.py`
- Test: `scripts/test_firmware_build_contract.py`
- Target: `scripts/check_evidence.py`

**Step 1: Execute Runner Contract Rejection Suite**
Run unit test suite enforcing the 10 failure rejection gates (missing IRQ, COMPLETE-only, fatal outside testcase, corrupted hash, stale run-id, empty log, duplicate testcase, child compile failure, child sim failure, missing/empty artifact):
```bash
python -m unittest discover -s scripts -p "test_*.py" -v
```
Expected output: All unit tests PASS with exit code `0`.

**Step 2: Verify Artifact Manifest Integrity Logic**
Verify that `check_evidence.py` resolves relative paths from workspace root and rejects self-hashing or corrupted manifests:
```bash
python -c "from scripts.check_evidence import calculate_sha256; import sys; print('[PASS] Manifest validator operational')"
```

---

### Task 2: Real Firmware Build with Correct `mtvec` & Vector Table

**Files:**
- Source: `Firmware/boot/crt0.S`
- Source: `Firmware/boot/hello.c`
- Source: `Firmware/boot/link.ld`
- Build System: `Firmware/Makefile`
- Builder: `Firmware/build_boot_image.py`
- Target Artifacts: `Firmware/build/hello.elf`, `hello.hex`, `hello.dump`, `hello.map`, `hello.bin`, `hello.sha256`

**Step 1: Implement Correct Vector Table in crt0.S**
Configure vector table layout:
- `0x0000_0000`: `_start` (sets `sp = 0x0001_7FF0`, copies `.data`, clears `.bss`, configures `mtvec`).
- Write `0x0000_0101` to `mtvec` (Base `0x0000_0100`, Mode `01` = Vectored).
- Interrupt vector table starting at `0x0000_0100`:
  - `0x0000_0100`: Exception / Synchronous trap handler
  - `0x0000_010C`: IRQ 3 (Software IRQ)
  - `0x0000_011C`: IRQ 7 (Machine Timer IRQ $\rightarrow$ jumps to `timer_isr`)
  - `0x0000_012C`: IRQ 11 (External IRQ)
  - `0x0000_0140`: IRQ 16 (Fast UART RX)
  - `0x0000_0144`: IRQ 17 (Fast UART TX)
  - `0x0000_0148`: IRQ 18 (Fast SPI / AFE Error)
  - `0x0000_014C`: IRQ 19 (Fast Ping-Pong DMA Buffer Complete $\rightarrow$ jumps to `dma_isr`)
  - `0x0000_0150`: IRQ 20 (Fast GPIO)

**Step 2: Build Firmware Image**
```bash
make -C Firmware hello CC=riscv32-unknown-elf-gcc OBJCOPY=riscv32-unknown-elf-objcopy OBJDUMP=riscv32-unknown-elf-objdump NM=riscv32-unknown-elf-nm READELF=riscv32-unknown-elf-readelf
```
Expected output:
- Native compiler exit code `0`.
- All artifacts generated in `Firmware/build/`.
- `hello.sha256` explicitly hashes only `hello.elf`, `hello.hex`, `hello.dump`, `hello.map`, `hello.bin`.

**Step 3: Disassembly & Vector Verification**
Verify that Timer IRQ vector at `0x0000_011C` jumps to `timer_isr` and `_start` is at `0x0000_0000`:
```bash
python -c "dump = open('Firmware/build/hello.dump').read(); assert '11c:' in dump or '0000011c' in dump; print('[PASS] Timer vector confirmed at 0x0000_011C')"
```

---

### Task 3: Dual-Port TCM Unit Verification (Strict Zero-Wait-State)

**Files:**
- DUT: `RTL/ecg_soc/tcm_sram.sv`
- Testbench: `Simulation/tcm_router_tb.sv`
- Runner: `Simulation/run_tcm.ps1`
- Filelist: `Synthesis/flist_tcm_router_tb.f`

**Step 1: Execute TCM Unit Testbench**
```powershell
powershell -File Simulation/run_tcm.ps1
```
Expected output:
- `TC-TCM-001`: Concurrent Port A instruction fetch and Port B data read (zero stall).
- `TC-TCM-002`: Port B read from I-TCM address space (`0x0000_0000 - 0x0000_7FFF`) for `.rodata` and `.data` copy.
- `TC-TCM-003`: Port B byte-enable masked write/read in D-TCM (`0x0001_0000 - 0x0001_7FFF`).
- `TC-TCM-004`: Memory boundary edge words (`0x0000_7FFC`, `0x0001_7FFC`).
- `TC-TCM-005`: Zero-wait-state combinational grant and single-cycle `rvalid` latency.
- Evidence manifest saved and validated by `check_evidence.py`.

---

### Task 4: OBI-to-APB3 Bridge & Peripheral Subsystem Verification

**Files:**
- Bridge DUT: `RTL/ecg_soc/obi_to_apb.sv`
- Interconnect: `RTL/ecg_soc/apb_interconnect.sv`
- SVA: `RTL/ecg_soc/sva/obi_to_apb_sva.sv`
- Peripherals: `uart_apb.sv`, `timer_apb.sv`, `gpio_apb.sv`, `spi_master_apb.sv`
- Testbench: `Simulation/obi_apb_bridge_tb.sv`

**Step 1: Verify APB Addressing & Backpressure Specifications**
- Decoded address ranges:
  - UART: `0x1A10_0000 - 0x1A10_0FFF`
  - SPI Control: `0x1A10_1000 - 0x1A10_1FFF`
  - Timer: `0x1A10_2000 - 0x1A10_2FFF`
  - GPIO: `0x1A10_3000 - 0x1A10_3FFF`
  - DMA Control: `0x1A10_4000 - 0x1A10_4FFF`
- Bridge FSM:
  - Request acceptance: Assert OBI `gnt` when APB bus is idle.
  - Variable wait-state: Wait for peripheral `PREADY` before asserting OBI `rvalid`.
  - Backpressure: If second OBI request arrives while APB transfer is active (`SETUP`/`ACCESS`), deassert `gnt` until prior transfer completes.

**Step 2: Run Directed Bridge Testbench**
Verify `TC-APB-001` (decode), `TC-APB-002` (wait-states), `TC-APB-003` (back-to-back requests), and `TC-APB-004` (unmapped error handling).

---

### Task 5: ADS1292R 1.0 MHz SPI Master Bring-Up & 72-Clock Acquisition

**Files:**
- SPI Master: `RTL/ecg_soc/spi_master.sv`
- APB Wrapper: `RTL/ecg_soc/spi_master_apb.sv`
- AFE Model: `Simulation/ads1292r_model.sv`
- Testbench: `Simulation/spi_master_tb.sv`
- Runner: `Simulation/run_spi.ps1`

**Step 1: 1.0 MHz Clock & Protocol Implementation**
- System clock: 50 MHz $\rightarrow$ Divider `div = 50` generates exact **1.0 MHz SCLK** ($t_{\text{SCLK}} = 1000\,\text{ns}$, $t_{\text{HIGH}} = 500\,\text{ns}$, $t_{\text{LOW}} = 500\,\text{ns}$).
- Mode 1 SPI: CPOL = 0, CPHA = 1 (data clocked on falling edge, latched on rising edge).
- Bring-up sequence verification:
  1. Power-up and PWDN/RESET pin release.
  2. Wait $t_{\text{RST}}$ ($18\,t_{\text{CLK}} \approx 36\,\mu\text{s}$).
  3. Send `SDATAC` command (`0x11`) to exit default continuous mode.
  4. Send `RREG ID` (`0x20, 0x00`) $\rightarrow$ verify response `0x73`.
  5. Send `WREG CONFIG1, CONFIG2, CH1SET, CH2SET`.
  6. Send `START` command (`0x08`) or assert START pin.
  7. Send `RDATAC` command (`0x10`) to enter data streaming.
  8. Wait for DRDY# falling edge.
  9. Frame capture:
     - SCLK runs for exactly 72 clock cycles.
     - CS# held continuously low for all 72 clocks, then returns high.
     - Capture 24-bit Status: `0xC00000`.
     - Capture 24-bit CH1: `0x123456` ($+1,193,046$).
     - Capture 24-bit CH2: `0xFEDCBA` ($-74,566$ sign-extended).
     - SCLK stops immediately after 72 clocks.

**Step 2: Run Gated SPI Testbench**
```powershell
powershell -File Simulation/run_spi.ps1
```
Expected: `TC-SPI-001` through `TC-SPI-008` PASS, evidence accepted by `check_evidence.py`.

---

### Task 6: Autonomous Ping-Pong DMA & 12-Byte Frame Buffer Verification

**Files:**
- DMA Controller: `RTL/ecg_soc/ecg_dma.sv`
- Ingress FIFO: `RTL/ecg_soc/sync_fifo.sv`
- Ping-Pong BRAM: `RTL/ecg_soc/dma_bram.sv`
- Testbench: `Simulation/ecg_dma_tb.sv`

**Step 1: DMA Architecture & Memory Mapping**
- Ingress Data Path:
  - SPI Master 72-bit output pushes 3 words to FIFO upon frame capture completion.
  - DMA unpacks words into standardized **12-byte ECG frame**:
    - `Word 0`: `status[31:0]` (bits `[31:24]` reserved $0$, bits `[23:0]` Status)
    - `Word 1`: `int32_t ch1` (sign-extended from 24 bits)
    - `Word 2`: `int32_t ch2` (sign-extended from 24 bits)
- Ping-Pong Buffer Memory Map (accessible via D-OBI):
  - Buffer A: `0x2000_0000 - 0x2000_0BFF` (256 frames $\times$ 12 bytes = 3,072 bytes)
  - Buffer B: `0x2000_1000 - 0x2000_1BFF` (256 frames $\times$ 12 bytes = 3,072 bytes)
- Control Plane (accessible via APB at `0x1A10_4000`):
  - `DMA_CTRL`, `DMA_STATUS`, `BUF_READY`, `BUF_RELEASE`, `SAMPLE_COUNT`.
- Interrupt Operation:
  - When active buffer reaches 256 frames, DMA toggles active buffer, sets `BUF_READY`, and triggers `irq_i[19]` (`BUFFER_DONE`).
  - CPU reads completed buffer via D-OBI and writes `BUF_RELEASE` when finished.
  - If next buffer fills before CPU releases current buffer, assert `OVERFLOW` flag.

**Step 2: Execute DMA Testbench**
Verify:
- `TC-DMA-001`: Ingress FIFO unpacking into 12-byte frame format.
- `TC-DMA-002`: Buffer A automatic fill and swap to Buffer B at 256 frames.
- `TC-DMA-003`: Assertion of `irq_i[19]` on buffer boundary.
- `TC-DMA-004`: Concurrent CPU read of Buffer A over D-OBI while Buffer B fills.
- `TC-DMA-005`: Overflow flag assertion on unreleased buffer swap.
- `TC-DMA-006`: 10,000-frame continuous stress test with zero sample loss.

---

### Task 7: Full CV32E40P SoC Co-Simulation (Boot, .data, Timer & DMA IRQ)

**Files:**
- Top SoC: `RTL/ecg_soc/cv32e40p_ecg_soc_top.sv`
- Core: `cv32e40p/rtl/cv32e40p_top.sv` (Release `cv32e40p_v1.8.3`)
- Testbench: `Simulation/soc_tb.sv`
- Filelist: `Synthesis/flist_cv32e40p_soc.f`
- Runner: `scripts/run_sim.ps1`
- Engine: Verilator (primary full-core engine) / Icarus Verilog

**Step 1: Execute Full SoC Co-Simulation**
```powershell
powershell -File scripts/run_sim.ps1
```
Verify:
- `TC-BOOT-001`: Core resets with `boot_addr_i = 0x0000_0000`, `mtvec_addr_i = 0x0000_0100`. Cr0 sets SP, outputs `"ECG BOOT: ALIVE"`.
- `TC-DATA-002`: Startup loop copies `.data` segment from I-TCM load address to D-TCM. Testbench verifies `g_data_array[4]` contains golden values, and `g_bss_zero_check == 0`.
- `TC-TIMER-003`: Timer peripheral programmed for periodic tick. Timer asserts `irq_i[7]`. Core vectors to `0x0000_011C`.
- `TC-MRET-004`: Callee-saved register canaries (`s2..s5`) verified across ISR. `mret` restores `mstatus.MIE` and resumes execution.
- `TC-DONE-005`: Main loop outputs `"ECG BOOT: COMPLETE"`.
- **Target Simulated Duration:** Completes within $< 100\,\mu\text{s}$ of simulated target time.
- Evidence manifest validated by `check_evidence.py`.

---

### Task 8: DSP Filtering & Fixed-Point Pan-Tompkins Validation

**Files:**
- Reference: `Firmware/dsp/fir_reference.c`
- Assembly: `Firmware/dsp/ecg_fir_pulp.S`
- QRS Detector: `Firmware/dsp/pan_tompkins.c`, `pan_tompkins.h`
- Testbench: `Firmware/dsp/dsp_test.c`
- Build System: `Firmware/Makefile`

**Step 1: Toolchain Probe & Kernel Configuration**
- Test toolchain for CORE-V mnemonic:
  - If compiler accepts `cv.sdotsp.h`, build with `CONFIG_COREV_PULP`.
  - If baseline compiler, build with `CONFIG_BASELINE_RV32IMC` (`mul`/`add` with `li t5, 16384; add a3, a3, t5`).
  - No silent fallbacks: Configuration recorded explicitly in manifest.

**Step 2: Arithmetic & Detection Tests**
```bash
make -C Firmware dsp-test-host
```
Verify:
- `TC-DSP-001`: Zero input produces exact 0.
- `TC-DSP-002`: Unit impulse matches tap 0 coefficient.
- `TC-DSP-003`: Multi-sample cardiac vectors yield bit-exact results between kernel and scalar reference.
- `TC-DSP-004`: Execution cycle counts measured via `mcycle` CSR (honest reporting, no mock counters).
- `TC-DSP-005`: 64-bit widening prevents squaring overflow for $|deriv| > 46340$.
- `TC-DSP-006`: Pan-Tompkins QRS peak detection correctly identifies synthetic QRS complex.

---

### Task 9: Physical FPGA Implementation on Artix-7 (Digilent Arty A7-100T)

**Files:**
- Top Module: `RTL/ecg_soc/fpga/ecg_arty_top.sv`
- Constraints: `Synthesis/fpga/ecg_artix7/arty_a7_100t.xdc`
- Tcl Script: `Synthesis/fpga/ecg_artix7/run_synth.tcl`
- Runner: `Synthesis/fpga/ecg_artix7/run_fpga.ps1`, `run_fpga.sh`

**Step 1: Physical Clocking & Constraints Verification**
- `MMCME2_BASE`: 100 MHz (Pin E3) $\rightarrow$ 50.0 MHz compute clock (20.00 ns period).
- Two-stage synchronizer on reset release conditioned on MMCM lock.
- Two-stage synchronizer on asynchronous AFE DRDY# input (`afe_drdy_ni`).
- False-path constraints on pushbuttons, reset, LEDs, and static AFE control lines.
- Generated SPI clock constraints verified against ADS1292R datasheet ($f_{\text{SCLK}} = 1.0\,\text{MHz}$, $t_{\text{HIGH}} \ge 400\,\text{ns}$, $t_{\text{LOW}} \ge 400\,\text{ns}$).

**Step 2: Vivado Implementation Execution**
```powershell
powershell -File Synthesis/fpga/ecg_artix7/run_fpga.ps1
```
Expected Reports:
- `timing_routed.rpt`: Setup WNS $\ge 0.000\,\text{ns}$, Hold WHS $\ge 0.000\,\text{ns}$.
- `check_timing.rpt`: Unconstrained endpoints $= 0$.
- `utilization_hierarchical.rpt`:
  - LUTs $< 63,400$
  - FFs $< 126,800$
  - BRAM36-equivalent $< 135$ (`RAMB36E1` + `RAMB18E1/2`)
  - DSP48E1 $< 240$
- `drc_routed.rpt`: 0 Errors.
- `routed.dcp`: Routed design checkpoint.
- `cv32e40p_ecg_soc.bit`: Programming bitstream.
- `fpga_manifest.json`: Full cryptographic manifest.

---

### Task 10: Benchmark, RTM & Master Evidence Sign-Off

**Files:**
- Dashboard: `reports/verification/rtm_dashboard.md`
- Benchmark: `reports/benchmark_report.md`
- Master Manifest: `reports/manifest.json`
- Checklist: `Instruction/session_checklist.md`

**Step 1: Synchronize Requirements Traceability Matrix**
- Promote verified simulation gates to `PASS (Sim)` with exact run IDs.
- Promote FPGA timing/utilization to `PASS (Routed)`.
- Mark any unmeasured physical board metrics strictly as `NOT_VERIFIED (Board Deferred)`.

**Step 2: Update Cryptographic Master Manifest**
Update `reports/manifest.json` with SHA-256 digests of all generated logs, bitstreams, and test outputs.

---

## Final GO / NO-GO Gate

Before advancing from planning to automated execution, all criteria in this gate must be strictly satisfied:

| Checkpoint | Requirement | Status |
| :--- | :--- | :---: |
| **Core Source** | Official tag `cv32e40p_v1.8.3` pinned; dynamic hash capture in manifest | **GO** |
| **Vector Layout** | `boot_addr = 0x0000_0000`, `mtvec` base 256-byte aligned (`0x0000_0100`), Timer IRQ 7 at `0x0000_011C` | **GO** |
| **Interrupt Map** | Reserved lines tied to `1'b0`; peripherals on lines 7, 16–20 | **GO** |
| **Bus Bridge** | Zero-wait restricted to TCM; OBI-to-APB supports wait-states and backpressure | **GO** |
| **Toolchain** | Explicit probe for `cv.sdotsp.h`; dual `CONFIG_BASELINE_RV32IMC` and `CONFIG_COREV_PULP` | **GO** |
| **AFE Clocking** | SPI SCLK frozen at 1.0 MHz across all phases (complies with TI $f_{\text{SCLK}} \le 2 \times f_{\text{CLK}}$) | **GO** |
| **AFE Protocol** | Complete bring-up: Power-up $\rightarrow$ `SDATAC` $\rightarrow$ ID Read $\rightarrow$ `WREG` $\rightarrow$ `START` $\rightarrow$ `RDATAC` $\rightarrow$ 72 SCLKs | **GO** |
| **Acquisition Load**| Autonomous hardware 72-clock capture; CPU interrupted only every 256 frames on DMA IRQ 19 | **GO** |
| **DMA Architecture**| Strict separation: APB control plane (`0x1A10_4000`) + D-OBI memory window (`0x2000_0000/1000`) | **GO** |
| **Frame Format** | Standardized 12-byte packed frame (`status`, `ch1`, `ch2`), 3 KB per ping-pong buffer | **GO** |
| **Manifest Integrity**| Hash manifest excludes itself; all paths resolved root-relative | **GO** |
| **Simulation Scope** | Clarified simulated target time ($< 100\,\mu\text{s}$); Verilator primary for full core | **GO** |
| **FPGA Physical** | 50 MHz MMCM, 2-stage synchronizers on reset/DRDY, BRAM36-equivalent $< 135$, WNS/WHS $\ge 0$ | **GO** |

**FINAL GATE VERDICT: FULL GO — ARCHITECTURAL SPECIFICATION FROZEN & VERIFIED.**

</details>
