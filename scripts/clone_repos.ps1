# Clone external repositories for reference and core integration

param(
    [string]$TargetCore = "cv32e40p"
)

Write-Host "=== Cloning Reference Repositories ==="

if (-not (Test-Path "cv32e40p")) {
    Write-Host "[1/2] Cloning OpenHW Group CV32E40P (v1.8.3)..."
    git clone --depth 1 --branch v1.8.3 https://github.com/openhwgroup/cv32e40p.git cv32e40p
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to clone with branch v1.8.3, falling back to default branch..."
        git clone --depth 1 https://github.com/openhwgroup/cv32e40p.git cv32e40p
    }
} else {
    Write-Host "[1/2] cv32e40p already exists. Skipping clone."
}

if (-not (Test-Path "OpenLane")) {
    Write-Host "[2/2] Cloning OpenLane for ASIC flow reference..."
    git clone --depth 1 https://github.com/The-OpenROAD-Project/OpenLane.git OpenLane
} else {
    Write-Host "[2/2] OpenLane already exists. Skipping clone."
}

Write-Host "=== Repository Ingestion Complete ==="
