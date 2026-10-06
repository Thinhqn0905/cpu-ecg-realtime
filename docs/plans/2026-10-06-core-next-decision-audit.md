# Core Next Decision Audit Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Give gem_implement_core an auditable decision path to retain CV32E40P, prove the 50 MHz baseline and measure real DSP kernels before claiming model inference or offload.

**Architecture:** Reuse immutable core HEAD 97086e9565f8145522ad6d62852123c0e5537529 and current OBI/APB/peripheral wrappers. Isolate diagnostic MAMBA behavior, keep128 KiB D-TCM in the initial control and preserve the current routed negative evidence. Resume model/offload development only with an exact graph, quantization, memory and measured workload contract.

**Tech Stack:** Pinned CV32E40P, explicit RV32IMC and compatible CORE-V toolchains, SystemVerilog/XSIM, Python unittest, existing Vivado2023.2 Artix-7 flow.

---

Use @writing-plans. Input audit: `reports/review/2026-10-06-core-next-decision-audit/audit.md` D1–D9 and manifest. Root inspected HEAD d165987; clean before documentation edits. This is a **plan, not execution evidence**: none of the build/test/tool commands below ran in this audit. Preserve failed runs. Scope given to gem_implement_core next: **Tasks 1–3 only**, then return a decision report. Tasks 4–6 are gated backlog; do not interpret them as permission to publish results or program the board. Existing V3 FULLGO and V9 done labels are superseded by this decision.

## Task 1: Correct decision claims and make acceptance fail closed

**Files:** Modify `scripts/check_evidence.py`, `scripts/test_evidence_gate.py`, `scripts/test_runner_contract.py`, `scripts/run_sim.ps1`, `scripts/run_sim.sh`, `Synthesis/fpga/ecg_artix7/run_fpga.ps1`, `run_fpga.sh`, `run_synth.tcl`, `reports/benchmark/tri_modal_resumamba_report.md`, `reports/verification/rtm_dashboard.md`, `reports/manifest.json`, `Instruction/session_checklist.md`; create `scripts/check_fpga_evidence.py`, `scripts/test_fpga_evidence.py`, `reports/verification/current_requirement_census.json`.

**Step 1:** Archive modified documents and all referenced run artifacts with hashes. Add dated correction: latest route completed but setup FAIL; bridge/cascade diagnostic stub; host reference and partial-float parity only. Preserve older positive and negative reports. Capture actual core describe/HEAD rather than a substituted release tag.

**Step 2:** Reconcile every RTM ID to canonical JSON and a check that actually tests its predicate. In census record `requirement_id`, `spec_revision`, `test_id`, `boundary`, `run_id`, `observed_assertion`, `status`, `reason`. Mark packetCRC/end-to-end latency/SVA/model claims NOT_VERIFIED until appropriate checks exist. Version intentional divider/DMA changes with rationale, do not silently weaken acceptance.

**Step 3:** Add negative fixture tests for the actual D1 routed summary (WNS−0.815, TNS−63.389,215 failures) with exit0 and a nonempty bitstream, missing/optional hash, source/boot mismatch, stale snapshot, assertion error and missing report. Fixture names: `test_exit_zero_negative_setup_rejected`, `test_positive_hold_cannot_mask_setup_failure`, `test_missing_source_hash_rejected`, `test_sva_error_rejected`.

Future command: `python -m unittest discover -s scripts -p 'test_*evidence*.py' -v`. Expected before repair: new cases expose acceptance holes. Store observed result, not prefilled expected PASS.

**Step 4:** Implement explicit gate predicate from parsed report values:

```python
def accept_timing(summary):
    return (
        summary['route_complete'] is True
        and summary['compute_period_ns'] == 20.0
        and summary['wns_ns'] >= 0 and summary['tns_ns'] == 0
        and summary['setup_failing_endpoints'] == 0
        and summary['whs_ns'] >= 0 and summary['ths_ns'] == 0
        and summary['hold_failing_endpoints'] == 0
        and summary['unconstrained_internal_endpoints'] == 0
        and summary['io_contract_reviewed'] is True
        and summary['drc_review_complete'] is True
    )
```

Reject absent/ambiguous census fields before invoking predicate. Parse global and all clock-pair groups; verify exact top/part/source/XDC/Tcl/ELF/image/run hashes. Do not make approval booleans arbitrary CLI bypasses: each must link a concrete reviewed report/contract. Emit `ROUTED_COMPLETE`, `TIMING_FAIL`, `NOT_VERIFIED` and `ACCEPTED` separately.

**Step 5:** Run future fixtures again; require intentional-negative rejection. Invoke FPGA evidence gate before runner SUCCESS. Use run-local output directory and archive-relative paths rather than mutable root reports; save failed manifests before nonzero exit. Simulation hash schema mandatory, stdout/stderr separate, bound source/filelists/tool flags/snapshot/firmware; add wall timeout. Do not replace empty native stdout with invented compiler output.

Future raw-report check after creating CLI: `python scripts/check_fpga_evidence.py --manifest Synthesis/fpga/ecg_artix7/reports/run_20261006_093347/fpga_manifest.json --expect-period-ns 20`. Expected exit nonzero with negative-setup reason; legacy missing schema also rejected with its own reason. No Vivado rerun is required for this negative fixture.

**Step 6:** Review diff and commit only the task files: `git diff --check`, `git diff --stat`, then explicit-path `git add`/commit after actual tests pass. Never commit a claim from anticipated output.

## Task 2: Establish a clean real-core baseline independent of model stubs

**Files:** Modify `RTL/ecg_soc/cv32e40p_ecg_soc_top.sv`, `RTL/ecg_soc/fpga/ecg_arty_top.sv`, `Firmware/boot/hello.c`, `Firmware/build_boot_image.py`, `scripts/run_sim.ps1`, `Simulation/soc_tb.sv`, `RTL/ecg_soc/tcm_sram.sv`; create `config/core_baseline.json`, `scripts/test_core_baseline_contract.py`. Keep `mamba_bridge.sv`/sidecar history unchanged unless fixing a clearly labeled experiment.

**Step 1:** Define named baseline: real core1, COREV_PULP1, MAMBA0, I32768,D131072, compute 50 MHz, pinned current HEAD. Propagate MAMBA selection explicitly through FPGA and simulation wrappers; do not switch upstream or silently synthesize a harness.

**Step 2:** Separate boot/data/IRQ hello from cascade diagnostic using explicit build configuration; production default omits fixed RR/class checks. Retain current cascade log under `diagnostic_stub`. Baseline runner expects only five boot cases; diagnostic runner has its own six-case census and excludes inference claims.

**Step 3:** Add image/source/runtime negative tests: missing/corrupt image, wrong sentinel, broken context restoration, second transaction during APB wait, last-valid/first-invalid D-TCM addresses. TCM firmware image may load only into its intended RAM; plusarg must not initialize D-TCM with the I image. Keep native firmware compile logs/version/flags and ELF→bin→hex checks in the run.

**Step 4:** Future commands, after fixture repair:

```powershell
python Firmware/build_boot_image.py
powershell -File scripts/run_sim.ps1 -Simulator vivado
powershell -File Simulation/run_tcm.ps1
```

Expected: source-bound real ELF/image; five boot events with data/bss/canary checks and actual IRQ/mret observation; extended memory/router checks pass. Negative variants fail nonzero. Do not claim all ISR registers from callee-saved-only canaries; inspect current disassembly and add caller-saved liveness/context assertions. XSIM simulated duration is distinct from wall duration; current boot text takes milliseconds, so remove V3 `<100 us` promise unless UART workload changes deliberately.

**Step 5:** Acceptance: narrow real-core boot/data/IRQ and memory smoke, with immutable source bundle, actual artifacts and rejected negative cases. Report remaining acquisition/CRC/model exclusions. Commit reviewed local baseline changes; verify `git -C cv32e40p status --short` stays empty.

## Task 3: Close matched routed timing at 50 MHz

**Files:** Modify `Synthesis/fpga/ecg_artix7/run_synth.tcl`, `run_fpga.ps1`, `run_fpga.sh`, `arty_a7_100t.xdc`; create `reports/evidence/core_50mhz/current.md`, `reports/evidence/core_50mhz/experiments.json`, `reports/evidence/core_50mhz/io_contract.md`. Use wrapper adaptations only; upstream core immutable.

**Step 1:** First preserve latest expanded candidate as rejected reference. Capture full core/local source fingerprint, hierarchy, image, XDC, tool and command recipe. Baseline Task 2 differs intentionally by disabling stub; do not use old16-BRAM control as if identical to128-KiB candidate.

**Step 2:** Review latest worst path family around `alu_operator_ex_o_reg`→multiply operands, with logic/routing/fanout and clock uncertainty. Review BRAM reset-control DRC (report capped at 20 REQP-1839), clock gating replacement and all I/O timing/exclusions. No false-path/multicycle exception on the core compute path without functional proof.

**Step 3:** Establish one reproducible control at 20 ns. Future command: `powershell -File Synthesis/fpga/ecg_artix7/run_fpga.ps1`. Expected result may be FAIL; gate must preserve it and return nonzero rather than call bitstream generation closure.

**Step 4:** Try one bounded implementation candidate per control, first physical optimization/placement options with fixed RTL/source/XDC/ELF. A direct post-route `phys_opt_design -directive AggressiveExplore` followed by required re-route is a candidate to evaluate, not a promise of closure. Capture command transcript and reports in a separate run; do not retain results from any failed command hidden by `catch` as if that step succeeded.

**Step 5:** For each candidate produce direct `report_timing_summary -delay_type min_max -report_unconstrained`, `check_timing -verbose`, routed hierarchy/utilization/DRC and DCP. Parse full global/clock-pair setup/hold census. Reject a candidate if global WNS regresses even when a named path/TNS improves. Accept only complete zero-violation setup/hold at 50 MHz and justified I/O/DRC coverage.

**Step 6:** If unable to close with wrapper/implementation work, return measured options and retained negative runs for the next decision. Keep requirement 50 MHz visible; don't call48.04 MHz estimate a pass. A new core or upstream modification requires explicit rationale/comparison and is not the default next action.

**Return gate:** At completion of Tasks 1–3, gem_implement_core returns actual manifests/checks and a GO/NO_GO table. Board programming waits for a separately authorized bring-up task after timing acceptance.

## Task 4: Measure actual scalar and DSP kernels before utilization claims

**Gate:** Baseline/provenance fixed; target firmware build/runtime usable. Timing FAIL blocks physical-board performance claims, but a separately labeled RTL-simulation cycle campaign may proceed.

**Files:** Modify `Firmware/Makefile`, `Firmware/dsp/dsp_test.c`, `ecg_fir_pulp.S`, `resumamba_kernels_pulp.S`; create `Firmware/dsp/kernel_benchmark.c`, `scripts/test_target_dsp_contract.py`, `reports/benchmarks/core_dsp/current.md`.

**Step 1:** Host reference tests explicitly SKIP target assembly/cycles; never compare a host stub to its own reference and call that assembly equality.
**Step 2:** Build two explicit firmware configurations: baseline RV32IMC and verified CORE-V/PULP mnemonic variant. Reuse upstream-compatible compiler probes; save tool versions, flags and objdump with actual custom instructions. Test odd45th tap, saturation/rounding, packed alignment, random/extrema/impulse vectors against an independently frozen integer reference.
**Step 3:** Wire benchmark to actual production kernel; measure mcycle before/after with counter overhead/wrap handling, exact vectors and trace. Unsupported counters/ISA fail or SKIP rather than fabricated0/PASS.
**Step 4:** Future command: `make -C Firmware dsp-test` after repairing target runtime/stdio support. Current `-nostdlib` recipe must not be assumed capable of printf/malloc. Add gated DSP runner with independent ELF/image/testcase identity; save result as simulation cycles or board cycles according to actual boundary.
**Step 5:** Withdraw12.718M cycles/<0.2%/speedup claims until measurements exist. Use profiling to decide whether offload is required. Do not add another accelerator merely because the prototype file exists.

## Task 5: Freeze exact ResUMamba graph/scales/memory before implementation

**Files:** Modify `scripts/quantize_resumamba.py`, `scripts/test_quantization_parity.py`, `Firmware/dsp/resumamba_infer.c`, `test_resumamba_infer.c`, `Firmware/boot/link.ld`; create `spec/resumamba_integer_contract.json`, `scripts/test_frozen_integer_contract.py`, `Firmware/dsp/resumamba_scales.h`, `reports/benchmarks/resumamba/current.md`.

**Step 1:** Reuse the referenced checkpoint/model, freeze hashes and constructor spec, list every layer/tensor/shape/nonlinearity/padding/branch and output. Keep sequence500×4 output semantics; do not replace it with the report's unrelated GAP classifier.
**Step 2:** Export per-layer weight/activation/bias scales and requant multipliers/shifts with integer reference; test reads frozen headers and must not regenerate them. Missing/changed tensor or scale fails. Rename current partial-float sensitivity experiment accurately.
**Step 3:** Add layer equality tests that call actual C with frozen same-ID inputs and compare all outputs; negative tensor mutation must fail. Restore learned ResU, SSM projections/prefilter and fusion incrementally from reused model. Context/rhythm optionality follows pinned model config; missing layer remains NOT_IMPLEMENTED rather than a smoothing replacement called parity.
**Step 4:** Produce static liveness arena and actual inference ELF map. Current184,000-byte allocation peak and44,492-byte parameter payload are blockers. Select explicit memory reuse/storage layout within available memories; validate heap/stack/model fit using linker ASSERTs and high-water checks. Do not keep unchecked calloc in a4-KiB heap. Memory expansion requires FPGA resource/timing revalidation.
**Step 5:** Future command: `python -m unittest discover -s scripts -p 'test_frozen_integer_contract.py' -v`; expected layer/header/scale mutations rejected. Run actual target inference only after memory/layer gates. Report FP32 agreement separately from labeled-data accuracy and clinical claims.

## Task 6: Conditional FIR/offload and real acquisition integration

**Gate:** Task 4 measured need for offload; Task 5 integer primitive/scales frozen; baseline resources/timing documented. Otherwise defer.

**Files:** Modify `RTL/ecg_soc/mamba_fir_sidecar.sv`, `mamba_bridge.sv`, `ecg_soc_top.sv`, `Simulation/mamba_fir_tb.sv`, `Simulation/soc_tb.sv`, `Firmware/boot/hello.c`; create `Simulation/run_mamba_fir.ps1`, `reports/evidence/mamba_fir/current.md`.

**Step 1:** Define actual primitive: channels 24, channel-specific128 taps, forward/backward boundary semantics, input/output counts, sequence ownership, scale and saturation. Bidirectional future samples need window buffering or a documented scheduling contract.
**Step 2:** Test exact output for all channels, reset/restart, signed extrema and randomized ready stalls; output must remain stable until accepted. Remove DONE/nonzero-energy shortcuts. Load frozen trained coefficients; generated placeholder coefficients stay a separately labeled toy test.
**Step 3:** Connect real data/source reads/output writes and instantiate sidecar in SoC. Unsupported full-inference opcode returns explicit error/NOT_IMPLEMENTED rather than a fixed class. Routed hierarchy must show the intended instance and mapped DSP resources.
**Step 4:** Future command: `powershell -File Simulation/run_mamba_fir.ps1` after creating gated runner. Require matching500-step raw latency and exact integer golden, not extrapolated16-step measurement labeled measured.
**Step 5:** Replace fabricated cascade RR list with actual captured sample processing/production detector, ring ownership and frozen inference. Check sampleID/order, CRC8, drop/overflow and DRDY→UART timestamps; a class marker alone cannot pass acquisition/latency. New RTL/memory/image changes invalidate old routed acceptance and trigger Task 3 again.

## Decision to hand to gem_implement_core now

**Keep the cloned CV32E40P. Execute Tasks 1–3, return evidence, then decide measured DSP/model/offload work.** Current50 MHz setup acceptance: FAIL. Current model/cascade functionality: NOT_VERIFIED/diagnostic stub. Current source/artifact improvements and retained boot smoke: useful, preserved. No complete SoC rewrite, core switch, clinical claim or board programming is required by this plan.
