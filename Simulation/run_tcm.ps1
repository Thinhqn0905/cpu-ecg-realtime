# Copyright 2026 RISC-V ECG Project
# SPDX-License-Identifier: Apache-2.0
#
# Compile and Run Dual-Port TCM Unit Simulation with Icarus Verilog
# Enforces strict exit code propagation and evidence validation per Instruction/claim_integrity.md

param(
    [string]$IverilogPath = "",
    [string]$VvpPath = ""
)

$ErrorActionPreference = "Stop"

$RunId = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$OutDir = "reports/simulation/tcm_run_$RunId"
if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
}

$VvpOut = "$OutDir/tcm_tb.vvp"
$CompileLog = "$OutDir/compile.log"
$SimLog = "$OutDir/tcm_tb.log"
$JsonOut = "$OutDir/sim_results.json"

Write-Host "================================================================"
Write-Host "  TCM ROUTER & MEMORY SUBSYSTEM SIMULATION RUNNER              "
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

Write-Host "[1/4] Compiling TCM testbench with Icarus Verilog..."
$compileArgs = @(
    "-g2012",
    "-Wall",
    "-Wno-timescale",
    "-I", "RTL/ecg_soc",
    "-s", "tcm_router_tb",
    "-o", $VvpOut,
    "-c", "Synthesis/flist_tcm_router_tb.f"
)

$startTime = Get-Date
$compileProcess = Start-Process -FilePath $IverilogPath -ArgumentList $compileArgs -RedirectStandardOutput $CompileLog -RedirectStandardError "$OutDir/compile_err.log" -Wait -PassThru -NoNewWindow
$compileExit = $compileProcess.ExitCode

if ($compileExit -ne 0) {
    Write-Host "[FAIL] Compilation failed with exit code $compileExit"
    if (Test-Path "$OutDir/compile_err.log") {
        Get-Content "$OutDir/compile_err.log" | Write-Host
    }
    $failManifest = [ordered]@{
        run_id = $RunId
        timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        compiler = $IverilogPath
        runtime = $VvpPath
        compile_exit = $compileExit
        simulation_exit = -1
        log_file = $CompileLog
        artifacts = @()
    }
    $failManifest | ConvertTo-Json -Depth 4 | Set-Content $JsonOut -Encoding utf8
    exit $compileExit
}
Write-Host "[PASS] Compilation successful: $VvpOut"

Write-Host "[2/4] Executing TCM Simulation..."
$simProcess = Start-Process -FilePath $VvpPath -ArgumentList @($VvpOut) -RedirectStandardOutput $SimLog -RedirectStandardError "$OutDir/sim_err.log" -Wait -PassThru -NoNewWindow
$simExit = $simProcess.ExitCode

if (Test-Path $SimLog) {
    Get-Content $SimLog | Write-Host
}

$duration = ((Get-Date) - $startTime).TotalSeconds

Write-Host "[3/4] Generating Run Evidence Manifest..."
$artifacts = @()
foreach ($artPath in @($VvpOut, $CompileLog, $SimLog)) {
    if (Test-Path $artPath) {
        $hash = (Get-FileHash -Path $artPath -Algorithm SHA256).Hash.ToLower()
        $artifacts += @{
            path = $artPath
            sha256 = $hash
        }
    }
}

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

if ($simExit -ne 0) {
    Write-Host "[FAIL] Simulation failed with exit code $simExit. Failure manifest saved to $JsonOut"
    exit $simExit
}

Write-Host "[4/4] Validating Evidence Gate with check_evidence.py..."
$pythonExe = "python"
$expectedCases = @("TC-TCM-001", "TC-TCM-002", "TC-TCM-003", "TC-TCM-004", "TC-TCM-005")
$gateArgs = @("scripts/check_evidence.py", $JsonOut) + $expectedCases + @("--run-id", $RunId)
$gateProcess = Start-Process -FilePath $pythonExe -ArgumentList $gateArgs -Wait -PassThru -NoNewWindow
$gateExit = $gateProcess.ExitCode

if ($gateExit -ne 0) {
    Write-Host "[FAIL] Evidence gate rejected TCM simulation (exit code $gateExit)"
    exit $gateExit
}

# Only on gate success do we update latest/
$latestDir = "reports/simulation/tcm_latest"
if (-not (Test-Path $latestDir)) {
    New-Item -ItemType Directory -Force -Path $latestDir | Out-Null
}
Copy-Item $JsonOut "$latestDir/sim_results.json" -Force
Copy-Item $SimLog "$latestDir/tcm_tb.log" -Force

Write-Host "[SUCCESS] TCM Simulation verified and accepted. Manifest: $JsonOut"
