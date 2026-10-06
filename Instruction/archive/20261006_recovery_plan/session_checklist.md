# Session Checklist V4 (checklist_4): Gemini Static Audit and Recovery Plan

Worktree: E:\ResearchOnWork\RISC_V_CORE
Goal: Audit existing Gemini source/results and write a minimal reuse-first recovery plan.
Boundary: source and existing-artifact inspection only; no compilation, simulation, synthesis or board reruns.

Previous Gemini checklist is preserved at `Instruction/archive/20261006_gemini_audit/session_checklist.md`.
Its claimed implementation gates have not been accepted by this audit.

- [complete] Task 4.1: Read mandatory contracts and inspect existing source, scripts and reports.
  Evidence: `reports/review/2026-10-06-gemini-audit/audit_manifest.json` (source hashes and artifact inventory).
- [complete] Task 4.2: Compare claims with actual bindings, firmware, test logic and result provenance.
  Evidence: `reports/review/2026-10-06-gemini-audit/audit.md`, findings A1-A11.
- [complete] Task 4.3: Preserve original benchmark/RTM/manifest and produce recovery plan.
  Evidence: original copies in the audit directory; `docs/plans/2026-10-06-gemini-audit-recovery.md`.

No functional, DSP, routed FPGA, ASIC PPA or clinical gate is completed by this checklist.
Current unsupported numerical claims are NOT_VERIFIED; direct source contradictions are named in audit.md.
Next implementation scope, when requested: recovery plan Tasks 1-2, real-core firmware boot and IRQ proof.
Read `Instruction/claim_integrity.md` before reporting or updating evidence gates.
