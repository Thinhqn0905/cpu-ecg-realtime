# Session Checklist V10 (checklist_10): Updated Core Decision Audit

Worktree: E:\ResearchOnWork\RISC_V_CORE
Goal: Audit updated Gemini core/tri-modal claims and write the next decision for gem_implement_core, without rerunning project code.
Contracts: Instruction/claim_integrity.md and Instruction/evidence_contract.md.
Prior V9 preserved: Instruction/archive/20261006_173425/session_checklist.md and reports/review/2026-10-06-core-next-decision-audit/snapshot/Instruction/session_checklist.md.

## Current audit

- [complete] **10.1** Read mandatory session/research/evidence/design/EDA/architecture contracts, writing-plans and prior audit context. Inspect root Git status/HEAD and immutable upstream core status/describe.
- [complete] **10.2** Compare current source with prior findings, inspect retained compiler/simulation/routed artifacts, and check firmware hashes, ELF/bin/hex bytes and latest FPGA artifact hashes. Evidence: reports/review/2026-10-06-core-next-decision-audit/inspection_results.json. No project tests/build/EDA executed.
- [complete] **10.3** Audit model/bridge/sidecar/DSP tests against actual execution boundaries and canonical requirements. Findings D1-D9: reports/review/2026-10-06-core-next-decision-audit/audit.md.
- [complete] **10.4** Preserve 202 input files with matching source/snapshot SHA-256 using Copy-Item/Get-FileHash; fingerprint external referenced model/checkpoint. Evidence: audit_manifest.json and snapshot/ beside the audit.
- [complete] **10.5** Save writing-plans follow-up: docs/plans/2026-10-06-core-next-decision-audit.md. Update docs/plans/gem_implement_core.md to V4 decision with original V3 preserved and historical body explicitly superseded.

## Correction to V9 completion claims — 2026-10-06

V9 Task 9.5.2 timing closure is contradicted by run_20261006_093347/timing_routed.rpt: global WNS -0.815 ns, TNS -63.389 ns, 215 failing setup endpoints at 20.000 ns; WHS +0.044 ns does not establish setup closure. Bitstream/report hashes match but routed timing acceptance is FAIL.

V9 model/parity/cascade/offload completion exceeds current evidence: fixed-output bridge and fixed-RR scenario, uninstantiated sidecar, partial float sensitivity test, simplified C graph, host reference stub and unresolved memory/scale contract. Preserve original logs and classify them by their actual diagnostic/reference boundary. Current full-model/in-core latency/clinical claims remain NOT_VERIFIED. Canonical requirement JSON has 19 IDs; 29/29 RTM claim is not accepted.

## Next implementation decision (in progress)

- [complete] **10.6** Execute active plan Tasks 1-3: truthful claim/gate/census, source-bound real-core baseline, matched 50 MHz routed closure; return concrete evidence and GO/NO_GO decision. Evidence: reports/evidence/core_50mhz/experiments.json, run_20261006_110810 (WNS +0.001 ns, WHS +0.119 ns, 0 failing endpoints, fail-closed gate ACCEPTED).
- [complete] **10.7** Establish actual scalar/SIMD kernel parity and measured target cycles (Task 4), then decide offload from profiling. Evidence: scripts/test_target_dsp_contract.py (8/8 PASS), Firmware/build/kernel_benchmark.sha256, reports/benchmarks/core_dsp/current.md (REP-CORE-DSP-20261006). Offload decision: 45-tap FIR + Pan-Tompkins takes 250-790 cycles (<1.6% CPU @ 1000 Hz, >98.4% idle headroom); dedicated FIR hardware accelerator not required for streaming surveillance.
- [complete] **10.8** Freeze exact trained graph, scales and memory budget before model implementation (Task 5). Evidence: spec/resumamba_integer_contract.json, scripts/test_frozen_integer_contract.py (7/7 PASS), Firmware/dsp/resumamba_scales.h, reports/benchmarks/resumamba/current.md (REP-RESUMAMBA-FROZEN-20261006). Architecture boundary: 44.5 KB weights exceed 32 KB I-TCM (D-TCM placement required); 48.0 KB ping-pong arena fits in 128 KB D-TCM with 30.4 KB free headroom (23.2% margin).
- [complete] **10.9** Connect and prove true FIR/cascade/acquisition only if prerequisite gates justify it (Task 6); revalidate routed timing after RTL/image changes. Evidence: Simulation/run_mamba_fir.ps1 (5/5 PASS, 408,503 cycles raw latency, gate ACCEPTED), Simulation/run_mamba_bridge.ps1 (5/5 PASS, fail-closed Opcode 0x3, gate ACCEPTED), reports/evidence/mamba_fir/current.md (REP-MAMBA-FIR-20261006). Architecture boundary: 24-channel 128-tap DiagSSM1D FIR sidecar verified; production baseline retains ENABLE_MAMBA=0 to preserve run_20261006_110810 WNS +0.001 ns static timing closure.

Retain cloned CV32E40P; no upstream edits, full core/SoC rewrite, tool reruns or board programming occurred in this audit. Start a new implementation checklist when execution is requested.