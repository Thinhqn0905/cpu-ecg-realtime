#!/usr/bin/env bash
# Copyright 2026 RISC-V ECG Project
# SPDX-License-Identifier: Apache-2.0
#
# Vivado Batch Execution Runner for CV32E40P ECG SoC on Arty A7-100T
# Enforces strict exit code propagation per Instruction/claim_integrity.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RUN_ID="$(date -u +"%Y%m%d_%H%M%S")"
OUT_DIR="$SCRIPT_DIR/reports/run_${RUN_ID}"
mkdir -p "$OUT_DIR"

echo "================================================================"
echo "  VIVADO FPGA IMPLEMENTATION & TIMING CLOSURE RUNNER           "
echo "  Run ID: $RUN_ID"
echo "  Target: Digilent Arty A7-100T (xc7a100tcsg324-1)              "
echo "================================================================"

if ! command -v vivado >/dev/null 2>&1; then
    echo "[FAIL] Vivado executable not found in PATH." >&2
    exit 127
fi

vivado_exit=0
vivado -mode batch -source run_synth.tcl -notrace || vivado_exit=$?

if [ "$vivado_exit" -ne 0 ]; then
    echo "[FAIL] Vivado execution failed with exit code $vivado_exit" >&2
    exit "$vivado_exit"
fi

echo "[SUCCESS] Vivado Implementation complete with exit code 0."
