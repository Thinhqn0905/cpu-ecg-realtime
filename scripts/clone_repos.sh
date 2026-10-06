#!/usr/bin/env bash
# Clone external repositories for reference and core integration
set -e

echo "=== Cloning Reference Repositories ==="

if [ ! -d "cv32e40p" ]; then
    echo "[1/2] Cloning OpenHW Group CV32E40P (v1.8.3)..."
    git clone --depth 1 --branch v1.8.3 https://github.com/openhwgroup/cv32e40p.git cv32e40p || \
    git clone --depth 1 https://github.com/openhwgroup/cv32e40p.git cv32e40p
else
    echo "[1/2] cv32e40p already exists. Skipping clone."
fi

if [ ! -d "OpenLane" ]; then
    echo "[2/2] Cloning OpenLane for ASIC flow reference..."
    git clone --depth 1 https://github.com/The-OpenROAD-Project/OpenLane.git OpenLane
else
    echo "[2/2] OpenLane already exists. Skipping clone."
fi

echo "=== Repository Ingestion Complete ==="
