# RISC-V ECG SoC — Simulation-First Execution Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Execute all 39 test cases across 7 verification environments, producing cryptographically-signed evidence logs that promote the RTM dashboard from "Code-Anchored" to "PASS (Sim)" status.

**Architecture:** CV32E40P (RV32IMC + Xpulpv2) SoC with Harvard OBI bus, dual-port TCM, OBI-to-APB3 bridge, 1.0 MHz ADS1292R SPI master, split-plane ping-pong DMA, vectored interrupt architecture. Frozen V3 design per `docs/plans/gem_implement_core.md`.

**Tech Stack:** Icarus Verilog 12.0+ (`iverilog`/`vvp`), Python 3.8+, RISC-V GCC (`riscv32-unknown-elf-gcc`), PowerShell 5.1+, Vivado 2024.x (FPGA synthesis — later phase)

**Prerequisites Confirmed:**
- All tools installed: iverilog, Python, RISC-V GCC, Vivado, make, host GCC
- Working directory: `E:\ResearchOnWork\RISC_V_CORE`
- NOT a git repository (Task 1 initializes it)

---

## Critical Discoveries From Pre-Plan Audit

| # | Finding | Impact | Resolution |
|---|---------|--------|------------|
| 1 | `Firmware/build/hello.dump` shows `_vector_table` at `0x0000_0000` — compiled from OLD `crt0.S` | Stale `.hex` will vector Timer IRQ to wrong address; SoC co-sim (Task 8.7.3) will fail | Must recompile firmware before SoC co-sim (Task 5) |
| 2 | `Firmware/build/hello.map` is 0 bytes (SHA = `e3b0c44...`) | No linker map — memory layout unverifiable | Regenerated during firmware recompile |
| 3 | `reports/simulation/sim_manifest.json` references obsolete IDs (`TC-SYS-001` etc.) | Stale manifest from older design — unusable | Will be superseded by per-run manifests |
| 4 | No git repository | No commit SHAs for evidence contracts | Task 1 initializes git |
| 5 | 0 of 39 test cases have produced actual simulation logs | All status is "Anchored in Code & TB", not verified | This plan produces all 39 pass/fail verdicts |

---

## Task 1: Initialize Git Repository and Baseline Commit

**Files:**
- Create: `.gitignore`
- Create: Git repository (`.git/`)

**Step 1: Create .gitignore**

```gitignore
# Build artifacts
Firmware/build/*.o
Firmware/build/*.elf
Firmware/build/*.hex
Firmware/build/*.dump
Firmware/build/*.map
Firmware/build/*.bin
Firmware/build/*.sha256
Firmware/build/dsp_test
Firmware/build/dsp_test.log

# Simulation artifacts (logs are evidence — keep manifests, exclude VCDs and VVPs)
reports/simulation/*/  
*.vvp
*.vcd

# Vivado
Synthesis/fpga/ecg_artix7/runs/
Synthesis/fpga/ecg_artix7/.Xil/
*.jou
*.log
!reports/**/*.log

# Python
__pycache__/
*.pyc

# OS
Thumbs.db
.DS_Store
```

**Step 2: Initialize repository and make baseline commit**

```powershell
cd E:\ResearchOnWork\RISC_V_CORE
git init
git add .gitignore
git add RTL/ Simulation/ Firmware/ Synthesis/ scripts/ Instruction/ docs/ reports/ spec/ config/ CLAUDE.md
git status
```

Inspect `git status` output. Ensure no secrets or massive binaries are staged. Then:

```powershell
git commit -m "baseline: V3 frozen architecture, 39 test cases code-anchored, 0 verified

All RTL, testbenches, runners, firmware source, and evidence infrastructure
committed as the pre-execution baseline. No simulation has been run yet.
All evidence gates are NOT_VERIFIED.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

**Expected:** Clean commit with SHA hash. Record this as `BASELINE_COMMIT` for all evidence manifests.

**Step 3: Verify baseline**

```powershell
git log --oneline -1
git status --short
```

**Expected:** No uncommitted changes.

---

## Task 2: Python Gate Infrastructure Verification

**Files:**
- Test: `scripts/test_runner_contract.py` (10 gates)
- Test: `scripts/test_evidence_gate.py`
- Test: `scripts/test_firmware_build_contract.py`

**Rationale:** Before running any simulation, prove the evidence validation infrastructure itself works. If the gate tests fail, simulation results cannot be trusted.

**Step 1: Run Python test suite**

```powershell
cd E:\ResearchOnWork\RISC_V_CORE
python -m unittest discover -s scripts -p "test_*.py" -v
```

**Expected:** All tests PASS. Exit code 0. Key output lines:
- `test_happy_path ... ok`
- `test_missing_irq_cases ... ok`
- `test_complete_only ... ok`
- `test_fatal_outside_event ... ok`
- `test_corrupted_hash ... ok`
- `test_stale_run_id ... ok`
- `test_empty_log ... ok`
- `test_duplicate_case ... ok`
- `test_child_failure ... ok`
- `test_missing_artifact ... ok`

**Step 2: Record result**

```powershell
python -m unittest discover -s scripts -p "test_*.py" -v 2>&1 | Out-File -Encoding utf8 reports/verification/gate_test_results.txt
echo $LASTEXITCODE
```

**Expected:** Exit code `0`. File `gate_test_results.txt` contains full verbose output.

**Step 3: Commit evidence**

```powershell
git add reports/verification/gate_test_results.txt
git commit -m "evidence: Python gate infrastructure passes 10/10 rejection tests

Co-Authored-By: Claude <noreply@anthropic.com>"
```

**Failure Protocol:** If any gate test fails:
1. Read the failure message carefully — it tells you which gate is broken
2. Fix the corresponding code in `scripts/check_evidence.py` or `scripts/test_runner_contract.py`
3. Re-run the full suite
4. Do NOT proceed to simulation until all gate tests pass

---

## Task 3: TCM Subsystem Simulation (5 Test Cases)

**Files:**
- Filelist: `Synthesis/flist_tcm_router_tb.f`
- Testbench: `Simulation/tcm_router_tb.sv`
- DUT: `RTL/ecg_soc/tcm_sram.sv`
- Runner: `Simulation/run_tcm.ps1`

**Step 1: Run TCM simulation**

```powershell
cd E:\ResearchOnWork\RISC_V_CORE
powershell -File Simulation/run_tcm.ps1
```

**Expected Output Lines:**
```
[PASS] TC-TCM-001: Concurrent I-fetch and D-read ...
[PASS] TC-TCM-002: CPU data port RODATA read ...
[PASS] TC-TCM-003: Byte-enable masking composite ...
[PASS] TC-TCM-004: Memory boundary 0x7FFC ...
[PASS] TC-TCM-005: Zero-wait timing verified ...
VERIFICATION RESULT: 5 PASSED, 0 FAILED
```
Exit code: `0`

**Step 2: Verify evidence artifacts exist**

```powershell
$latestDir = Get-ChildItem reports/simulation/tcm_run_* -Directory | Sort-Object Name | Select-Object -Last 1
Get-ChildItem $latestDir.FullName
```

**Expected:** `tcm_tb.log`, `tcm_tb.vvp`, `sim_results.json`, `compile.log` all present and non-zero.

**Step 3: Inspect simulation log for completeness**

```powershell
Select-String -Path "$($latestDir.FullName)\tcm_tb.log" -Pattern "\[PASS\]|\[FAIL\]|\[FATAL\]"
```

**Expected:** Exactly 5 `[PASS]` lines, 0 `[FAIL]`, 0 `[FATAL]`.

**Step 4: Commit evidence**

```powershell
git add $latestDir.FullName
git commit -m "evidence(E1): TCM subsystem 5/5 PASS — zero-wait grant, byte-enable, boundaries

Run ID: $(Split-Path $latestDir -Leaf)
Tool: Icarus Verilog
Census: TC-TCM-001..005 all PASS, 0 FAIL

Co-Authored-By: Claude <noreply@anthropic.com>"
```

**Failure Protocol:** If any TCM test fails:
1. Read the `[FAIL]` message — it names the expected vs actual value
2. Check `RTL/ecg_soc/tcm_sram.sv` for the specific logic error
3. Fix the RTL, re-run `run_tcm.ps1`
4. Preserve the failed log in the run directory (do not delete it)
5. Create a new run — never overwrite a failed run's evidence

---

## Task 4: OBI-to-APB3 Bridge Simulation (4 Test Cases)

**Files:**
- Filelist: `Synthesis/flist_obi_apb_bridge_tb.f`
- Testbench: `Simulation/obi_apb_bridge_tb.sv`
- DUT: `RTL/ecg_soc/obi_to_apb.sv`, `RTL/ecg_soc/apb_interconnect.sv`
- SVA: `RTL/ecg_soc/sva/obi_to_apb_sva.sv`, `RTL/ecg_soc/sva/obi_to_apb_bind.sv`
- Runner: `Simulation/run_bridge.ps1`

**Step 1: Run Bridge simulation**

```powershell
cd E:\ResearchOnWork\RISC_V_CORE
powershell -File Simulation/run_bridge.ps1
```

**Expected Output Lines:**
```
[PASS] TC-APB-001: Address decode sweep (5 slaves, dual windows) ...
[PASS] TC-APB-002: Variable wait-states via PREADY ...
[PASS] TC-APB-003: Backpressure gnt deassertion ...
[PASS] TC-APB-004: Unmapped address returns 0 ...
VERIFICATION RESULT: 4 PASSED, 0 FAILED
```
Exit code: `0`

**Step 2: Verify artifacts and commit**

```powershell
$latestDir = Get-ChildItem reports/simulation/bridge_run_* -Directory | Sort-Object Name | Select-Object -Last 1
Select-String -Path "$($latestDir.FullName)\bridge_tb.log" -Pattern "\[PASS\]|\[FAIL\]|\[FATAL\]"
git add $latestDir.FullName
git commit -m "evidence(E1): OBI-APB bridge 4/4 PASS — address decode, wait-states, backpressure

Run ID: $(Split-Path $latestDir -Leaf)
Census: TC-APB-001..004 all PASS, 0 FAIL

Co-Authored-By: Claude <noreply@anthropic.com>"
```

**Known Risk:** SVA assertions (`obi_to_apb_sva.sv`) may not be supported by Icarus Verilog. If compilation fails with SVA errors:
1. Check if the filelist includes SVA bind files
2. Icarus Verilog does NOT support SystemVerilog Assertions natively
3. **Fix:** Edit `Synthesis/flist_obi_apb_bridge_tb.f` to comment out SVA files for Icarus, add a note that SVA verification requires a commercial simulator (Questa/VCS)
4. Re-run without SVA — the functional testbench still covers the same logic

---

## Task 5: SPI Master Simulation (9 Pass Gates / 7 Named Tests)

**Files:**
- Filelist: `Synthesis/flist_spi_master_tb.f`
- Testbench: `Simulation/spi_master_tb.sv`
- DUT: `RTL/ecg_soc/spi_master.sv`, `RTL/ecg_soc/spi_master_apb.sv`
- AFE Model: `Simulation/ads1292r_model.sv`
- SVA: `RTL/ecg_soc/sva/spi_master_sva.sv`, `RTL/ecg_soc/sva/spi_master_bind.sv`
- Runner: `Simulation/run_spi.ps1`

**Step 1: Run SPI simulation**

```powershell
cd E:\ResearchOnWork\RISC_V_CORE
powershell -File Simulation/run_spi.ps1
```

**Expected Output Lines:**
```
[PASS] TC-SPI-001A: CLKDIV register read back matches (10)
[PASS] TC-SPI-001B: SAMPLE_CNT register read back matches (0x12345678)
[PASS] TC-SPI-002: Single 24-bit SPI Transfer completed
[PASS] TC-SPI-003: Caught DRDY# falling edge interrupt from AFE
[PASS] TC-SPI-003B: Frame transfer finished, FRAME_VALID asserted
[PASS] TC-SPI-004: All 72 bits and decoded signed values match exact golden frame!
[PASS] TC-SPI-005: CS# remained continuously LOW across exactly 72 bits
[PASS] TC-SPI-006: FRAME_VALID flag successfully cleared by W1C
[PASS] TC-SPI-007: Direct sample streaming outputs contain exact golden frame!
VERIFICATION RESULT: 9 PASSED, 0 FAILED
```
Exit code: `0`
Census gate: `pass_count == 9`

**Step 2: Verify 72-bit frame accuracy (critical for ADS1292R compliance)**

From the log, confirm these exact values:
- Status byte: `0xC0`
- CH1 signed: `+1193046` (hex `0x123456`)
- CH2 signed: `-74566` (hex `0xFEDCBA`, sign-extended to `0xFFFEDCBA`)
- SCLK pulse count: exactly `72`
- CS# glitch: `0` (no deassertions during transfer)

**Step 3: Verify artifacts and commit**

```powershell
$latestDir = Get-ChildItem reports/simulation/spi_run_* -Directory | Sort-Object Name | Select-Object -Last 1
Select-String -Path "$($latestDir.FullName)\spi_tb.log" -Pattern "\[PASS\]|\[FAIL\]|\[FATAL\]"
git add $latestDir.FullName
git commit -m "evidence(E1): SPI master 9/9 PASS — 72-bit frame, continuous CS#, DRDY auto-capture

Run ID: $(Split-Path $latestDir -Leaf)
Census: TC-SPI-001A/B through TC-SPI-007 all PASS, 0 FAIL
Golden frame: Status=0xC0, CH1=+1193046, CH2=-74566
SCLK pulses: 72 exact, CS# glitch: 0

Co-Authored-By: Claude <noreply@anthropic.com>"
```

**Known Risk:** Same SVA issue as Task 4. If `spi_master_sva.sv` or `spi_master_bind.sv` cause Icarus compilation errors, comment them out of the filelist.

---

## Task 6: DMA Simulation (6 Test Cases)

**Files:**
- Filelist: `Synthesis/flist_ecg_dma_tb.f`
- Testbench: `Simulation/ecg_dma_tb.sv`
- DUT: `RTL/ecg_soc/ecg_dma.sv`
- Runner: `Simulation/run_dma.ps1`

**Step 1: Run DMA simulation**

```powershell
cd E:\ResearchOnWork\RISC_V_CORE
powershell -File Simulation/run_dma.ps1
```

**Expected Output Lines:**
```
[PASS] TC-DMA-001: 12-byte frame layout (Status=0x000000C0, CH1=0x00123456, CH2=0xFFFEDCBA)
[PASS] TC-DMA-002: Bank A→B swap on 32-sample boundary
[PASS] TC-DMA-003: buffer_ready_irq_o asserted at boundary
[PASS] TC-DMA-004: D-OBI concurrent readout returns valid data
[PASS] TC-DMA-005: Overflow error latched on unreleased bank
[PASS] TC-DMA-006: 256-sample stress streaming, zero loss
VERIFICATION RESULT: 6 PASSED, 0 FAILED
```
Exit code: `0`
Census gate: `pass_count == 6`

**Step 2: Verify sign extension (critical for ECG data integrity)**

From TC-DMA-001, confirm:
- Word 0 (Status): `0x000000C0` — zero-padded 8-bit status
- Word 1 (CH1): `0x00123456` — positive 24-bit, zero-extended to 32-bit
- Word 2 (CH2): `0xFFFEDCBA` — negative 24-bit, sign-extended to 32-bit

**Step 3: Verify artifacts and commit**

```powershell
$latestDir = Get-ChildItem reports/simulation/dma_run_* -Directory | Sort-Object Name | Select-Object -Last 1
Select-String -Path "$($latestDir.FullName)\dma_tb.log" -Pattern "\[PASS\]|\[FAIL\]|\[FATAL\]"
git add $latestDir.FullName
git commit -m "evidence(E1): DMA 6/6 PASS — 12-byte frame, bank swap, IRQ, overflow, 256-sample stress

Run ID: $(Split-Path $latestDir -Leaf)
Census: TC-DMA-001..006 all PASS, 0 FAIL
Frame format: {0x000000C0, 0x00123456, 0xFFFEDCBA} verified

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 7: Firmware Recompilation (CRITICAL — Stale Binary Fix)

**Files:**
- Modify: `Firmware/build/` (all outputs regenerated)
- Source: `Firmware/boot/crt0.S`, `Firmware/boot/hello.c`, `Firmware/boot/link.ld`
- Build: `Firmware/Makefile`

**Rationale:** The existing `hello.dump` shows `_vector_table` at `0x0000_0000` — compiled from an OLDER version of `crt0.S`. The current source places `_vector_table` at `0x0000_0100` with Timer ISR at entry 7 (`0x0000_011C`). The binary MUST be recompiled before SoC co-simulation.

**Step 1: Verify RISC-V GCC availability**

```powershell
riscv32-unknown-elf-gcc --version
```

**Expected:** Version string with `riscv32-unknown-elf-gcc (GCC) 1x.x.x` or similar.

**Step 2: Clean and rebuild**

```powershell
cd E:\ResearchOnWork\RISC_V_CORE
make -C Firmware clean
make -C Firmware hello
```

**Expected:** Clean compilation with no errors. Outputs:
- `Firmware/build/hello.elf`
- `Firmware/build/hello.hex`
- `Firmware/build/hello.dump`
- `Firmware/build/hello.map`
- `Firmware/build/hello.sha256`

**Step 3: Verify vector table layout in disassembly (THE CRITICAL CHECK)**

```powershell
Select-String -Path Firmware/build/hello.dump -Pattern "_vector_table|_start|timer_irq_handler" | Select-Object -First 10
```

**Expected Layout:**
```
0x00000000 <_start>:          # Boot entry point
0x00000100 <_vector_table>:   # Vector table base (mtvec = 0x0101 vectored)
0x0000011c:                   # Entry 7 = Timer IRQ handler jump target
```

**REJECTION CRITERIA:** If `_vector_table` appears at `0x0000_0000` instead of `0x0000_0100`, the linker script is wrong. Check `Firmware/boot/link.ld` sections `.boot` and `.vectors`.

**Step 4: Verify map file is non-empty**

```powershell
(Get-Item Firmware/build/hello.map).Length
```

**Expected:** Non-zero file size (the old map was 0 bytes).

**Step 5: Verify SHA-256 manifest**

```powershell
Get-Content Firmware/build/hello.sha256
```

**Expected:** SHA-256 hashes for `.elf`, `.hex`, `.dump`, `.map` files.

**Step 6: Commit rebuilt firmware**

```powershell
git add Firmware/build/
git commit -m "evidence: firmware recompiled with correct vector table layout

_vector_table at 0x0000_0100 (was incorrectly at 0x0000_0000 in stale binary)
Timer ISR entry 7 at 0x0000_011C
mtvec = 0x0000_0101 (vectored mode)
hello.map now non-empty
GCC version: $(riscv32-unknown-elf-gcc --version | Select-Object -First 1)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 8: Full SoC Co-Simulation (5 Test Cases)

**Files:**
- Filelist: `Synthesis/flist_cv32e40p_soc.f`
- Testbench: `Simulation/soc_tb.sv`
- DUT: `RTL/ecg_soc/cv32e40p_ecg_soc_top.sv` + all peripherals + CV32E40P core
- Firmware: `Firmware/build/hello.hex` (must be freshly compiled from Task 7)
- Runner: `scripts/run_sim.ps1`

**DEPENDENCY:** Task 7 MUST complete successfully first. The SoC testbench loads `hello.hex` into TCM for the CV32E40P core to execute.

**Step 1: Verify firmware hex exists and is fresh**

```powershell
Test-Path Firmware/build/hello.hex
(Get-Item Firmware/build/hello.hex).LastWriteTime
```

**Expected:** File exists. Timestamp is from Task 7 execution (today).

**Step 2: Run SoC co-simulation**

```powershell
cd E:\ResearchOnWork\RISC_V_CORE
powershell -File scripts/run_sim.ps1
```

**Expected Output Lines:**
```
ECG BOOT: CV32E40P ALIVE        → TC-BOOT-001 PASS
ECG BOOT: DATA OK               → TC-DATA-002 PASS  
ECG BOOT: TIMER IRQ OK          → TC-TIMER-003 PASS
ECG BOOT: CANARY OK             → TC-MRET-004 PASS
ECG BOOT: COMPLETE              → TC-DONE-005 PASS
```
Exit code: `0`
Simulated time: < 100 µs

**Step 3: Verify evidence gate validation**

The runner script calls `check_evidence.py` automatically. Check its exit code:

```powershell
$latestDir = Get-ChildItem reports/simulation/run_* -Directory | Sort-Object Name | Select-Object -Last 1
Get-Content "$($latestDir.FullName)\sim_results.json"
```

**Expected:** JSON with `"status": "PASS"`, all 5 test cases listed.

**Step 4: Commit evidence**

```powershell
git add $latestDir.FullName
git commit -m "evidence(E1): Full SoC co-sim 5/5 PASS — CV32E40P boot, data init, timer IRQ, canary, complete

Run ID: $(Split-Path $latestDir -Leaf)
Census: TC-BOOT-001, TC-DATA-002, TC-TIMER-003, TC-MRET-004, TC-DONE-005
Core: CV32E40P @ cv32e40p_v1.8.3 (97086e9)
Firmware: hello.hex (freshly compiled, mtvec=0x0101)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

**Known Risks:**
1. **Compilation may be slow** — the CV32E40P core has 27+ source files. Icarus Verilog compilation could take 2-10 minutes.
2. **Icarus may not support all SystemVerilog constructs** used by CV32E40P. If compilation fails:
   - Check error messages for unsupported constructs (`interface`, `modport`, `always_comb`, etc.)
   - CV32E40P uses SystemVerilog extensively — Icarus 12.0+ has improved SV support but it may not be sufficient
   - **Fallback:** Use Verilator for SoC-level simulation if Icarus fails
3. **Hex loading:** `soc_tb.sv` uses `$readmemh` to load `hello.hex` into TCM. Verify the path is correct.

---

## Task 9: DSP Host Verification (6 Test Cases)

**Files:**
- Source: `Firmware/dsp/dsp_test.c`, `Firmware/dsp/pan_tompkins.c`, `Firmware/dsp/pan_tompkins.h`
- Build: `Firmware/Makefile` (target: `dsp-test-host`)

**Step 1: Build DSP test for host execution**

```powershell
cd E:\ResearchOnWork\RISC_V_CORE
make -C Firmware dsp-test-host
```

**Expected:** Compiles with host GCC (not RISC-V GCC). Produces `Firmware/build/dsp_test` or `dsp_test.exe`.

**Step 2: Run DSP tests**

```powershell
./Firmware/build/dsp_test 2>&1 | Tee-Object -FilePath Firmware/build/dsp_test.log
```

**Expected Output:**
```
[PASS] TC-DSP-001: Zero input → zero output
[PASS] TC-DSP-002: Impulse response matches Tap 0 coefficient (-12)
[PASS] TC-DSP-003: ecg_fir_pulp matches ecg_fir_scalar_reference bit-for-bit
[PASS] TC-DSP-004: Cycle count measured via mcycle CSR
[PASS] TC-DSP-005: 64-bit widening prevents squaring overflow
[PASS] TC-DSP-006: Pan-Tompkins QRS peak detected at expected sample
```

**Note on TC-DSP-004:** On host (x86), `mcycle` CSR is not available. The test should either skip the cycle count or use `clock()` as a proxy. Check `dsp_test.c` for `#ifdef __riscv` guards.

**Step 3: Commit evidence**

```powershell
git add Firmware/build/dsp_test.log
git commit -m "evidence(E1-host): DSP 6/6 PASS — FIR filter, Pan-Tompkins QRS detection

Census: TC-DSP-001..006 all PASS on host GCC
Note: TC-DSP-004 cycle count uses host clock, not mcycle CSR
FIR kernel: 45-tap Q1.15, widening multiply verified
Pan-Tompkins: Adaptive threshold, QRS peak detected

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 10: RTM Dashboard Update and Evidence Synchronization

**Files:**
- Modify: `reports/verification/rtm_dashboard.md`
- Modify: `reports/manifest.json`
- Modify: `Instruction/session_checklist.md`

**Step 1: Collect all run IDs and results**

After Tasks 3-9, you should have:
- TCM: `reports/simulation/tcm_run_<id>/` — 5/5 PASS
- Bridge: `reports/simulation/bridge_run_<id>/` — 4/4 PASS
- SPI: `reports/simulation/spi_run_<id>/` — 9/9 PASS
- DMA: `reports/simulation/dma_run_<id>/` — 6/6 PASS
- SoC: `reports/simulation/run_<id>/` — 5/5 PASS
- DSP: `Firmware/build/dsp_test.log` — 6/6 PASS
- Gate: `reports/verification/gate_test_results.txt` — 10/10 PASS

**Step 2: Update RTM dashboard**

For each requirement that now has a verified simulation log, change status from:
```
**Anchored in Code & TB**
```
to:
```
**PASS (Sim)** — Run ID: `<run_id>`, Log: `<path>`
```

**Step 3: Update manifest.json**

Add verification campaign entries with:
- `campaign_id`: the run ID
- `tool`: `"Icarus Verilog 12.0"` (verify exact version from `iverilog -V`)
- `exit_status`: `0`
- `artifact_hashes`: SHA-256 of each log file

**Step 4: Mark checklist tasks complete**

In `Instruction/session_checklist.md`, change from `[pending]` to `[complete]` for:
- Task 8.1.3 (Python gate tests)
- Task 8.3.4 (TCM simulation)
- Task 8.4.4 (Bridge simulation)
- Task 8.5.4 (SPI simulation)
- Task 8.6.4 (DMA simulation)
- Task 8.7.3 (SoC co-simulation) — if successful
- Task 8.8.3 (DSP host verification)

Tasks 8.2.5 (firmware) and 8.9.3 (FPGA synthesis) are handled separately.

**Step 5: Final commit**

```powershell
git add reports/verification/rtm_dashboard.md reports/manifest.json Instruction/session_checklist.md
git commit -m "evidence: RTM dashboard promoted to PASS(Sim) for 24/25 requirements

Verified: REQ-CORE-001..004, REQ-SPI-001..005, REQ-APB-001..003,
REQ-BUF-001..004, REQ-UART-001/003, REQ-DSP-001..002, REQ-SYS-001/003
Remaining: REQ-SYS-002 (FPGA synthesis), REQ-MAMBA-001 (deferred)
Gate infrastructure: 10/10 rejection gates verified

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Execution Order Summary

```
Task 1: git init + baseline commit          [NO DEPENDENCIES]
Task 2: Python gate tests                   [AFTER Task 1]
Task 3: TCM simulation (5 tests)            [AFTER Task 2]
Task 4: Bridge simulation (4 tests)         [AFTER Task 2, PARALLEL with Task 3]
Task 5: SPI simulation (9 tests)            [AFTER Task 2, PARALLEL with Tasks 3-4]
Task 6: DMA simulation (6 tests)            [AFTER Task 2, PARALLEL with Tasks 3-5]
Task 7: Firmware recompilation              [AFTER Task 2, PARALLEL with Tasks 3-6]
Task 8: SoC co-simulation (5 tests)         [AFTER Task 7 — HARD DEPENDENCY on fresh hex]
Task 9: DSP host verification (6 tests)     [AFTER Task 2, PARALLEL with Tasks 3-7]
Task 10: RTM dashboard update               [AFTER ALL previous tasks]
```

**Parallelism:** Tasks 3, 4, 5, 6, 7, and 9 are independent and can run in parallel after Task 2 completes. Task 8 depends on Task 7 (firmware). Task 10 depends on all.

**Total test cases:** 5 + 4 + 9 + 6 + 5 + 6 + 10 = **45 pass gates** across 39 unique test case IDs + 10 infrastructure gates = **49 total verification points**

---

## Failure Recovery Procedures

### Icarus Verilog Compilation Failure
If `iverilog` cannot compile a testbench:
1. Save `compile.log` — it contains the exact error
2. Common issues:
   - `error: ... is not a type name` → Missing package import
   - `error: ... System function not supported` → `$fatal` syntax differences
   - `error: ... interface not supported` → Icarus SV limitation
3. For SV-only constructs, try adding `-g2012` flag to iverilog command
4. If CV32E40P core fails to compile in Icarus, consider Verilator as alternative

### Simulation Hangs (No Output)
If a simulation produces no output after 60 seconds:
1. Check for infinite loops in RTL (missing clock edges, stuck FSM)
2. Kill the process and check partial output
3. Verify testbench watchdog timeout is set (all TBs have 100ms+ watchdogs)
4. Run with VCD dump enabled and inspect waveform

### Evidence Gate Rejection
If `check_evidence.py` rejects a passing simulation:
1. Read the rejection message — it names the specific gate
2. Common causes: missing testcase in log, stale run ID, corrupted hash
3. Do NOT modify `check_evidence.py` to bypass the rejection
4. Fix the root cause (usually a testbench output format issue)
