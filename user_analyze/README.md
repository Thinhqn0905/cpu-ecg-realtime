# User Analysis Directory: RISC-V Core Selection for Biomedical ECG SoC

This directory contains research papers, technical evaluations, and architectural trade-off analysis documents supporting the core selection and hardware architecture decisions for the Real-Time ECG SoC.

---

## Documents

### 1. `RISC-V_core_selection_for_FPGA-based_ECG_SoC_LeapSpace.pdf`

**Title:** *RISC-V Core Selection for FPGA-based ECG SoC: Comparative Analysis of CVA6, Ibex, and CV32E40P*  
**Scope:** Biomedical signal acquisition (ECG), real-time processing constraints, and FPGA resource budgets on Xilinx Artix-7.

#### Key Architectural Conclusions & Findings:

1. **CVA6 (6-stage in-order RV32IMA/RV64GC)**:
   - *Strengths:* Linux-capable Sv32 MMU, high clock frequencies on ASIC/high-end FPGA, standard AXI4 bus.
   - *Weaknesses for ECG:* High resource footprint (>15,000 LUTs), lack of DSP/SIMD instruction extensions in baseline, excess pipeline latency for low-power biosignal capture.
   - *Role in Project:* Kept as the upstream reference and architectural verification baseline under `cva6/`.

2. **Ibex (2-stage in-order RV32IMC)**:
   - *Strengths:* Extremely small footprint (~2,000 LUTs), low power, simple interrupt handling.
   - *Weaknesses for ECG:* No DSP extensions; multi-cycle multiply/divide; insufficient compute throughput for multi-lead FIR filtering and Pan-Tompkins QRS morphology detection without external hardware accelerators.

3. **CV32E40P (4-stage in-order RV32IMC + CORE-V `Xpulpv2` DSP)** — **SELECTED CORE**:
   - *Strengths:*
     - Full support for `Xpulpv2` extensions: hardware loops (`lp.setup`), post-increment load/store, single-cycle 32-bit MAC (`p.mac`), and 16-bit SIMD vector operations (`pv.dotsp.h`).
     - Decoupled Harvard Open Bus Interface (OBI) with single-cycle zero-wait-state memory access.
     - Direct-vectored fast interrupts (`irq_i[30:16]`), achieving sub-microsecond ISR entry without arbitration overhead.
     - Fits comfortably on Digilent Arty A7-100T (< 17% LUTs, < 6% FFs).
   - *DSP Performance Gain:* Provides >3.8x execution speedup on the 45-tap Q1.15 bandpass FIR filter and Pan-Tompkins real-time cardiac QRS detector compared to baseline RV32I.

---

## Cross-References

- [Architecture Reference Manual](../docs/architecture/ARCHITECTURE_DESCRIPTION.md)
- [Requirements Traceability Matrix](../reports/verification/rtm_dashboard.md)
- [RTL Subsystem Documentation](../RTL/README.md)
- [Firmware & DSP Documentation](../Firmware/README.md)
