#!/usr/bin/env bash
# Copyright 2026 RISC-V ECG Project
# SPDX-License-Identifier: Apache-2.0
#
# Compile and Run Full CV32E40P ECG SoC Co-Simulation with Icarus Verilog
# Enforces strict exit code propagation and evidence validation per Instruction/claim_integrity.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$WORKSPACE_ROOT"

RUN_ID="$(date -u +"%Y%m%d_%H%M%S")"
OUT_DIR="reports/simulation/run_${RUN_ID}"
mkdir -p "$OUT_DIR"

VVP_OUT="$OUT_DIR/soc_tb.vvp"
COMPILE_LOG="$OUT_DIR/compile.log"
SIM_LOG="$OUT_DIR/soc_tb.log"
JSON_OUT="$OUT_DIR/sim_results.json"

echo "================================================================"
echo "  CV32E40P ECG SoC CO-SIMULATION RUNNER                        "
echo "  Run ID:    $RUN_ID"
echo "  Workspace: $WORKSPACE_ROOT"
echo "  Output:    $OUT_DIR"
echo "================================================================"

# Verify iverilog tool availability
if ! command -v iverilog >/dev/null 2>&1; then
    echo "[FAIL] iverilog executable not found in PATH." >&2
    exit 127
fi

if ! command -v vvp >/dev/null 2>&1; then
    echo "[FAIL] vvp executable not found in PATH." >&2
    exit 127
fi

echo "[1/4] Compiling SystemVerilog source tree..."
compile_exit=0
iverilog -g2012 -Wall -Wno-timescale \
    -I cv32e40p/rtl/include \
    -I cv32e40p/bhv \
    -I cv32e40p/bhv/include \
    -I RTL/ecg_soc \
    -s soc_tb \
    -o "$VVP_OUT" \
    -c Synthesis/flist_cv32e40p_soc.f \
    Simulation/ads1292r_model.sv \
    Simulation/soc_tb.sv > "$COMPILE_LOG" 2>&1 || compile_exit=$?

if [ "$compile_exit" -ne 0 ]; then
    echo "[FAIL] Compilation failed with exit code $compile_exit" >&2
    cat "$COMPILE_LOG" >&2
    cat <<EOF > "$JSON_OUT"
{
  "run_id": "$RUN_ID",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "tool": "$(iverilog -V | head -n 1)",
  "compile_exit": $compile_exit,
  "simulation_exit": -1,
  "log_file": "$COMPILE_LOG",
  "artifacts": []
}
EOF
    exit "$compile_exit"
fi
echo "[PASS] Compilation successful."

echo "[2/4] Executing Co-Simulation..."
sim_exit=0
vvp "$VVP_OUT" > "$SIM_LOG" 2>&1 || sim_exit=$?

# Display simulation log
cat "$SIM_LOG"

echo "[3/4] Generating Run Evidence Manifest with SHA-256 digests..."
python3 -c "
import json, hashlib, sys
from pathlib import Path

def hash_file(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()

out = {
    'run_id': '$RUN_ID',
    'timestamp': '$(date -u +"%Y-%m-%dT%H:%M:%SZ")',
    'compiler': '$(iverilog -V | head -n 1)',
    'runtime': '$(vvp -V | head -n 1)',
    'compile_exit': $compile_exit,
    'simulation_exit': $sim_exit,
    'log_file': '$SIM_LOG',
    'artifacts': [
        {'path': '$VVP_OUT', 'sha256': hash_file('$VVP_OUT')},
        {'path': '$COMPILE_LOG', 'sha256': hash_file('$COMPILE_LOG')},
        {'path': '$SIM_LOG', 'sha256': hash_file('$SIM_LOG')}
    ]
}
with open('$JSON_OUT', 'w', encoding='utf-8') as f:
    json.dump(out, f, indent=2)
"

if [ "$sim_exit" -ne 0 ]; then
    echo "[FAIL] Simulation failed with exit code $sim_exit. Failure manifest saved to $JSON_OUT" >&2
    exit "$sim_exit"
fi

echo "[4/4] Validating Evidence Gate with check_evidence.py..."
python3 scripts/check_evidence.py "$JSON_OUT" TC-BOOT-001 TC-DATA-002 TC-TIMER-003 TC-MRET-004 TC-DONE-005 --run-id "$RUN_ID"

# Link latest run only after gate pass
mkdir -p "reports/simulation/latest"
cp "$JSON_OUT" "reports/simulation/latest/sim_results.json"
cp "$SIM_LOG" "reports/simulation/latest/soc_tb.log"

echo "[SUCCESS] Simulation run verified and accepted cleanly. Manifest saved to $JSON_OUT."
