# Session Checklist V2 (checklist_2): Source Review and Implementation Planning

Worktree: E:\ResearchOnWork\RISC_V_CORE.
Goal: Review ECG source direction and produce a writing-plans implementation
plan. User clarified that running code is outside this goal.

Previous checklist: `Instruction/archive/20261006_0042/session_checklist.md`.
Existing checklist_1 and RTM snapshots are also preserved in that archive.

- [complete] Task 2.1: Read mandatory contracts, spec, configuration and RTL.
  Findings: `reports/review/2026-10-06-source-audit/source_review.md`.
- [complete] Task 2.2: Identify architecture and evidence inconsistencies.
  Source identity: `reports/review/2026-10-06-source-audit/manifest.json`.
  Earlier limited compile/smoke/lint runs are preserved there; they are not
  full-SoC or board acceptance evidence.
- [complete] Task 2.3: Write exact-file, ordered implementation tasks using
  writing-plans: `docs/plans/2026-10-06-ecg-soc-baseline-recovery.md`.
- [complete] Task 2.4: Record planning-only scope and defer implementation.
  Scope recorded in the plan's audit-input and execution-handoff paragraphs.

No implementation or hardware gate is completed by this checklist. Core boot,
synthesis, routing, AFE communication and ECG streaming remain NOT_VERIFIED.
Future implementation starts a new numbered checklist.

Read Instruction/claim_integrity.md before reporting or completing a gate.
Every status update requires terminal artifacts and raw locators.
