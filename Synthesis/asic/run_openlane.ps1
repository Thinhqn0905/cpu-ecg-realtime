# Copyright 2026 RISC-V ECG Project
# SPDX-License-Identifier: Apache-2.0
#
# OpenLane ASIC Tapeout Automation Script for Windows / Docker
# Enforces strict exit code propagation per Instruction/claim_integrity.md

param(
    [string]$PDK = "gf180mcu", # "gf180mcu" or "sky130"
    [string]$OpenLaneImage = "efabless/openlane:v2023.11.03",
    [string]$PdkRoot = "C:/pdk"
)

$ErrorActionPreference = "Stop"

Write-Host "================================================================"
Write-Host "  CV32E40P ECG SoC SILICON ASIC PHYSICAL DESIGN FLOW (GATE 6)  "
Write-Host "  Design: cv32e40p_ecg_soc_top                                  "
Write-Host "  Target PDK: $PDK                                              "
Write-Host "  Status: DEFERRED until FPGA boot/acquisition/DSP is proven    "
Write-Host "================================================================"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$workspaceRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)
$openlaneDir = Join-Path $scriptDir "openlane"

# Select Config File
if ($PDK -eq "sky130") {
    $configFile = "config_sky130.json"
} else {
    $configFile = "config.json"
}

Write-Host "Using configuration: $configFile"

# Check Docker
$dockerCmd = Get-Command "docker" -ErrorAction SilentlyContinue
if (-not $dockerCmd) {
    Write-Error "[FAIL] Docker is not installed or not in PATH. Cannot run OpenLane."
    exit 127
}

if (-not (Test-Path $PdkRoot)) {
    Write-Error "[FAIL] PDK root not found at '$PdkRoot'. Cannot run OpenLane without PDK."
    exit 1
}

Write-Host "Running OpenLane flow in Docker container..."
$proc = Start-Process -FilePath "docker" -ArgumentList @(
    "run", "--rm",
    "-v", "${workspaceRoot}:/workspace",
    "-v", "${PdkRoot}:/pdk",
    "-e", "PDK_ROOT=/pdk",
    $OpenLaneImage,
    "flow.tcl", "-design", "/workspace/Synthesis/asic/openlane", "-config_file", "/workspace/Synthesis/asic/openlane/$configFile"
) -Wait -PassThru -NoNewWindow

$dockerExit = $proc.ExitCode

if ($dockerExit -ne 0) {
    Write-Error "[FAIL] OpenLane Docker flow failed with exit code $dockerExit"
    exit $dockerExit
}

Write-Host "[SUCCESS] OpenLane run complete with exit code 0."
