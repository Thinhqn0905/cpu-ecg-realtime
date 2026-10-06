# Checklist Management

## Active Checklist
`Instruction/session_checklist.md` — always the current active checklist.

## Naming Convention
- Active: `session_checklist.md` (in `Instruction/`)
- Future: `checklist_<N>.md` (in `Instruction/checklists/`)
- Archived: `Instruction/archive/YYYYMMDD_HHMM/session_checklist_v<N>.md`

## Numbering
- checklist_0: CVA6 Core Bring-Up on Artix-7
- checklist_1: SPI Master + ECG AFE Interface
- checklist_2: (future) ECG Data Streaming Pipeline
- checklist_3: (future) Signal Processing + R-Peak Detection
- checklist_4: (future) Multi-Channel + ADS1298 Support
- checklist_5: (future) Hardware Accelerators (if needed)
- checklist_6: (future) Documentation + Publication

## Retention Policy
- Keep all archived checklists that contain unique evidence references.
- Do not automatically prune archives.
- Archive before replacing the active checklist.

## Status Values
- `pending` — not started
- `in_progress` — actively being worked on
- `complete` — finished with evidence link

## Rules
- A checklist is NOT evidence. Every completed item must link to a raw
  artifact (synthesis report, simulation log, board transcript, etc.).
- Do not mark items complete without verifiable evidence.
- Preserve failed attempts — they are valuable negative evidence.
