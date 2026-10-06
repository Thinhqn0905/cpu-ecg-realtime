# Copyright 2026 RISC-V ECG Project
# SPDX-License-Identifier: Apache-2.0
#
# Vivado Batch Execution Runner for CV32E40P ECG SoC on Arty A7-100T
# Enforces strict preflight, artifact hashing, and exit code propagation
# per docs/plans/2026-10-06-gemini-recovery-followup.md (Task 6) and Instruction/claim_integrity.md

param(
    [string]$VivadoPath = ""
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = (Resolve-Path "$scriptDir/../../..").Path
$RunId = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$OutDir = "$scriptDir/reports/run_$RunId"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$LogFile = "$OutDir/vivado.log"
$JsonOut = "$OutDir/fpga_manifest.json"

Write-Host "================================================================"
Write-Host "  VIVADO FPGA IMPLEMENTATION & TIMING CLOSURE RUNNER           "
Write-Host "  Run ID:      $RunId"
Write-Host "  Project:     $rootDir"
Write-Host "  Target Part: Digilent Arty A7-100T (xc7a100tcsg324-1)"
Write-Host "  Output Dir:  $OutDir"
Write-Host "================================================================"

# ------------------------------------------------------------------------------
# 1. Preflight Integrity Checks
# ------------------------------------------------------------------------------
$coreTop = "$rootDir/cv32e40p/rtl/cv32e40p_top.sv"
if (-not (Test-Path $coreTop)) {
    Write-Error "[FATAL] Pinned CV32E40P core RTL not found at '$coreTop'!"
    exit 1
}

$bootHex = "$rootDir/Firmware/build/hello.hex"
if (-not (Test-Path $bootHex)) {
    Write-Error "[FATAL] Preflight check failed: Boot image hex not found at '$bootHex'!"
    Write-Error "        Please run 'make -C Firmware hello' to generate a verified image."
    exit 1
}

$bootHexHash = (Get-FileHash -Path $bootHex -Algorithm SHA256).Hash.ToLower()
$coreHash = (Get-FileHash -Path $coreTop -Algorithm SHA256).Hash.ToLower()

Write-Host "[PASS] Preflight passed:"
Write-Host "  Core RTL: $coreTop (SHA256: $coreHash)"
Write-Host "  Boot Hex: $bootHex (SHA256: $bootHexHash)"

# ------------------------------------------------------------------------------
# 2. Locate Vivado Toolchain
# ------------------------------------------------------------------------------
if ($VivadoPath -eq "") {
    if (Test-Path "E:\Vivado\2023.2\bin\vivado.bat") {
        $VivadoPath = "E:\Vivado\2023.2\bin\vivado.bat"
    } else {
        $vivadoCmd = Get-Command "vivado" -ErrorAction SilentlyContinue
        if ($vivadoCmd) {
            $VivadoPath = $vivadoCmd.Source
        } else {
            $possiblePaths = Get-ChildItem -Path @("E:\Vivado", "C:\Xilinx\Vivado") -Recurse -Filter "vivado.bat" -ErrorAction SilentlyContinue
            if ($possiblePaths -and $possiblePaths.Count -gt 0) {
                $VivadoPath = $possiblePaths[0].FullName
            }
        }
    }
}

if ($VivadoPath -eq "" -or (-not (Test-Path $VivadoPath))) {
    Write-Host "[NOT_VERIFIED] Vivado executable not found at '$VivadoPath' or in PATH."
    Write-Host "               Recording unexecuted run per Instruction/claim_integrity.md."
    $manifestObj = [ordered]@{
        run_id = $RunId
        timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        target_part = "xc7a100tcsg324-1"
        toolchain = "NOT_FOUND"
        status = "NOT_VERIFIED"
        core_hash = $coreHash
        boot_hex_hash = $bootHexHash
        artifacts = @()
    }
    $manifestObj | ConvertTo-Json -Depth 4 | Set-Content $JsonOut -Encoding utf8
    exit 127
}

Write-Host "Found Vivado at: $VivadoPath"

# ------------------------------------------------------------------------------
# 3. Clean Stale Root Reports & Execute Vivado Batch Implementation
# ------------------------------------------------------------------------------
$staleFiles = @("utilization_synth.rpt", "timing_synth.rpt", "utilization_placed.rpt",
                "timing_routed.rpt", "timing_min_max.rpt", "timing_setup.rpt",
                "timing_hold.rpt", "check_timing.rpt", "utilization_hierarchical.rpt",
                "drc_routed.rpt", "power_routed.rpt", "routed.dcp", "cv32e40p_ecg_soc.bit")
foreach ($sf in $staleFiles) {
    $target = "$scriptDir/reports/$sf"
    if (Test-Path $target) {
        Remove-Item -Force $target -ErrorAction SilentlyContinue
    }
}

Push-Location $scriptDir
$startTime = Get-Date
$env:VIVADO_OUT_DIR = $OutDir
try {
    $proc = Start-Process -FilePath $VivadoPath -ArgumentList @("-mode", "batch", "-source", "run_synth.tcl", "-notrace") -RedirectStandardOutput $LogFile -RedirectStandardError "$OutDir/vivado_err.log" -Wait -PassThru -NoNewWindow
    $vivadoExit = $proc.ExitCode
} finally {
    Pop-Location
    $env:VIVADO_OUT_DIR = $null
}

$duration = ((Get-Date) - $startTime).TotalSeconds

# ------------------------------------------------------------------------------
# 4. Collect Reports and Generate Manifest
# ------------------------------------------------------------------------------
$artifacts = @()
$reportFiles = @(
    "$OutDir/utilization_synth.rpt",
    "$OutDir/timing_synth.rpt",
    "$OutDir/utilization_placed.rpt",
    "$OutDir/timing_routed.rpt",
    "$OutDir/timing_min_max.rpt",
    "$OutDir/timing_setup.rpt",
    "$OutDir/timing_hold.rpt",
    "$OutDir/check_timing.rpt",
    "$OutDir/utilization_hierarchical.rpt",
    "$OutDir/drc_routed.rpt",
    "$OutDir/power_routed.rpt",
    "$OutDir/routed.dcp",
    "$OutDir/cv32e40p_ecg_soc.bit",
    $LogFile
)

foreach ($rf in $reportFiles) {
    if (Test-Path $rf) {
        $copyTarget = "$scriptDir/reports/" + (Split-Path $rf -Leaf)
        if ($rf -ne $copyTarget) {
            Copy-Item $rf $copyTarget -Force -ErrorAction SilentlyContinue
        }
        $h = (Get-FileHash -Path $rf -Algorithm SHA256).Hash.ToLower()
        $artifacts += @{
            path = $rf
            sha256 = $h
        }
    }
}

$manifestObj = [ordered]@{
    run_id = $RunId
    timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    target_part = "xc7a100tcsg324-1"
    toolchain = $VivadoPath
    exit_code = $vivadoExit
    duration_seconds = $duration
    log_file = $LogFile
    core_sha256 = $coreHash
    boot_hex_sha256 = $bootHexHash
    artifacts = $artifacts
}

$manifestObj | ConvertTo-Json -Depth 4 | Set-Content $JsonOut -Encoding utf8

if ($vivadoExit -ne 0) {
    Write-Error "[FAIL] Vivado batch implementation failed with exit code $vivadoExit (Manifest: $JsonOut)"
    exit $vivadoExit
}

# ------------------------------------------------------------------------------
# 5. Fail-Closed FPGA Evidence Gate Verification
# ------------------------------------------------------------------------------
Write-Host "================================================================"
Write-Host "  VALIDATING FPGA EVIDENCE GATE & STATIC TIMING ACCEPTANCE      "
Write-Host "================================================================"
$gateScript = "$rootDir/scripts/check_fpga_evidence.py"
$ioContractDoc = "$rootDir/reports/evidence/core_50mhz/io_contract.md"
$drcReviewDoc = "$rootDir/reports/evidence/core_50mhz/drc_review.md"
$gateArgs = @($gateScript, "--manifest", $JsonOut, "--expect-period-ns", "20.0")
if (Test-Path $ioContractDoc) {
    $gateArgs += @("--io-contract", $ioContractDoc)
}
if (Test-Path $drcReviewDoc) {
    $gateArgs += @("--drc-review", $drcReviewDoc)
}
$gateProc = Start-Process -FilePath "python" -ArgumentList $gateArgs -Wait -PassThru -NoNewWindow
$gateExit = $gateProc.ExitCode

if ($gateExit -ne 0) {
    Write-Error "[FAIL] FPGA evidence gate rejected implementation with exit code $gateExit (Manifest: $JsonOut)"
    exit $gateExit
}

Write-Host "[SUCCESS] Vivado Implementation verified, timing constraints met. Manifest: $JsonOut"
