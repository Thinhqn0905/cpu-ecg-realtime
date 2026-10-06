# Gemini Audit Recovery Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Turn the existing cloned CV32E40P ECG prototype into a minimally demonstrated system with truthful, reproducible evidence.

**Architecture:** Retain upstream CV32E40P and reusable local peripherals. Repair only interface, firmware-loading, protocol and verification gaps identified by static audit. Exclude synthetic MAMBA outputs from functional claims and defer ASIC flow until FPGA boot/acquisition/DSP evidence exists.

**Tech Stack:** Existing CV32E40P SystemVerilog, CORE-V-compatible compiler, C/assembly firmware, upstream tests, Python evidence checks, Vivado.

---

Current scope is audit plus planning. No implementation commands below were
executed. Audit: `reports/review/2026-10-06-gemini-audit/audit.md`; source identity:
`audit_manifest.json` beside it. Root lacks Git; preserve hashed snapshots until
project version control exists. Never edit/rewrite cloned core to mask local
integration defects. Use @writing-plans for plan updates; execution skill in
header is a future workflow if installed, not an evidence dependency.

## Task 1: Withdraw unsupported claims and stop false-success gates

**Files:** Modify `reports/benchmark_report.md`, `reports/manifest.json`,
`reports/verification/rtm_dashboard.md`, `scripts/run_sim.ps1`,
`scripts/run_sim.sh`, `Synthesis/fpga/ecg_artix7/run_fpga.ps1`, `run_fpga.sh`,
`Synthesis/asic/run_openlane.ps1`; create `scripts/check_evidence.py`,
`scripts/test_evidence_gate.py`. Read EDA contract before script edits.

1. Preserve original reports/checklist under a dated archive (audit has already
   preserved report copies). Record corrections without erasing originals.
2. Write failing tests for empty log, missing tool, child nonzero exit despite
   PASS text, missing expected testcase, duplicate testcase and stale artifacts.
   Concrete accepted-run condition:

```python
def accepted_run(compile_exit, simulation_exit, expected, observed, artifacts):
    return (compile_exit == 0 and simulation_exit == 0
            and bool(expected) and set(observed) == set(expected)
            and len(observed) == len(expected)
            and all(value == 'PASS' for value in observed.values())
            and bool(artifacts) and all(p.is_file() for p in artifacts))
```

   This minimal predicate needs manifest/hash checks and explicit testcase
   event parsing; do not use it as a shortcut for checking golden correctness.
3. Run future tests: `python -m unittest discover -s scripts -p 'test_*.py'`;
   expect initial failures for old behavior. Fix shell with `set -euo pipefail`,
   captured real exit codes and unique run directories; PS propagates native
   failures/missing tools nonzero. Do not overwrite result exit codes with zero.
4. Set unmeasured timing/PPA/DSP/clinical claims to NOT_VERIFIED. Replace tag
   text with observed HEAD until tag metadata is checked. Retain official
   core-feature claims with source attribution, separately from measurements.
5. Rerun gate unit tests; expect deliberate negative cases rejected. Commit
   only reviewed task files once root version control is established.

## Task 2: Correct bindings and demonstrate real firmware boot

**Files:** Modify `RTL/ecg_soc/cv32e40p_ecg_soc_top.sv`, `ecg_soc_top.sv`,
`tcm_sram.sv`, `obi_to_apb.sv`, `Simulation/soc_tb.sv`,
`Synthesis/flist_cv32e40p_soc.f`, `Firmware/boot/crt0.S`, `link.ld`;
create `Firmware/Makefile`, `Firmware/boot/hello.c` and an image-loading adapter.

1. Read pinned upstream manifest, hello-world/runtime and interrupt examples;
   reuse compatible startup/clock-gate/test infrastructure before writing more.
2. Write failing checks for actual named-port bindings, valid IRQ widths,
   real-core selection, exact address boundaries and image hash. Fix names to
   existing declarations; disable MAMBA in baseline instead of array index 5.
3. Add true image loading using a project wrapper/adapter and choose one
   consistent map. Permit CPU data reads of rodata/.data load source, eliminate
   D-TCM aliases, route responses by accepted transaction, handle OBI byte
   enables explicitly. Do not leave NOP initialization as firmware proof.
4. Build hello using a pinned toolchain: `make -C Firmware hello`. Expected:
   ELF, map, disassembly and memory image with hashes; initial missing recipe
   or binding tests must fail visibly.
5. Use fixed-width vector entries, interrupt wrappers with context/mret, global
   MIE and reviewed source priority/clear semantics. Test one timer/DRDY IRQ
   returning to the interrupted instruction; do not yet claim six-cycle latency.
6. Run future `powershell -File scripts/run_sim.ps1` with a boot-only self-checking
   scenario. Require exact `ECG BOOT` UART bytes and firmware completion marker,
   not address>=0. Require missing/corrupt image to fail. Save raw log/ELF/image
   identity. Acceptance: real CPU executes firmware and returns from one IRQ.

## Task 3: Prove one complete AFE frame before DSP

**Files:** Modify `RTL/ecg_soc/spi_master.sv`, `spi_master_apb.sv`,
`ecg_soc_top.sv`, `uart_apb.sv`, `Firmware/drivers/ads1292r.c`, `ads1292r.h`,
`uart.c`, `Simulation/ads1292r_model.sv`, `spi_master_tb.sv`, `soc_tb.sv`.

1. Freeze a tiny register contract matching existing RTL: TX start, done/pending
   clear, continuous-CS frame read and status/CH1/CH2 ownership. Avoid invented
   FIFO-empty bits. Initialize AFE control GPIOs and verify command counts/gaps.
2. Add exact golden frame `status=0xC00000, CH1=0x123456, CH2=0xFEDCBA`;
   compare all 72 bits and decoded signed channels. First expect failure with
   zero DMA channels/single RX latch; preserve mismatch.
3. Repair master/model edges and complete frame publication. Publish valid
   after transfer completion; retain all status bits. Fix driver start strobe,
   RREG/WREG ordering, busy/timeout and GPIO reset/start sequence.
4. Fix APB RX side effects to accepted ACCESS only; test one APB read removes
   one byte. Choose one timestamp/CRC packet contract shared with host checker.
5. Extend model test beyond sample period; zero DRDY, stuck busy, corrupted byte
   and dropped frame must fail nonzero. Use `$fatal(1, ...)`, watchdog and exact
   testcase census. Acceptance: real firmware emits a packet containing the
   known frame; this remains simulation, not physical AFE proof.

## Task 4: Validate DSP arithmetic and measure cycles honestly

**Files:** Modify `Firmware/dsp/ecg_fir_pulp.S`, `ecg_iir_pulp.S`,
`pan_tompkins.c`, `Firmware/main.c`; create `Firmware/dsp/fir_reference.c`,
`Firmware/dsp/dsp_test.c`, `reports/benchmarks/dsp/` campaign artifacts.

1. Inspect pinned manual/toolchain for instruction spelling and semantics.
   Use accumulating signed dot product for the FIR accumulator; verify actual
   disassembly instead of assuming legacy `pv.*` aliases.
2. Write exact scalar fixed-point reference and tests: impulse, step, zero,
   random pairs, odd final tap and extrema. Define accumulator width, saturation,
   rounding and 24-bit-to-Q15 conversion. Check coefficient response/symmetry
   before retaining “40 Hz linear phase” text.
3. First run reference versus current kernel; expect mismatches where supported
   by actual emitted instructions, preserving raw output. Make minimal arithmetic
   fixes; widen before squaring in detector and test overflow explicitly.
4. Run `make -C Firmware dsp-test`; require exact reference equality and
   no illegal instructions. Measure mcycle around actual kernel and subtract
   stated counter overhead; preserve trace, memory wait states and workload hash.
5. Report measured FIR/IIR cycles separately from ISR, sample processing and
   whole-system utilization. Compare CVA6 only after matched workload/precision
   runs exist. Acceptance: exact DSP result plus measured cycle count; no target
   of 28 cycles imposed on the test. MIT-BIH accuracy evaluation is a separate
   later task with record IDs, annotations and matching tolerance.

## Task 5: Make the FPGA clock and routed evidence real

**Files:** Create `RTL/ecg_soc/fpga/ecg_arty_top.sv`; modify
`Synthesis/fpga/ecg_artix7/arty_a7_100t.xdc`, `run_synth.tcl`, `run_fpga.ps1`,
`run_fpga.sh`; create campaign under `reports/evidence/fpga_50mhz/`.

1. Reuse a proven clock/reset adapter; expose 100 MHz oscillator separately
   from MMCM/BUFG 50 MHz compute clock. Constrain 10 ns input and verify generated
   20 ns clock. Record board revision, all named pins, I/O and CDC assumptions.
2. Make filelist/top/core/image explicit and fail if missing; remove implied
   fallback harness. Retain upstream FPGA clock-gate replacement hook.
3. Future run: `powershell -File Synthesis/fpga/ecg_artix7/run_fpga.ps1`.
   Require logs/version, actual hierarchy, source/ELF hashes, mapped resources,
   completed routing, DCP and these direct reports:

```tcl
report_utilization -hierarchical -file utilization_routed.rpt
report_timing_summary -delay_type min_max -report_unconstrained -file timing_routed.rpt
check_timing -verbose -file check_timing.rpt
report_drc -file drc_routed.rpt
write_checkpoint -force ecg_routed.dcp
```

4. Gate on complete setup/hold and unconstrained-endpoint census, consistent
   clock and reviewed DRC/CDC. Preserve failed runs. A script or positive printed
   WNS alone is insufficient. Board bring-up follows this gate; do not infer
   measured Fmax or FPGA function from synthesis.

## Deferred work

MAMBA: retain bridge only as a labelled stub outside baseline. Add real compute
RTL/weights/data stream and input-dependent golden comparison before inference
claims. ASIC: select one actual flow version/PDK, mount source+PDK correctly,
resolve SRAM/clock cells and produce netlist/STA/GDS/DRC/LVS/activity-bound power
reports before PPA comparisons. Neither is required for the next boot milestone.

## Execution handoff

Recommended next implementation scope: Tasks 1–2 only, ending at exact real-core
hello/IRQ proof. Then acquisition and DSP; then FPGA. Reuse the already cloned
core and existing modules. This plan creates no obligation to rewrite a complete
RISC-V SoC and does not authorize executing tools during this planning turn.
