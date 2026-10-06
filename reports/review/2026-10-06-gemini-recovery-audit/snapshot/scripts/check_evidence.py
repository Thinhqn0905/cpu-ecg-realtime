#!/usr/bin/env python3
"""
Evidence Gate Validator for RISC-V ECG SoC Project
Mandatory checks per Instruction/claim_integrity.md and docs/plans/2026-10-06-gemini-audit-recovery.md

Ensures no false-success runs are accepted:
- Rejects missing tools / nonzero exits
- Enforces exact census of expected testcases
- Requires all expected artifacts to exist on disk as non-empty files
- Rejects logs with duplicates or missing expected cases
"""

import sys
import os
import re
import json
import hashlib
from pathlib import Path
from typing import Dict, List, Set, Optional, Tuple, Any


def calculate_sha256(filepath: Path) -> str:
    """Calculate SHA-256 hex digest of a file."""
    h = hashlib.sha256()
    with open(filepath, 'rb') as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()


def parse_test_events(log_content: str) -> Tuple[Dict[str, str], List[str]]:
    """
    Parse test events from simulation log content.
    Returns:
        observed: Dict mapping testcase name to outcome ('PASS', 'FAIL', etc.)
        duplicates: List of testcase names that appeared more than once
    """
    observed: Dict[str, str] = {}
    duplicates: List[str] = []

    # Matches patterns like:
    # [PASS] TC-SYS-001: Description
    # [FAIL] TC-SYS-001: Description
    pattern = re.compile(r'\[(PASS|FAIL)\]\s+([A-Za-z0-9_-]+):?')

    for line in log_content.splitlines():
        match = pattern.search(line)
        if match:
            status, tc_id = match.group(1), match.group(2)
            if tc_id in observed:
                duplicates.append(tc_id)
            else:
                observed[tc_id] = status

    return observed, duplicates


def accepted_run(compile_exit: int,
                 simulation_exit: int,
                 expected: Set[str],
                 observed: Dict[str, str],
                 artifacts: List[Path]) -> bool:
    """
    Minimal predicate defined in docs/plans/2026-10-06-gemini-audit-recovery.md.
    """
    return (compile_exit == 0 and simulation_exit == 0
            and bool(expected) and set(observed) == set(expected)
            and len(observed) == len(expected)
            and all(value == 'PASS' for value in observed.values())
            and bool(artifacts) and all(p.is_file() and p.stat().st_size > 0 for p in artifacts))


def validate_run(compile_exit: int,
                 simulation_exit: int,
                 expected_testcases: Set[str],
                 log_path: Optional[Path] = None,
                 log_content: Optional[str] = None,
                 artifacts: Optional[List[Path]] = None) -> Tuple[bool, List[str]]:
    """
    Comprehensive validation of a verification run.
    Returns (is_valid, list_of_errors).
    """
    errors: List[str] = []

    if compile_exit != 0:
        errors.append(f"Compile step failed with exit code {compile_exit}")

    if simulation_exit != 0:
        errors.append(f"Simulation step failed with exit code {simulation_exit}")

    if log_content is None:
        if log_path is None or not log_path.is_file():
            errors.append(f"Simulation log file missing: {log_path}")
            return False, errors
        log_content = log_path.read_text(encoding='utf-8', errors='replace')

    if not log_content.strip():
        errors.append("Simulation log is empty")
        return False, errors

    observed, duplicates = parse_test_events(log_content)

    if duplicates:
        errors.append(f"Duplicate testcase IDs detected in log: {sorted(set(duplicates))}")

    if not expected_testcases:
        errors.append("No expected testcases specified")
    else:
        missing = expected_testcases - set(observed.keys())
        if missing:
            errors.append(f"Missing expected testcases: {sorted(missing)}")

        unexpected = set(observed.keys()) - expected_testcases
        if unexpected:
            errors.append(f"Unexpected testcases observed: {sorted(unexpected)}")

    for tc_id, status in observed.items():
        if status != 'PASS':
            errors.append(f"Testcase {tc_id} reported status {status}")

    if not artifacts:
        errors.append("No required artifacts specified")
    else:
        for p in artifacts:
            if not p.exists():
                errors.append(f"Required artifact does not exist: {p}")
            elif not p.is_file():
                errors.append(f"Required artifact is not a regular file: {p}")
            elif p.stat().st_size == 0:
                errors.append(f"Required artifact is empty (0 bytes): {p}")

    is_valid = len(errors) == 0
    return is_valid, errors


def main() -> int:
    """Command-line entry point for evidence verification."""
    if len(sys.argv) < 3:
        print("Usage: check_evidence.py <run_results.json> <expected_tc1> [expected_tc2 ...]")
        return 2

    results_path = Path(sys.argv[1])
    expected = set(sys.argv[2:])

    if not results_path.is_file():
        print(f"[FAIL] Results file not found: {results_path}")
        return 1

    try:
        data = json.loads(results_path.read_text(encoding='utf-8'))
    except Exception as e:
        print(f"[FAIL] Invalid JSON in {results_path}: {e}")
        return 1

    compile_exit = data.get("compile_exit", 1)
    sim_exit = data.get("simulation_exit", 1)
    log_file = data.get("log_file")
    artifacts = [Path(p) for p in data.get("artifacts", [])]

    log_content = None
    if log_file:
        log_path = Path(log_file)
        if log_path.is_file():
            log_content = log_path.read_text(encoding='utf-8', errors='replace')

    is_valid, errors = validate_run(
        compile_exit=compile_exit,
        simulation_exit=sim_exit,
        expected_testcases=expected,
        log_content=log_content,
        artifacts=artifacts
    )

    if is_valid:
        print("[PASS] Evidence gate validation successful.")
        return 0
    else:
        print("[FAIL] Evidence gate validation rejected run:")
        for err in errors:
            print(f"  - {err}")
        return 1


if __name__ == '__main__':
    sys.exit(main())
