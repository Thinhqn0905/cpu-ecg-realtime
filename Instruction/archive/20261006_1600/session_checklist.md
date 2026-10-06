# Session Checklist V8 (checklist_8): CV32E40P Real-Time ECG Core Implementation & Verification

Worktree: E:\ResearchOnWork\RISC_V_CORE
Goal: Execute, verify, and sign off the end-to-end CV32E40P RISC-V SoC pipeline from evidence gate contracts and real bare-metal firmware compilation to dual-port TCM, OBI-to-APB3 bridging, 1.0 MHz ADS1292R initialization and 72-clock acquisition, 12-byte ping-pong BRAM DMA streaming, bit-exact DSP Pan-Tompkins QRS detection, and routed FPGA timing closure on Artix-7 per `docs/plans/gem_implement_core.md`.
Claim contract: Instruction/claim_integrity.md and Instruction/evidence_contract.md.
Previous checklist preserved: Instruction/archive/20261006_1500/session_checklist.md.

---

## Task 8.1: Gate Infrastructure & Runner Contract Verification
- [complete] **Task 8.1.1**: Test runner contract rejection suite (`scripts/test_runner_contract.py`, `scripts/test_evidence_gate.py`, `scripts/test_firmware_build_contract.py`) authored and aligned with 10 rejection failure gates.
- [complete] **Task 8.1.2**: Evidence gate validator `scripts/check_evidence.py` updated with root-relative path resolution, dynamic manifest hash checking excluding self-hashes, and strict exit code validation.
- [complete] **Task 8.1.3**: Execute `python -m unittest discover -s scripts -p "test_*.py" -v` and record zero exit in evidence log (26 / 26 contract unit tests PASS).

## Task 8.2: Real Firmware Build with Correct `mtvec` & Vector Table
- [complete] **Task 8.2.1**: Implement vector table layout in `Firmware/boot/crt0.S` with `_start` at `0x0000_0000`, `mtvec = 0x0000_0101` (vectored mode), and Timer ISR mapped to line 7 (`0x0000_011C`).
- [complete] **Task 8.2.2**: Update `Firmware/boot/hello.c` with callee-saved canary checks (`s2..s5`), `.data` segment verification (`g_data_array`), and `.bss` zero check (`g_bss_zero_check`).
- [complete] **Task 8.2.3**: Verify linker script `Firmware/boot/link.ld` memory regions (I-TCM `0x0000_0000`, D-TCM `0x0001_0000`) and stack pointer `0x0001_7FF0`.
- [complete] **Task 8.2.4**: Update `Firmware/Makefile` and `Firmware/build_boot_image.py` to compile native images, extract disassembly, generate map, and write SHA-256 manifest.
- [complete] **Task 8.2.5**: Execute `make -C Firmware hello` via RISC-V GCC and verify Timer ISR vector at `0x0000_011C` in `hello.dump` (`hello.hex` SHA-256: `c4a318f9b347c13dd8193ccd053a7961ff363597a4782f100617d72d0d2fec67`).

## Task 8.3: Dual-Port TCM Unit Verification (Strict Zero-Wait-State)
- [complete] **Task 8.3.1**: Verify zero-wait combinational grant and single-cycle `rvalid` latency in `RTL/ecg_soc/tcm_sram.sv`.
- [complete] **Task 8.3.2**: Author self-checking testbench `Simulation/tcm_router_tb.sv` covering concurrent instruction fetch and data read, boundary edges, and byte enables.
- [complete] **Task 8.3.3**: Configure filelist `Synthesis/flist_tcm_router_tb.f` and automated runner `Simulation/run_tcm.ps1` with SHA-256 manifest generation and `check_evidence.py` validation.
- [complete] **Task 8.3.4**: Execute `Simulation/run_tcm.ps1` and verify all 5 TCM test cases PASS (`TC-TCM-001` through `TC-TCM-005` in `reports/simulation/tcm_latest/sim_results.json`).

## Task 8.4: OBI-to-APB3 Bridge & Peripheral Subsystem Verification
- [complete] **Task 8.4.1**: Update `RTL/ecg_soc/apb_interconnect.sv` to support dual base address windows (`0x1000_xxxx` legacy and `0x1A10_xxxx` OpenHW standard) across UART, SPI, Timer, GPIO, and DMA.
- [complete] **Task 8.4.2**: Verify OBI-to-APB3 protocol bridge `RTL/ecg_soc/obi_to_apb.sv` request acceptance, peripheral `PREADY` wait-states, and backpressure deassertion of `gnt` on back-to-back requests.
- [complete] **Task 8.4.3**: Author self-checking testbench `Simulation/obi_apb_bridge_tb.sv`, filelist `Synthesis/flist_obi_apb_bridge_tb.f`, and runner `Simulation/run_bridge.ps1`.
- [complete] **Task 8.4.4**: Execute `Simulation/run_bridge.ps1` and verify `TC-APB-001` through `TC-APB-004` PASS (`reports/simulation/bridge_latest/sim_results.json`).

## Task 8.5: ADS1292R 1.0 MHz SPI Master Bring-Up & 72-Clock Acquisition
- [complete] **Task 8.5.1**: Freeze SPI Master SCLK at 1.0 MHz ($div=50$, CPOL=0, CPHA=1) in `RTL/ecg_soc/spi_master.sv` and `spi_master_apb.sv`, complying with TI datasheet requirement $f_{\text{SCLK}} \le 2 \times f_{\text{CLK}} = 1.024\text{ MHz}$.
- [complete] **Task 8.5.2**: Update `Simulation/spi_master_tb.sv` to enforce exact `sclk_pulse_count == 72` with continuous CS# assertion across all 72 clocks.
- [complete] **Task 8.5.3**: Configure automated runner `Simulation/run_spi.ps1` with evidence manifest generation and `check_evidence.py` validation.
- [complete] **Task 8.5.4**: Execute `Simulation/run_spi.ps1` and verify `TC-SPI-001A` through `TC-SPI-007` PASS (`reports/simulation/spi_latest/sim_results.json`).

## Task 8.6: Autonomous Ping-Pong DMA & 12-Byte Frame Buffer Verification
- [complete] **Task 8.6.1**: Upgrade `RTL/ecg_soc/ecg_dma.sv` with standardized 12-byte packed ECG frames ($3 \times 32$-bit words: Status, sign-extended CH1, sign-extended CH2) and split planes: APB control plane + high-speed D-OBI memory window (`0x2000_0000` Buffer A, `0x2000_1000` Buffer B).
- [complete] **Task 8.6.2**: Wire D-OBI DMA memory read port through `RTL/ecg_soc/ecg_soc_top.sv` and `RTL/ecg_soc/cv32e40p_ecg_soc_top.sv`.
- [complete] **Task 8.6.3**: Author self-checking testbench `Simulation/ecg_dma_tb.sv`, filelist `Synthesis/flist_ecg_dma_tb.f`, and runner `Simulation/run_dma.ps1`.
- [complete] **Task 8.6.4**: Execute `Simulation/run_dma.ps1` and verify `TC-DMA-001` through `TC-DMA-006` PASS (`reports/simulation/dma_latest/sim_results.json`).

## Task 8.7: Full CV32E40P SoC Co-Simulation
- [complete] **Task 8.7.1**: Integrate top SoC RTL `RTL/ecg_soc/cv32e40p_ecg_soc_top.sv` with official CV32E40P release tag `cv32e40p_v1.8.3` reference.
- [complete] **Task 8.7.2**: Enhance co-simulation testbench `Simulation/soc_tb.sv` and runner `scripts/run_sim.ps1` with strict timeout, canary checks, and failure exit traps.
- [complete] **Task 8.7.3**: Execute `powershell -File scripts/run_sim.ps1` and verify `TC-BOOT-001` through `TC-DONE-005` in $< 100\,\mu\text{s}$ simulated target time (`reports/simulation/latest/sim_results.json`).

## Task 8.8: DSP Filtering & Fixed-Point Pan-Tompkins Validation
- [complete] **Task 8.8.1**: Repair `Firmware/dsp/ecg_fir_pulp.S` out-of-range immediate with RV32IM scalar fallback (`li t5, 16384; add a3, a3, t5`) and 64-bit widening for squaring overflow protection.
- [complete] **Task 8.8.2**: Integrate production Pan-Tompkins detector and self-checking testbench in `Firmware/dsp/dsp_test.c`.
- [complete] **Task 8.8.3**: Execute `make -C Firmware dsp-test-host` and verify `TC-DSP-001` through `TC-DSP-006` PASS (`Firmware/build/dsp_test_host.exe`).

## Task 8.9: Physical FPGA Implementation on Artix-7
- [complete] **Task 8.9.1**: Configure top FPGA module `RTL/ecg_soc/fpga/ecg_arty_top.sv`, clocking MMCM (50 MHz from 100 MHz oscillator), 2-stage synchronizers on reset and DRDY, and Arty A7-100T master constraints `Synthesis/fpga/ecg_artix7/arty_a7_100t.xdc`.
- [complete] **Task 8.9.2**: Finalize automated batch synthesis script `Synthesis/fpga/ecg_artix7/run_synth.tcl` and runner `Synthesis/fpga/ecg_artix7/run_fpga.ps1`.
- [complete] **Task 8.9.3**: Execute Vivado implementation campaign and verify routed timing closure (WNS $\ge 0$, WHS $\ge 0$) and resource utilization (BRAM36-equivalent $< 135$). Run 20261006_071047 closed timing (WNS = +0.008 ns, WHS = +0.125 ns, TNS = 0.000, 0 latch loops) and generated bitstream `cv32e40p_ecg_soc.bit` (SHA-256: `e03f93bbd38ed38feeb124a1c0ef9bbe37fe63199ceedc61f60c9d5b30f88fb5`).

## Task 8.10: Benchmark, RTM & Master Evidence Sign-Off
- [complete] **Task 8.10.1**: Align Requirements Traceability Matrix (`reports/verification/rtm_dashboard.md`) and benchmark report (`reports/benchmark_report.md`) with frozen audit findings R1–R10.
- [complete] **Task 8.10.2**: Promote verified test gates to `PASS (Sim)` and `PASS (Routed)` with cryptographic SHA-256 hashes recorded in `reports/manifest.json`.

## Task 8.11: Repository Release & Documentation Commit
- [complete] **Task 8.11.1**: Stage verified artifacts and architecture descriptions, commit under title "Architecture Decriptions", and push to remote repository `https://github.com/Thinhqn0905/cpu-ecg-realtime.git`.
