# Instruction Directory: Workspace Operating Rules & Integrity Protocols

This directory contains the foundational operating rules, evidence contracts, architecture specifications, and claim integrity protocols governing development and verification in this workspace.

---

## Directory Hierarchy

```
Instruction/
├── claim_integrity.md           # Mandatory anti-hallucination & evidence verification protocol
├── evidence_contract.md         # Formal verification evidence contracts & gate definitions
├── design_rules.md              # SystemVerilog RTL, FPGA synthesis, and firmware coding standards
├── architecture.md              # Target processor, bus, memory, and peripheral architectural rules
├── eda_script_style.md          # Tool automation rules for Icarus, Vivado, and OpenLane
├── research_spec.md             # Clinical ECG constraints and biomedical domain parameters
├── roadmap.md                   # Multi-phase development roadmap and milestones
├── session_checklist.md         # Active session checklist tracking current sprint goals
├── todo.md                      # Backlog of architectural and verification tasks
├── commands_reference.md        # Reference manual for build, test, and synthesis commands
├── checklists/                  # Reusable procedure checklists
│   ├── README.md
│   ├── checklist_1.md
│   └── checklist_2.md
└── archive/                     # Preserved historical session checklists & evidence snapshots
```

---

## 1. Claim Integrity Protocol (`claim_integrity.md`)

Before reporting any result or marking a verification gate complete:
- **Zero Hallucination / Status Inflation**: Never report a test case as `PASS` based on filelist inclusion, testbench presence, or golden replay. Status `PASS (Sim)` is strictly gated on raw simulation logs with exit code 0.
- **Cryptographic Provenance**: Every run must record commit SHA, toolchain version, command line, raw stdout/stderr, and computed SHA-256 digests.
- **Preservation of Failed Evidence**: Never overwrite or delete failed logs; record corrections and maintain historical auditability.

---

## 2. Evidence Contract (`evidence_contract.md`)

Defines the 10 failure rejection gates enforced by `scripts/check_evidence.py`:
- Rejects non-zero exit codes, stale run IDs, hash mismatches, empty artifacts, incomplete test censuses, unsolicited fatal events, omitted interrupt tests, duplicate test IDs, and synthetic mock fallbacks.

---

## 3. Design Rules & Coding Standards (`design_rules.md`)

- **Synthesizable RTL**: IEEE 1800-2012 SystemVerilog. No `real`, `shortreal`, or DPI math in hardware modules.
- **Clock Domain Boundaries**: Strict single-clock design for the internal core and peripherals (50 MHz MMCM clock). Asynchronous inputs (`drdy_n`, `uart_rx`, `rst_n`) must be dual-rank synchronized.
- **Firmware Standards**: Bare-metal C99 / RV32 assembly. Freestanding, no standard C runtime library dependencies. Stack pointer and vector table strictly aligned.
