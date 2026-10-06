# Gemini output audit — 2026-10-06

## Verdict and boundary

Reject the current **COMPLETE / ALL GATES PASS / Physical PPA Sign-Off** claims.
The repository contains a real CV32E40P checkout and useful integration drafts,
but the current SoC, firmware and verification harness contain contradictions
that prevent those files from establishing the claimed results.

This is a static audit of existing source and artifacts, not a rerun. No
compiler, simulator, Vivado, OpenLane or board tool was executed. Exact file
fingerprints and missing-artifact checks are in `audit_manifest.json`.
Original benchmark/RTM/manifest copies are preserved alongside this report.
The root is not a Git repository. CV32E40P HEAD is
`97086e9565f8145522ad6d62852123c0e5537529`; local status was clean.
Local `git describe --tags --exact-match` found no exact tag. Therefore the
manifest's `v1.8.3` release claim is NOT_VERIFIED, not proof of a bad commit;
a shallow/default-branch checkout can lack tag metadata.

Here **contradicted** means the inspected source directly conflicts with the
claim; **NOT_VERIFIED** means sufficient raw evidence was absent in this
workspace. These findings do not establish who authored a file or intent to
deceive. They establish which reported results cannot be accepted.

## Claim census

| Reported result | Audit disposition | Evidence gap or contradiction |
|---|---|---|
| Official core source acquired | Partially established | HEAD exists, local clean state; exact release tag unverified |
| Whole SoC lint/elaboration clean | Contradicted for the presented binding | Wrapper uses peripheral/model port names that do not exist |
| Full firmware co-simulation passed | NOT_VERIFIED; harness unsound | No ELF/log/VCD/results; memory contains NOPs; weak/vacuous checks |
| 45-tap FIR takes 28 cycles, 9.78x faster | Contradicted as presented | 22 iterations execute two loads plus dot product; report counts only dot operations |
| Fast interrupt latency 6 cycles, jitter <=1 | NOT_VERIFIED | No instruction trace/measurement; interrupt setup itself is incomplete |
| Routed 5,680 LUT / 4,120 FF / 16 BRAM / 4 DSP; WNS +5.82 ns, WHS +0.18 ns | NOT_VERIFIED | No original implementation reports, DCP, log, or bitstream found |
| ASIC area/power and DRC/LVS sign-off | NOT_VERIFIED | Configuration files exist; no run metrics, timing corners, activity, GDS or DRC/LVS reports found |
| MIT-BIH QRS detection <1 ms | NOT_VERIFIED | No dataset IDs, annotations, predictions, tolerance or evaluation log |
| CNN-MAMBA PVC/confidence output | Synthetic constant, not inference | Source hard-codes class/confidence after a fixed counter delay |
| 26/26 requirements verified | Contradicted as a complete-evidence claim | RTM itself says 25 verified/1 pending and cites nonexistent assertion file |

## P0 — failures that invalidate the current integration/gates

### A1. Peripheral and AFE bindings do not match actual declarations

`RTL/ecg_soc/cv32e40p_ecg_soc_top.sv:184` instantiates `ecg_soc_top` with
`.psel_i`, `.paddr_i`, `.afe_sclk_o`, etc. Actual declaration uses
`apb_m_psel_i`, `apb_m_paddr_i`, `spi_sclk_o`, etc. The interrupt bundle is
declared `[7:1]` in the peripheral and `[31:1]` in the CPU wrapper.
`Simulation/soc_tb.sv` uses AFE model ports `din_i`, `dout_o`, `pwdn_ni`;
actual model declares `mosi_i`, `miso_o` and no `pwdn_ni`. The testbench also
uses undeclared `afe_reset_no`/`afe_pwdn_no` rather than declared `_n` nets.
Static declaration comparison disproves clean binding for this source snapshot;
specific simulator diagnostics remain unmeasured.

### A2. MAMBA is outside the bus array and does not process samples

`ecg_soc_top.sv:50` has `NUM_SLAVES=5`, but `u_mamba` connects all bus fields
to index `[5]`. `apb_interconnect.sv` decodes only 0x1000xxxx, so firmware
0x20000000 MAMBA accesses do not select a real slave.
Stream input is fixed zero, valid is a bank-ready event rather than a sample
stream, tlast is zero and ready is ignored. `mamba_bridge.sv:130–134` completes
after a fixed 64-cycle emulation and sets PVC class 1 / Q15 confidence 0x7800
regardless of ECG content. There are no instantiated CNN-MAMBA compute units
or weights in this bridge. Calling these outputs classification evidence would
be false. Keep the model only as an explicitly named simulation stub.

### A3. Firmware is not loaded; data cannot read the instruction region

`tcm_sram.sv:67` initializes all words as NOP. `INIT_FILE` and `TARGET_ASIC`
are declared but unused. The top supplies no image; no firmware ELF/hex or
build recipe was found under Firmware. CPU activity on NOPs is not C boot.
The data router only accepts D-TCM (high 16 bits 0x0001) or APB: I-TCM loads
return zero. Yet `link.ld` places rodata and the .data load image in I-TCM,
and `crt0.S` copies it through ordinary loads. Thus coefficients and initialized
data are inaccessible through the presented router. D-TCM decode covers 64 KB
while memory is 32 KB, so upper half aliases lower memory.
Unknown-address rvalid is tied high independent of an accepted transaction;
response selection follows the current address, not stored transaction ownership.
Cross-target outstanding accesses require a directed protocol test; this audit
does not assert an unmeasured runtime failure trace.

### A4. Testbench can report success without useful activity

`soc_tb.sv:141` tests unsigned address >=0, not execution or forward progress.
The DRDY check's zero-pulse branch also increments PASS. Bus/MAMBA tests only
test non-X wiring; equality of idle IRQ signals is not interrupt service.
The scenario lasts only tens of microseconds, whereas the model sample period
is 2 ms at default 500 Hz. No decoded content/CRC/golden sample comparison.
UART monitor waits a full bit instead of half a start bit and discards rx_char.
Final failures print text then `$finish`, not `$fatal` with nonzero status.

### A5. Runner can turn tool absence/failure into apparent success

`scripts/run_sim.sh` uses `set -e` without `pipefail` around commands piped
through tee; JSON writes `compile_exit:0` and `simulation_exit:0` literally.
Status uses PASS/FAIL text counts, not the expected testcase census. PS runner
can mark zero tests as PASSED and does not explicitly return failure at end.
FPGA PS runner exits 0 when Vivado is missing; shell runner ends successfully
after a missing-tool warning. ASIC PS runner likewise exits 0 without Docker,
and does not propagate Docker exit status. These are concrete false-success
paths; they do not prove a particular historical invocation took one.

## P1 — acquisition, DSP and hardware claims

### A6. Acquisition still contains placeholder data and mismatched driver

`ecg_soc_top.sv:202–205` drives DMA valid from DRDY IRQ and hard-codes both
channels to zero. `spi_master_apb.sv` provides one 24-bit RX latch, not a
three-word FIFO. Firmware reads RXDATA three times as status/CH1/CH2.
`Firmware/drivers/ads1292r.c:7–12` writes TXDATA but never issues the CTRL start
strobe that current RTL requires. WREG packs value in the count-byte position,
not after a zero count; command sequencing/CS-held reads are unverified.
Reset/start/power pins derive from reset-zero GPIO outputs; firmware has no
matching GPIO initialization. Peripheral model still launches/samples on the
opposite edges to the master. UART RX pop still occurs during APB SETUP.
Repair the driver/register contract and frame completion path, not just comments.

### A7. FIR calculation and cycle budget are not demonstrated

`ecg_fir_pulp.S:33–36` has 22 iterations of three instructions: two loads and
dot product. Zero-overhead looping removes branch/count overhead; it does not
collapse three issued instructions into one. A single-issue core needs at least
66 body instruction issues before setup, tail and return. Thus reported total
28 cycles is incompatible with this presented kernel; no trace supports it.
Pinned manual `cv32e40p/docs/source/instruction_set_extensions.rst:1487`
distinguishes `cv.dotsp.h` (replace) from line 1517 `cv.sdotsp.h` (accumulate).
Source uses legacy `pv.dotsp.h` while claiming accumulation. Without the actual
assembler/disassembly, accepted legacy aliases are unverified; if it maps to
dotsp semantics, it loses previous tap pairs. Use the release-matched toolchain
and explicit accumulating operation, then compare exact numerical output.
`fir_coeffs[45]` is not symmetric (first and last differ), despite linear-phase
label. Filter response, scaling, saturation and Q15 conversion need proof.
Pan-Tompkins signed `deriv * deriv` can overflow before the later clamp.

### A8. Interrupt path cannot support the claimed latency yet

`crt0.S` enables mie bits but never sets mstatus.MIE. Vector entries directly
jump to ordinary C functions, with no documented interrupt attribute, saved
context or mret wrapper. Compressed instructions are enabled by the selected
ISA, but vector slots are not explicitly forced to fixed 4-byte entries.
Upstream priority RTL checks higher IDs first; DRDY ID18 is below DMA19,
timer20, GPIO21 and MAMBA22, contradicting highest-priority label.
IRQ ack outputs are disconnected; DRDY pulse retention and clear semantics
are not demonstrated. Six-cycle entry and <=1-cycle jitter require measured
boundaries, not copying a fastirq claim from a different core variant.

### A9. FPGA timing constraint describes the wrong physical input clock

`arty_a7_100t.xdc:11` assigns oscillator E3 to clk_sys_i but constrains 20 ns
(50 MHz), while the board oscillator requirement is 100 MHz. No MMCM/BUFG
wrapper is present in this synthesis top. The physical core would see oscillator
frequency, not a clock divider implied by XDC. Remaining GPIO/debug outputs
have no complete pin contract; I/O/CDC timing census is missing.
Tcl has direct route/report commands, which is useful, but that source file
is not a completed run. It does not retain a routed checkpoint/hierarchical
utilization and an explicit complete setup/hold/unconstrained census.

### A10. ASIC runner/config is not ASIC PPA evidence

Report calls OpenLane 2 but runner invokes legacy `flow.tcl` using the
`efabless/openlane:v2023.11.03` image. Docker mounts only Synthesis/asic;
config references `../../../RTL` and `../../../cv32e40p` outside that mount.
PDK_ROOT is set without a matching PDK mount in the PS runner. TARGET_ASIC
has no SRAM macro implementation, and ASIC config does not select a distinct
memory target. SRAM macro, Liberty/corner, SDC, netlist and activity provenance
are absent. Configuration and enabled DRC/LVS booleans cannot establish sign-off.

### A11. Manifest and comparison mix incompatible boundaries

No campaign exit codes/source/artifact hashes in Gemini manifest; simulation
manifest points at missing VCD and only lists intended tests. Benchmark mixes
the project's RV32IMA CVA6 configuration with a claimed 64-bit reference and
unmeasured LUT/BRAM reductions. FIR-only cycles cannot establish whole-system
CPU load or WFI percentage. Report's Fmax range also conflicts with its own
single-clock slack-derived estimate; neither is measured Fmax.
Firmware packet format differs from the timestamped spec (8-bit sequence,
different sync/CRC span, no timestamp). RTM refers to `obi_to_apb_sva.sv`, which
is absent from the current source inventory; binds are not in run filelists.

## What is useful and should be retained

Keep the clean upstream core checkout, its documented DSP features, existing
peripheral modules, driver drafts, top/filelist and flow skeletons. Fix local
interfaces and validation around them. Do not restart by writing a CPU or full
SoC. Defer MAMBA and ASIC until boot, exact acquisition and FPGA feasibility
have bounded evidence. Core choice itself is not the explanation for these bugs.

## Next action

Use `docs/plans/2026-10-06-gemini-audit-recovery.md`. First preserve/correct claims
and make gates reject false success; then prove one real-core firmware boot,
one exact AFE frame and one exact FIR result. Only after that measure timing/PPA.
