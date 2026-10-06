# Specification Directory: Architectural Requirements & Traceability Maps

This directory contains the formal architectural specifications, structured machine-readable requirements definitions, and module traceability mapping for the CV32E40P RISC-V Real-Time ECG SoC.

---

## Directory Hierarchy

```
spec/
├── ecg_soc_spec.md              # Full architectural specification & hardware-software contract
├── ecg_soc_reqs.json            # Machine-readable requirements database (JSON schema)
└── ecg_soc_module_map.json      # Traceability map connecting RTL modules to formal requirements
```

---

## 1. Architectural Specification (`ecg_soc_spec.md`)

Defines the quantitative constraints, interface rules, and electrical requirements:
- **Processor Constraints**: CV32E40P RV32IMC + Xpulpv2, 50 MHz system clock, Harvard OBI interconnect.
- **Memory Boundary**: 32 KB Instruction TCM (`0x0000_0000`), 32 KB Data TCM (`0x0001_0000`), zero wait-state combinational SRAM interface.
- **Analog Front-End Constraints**: Texas Instruments ADS1292R, 24-bit resolution, 250 - 1000 SPS sampling rate, 1.0 MHz SPI clock (Mode 1: CPOL=0, CPHA=1), 72-bit continuous CS# assertion.
- **Data Buffering**: Split-plane ping-pong DMA, standardized 12-byte frames, Fast IRQ 18 vectoring.
- **Data Output**: 16550 UART at 115200 baud, 8N1 framing, 16-deep FIFOs.
- **Interrupt Dispatch**: Direct-vectored mode (`mtvec = 0x0000_0101`), trap vector table at `0x0000_0100`.

---

## 2. Requirements Database (`ecg_soc_reqs.json`)

Contains the complete machine-readable set of system requirements:
- Each requirement contains:
  - `id`: Unique requirement identifier (e.g. `REQ-SPI-001`).
  - `category`: Functional category (`CORE`, `BUS`, `SPI`, `DMA`, `UART`, `DSP`).
  - `description`: Formal requirement statement.
  - `verification_method`: Verification approach (`SIMULATION`, `FORMAL`, `SYNTHESIS`).
  - `target_testcases`: Mapped test case IDs (e.g. `TC-SPI-001A`, `TC-SPI-001B`).

---

## 3. Module Traceability Map (`ecg_soc_module_map.json`)

Establishes bidirectional traceability between RTL source code and requirements:
- Connects every synthesizable SystemVerilog module in `RTL/ecg_soc/` to the specific requirements it implements.
- Enables automated coverage auditing and gap analysis across the verification lifecycle.
