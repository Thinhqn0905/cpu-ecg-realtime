# Copyright 2026 RISC-V ECG Project
# SPDX-License-Identifier: Apache-2.0
#
# Vivado Batch Execution Runner for CV32E40P ECG SoC on Arty A7-100T
# Enforces strict exit code propagation per Instruction/claim_integrity.md

param(
    [string]$VivadoPath = ""
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RunId = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$OutDir = "$scriptDir/reports/run_$RunId"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

Write-Host "================================================================"
Write-Host "  VIVADO FPGA IMPLEMENTATION & TIMING CLOSURE RUNNER           "
Write-Host "  Run ID: $RunId"
Write-Host "  Target: Digilent Arty A7-100T (xc7a100tcsg324-1)              "
Write-Host "================================================================"

# Locate Vivado
if ($VivadoPath -eq "") {
    $vivadoCmd = Get-Command "vivado" -ErrorAction SilentlyContinue
    if ($vivadoCmd) {
        $VivadoPath = $vivadoCmd.Source
    } else {
        $possiblePaths = Get-ChildItem -Path "C:\Xilinx\Vivado" -Recurse -Filter "vivado.bat" -ErrorAction SilentlyContinue
        if ($possiblePaths -and $possiblePaths.Count -gt 0) {
            $VivadoPath = $possiblePaths[0].FullName
        }
    }
}

if ($VivadoPath -eq "" -or (-not (Test-Path $VivadoPath))) {
    Write-Error "[FAIL] Vivado executable not found at '$VivadoPath' or in PATH. Cannot proceed."
    exit 127
}

Write-Host "Found Vivado at: $VivadoPath"

Push-Location $scriptDir
try {
    $proc = Start-Process -FilePath $VivadoPath -ArgumentList @("-mode", "batch", "-source", "run_synth.tcl", "-notrace") -Wait -PassThru -NoNewWindow
    $vivadoExit = $proc.ExitCode
} finally {
    Pop-Location
}

if ($vivadoExit -ne 0) {
    Write-Error "[FAIL] Vivado batch implementation failed with exit code $vivadoExit"
    exit $vivadoExit
}

Write-Host "[SUCCESS] Vivado Implementation complete with exit code 0."
