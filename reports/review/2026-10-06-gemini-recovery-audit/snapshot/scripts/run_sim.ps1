# Copyright 2026 RISC-V ECG Project
# SPDX-License-Identifier: Apache-2.0
#
# Compile and Run Full CV32E40P ECG SoC Co-Simulation with Icarus Verilog
# Enforces strict exit code propagation and evidence validation per Instruction/claim_integrity.md

param(
    [string]$IverilogPath = "",
    [string]$VvpPath = ""
)

$ErrorActionPreference = "Stop"

$RunId = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$OutDir = "reports/simulation/run_$RunId"
if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
}

$VvpOut = "$OutDir/soc_tb.vvp"
$CompileLog = "$OutDir/compile.log"
$SimLog = "$OutDir/soc_tb.log"
$JsonOut = "$OutDir/sim_results.json"

Write-Host "================================================================"
Write-Host "  CV32E40P ECG SoC CO-SIMULATION RUNNER (POWERSHELL)           "
Write-Host "  Run ID:    $RunId"
Write-Host "  Output:    $OutDir"
Write-Host "================================================================"

# Locate iverilog
if ($IverilogPath -eq "") {
    if (Test-Path "E:/iverilog/bin/iverilog.exe") {
        $IverilogPath = "E:/iverilog/bin/iverilog.exe"
    } else {
        $cmd = Get-Command "iverilog" -ErrorAction SilentlyContinue
        if ($cmd) {
            $IverilogPath = $cmd.Source
        }
    }
}

# Locate vvp
if ($VvpPath -eq "") {
    if (Test-Path "E:/iverilog/bin/vvp.exe") {
        $VvpPath = "E:/iverilog/bin/vvp.exe"
    } else {
        $cmd = Get-Command "vvp" -ErrorAction SilentlyContinue
        if ($cmd) {
            $VvpPath = $cmd.Source
        }
    }
}

if ($IverilogPath -eq "" -or (-not (Test-Path $IverilogPath))) {
    Write-Error "[FAIL] iverilog executable not found at '$IverilogPath' or in PATH."
    exit 127
}

if ($VvpPath -eq "" -or (-not (Test-Path $VvpPath))) {
    Write-Error "[FAIL] vvp executable not found at '$VvpPath' or in PATH."
    exit 127
}

Write-Host "Using compiler: $IverilogPath"
Write-Host "Using runtime:  $VvpPath"

Write-Host "[1/3] Compiling SystemVerilog source tree with Icarus Verilog..."
$compileArgs = @(
    "-g2012",
    "-Wall",
    "-Wno-timescale",
    "-I", "cv32e40p/rtl/include",
    "-I", "cv32e40p/bhv",
    "-I", "cv32e40p/bhv/include",
    "-I", "RTL/ecg_soc",
    "-s", "soc_tb",
    "-o", $VvpOut,
    "-c", "Synthesis/flist_cv32e40p_soc.f",
    "Simulation/ads1292r_model.sv",
    "Simulation/soc_tb.sv"
)

$startTime = Get-Date
$compileProcess = Start-Process -FilePath $IverilogPath -ArgumentList $compileArgs -RedirectStandardOutput $CompileLog -RedirectStandardError "$OutDir/compile_err.log" -Wait -PassThru -NoNewWindow
$compileExit = $compileProcess.ExitCode

if ($compileExit -ne 0) {
    Write-Host "[FAIL] Compilation failed with exit code $compileExit"
    if (Test-Path "$OutDir/compile_err.log") {
        Get-Content "$OutDir/compile_err.log" | Write-Host
    }
    exit $compileExit
}
Write-Host "[PASS] Compilation successful: $VvpOut"

Write-Host "[2/3] Executing Co-Simulation..."
$simProcess = Start-Process -FilePath $VvpPath -ArgumentList @($VvpOut) -RedirectStandardOutput $SimLog -RedirectStandardError "$OutDir/sim_err.log" -Wait -PassThru -NoNewWindow
$simExit = $simProcess.ExitCode

if (Test-Path $SimLog) {
    Get-Content $SimLog | Write-Host
}

if ($simExit -ne 0) {
    Write-Host "[FAIL] Simulation failed with exit code $simExit"
    exit $simExit
}

$duration = ((Get-Date) - $startTime).TotalSeconds

Write-Host "[3/3] Generating Run Evidence Manifest..."
$artifacts = @($VvpOut, $CompileLog, $SimLog)
$manifestObj = [ordered]@{
    run_id = $RunId
    timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    compiler = $IverilogPath
    runtime = $VvpPath
    compile_exit = $compileExit
    simulation_exit = $simExit
    duration_seconds = $duration
    log_file = $SimLog
    artifacts = $artifacts
}

$manifestObj | ConvertTo-Json -Depth 4 | Set-Content $JsonOut -Encoding utf8

# Maintain latest link
$latestDir = "reports/simulation/latest"
if (-not (Test-Path $latestDir)) {
    New-Item -ItemType Directory -Force -Path $latestDir | Out-Null
}
Copy-Item $JsonOut "$latestDir/sim_results.json" -Force
Copy-Item $SimLog "$latestDir/soc_tb.log" -Force

Write-Host "[SUCCESS] Simulation finished with exit code 0. Manifest: $JsonOut"
