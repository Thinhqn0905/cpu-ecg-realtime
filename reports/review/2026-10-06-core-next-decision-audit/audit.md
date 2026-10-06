# Updated core / Gemini implementation decision audit — 2026-10-06

**Decision:** Retain the existing CV32E40P candidate and reusable peripherals. **NO_GO for 50 MHz routed acceptance and full ResUMamba/cascade claims. GO for a bounded baseline recovery and actual DSP-kernel campaign.** No build, simulator, test suite, Vivado, checkpoint opening or board programming was performed in this audit. Commands used read source/Git metadata, inspect existing artifact bytes, and compute hashes. Historical evidence is not a fresh rerun.

Root source HEAD: `d1659874120fcb6bd09366212dd699dae0011926`, clean at audit start. Core HEAD: `97086e9565f8145522ad6d62852123c0e5537529`, clean; `git describe --tags --always` = `cv32e40p_v1.8.3-6-g97086e9`. No tag points at core HEAD. File fingerprints and preserved inputs: `audit_manifest.json` and `snapshot/` beside this report. Live evidence manifests still do not bind all local/core sources to their runs.

## What changed since the previous recovery audit

| Previous finding | Current inspection | Disposition |
|---|---|---|
| Automatic handwritten/mock ELF fallback | Current `Firmware/build_boot_image.py` requires GCC/binutils and propagates compiler failure; old encoder removed | Fixed in source; do not repeat old accusation as current |
| Missing ELF and mismatched firmware hashes | Actual ELF/bin/map/dump/nm/readelf/hex exist; **7/7** hashes match `hello.sha256` | Current artifact integrity checked |
| Inconsistent ELF/image relationship | Static byte inspection: two PT_LOAD payloads match the 2108-byte bin at physical load addresses; bin prefix matches hex; zero mismatched bytes | Consistent artifact chain; not a compiler rerun |
| Undeclared D-TCM grant / C type in SV | Grant now uses declared `dtcm_gnt`; SPI TB uses SV signed int | Fixed in source |
| Runner never calls validator | PS simulation runner invokes validator before latest/SUCCESS; hash/run-id/census logic added | Improved; gaps remain in D6 |
| No routed FPGA evidence | Latest archived reports/DCP/bit/log exist; **14/14** listed artifact hashes match archived copies | Real retained routed artifacts; latest setup FAIL |
| Wrapper simulation clock pass-through | SIMULATION branch now divides oscillator by two | Fixed in source |

Stored XSIM `run_20261006_091539` log shows real-core boot/IRQ markers and six PASS events. Its two listed log artifacts match hashes. Firmware now checks .data/.bss and register canaries. This supports a **retained real-core boot/IRQ smoke simulation**, with source/firmware binding and independent negative-proof limits below. It does not prove inference, AFE streaming, DSP latency or a physical board.

## Findings and next decisions

### D1 — P0: Latest routed 50 MHz gate is FAIL, despite exit zero and bitstream

Run `20261006_093347`, Vivado2023.2, `ecg_arty_top`, `xc7a100tcsg324-1`:

| Boundary | Clock requirement | Setup WNS / TNS | Setup failing / total endpoints | Hold WHS / THS | Hold failing / total endpoints |
|---|---|---|---|---|---|
| Routed, global census | Generated compute clock 20.000 ns (50 MHz), oscillator 10.000 ns | **−0.815 / −63.389 ns** | **215 / 18,669** | +0.044 / 0.000 ns | 0 / 18,669 |

`timing_routed.rpt:162-167` explicitly says constraints are not met. Compute-clock-only setup census is215/15,454. `Instruction/session_checklist.md` V9 Task9.5.2 calls this closure based on positive hold slack and a48.04 MHz figure. That figure is consistent with a simple period/slack estimate, **not closure at 50 MHz or a measured Fmax campaign**, and it is below the specified50 MHz minimum.

`run_synth.tcl` retries routing, then writes reports/checkpoint/bitstream regardless of remaining negative slack. `run_fpga.ps1` declares success solely from native exit0. Thus bitstream existence and exit0 are genuine artifacts, but the **closure claim is contradicted**.

Worst retained setup path (`timing_setup.rpt:15-30`): core ID `alu_operator_ex_o_reg[5]` to `mult_operand_b_ex_o_reg[26]`; delay20.576 ns with5.753 ns logic and14.823 ns routing,27 logic levels. This identifies a path to investigate, not a proven cause or justification for a new CPU. Reuse core; first evaluate matched implementation recipes and wrapper/constraint correctness. Do not patch immutable upstream to make reports pass.

Historical `run_20261006_071047` reports WNS+0.008 ns/WHS+0.125 ns with a different endpoint census and16 RAMB36 rather than current40. It cannot be substituted for the expanded current candidate or treated as a controlled A/B comparison without matched inputs.

### D2 — P0: Cascade PASS is a diagnostic scenario with fixed output

`mamba_bridge.sv:72,128-155` sinks sample data/tlast, does not read src/dst memory, counts 64 cycles and assigns class 2/confidence0x7800 for opcode 3. `ecg_soc_top.sv:239-253` wires stream data to zero and valid to buffer-ready IRQ; this is not a sample payload DMA.

`hello.c` uses `beat_rr={800,800,480}` and arithmetic threshold to trigger opcode 3; it never calls production Pan-Tompkins, signal conditioning or `resumamba_infer_full`. It then expects precisely that fixed class/confidence. `soc_tb.sv` promotes the UART marker to cascade PASS. The successful log is consistent with this diagnostic stub, but **does not demonstrate Pan-Tompkins-triggered ResUMamba inference**. Preserve it as `diagnostic_stub`, withdraw inference/accuracy claims, disable that stub from the default baseline. Do not treat fixed results as trained-network evidence.

### D3 — P0: FIR sidecar is standalone, not the synthesized inference datapath

Tcl/filelist inclusion of `mamba_fir_sidecar.sv` does not instantiate it. No sidecar instance appears in the actual SoC sources or routed hierarchy. Latest routed hierarchy attributes all 7 DSP blocks to the CPU; `gen_mamba.u_mamba` uses 79 LUTs/143 FFs/zero DSPs. Therefore the FPGA resources do not prove synthesis of the claimed4-lane offload.

Standalone sidecar uses generated coefficients2048/(1+k/8),1024/(1+k/8), shared across lanes rather than exported per-channel model weights. It multiplies history samples by `fwd+bwd` coefficients: both contributions use **past** samples, not x[t−k] and x[t+k]. Default NUM_CHANNELS24 is unused in scheduling; it accepts only channel IDs below NUM_LANES4. `fir_ready_i` is explicitly unused and outputs advance without backpressure. History is not reset between start/restart operations. These are concrete source/contract gaps; no fresh dynamic failure is claimed.

`mamba_fir_tb.sv` impulse acceptance includes `... || done_o==1` after waiting for done, so zero output can pass. Other cases require nonzero energies instead of exact model reference. Latency benchmark configures16 steps; the report's69,632-cycle500-step “measured” result needs a matching raw500-step campaign. Scope: a standalone prototype FIR; not a connected, bit-exact24-channel bidirectional DiagSSM layer.

### D4 — P0: Quantization test does not execute frozen integer firmware

`scripts/quantize_resumamba.py:212-241` re-exports headers during testing and runs PyTorch after replacing only stem1, SSM FIR weights, and head with **dequantized float** weights. Many layers remain FP32; activation/accumulation/requantization follow PyTorch float execution. Existing C headers are not consumed as a frozen model by this test. Thus99.80% and0.01256, even if reproduced for that function, are neither C parity nor all-layer integer accuracy. One synthetic waveform without labels establishes prediction agreement only; no clinical tolerance/accuracy claim is justified.

Exporter computes independent max-based tensor scales but does not emit them to C. Firmware instead uses shifts7/15; it cannot reconstruct these arbitrary scales/bias relationships from raw integer arrays. Test MAE variable is actually `np.max(abs(...))`, not mean absolute error; use explicit metric naming.

Externally referenced model/checkpoint exist and were fingerprinted, not executed: `E:/ResearchOnWork/Backup/PhD_VNU/ecgr_torch/model.py` and `checkpoints_pt/resumamba_30k.pt`. Their existence does not prove export completeness.

### D5 — P0: C inference is a simplified graph and does not fit the current memory plan

`resumamba_infer.c:194-271` replaces ResU with smoothing, calls only block 0 of ResU/SSM, replaces learned fusion with averaging, and skips exported context/AdaIN layers. SSM implementation skips exported input projection/depthwise prefilter. The referenced PyTorch graph executes learned ResU blocks, SSM preprocessing, graph-configured branches and learned concatenation fusion; firmware is not that same graph. `test_resumamba_infer.c` checks nonzero energy and softmax sum, not layer parity; softmax sum is explicitly constructed by the production function. TC-INF-002 is described but not executed in main.

Static memory accounting from actual C declarations:

- Full inference keeps four500×24×int16 buffers =96,000 bytes live.
- Nested stem adds two2500×8×int16 buffers and500×8×int16 =88,000 bytes.
- Peak of those allocations alone is **184,000 bytes**, before raw input/output/stack/allocator overhead, beyond128 KiB D-TCM. Linker reserves only4 KiB heap. Allocations are unchecked.
- Headers contain31,204 weight elements and500 bias elements =**44,492 bytes** of declared parameter payload, not30,420 parameters/32.4 KB. This exceeds32 KiB I-TCM if the full payload is linked as current `.rodata`; actual live retained weight set must be established from a real inference ELF, not header/file size alone.

No ResUMamba symbols appear in inspected hello.nm; hello.elf is a2108-byte boot/stub program. Enlarging D-TCM does not prove the model runs. Reuse trained graph/export contract; either implement exact graph incrementally or explicitly name/evaluate a different reduced model.

### D6 — P1: Better validator still lacks mandatory campaign binding and timing acceptance

Simulation manifests hash logs/output but omit the full source/filelist fingerprint, firmware ELF/hex and compiler flags/version. Validator accepts plain path entries and dict artifacts without a hash; omission is not rejected. Fatal detector does not generally reject plain simulator `ERROR` or SVA `$error` messages. Shared XSIM snapshot `soc_tb_sim`, no wall timeout and mutable canonical firmware remain reproducibility risks. Fabricating a “clean compilation” stdout line when empty also loses the raw-output distinction; record the empty native output plus exit separately.

FPGA manifest binds only core top file and boot image, not core RTL/local sources/XDC/Tcl. Artifact paths refer to mutable root reports, although archived copies hash-match today. Run-local paths must be canonical. Source identity of each historical run remains NOT_VERIFIED until its source snapshot is supplied. Timing/constraints/DRC gate is absent entirely.

### D7 — P1: “29/29 verified” does not match requirements or checks

Canonical `spec/ecg_soc_reqs.json` has19 requirements; RTM has29 entries, including requirements absent from that JSON, and stale header says pending runs above a full-pass table. It maps SYS001(clock50 MHz) to hello markers, SYS003(DRDY→UART ≤10 ms) to isolated DMA/SPI checks, UART003/004(14-byte packet and CRC8) to text boot UART/byte controller. Those tests do not establish their requirements. DMA contract still differs: JSON32 samples/288 bytes per bank, implementation default256 samples/12-byte frames. Plan SPI divider50 conflicts with JSON25.

SVA files exist under `RTL/ecg_soc/sva/`, but `flist_spi_master_tb.f` omits checker/bind, while RTM calls them PASS(SVA) and cites an incorrect path. Even if enabled, `p_cs_setup_time` checks4 **system-clock** cycles (80 ns at 50 MHz), not4 SCLK cycles; `p_done_pulse` checks busy deassertion, not CS hold. Withdraw those requirement PASS labels. Never solve this by weakening a requirement just to match the current implementation; document an intentional contract revision first.

### D8 — P1: Core pin and physical exclusions need explicit review

`gem_implement_core.md` calls exact release tag/final frozen/fullGO; current core is six commits beyond the tag. Keep actual immutable HEAD and record it; do not checkout a different core merely to make text match.

Latest `check_timing.rpt` has no unconstrained **internal** endpoints, but no_input_delay8 (2 HIGH,6 false-path) and no_output_delay11 (4 HIGH,7 false-path). “Internal endpoints0” does not mean complete I/O timing. DRC lists47 warnings with REQP-1839 rule limit reached at 20; review reset/BRAM controls and rule truncation before signoff. XDC pin/voltage comments need retained official-board-source support before programming. Board execution remains NOT_VERIFIED.

### D9 — P1: DSP proof remains host-only; cycle figures unsupported

`dsp_test.c:29-34` host `ecg_fir_pulp` calls the very scalar reference used for comparison. TC-DSP-004 host branch emits PASS for a stubbed counter. This is a reference smoke, not assembly equivalence or target cycles. `resumamba_kernels_pulp.S` currently implements an ordinary lh/lb/mul/add loop, with no promised FIR hardware-loop function, and C inference does not call it. COREV_PULP=1 enables hardware features, but does not prove software uses them.

Tri-modal report's12,718,000 cycles,254.36 ms,12.72% load,<0.2% surveillance utilization and speedup lack matching on-target cycle/workload evidence. Retain only labeled estimates if a calculation/source is supplied; otherwise NOT_VERIFIED. No current signal/model test establishes clinical-grade validation.

## Recommended decision for gem_implement_core

1. Suspend V3 FULL GO and V9 completion promotions; preserve successful **and failed** runs. Separate boot smoke, routed completion, routed timing acceptance, standalone FIR, host reference and clinical boundaries.
2. Keep CV32E40P current immutable HEAD, local OBI/APB/TCM/DMA and50 MHz requirement. Gate baseline independently; default MAMBA diagnostic off. Do not write a replacement processor or complete new SoC.
3. Close evidence/RTM gate first, then a matched50 MHz timing campaign and small actual scalar/SIMD kernel campaign. If timing remains negative, report FAIL; lowering frequency below 50 MHz is a requirements decision, not a repair claim.
4. Freeze exact model/scales/memory contract before more model code. Connect a genuine input-dependent FIR only after measured firmware profiling justifies offload; preserve current standalone prototype as historical experimental work.

Next execution plan: `docs/plans/2026-10-06-core-next-decision-audit.md`. This audit modifies documentation/checklist only; it does not execute that plan or send instructions to another agent/service.
