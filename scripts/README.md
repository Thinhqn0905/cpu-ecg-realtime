# Scripts Directory: Evidence Gate & Automation Infrastructure

This directory contains the verification enforcement engine, cryptographic integrity validators, and automated regression runners for the CV32E40P RISC-V Real-Time ECG SoC.

---

## Directory Hierarchy

```
scripts/
├── check_evidence.py                # Strict 10-gate cryptographically-signed evidence validator
├── test_evidence_gate.py            # Unit tests for evidence rejection rules (13 test cases)
├── test_runner_contract.py          # Unit tests for runner contract enforcement (11 test cases)
├── test_firmware_build_contract.py  # Unit tests for toolchain integrity & fallback prevention (2 test cases)
├── run_sim.ps1                      # Master PowerShell regression runner
├── run_sim.sh                       # Master Bash regression runner
├── clone_repos.ps1                  # PowerShell helper for cloning reference repositories
└── clone_repos.sh                   # Bash helper for cloning reference repositories
```

---

## 1. The Evidence Gate Validator (`check_evidence.py`)

Per `Instruction/claim_integrity.md`, status claims in the RTM dashboard cannot transition to `PASS (Sim)` without surviving the strict automated gate checker. It inspects compile logs, simulation logs, JSON results manifests, and SHA-256 hashes against 10 strict rejection gates:

| Gate | Name | Rule Enforced | Rejection Trigger |
|------|------|---------------|-------------------|
| **Gate 1** | Non-Zero Exit Code | Compilation and simulation processes must return exit status `0`. | Non-zero exit code in compile or simulation. |
| **Gate 2** | Stale Run ID | Artifact timestamps must match the active campaign timestamp. | Timestamp mismatch between directory and manifest. |
| **Gate 3** | Corrupted Artifact Hash | Computed SHA-256 must match recorded manifest hash. | Any byte modification in `.log` or `.json` file. |
| **Gate 4** | Missing / Empty Artifact | Required log files must exist and contain $>0$ bytes. | File missing or file size $= 0$ bytes. |
| **Gate 5** | Incomplete Census | All expected test cases for a suite must report a verdict. | Missing test case IDs (e.g. 8 of 9 reported). |
| **Gate 6** | Unsolicited Fatal Event | Simulation must not terminate via unhandled `$fatal`. | Any `$fatal` event outside designated error tests. |
| **Gate 7** | Missing Interrupt Test | Interrupt firing and handler execution must be explicit. | Omission of IRQ line activation assertions. |
| **Gate 8** | Duplicate Test Identifier | Each test case identifier must appear exactly once. | Repeated `[PASS] TC-...` occurrences in log. |
| **Gate 9** | "Complete-Only" Log | Summary completion lines without individual test tags are rejected. | Log ends with "PASSED" but lacks per-test verdicts. |
| **Gate 10**| Hard Build Contract | Firmware builds must fail hard when the toolchain is absent. | Silent fallback to mock or synthetic hex data. |

### Running the Evidence Validator
```powershell
python scripts/check_evidence.py --manifest reports/simulation/sim_manifest.json --strict
```

---

## 2. Gate Infrastructure Unit Tests

Before any simulation campaign is executed, the gate checker itself is verified to ensure it reliably rejects invalid or tampered evidence:

```powershell
# Run all 26 verification contract unit tests
python -m unittest discover -s scripts -p "test_*.py" -v
```

### Test Suite Breakdown:
- **`test_evidence_gate.py` (13 tests)**:
  - `test_accepted_run_happy_path`: Validates standard compliant run directory.
  - `test_rejected_complete_only_log`: Rejects logs without atomic test verdicts.
  - `test_rejected_corrupted_artifact_hash`: Detects modified log content.
  - `test_rejected_duplicate_testcase`: Catches duplicate test case IDs.
  - `test_rejected_empty_log`: Detects zero-length log output.
  - `test_rejected_fatal_outside_tc_event`: Catches unhandled `$fatal`.
  - `test_rejected_missing_irq_case`: Detects omitted interrupt test cases.
  - `test_rejected_nonzero_compile_exit`: Rejects compiler failure with fake log.
  - `test_rejected_nonzero_simulation_exit`: Rejects simulation crash.
  - `test_rejected_stale_run_id`: Rejects recycled run directories.
  - `test_rejected_testcase_failure`: Rejects logs containing `[FAIL]`.
- **`test_runner_contract.py` (11 tests)**:
  - Verifies runner process trapping, timeout handling, and JSON schema output.
- **`test_firmware_build_contract.py` (2 tests)**:
  - Verifies that `build_boot_image.py` exits with hard failure when `riscv32-unknown-elf-gcc` is missing, preventing synthetic hex substitution.

---

## 3. Automated Simulation Runners

- **`scripts/run_sim.ps1`**:
  - Compiles the full SoC testbench (`Simulation/soc_tb.sv`) with `Synthesis/flist_cv32e40p_soc.f`.
  - Executes Icarus Verilog `vvp` engine.
  - Extracts test case verdicts (`TC-SYS-001` through `TC-SYS-017`).
  - Generates immutable run directory under `reports/simulation/run_YYYYMMDD_HHMMSS/`.
  - Computes SHA-256 digests and writes `sim_results.json`.
  - Invokes `scripts/check_evidence.py` to validate gate compliance.
