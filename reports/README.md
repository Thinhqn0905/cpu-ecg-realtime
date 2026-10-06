# Reports Directory: Verification Dashboards, Manifests & Audit History

This directory contains the central evidence repository, Requirements Traceability Matrix (RTM) dashboards, performance benchmark records, and independent multi-round audit trails.

---

## Directory Hierarchy

```
reports/
├── verification/                # Live Requirements Traceability Matrix & test mapping
│   ├── rtm_dashboard.md         # Active RTM Dashboard tracking all 39 test cases
│   └── test_traceability_audit.md # Code-anchored source line traceability audit
├── simulation/                  # Immutable simulation run evidence directories
│   ├── sim_manifest.json        # Machine-readable compilation and execution manifest
│   └── run_*/                   # Per-campaign immutable run evidence (logs, JSON, SHA256)
├── review/                      # Independent multi-round audit trails & snapshots
│   ├── 2026-10-06-source-audit/ # Baseline code and Verilator lint audit
│   ├── 2026-10-06-gemini-audit/ # First-round independent adversarial audit
│   ├── 2026-10-06-gemini-recovery-audit/ # Second-round remediation verification
│   └── 2026-10-06-provenance-correction/ # Corrective actions and provenance notes
├── benchmark_report.md          # CoreMark, DSP throughput, and latency benchmarks
├── manifest.json                # Master project artifact manifest
└── test.md                      # Verification summary notes
```

---

## 1. Requirements Traceability Matrix (`verification/rtm_dashboard.md`)

The RTM Dashboard serves as the single source of truth for design verification status:
- Tracks all **39 code-anchored test cases** across:
  - TCM Memory Subsystem (`TC-TCM-001` - `005`)
  - OBI-to-APB3 Protocol Bridge (`TC-BRG-001` - `004`)
  - ADS1292R 72-bit Continuous-CS SPI Master (`TC-SPI-001A` - `007`)
  - Ping-Pong Frame Unpacking DMA (`TC-DMA-001` - `006`)
  - CV32E40P Full-SoC Co-Simulation (`TC-SYS-001` - `017`)
- Strict Status Nomenclature:
  - `NOT_VERIFIED`: Baseline state prior to simulation execution.
  - `Anchored in Code & TB`: Source code lines and testbench assertions mapped, awaiting runner execution.
  - `PASS (Sim)`: Simulation completed with exit code 0, log parsed, SHA-256 signed, and validated through `check_evidence.py`.

---

## 2. Benchmark Characterization (`benchmark_report.md`)

Documents quantitative performance metrics for the CV32E40P core and peripherals:
- **Core Processing Throughput**:
  - Operating Frequency: 50 MHz on Xilinx Artix-7.
  - CoreMark Benchmark: 1.82 CoreMark/MHz (RV32IMC mode).
- **DSP Speedup via PULP Xpulpv2**:
  - 45-tap Q1.15 FIR Filter: 47 cycles/sample (PULP `p.mac` + hardware loops) vs. 182 cycles/sample (standard RV32I) $\implies \mathbf{3.87\times}$ acceleration.
- **Acquisition Latency**:
  - ADS1292R 72-bit transfer duration @ 1.0 MHz SCLK: $72\text{ }\mu\text{s}$.
  - DMA frame assembly and memory write: $0.24\text{ }\mu\text{s}$.
  - Total latency from AFE `DRDY#` assertion to D-TCM buffer availability: $<\mathbf{75\text{ }\mu\text{s}}$ (well within the 10 ms clinical latency budget).

---

## 3. Independent Audit History (`reports/review/`)

To guarantee strict compliance with `Instruction/claim_integrity.md`, all historical review rounds and adversarial audits are permanently preserved:
- **`2026-10-06-gemini-audit/`**: Initial adversarial audit detecting unverified status inflation and lack of run evidence.
- **`2026-10-06-gemini-recovery-audit/`**: Audit of frozen V3 architecture and code-anchoring remediation.
- **`snapshot/`**: Historical source snapshots preserved at exact review checkpoints to maintain cryptographic auditability.
