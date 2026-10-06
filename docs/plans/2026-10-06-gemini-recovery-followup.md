# Gemini Recovery Follow-up Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Establish trustworthy compiler provenance and one independently checked CV32E40P boot/data/IRQ milestone before advancing acquisition, DSP or FPGA claims.

**Architecture:** Reuse the cloned CV32E40P and existing local peripherals. Repair build/evidence/integration boundaries incrementally; preserve upstream and rejected artifacts. Keep CV32E40P as the DSP integration candidate until a documented, matched resource comparison resolves the older CVA6 contract.

**Tech Stack:** RISC-V GCC/binutils, CORE-V-compatible DSP toolchain when needed, existing SystemVerilog, Python unittest, simulator supporting the pinned upstream core, Vivado for later FPGA work.

---

Dùng @writing-plans. Audit input: `reports/review/2026-10-06-gemini-recovery-audit/audit.md` (R1–R10) và snapshot manifest. **Planning only: none of the build/test commands below have been run.** Execution header is a future workflow, not a dependency of this audit. Do not synthesize now. Root currently lacks Git; use dated snapshots/hashes until version control exists, then commit only task-specific files after checks. Do not run destructive `make clean` over historical evidence.

## Task 1: Correct provenance claims and preserve failed evidence (R1/R2/R8)

**Files:** Modify `Instruction/session_checklist.md`, `reports/verification/rtm_dashboard.md`, `reports/manifest.json`, `reports/benchmark_report.md`; create `reports/review/<new-run-id>/corrections.md`; read `Instruction/claim_integrity.md` before updates.

1. Preserve current Firmware/build and reports with hashes (audit snapshot already preserves the inspected files).
2. Record GCC compilation/boot as NOT_VERIFIED; record hash mismatch as artifact-integrity violation. Preserve old SPI smoke under historical revision, remove its promotion to new 72-bit requirements.
3. Distinguish source-authored items from measured gates in checklist; keep unexecuted gate/boot tasks pending.
4. Read core-choice sections of `Instruction/research_analysis.md`, `Instruction/architecture.md`, `spec/ecg_soc_spec.md`. Add a small decision record `docs/decisions/cv32e40p-candidate.md` recording pinned core revision/features, candidate status, OBI/APB/IRQ map, missing CVA6 resource comparison. Do not assert final PPA superiority or overwrite upstream.
5. Future validation: `Get-FileHash Firmware/build/hello.* -Algorithm SHA256`. Expected: archived old mismatch retained; reports no longer describe it as verified GCC output. Save this dated correction separately from executable validation.

## Task 2: Close false-success gates first (R5/R6)

**Files:** Modify `scripts/check_evidence.py`, `scripts/test_evidence_gate.py`, `scripts/run_sim.ps1`, `scripts/run_sim.sh`, `Simulation/soc_tb.sv`, `Simulation/spi_master_tb.sv`; create `scripts/test_runner_contract.py`.

1. Add fixture cases: zero-exit log missing IRQ, COMPLETE-only, FAIL outside TC event, corrupted hash, old run-id, empty log, duplicate case, child failure and timeout. Test runners with fake tools so native exit zero alone cannot accept a run.
2. Future command: `python -m unittest discover -s scripts -p 'test_*.py' -v`. Expected before fixes: rejection/runner-wiring cases fail. Save transcript, do not claim they failed until observed.
3. Enforce manifest identities before census. Minimal hash operation:

```python
for artifact in manifest['artifacts']:
    path = Path(artifact['path'])
    if not path.is_file() or calculate_sha256(path) != artifact['sha256']:
        raise ValueError('missing or mismatched artifact')
if manifest['run_id'] != requested_run_id:
    raise ValueError('stale run')
```

   Bind root-relative paths, source/filelist digest, compiler/simulator versions, boot ELF/image digest and command/exit results. Reject fatal/error events; store failures and stderr too. Handle JSON BOM explicitly or write BOM-free UTF-8.
4. In each runner invoke `check_evidence.py` with all required testcase IDs **before** latest/SUCCESS; propagate its exit, preserve failure manifest and enforce a wall timeout. Expected boot IDs: TC-BOOT-001, TC-DATA-002, TC-TIMER-003, TC-MRET-004, TC-DONE-005.
5. Replace failure exits in both TBs with `$fatal(1, "verification failed")`; success requires all expected conditions, including independent checks in Task4. For boot's final condition at minimum:

```systemverilog
if (!(seen_alive && seen_irq_pass && seen_complete) || fail_count != 0)
  $fatal(1, "Incomplete boot testcase census");
```

6. Rerun future fixture suite. Expected: every deliberate failure rejected nonzero; valid complete fixture accepted. Freeze this gate before interpreting any functional run.

## Task 3: Build real firmware with no synthetic replacement (R1–R3/R7)

**Files:** Modify `Firmware/build_boot_image.py`, `Firmware/Makefile`; test in new `scripts/test_firmware_build_contract.py`; output to fresh `Firmware/build_runs/<id>/` instead of overwriting archived files.

1. Add tests that missing compiler and compiler failure exit nonzero without producing hello success artifacts. Add ELF→binary→hex equality check and compiler provenance assertions.
2. Future command: `python -m unittest discover -s scripts -p 'test_firmware_build_contract.py' -v`. Expected before repair: fallback acceptance tests fail.
3. Remove automatic standalone fallback from production hello build. If retained as a diagnostic fixture, separate names/directory and label hand-encoded, not GCC output. Propagate compiler/binutils failures.
4. Fix GNU make CC built-in handling; require explicit compiler tools. Include map in hashed outputs; capture flags/version/stdout/stderr; build startup and C exactly as listed.
5. Future command from root, after tool availability is established:

```powershell
make -C Firmware hello CC=riscv32-unknown-elf-gcc OBJCOPY=riscv32-unknown-elf-objcopy OBJDUMP=riscv32-unknown-elf-objdump
```

   Expected: native compiler exit0 and actual ELF, objects, map, bin, objdump disassembly, hex. If tool missing, NOT_VERIFIED with nonzero exit; no substitute image. Configure fresh output directory in repaired Makefile before running.
6. Validate ELF segments/entry, .data load address and startup symbols against linker map; derive hex from that ELF and compare all payload bytes. Disassemble vector PC0x4 independently: target must match `_default_isr`; all branch targets must match opcodes. Recompute and verify every stored hash.
7. Acceptance: reproducible source→ELF→image chain. This alone is **build evidence**, not CPU boot evidence.

## Task 4: Prove local binding, memory and one real IRQ (R4/R6/R10)

**Files:** Modify `RTL/ecg_soc/cv32e40p_ecg_soc_top.sv`, `tcm_sram.sv`, `Simulation/soc_tb.sv`, `Firmware/boot/hello.c`, `crt0.S`; create `Simulation/tcm_router_tb.sv`, `Synthesis/flist_tcm_router_tb.f`; include existing `RTL/ecg_soc/sva/obi_to_apb_sva.sv` in an assertion-enabled compatible runner.

1. Fix `dtcm_data_gnt` to declared `dtcm_gnt`; add strict undeclared-net elaboration in local wrappers. Review pending-target ownership against upstream OBI outstanding limits. Serialize outstanding requests or track them correctly; do not mask errors in the core.
2. Add directed memory tests for last-valid/first-invalid addresses, byte writes, rodata reads, APB stall then D-TCM request and response ordering. Add missing/corrupt/wrong-width image fatal checks; only I-TCM may consume the firmware plusarg. Keep FPGA ROM initialization and simulation loader contracts explicit.
3. Future peripheral command: `iverilog -g2012 -s tcm_router_tb -c Synthesis/flist_tcm_router_tb.f -o reports/simulation/<id>/tcm_router.vvp`, then `vvp reports/simulation/<id>/tcm_router.vvp`. Expected after repairs: no implicit nets; exact golden/ordering checks pass, deliberate invalid images fail. Create destination/manifest through repaired runner, not these shorthand commands alone.
4. Use real compiled firmware. Require .data sentinel check/copy from ELF load address plus .bss zero check. Interrupt canaries must exercise registers live across IRQ, check expected cause/count, record interrupted/resumed PC or equivalent independent control-flow proof, and confirm mret restores status/context.
5. Future command: `powershell -File scripts/run_sim.ps1`. If Icarus cannot elaborate pinned upstream features, record the failure and reuse upstream-supported simulation flow; do not switch to harness and call it real-core boot.
6. Acceptance: complete five-case census + independent data/context checks + exact ELF/image/source hashes, and negative cases (missing image, corrupt sentinel, broken mret/context) rejected. End the first implementation milestone here.

## Task 5: Prove acquisition and DSP separately (R4/R7/R8)

**Files:** Modify `Simulation/spi_master_tb.sv`, `RTL/ecg_soc/spi_master.sv`, `spi_master_apb.sv`, `Firmware/dsp/ecg_fir_pulp.S`, `fir_reference.c`, `dsp_test.c`, `Firmware/Makefile`; create `Simulation/run_spi.ps1` and `reports/benchmarks/dsp/<id>/` manifests.

1. Replace unsupported int32_t in SV with `int signed`; exact72 SCLK sampling edges within one CS interval. Freeze nominal divider meaning, test odd/even dividers and Mode1 setup/hold against a cited datasheet. Preserve full72-bit golden, signed CH1=1193046 and CH2=-74566, DRDY/frame-valid and busy/drop behavior. Acceptance requires a new revision-bound run, not the old smoke log.
2. Future command: `powershell -File Simulation/run_spi.ps1` (create gated runner first). Expected: golden frame and timing census; missing DRDY, wrong byte, extra/missing edge fail nonzero.
3. Define fixed-point contract: 45 taps, accumulation width/bound, rounding, saturating output, odd tail and packing/alignment. Do not silently retain a “linear-phase 0.5–40 Hz” label for unverified coefficients.
4. Fix XPULP ADDI with `li t5, 16384; add a3, a3, t5`; verify aliases/hardware-loop boundary against pinned compiler/manual. Match kernel arithmetic to contract including saturation. Reuse compatible upstream/compiler tests.
5. Add `dsp-test` build/run recipe. Call actual `ecg_fir_pulp(samples, coeffs, 22)` and compare against scalar for zero/impulse/step/extrema/random/tail. Mutate tap45 and accumulator to ensure tests reject. Overflow test calls production detector, not a copied expression.
6. Future command: `make -C Firmware dsp-test` using explicitly pinned compiler/runner. Expected exact equality for both RV32IM and XPULP builds; retain actual objdump proving SIMD instructions. Host branch cannot claim mcycle; fail/NOT_VERIFIED when counter unavailable. Measure actual kernel with stated overhead and wrap handling, never unconditional PASS or prefilled cycle target.

## Task 6: Prepare FPGA campaign after functional gates (R9)

**Files:** Modify `RTL/ecg_soc/fpga/ecg_arty_top.sv`, `Synthesis/fpga/ecg_artix7/run_synth.tcl`, `run_fpga.ps1`, `run_fpga.sh`, `arty_a7_100t.xdc`.

1. Resolve image relative to explicit project root for both memory initialization and preflight. Fail on missing core/image; remove misleading standalone verification message. Review upstream-supported clock gate adaptation in wrapper/filelist.
2. Correct simulation clock model50 MHz; verify physical generated clock20 ns from oscillator10 ns. Record official board/XDC revision and I/O assumptions, source/image hashes.
3. Add direct routed hierarchy/utilization, min/max timing with unconstrained census, check_timing, DRC and routed checkpoint reports. Keep all failures, and report setup/hold separately.
4. Future command: `powershell -File Synthesis/fpga/ecg_artix7/run_fpga.ps1`. Expected only after actual terminal run: exact top/part/source identity, completed route, complete setup/hold/unconstrained counts with reviewed constraints, DCP. Until then timing/PPA remain NOT_VERIFIED.
5. Board UART → SPI loopback → physical AFE → continuous stream comes after matched routed acceptance. MAMBA/ASIC and clinical claims stay deferred.

## Recommended next scope

Execute Tasks1–4 only when implementation is requested. Deliver one trustworthy boot/data/IRQ campaign using the already cloned core. Then acquisition and measured DSP, then FPGA. No full-core/SoC rewrite is required; no commands in this plan count as executed evidence.
