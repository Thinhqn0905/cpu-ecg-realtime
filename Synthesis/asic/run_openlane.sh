#!/usr/bin/env bash
# Copyright 2026 RISC-V ECG Project
# SPDX-License-Identifier: Apache-2.0
#
# OpenLane ASIC Tapeout Automation Script for CV32E40P ECG SoC
# Supports GF180MCU (180nm Open PDK) and SkyWater Sky130

set -e

DESIGN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENLANE_ROOT="${OPENLANE_ROOT:-/opt/openlane}"
PDK_ROOT="${PDK_ROOT:-/opt/pdk}"

echo "================================================================"
echo "  STARTING CV32E40P ECG SoC SILICON ASIC PHYSICAL DESIGN FLOW   "
echo "  Design: cv32e40p_ecg_soc_top                                  "
echo "  Target Node: GF180MCU / Sky130 (100 MHz target)               "
echo "================================================================"

# Check OpenLane environment
if [ ! -d "$OPENLANE_ROOT" ]; then
    echo "[INFO] Running via OpenLane Docker container..."
    docker run --rm \
        -v "$OPENLANE_ROOT:/openlane" \
        -v "$PDK_ROOT:/pdk" \
        -v "$DESIGN_DIR:/project" \
        -e PDK_ROOT=/pdk \
        -u $(id -u):$(id -g) \
        efabless/openlane:v2023.11.03 \
        flow.tcl -design /project/openlane
else
    echo "[INFO] Running native OpenLane flow..."
    flow.tcl -design "$DESIGN_DIR/openlane"
fi

echo "================================================================"
echo "  ASIC FLOW COMPLETE! GDSII & Sign-off reports in runs/         "
echo "================================================================"
