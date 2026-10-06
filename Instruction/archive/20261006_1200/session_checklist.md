# Session Checklist V6 (checklist_6): Static audit of Gemini recovery

Worktree: E:\ResearchOnWork\RISC_V_CORE
Goal: Audit V5 recovery source/artifacts and write the next implementation plan without executing project code.
Claim contract: Instruction/claim_integrity.md and Instruction/evidence_contract.md.
Previous checklist preserved: Instruction/archive/20261006_0935/session_checklist.md; exact inspected copy/hash also in the audit snapshot.

## Current audit goal

- [complete] **6.1** Read session/research/evidence/design/EDA/architecture contracts and inspect root Git status (root is not a Git repository).
- [complete] **6.2** Continue inspection of V5 in-progress gate/boot work at the user-authorized static boundary. Review validator/runners/boot artifacts; no unit tests, compiler or simulator executed. Findings R1-R6: reports/review/2026-10-06-gemini-recovery-audit/audit.md.
- [complete] **6.3** Check remaining SPI/DSP/FPGA gaps and unsupported claims. Findings R7-R10 in the same audit; source-authored fixes distinguished from measured gates.
- [complete] **6.4** Preserve 36 inspected files and confirm source/copy SHA-256 equality using PowerShell Copy-Item and Get-FileHash. Evidence: reports/review/2026-10-06-gemini-recovery-audit/audit_manifest.json and snapshot/.
- [complete] **6.5** Write follow-up with exact files, future commands and acceptance criteria: docs/plans/2026-10-06-gemini-recovery-followup.md.

## Dated correction to V5

V5 Task 5.2.5 claimed GCC compilation complete. Current ELF/bin are absent, supplied hashes disagree with actual build files, dump/opcode targets conflict, and the build script substitutes handwritten/mock artifacts on compiler failure. GCC provenance is NOT_VERIFIED; artifact integrity violation is documented in R1/R2. V5 source edits do not establish functional completion. Historical V5 and failed evidence remain preserved.

## Next implementation milestones (pending, not executed in this audit)

- [pending] **6.6** Correct live RTM/report provenance, close runner gate wiring and prove rejection of false-success fixtures (plan Tasks 1-2).
- [pending] **6.7** Produce real compiler ELF/image with validated provenance, repair local binding/memory, demonstrate independently checked real-core boot/data/IRQ (plan Tasks 3-4). V5 execution tasks 5.1.5 and 5.2.6 remain unverified.
- [pending] **6.8** Produce new revision-bound 72-bit SPI timing/data and actual DSP-kernel equivalence/cycle campaigns (plan Task 5).
- [pending] **6.9** Resolve FPGA image/clock/filelist boundary and establish matched routed setup/hold evidence (plan Task 6); board/clinical gates remain NOT_VERIFIED.

No RTL/firmware/EDA implementation changes or execution are implied by checklist completion above. Start a new current implementation checklist when that goal is authorized.
