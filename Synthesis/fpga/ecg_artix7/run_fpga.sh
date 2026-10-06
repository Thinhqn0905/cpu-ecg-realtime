#!/usr/bin/env bash
# Copyright 2026 RISC-V ECG Project
# SPDX-License-Identifier: Apache-2.0
#
# Vivado Batch Execution Runner for CV32E40P ECG SoC on Arty A7-100T
# Enforces strict preflight, artifact hashing, and exit code propagation
# per docs/plans/2026-10-06-gemini-recovery-followup.md (Task 6) and Instruction/claim_integrity.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

RUN_ID="$(date -u +"%Y%m%d_%H%M%S")"
OUT_DIR="${SCRIPT_DIR}/reports/run_${RUN_ID}"
mkdir -p "${OUT_DIR}"

LOG_FILE="${OUT_DIR}/vivado.log"
JSON_OUT="${OUT_DIR}/fpga_manifest.json"

echo "================================================================"
echo "  VIVADO FPGA IMPLEMENTATION & TIMING CLOSURE RUNNER           "
echo "  Run ID:      ${RUN_ID}"
echo "  Project:     ${ROOT_DIR}"
echo "  Target Part: Digilent Arty A7-100T (xc7a100tcsg324-1)"
echo "  Output Dir:  ${OUT_DIR}"
echo "================================================================"

# 1. Preflight Integrity Checks
CORE_TOP="${ROOT_DIR}/cv32e40p/rtl/cv32e40p_top.sv"
if [ ! -f "${CORE_TOP}" ]; then
    echo "[FATAL] Pinned CV32E40P core RTL not found at '${CORE_TOP}'!" >&2
    exit 1
fi

BOOT_HEX="${ROOT_DIR}/Firmware/build/hello.hex"
if [ ! -f "${BOOT_HEX}" ]; then
    echo "[FATAL] Preflight check failed: Boot image hex not found at '${BOOT_HEX}'!" >&2
    echo "        Please run 'make -C Firmware hello' to generate a verified image." >&2
    exit 1
fi

CORE_HASH=$(sha256sum "${CORE_TOP}" | awk '{print $1}')
BOOT_HASH=$(sha256sum "${BOOT_HEX}" | awk '{print $1}')

echo "[PASS] Preflight passed:"
echo "  Core RTL: ${CORE_TOP} (SHA256: ${CORE_HASH})"
echo "  Boot Hex: ${BOOT_HEX} (SHA256: ${BOOT_HASH})"

# 2. Locate Vivado
if ! command -v vivado >/dev/null 2>&1; then
    echo "[NOT_VERIFIED] Vivado executable not found in PATH." >&2
    echo "               Recording unexecuted run per Instruction/claim_integrity.md." >&2
    cat <<EOF > "${JSON_OUT}"
{
    "run_id": "${RUN_ID}",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "target_part": "xc7a100tcsg324-1",
    "toolchain": "NOT_FOUND",
    "status": "NOT_VERIFIED",
    "core_sha256": "${CORE_HASH}",
    "boot_hex_sha256": "${BOOT_HASH}",
    "artifacts": []
}
EOF
    exit 127
fi

# 3. Execute Vivado
cd "${SCRIPT_DIR}"
vivado_exit=0
vivado -mode batch -source run_synth.tcl -notrace > "${LOG_FILE}" 2>&1 || vivado_exit=$?

if [ "${vivado_exit}" -ne 0 ]; then
    echo "[FAIL] Vivado execution failed with exit code ${vivado_exit}" >&2
    exit "${vivado_exit}"
fi

# 4. Fail-Closed FPGA Evidence Gate Verification
echo "================================================================"
echo "  VALIDATING FPGA EVIDENCE GATE & STATIC TIMING ACCEPTANCE      "
echo "================================================================"
gate_exit=0
gate_args=("${ROOT_DIR}/scripts/check_fpga_evidence.py" --manifest "${JSON_OUT}" --expect-period-ns 20.0)
if [ -f "${ROOT_DIR}/reports/evidence/core_50mhz/io_contract.md" ]; then
    gate_args+=(--io-contract "${ROOT_DIR}/reports/evidence/core_50mhz/io_contract.md")
fi
if [ -f "${ROOT_DIR}/reports/evidence/core_50mhz/drc_review.md" ]; then
    gate_args+=(--drc-review "${ROOT_DIR}/reports/evidence/core_50mhz/drc_review.md")
fi
python3 "${gate_args[@]}" || gate_exit=$?

if [ "${gate_exit}" -ne 0 ]; then
    echo "[FAIL] FPGA evidence gate rejected implementation with exit code ${gate_exit}" >&2
    exit "${gate_exit}"
fi

echo "[SUCCESS] Vivado Implementation verified, timing constraints met. Manifest: ${JSON_OUT}"
