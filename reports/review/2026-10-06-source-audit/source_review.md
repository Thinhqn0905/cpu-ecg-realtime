# ECG SoC source review — 2026-10-06

## Verdict

The APB peripheral decomposition is a useful starting point, but this is a
peripheral prototype, not an integrated CVA6 ECG SoC. The active specification
has diverged from the operating rules. Do not proceed on the basis of the
existing ALL GATES PASS dashboard. Restore one CVA6 RV32IMA, firmware-first
baseline and establish core feasibility before accelerator development.

## Reproducible boundary

Campaign: `2026-10-06-source-audit`. Fingerprints, exact filelists, commands and
exit codes: `manifest.json` in this directory. Root workspace has no Git
repository; its source identity is the captured SHA-256 list, not a commit.
Upstream CVA6 commit: `81245a47fad8fe1a5d562d953ef2662e099def76`;
`git -C cva6 status --short` was empty. All 18 listed upstream submodules had
the leading `-` marker (not initialized). No upstream files were edited.

| Check | Actual observation | Permitted conclusion |
|---|---|---|
| Icarus 12.0, SPI testbench compile | exit 0, warnings in `spi_compile.log` | Compiled this testbench, without SVA bind |
| Icarus, peripheral top compile | exit 0, warnings in `top_compile.log` | Peripheral top elaborates in Icarus; no CPU |
| Original SPI smoke test | exit 0, five PASS messages, RX `0xc00000`; `spi_run.json` | Limited smoke simulation reproduced; not full sample correctness |
| WSL Ubuntu Verilator 4.038, `--lint-only -Wall` | exit 1, 30 warnings; `verilator_lint.log` | This exact strict lint invocation fails; some warnings are intentional open pins, others widths/unused signals |
| CVA6 boot/elaboration, firmware, Vivado synthesis, routing, board | No matching raw evidence found | NOT_VERIFIED |

Windows PATH did not expose Vivado, Verilator or RISC-V GCC; WSL exposed
Verilator and Icarus. This is discovery evidence, not proof that tools are absent
elsewhere. Verilator 4.038 is old; select a supported version before treating
its diagnostics as the sole language-compatibility verdict.

## Findings, ordered by impact

1. **Critical — acquisition data is disconnected.**
   `RTL/ecg_soc/ecg_soc_top.sv:201` passes `spi_irq` to DMA valid;
   `spi_master_apb.sv:77` defines that IRQ as a DRDY edge, not transfer completion.
   Top lines 202–204 hard-code status and both channels (zero channels).
   `spi_master_apb.sv:54` fixes WORD_LEN to 24. There is no 72-bit frame assembler
   or completed-sample handshake. This wiring cannot deliver both AFE channels.

2. **Critical — architecture drift.** `spec/ecg_soc_spec.md:58` recommends Ibex
   and its diagram uses RV32IMC, while AGENTS requires CVA6 RV32IMA.
   CNN-MAMBA, enabled accelerator config and autonomous DMA precede firmware
   profiling, contrary to the required firmware-first boundary. Research
   comparisons are proposals, not authority to switch cores. Keep these as
   deferred alternatives until an explicit decision supported by matched
   measurements. No CPU, AXI bridge, PLIC, CLINT, ROM, SRAM or MMCM is
   instantiated in `ecg_soc_top.sv`.

3. **High — reported verification exceeds the tests.** RTM lists 19 requirement
   rows and JSON contains 19 IDs, but its summary says 18. The only current
   DUT testbench exercises TC-001/002/007; five PASS messages are five checks,
   not 12 executed testcases. TC-002 prints Done=1 without asserting it;
   TC-007 accepts any nonzero RX and waits a fixed 100 cycles. It reproduced
   the model's status word `0xc00000`, not a validated channel sample. No
   timeout or `$fatal` on final failure; `$finish` can return success despite
   errors. No raw mutation campaign, approval record or full RTM evidence.

4. **High — AFE model uses opposite SPI edges.** Model lines 63–97 sample DIN
   on rising edges and shift DOUT on falling edges. TI specifies DIN capture
   on falling edges and DOUT changes after rising edges. Its register read
   recognition checks only the second byte and ignores the first opcode.
   Model/master interactions cannot establish datasheet compliance.

5. **High — timing contract has incorrect units and register address.**
   `design_rules.md:16` and spec REQ-SPI-004/005 conflate AFE CLK and SCLK.
   TI Table 6.6 gives tCSSC in ns, tSCCS = 3 tCLK, tCSH = 2 tCLK and
   tSDECODE = 4 tCLK. At nominal 512 kHz AFE CLK, 3 tCLK is approximately
   5.86 us (derived), whereas four 2 MHz SCLK periods are 2 us. Select actual
   AFE clock and worst-case bounds before defining command timing.
   `evidence_contract.md` incorrectly identifies ID register address as 0x01;
   TI section 8.6.1.1 says 0x00. The silicon ID mask/value must follow that table.

6. **High — UART RX has an APB side effect in SETUP.**
   `uart_apb.sv:88–92` asserts rx_ready whenever PSEL and read address match,
   without PENABLE/PREADY. A normal setup/access transaction can pop twice
   and return the next byte. Fix to a single accepted access. TX writes when
   full are acknowledged and dropped without a visible overrun indication;
   FIFO error outputs are discarded. These are source-level findings requiring
   directed simulation to quantify behavior.

7. **High — buffer ownership and latency are unresolved.** DMA lines 63 and
   108 make overflow transient rather than sticky; no dropped-sample counter.
   It keeps writing into an unread bank and produces a pulse instead of the
   specified persistent bank-ready level. The pointer and read index are fixed
   at 5 bits although bank size is a parameter. Stores 8 bytes/sample, not the
   specified full 9 bytes; status is reduced to 8 bits. If firmware waits for a
   32-sample bank at 500 Hz, the first sample waits 31/500 = 62 ms before
   readout (derived), already exceeding the 10 ms budget. A future continuous
   per-sample consumer can avoid this; that consumer does not exist yet.

8. **Medium — divider and modes do not match configuration.**
   SPI line 82 uses floor(clk_div/2) for each half-period. With divider 25 at
   nominal 50 MHz, period is 24 system cycles and frequency is approximately
   2.0833 MHz, not 2 MHz (source-derived, not measured). CPHA and DEFAULT_CLK_DIV
   parameters are unused; wrapper fixes Mode 1/24 bits and no SPI FIFO exists.
   SCLK is an output toggled by the system clock; an asynchronous FIFO is not
   justified by an internally created second domain here. Correct the spec or
   define and verify an actual clock-domain crossing.

9. **Medium — assertions do not check the claimed timing.**
   `spi_master_sva.sv:41` checks four system-clock samples, not four SCLK periods;
   `p_done_pulse` checks busy deassertion, not CS hold time. Our compile and lint
   filelists did not include these assertions. Their execution remains NOT_VERIFIED.

10. **Medium — maps and boot assumptions disagree.** IRQ IDs differ among spec,
    architecture and package; PLIC span is 64 KB in spec versus 64 MB in
    architecture. Neither is a validated decode map. CVA6's selected config
    enables execution at 0x80000000, 0x00010000 and 0x00000000 with bounded
    lengths (`cv32a6_ima_sv32_fpga_config_pkg.sv:135–137`); proposed SRAM at
    0x01000000 is outside those regions. The proposed 64 KB ROM at zero also
    exceeds the 4 KB executable region there. Match reset PC, executable map,
    ROM/SRAM placement and linker before boot tests, using an external project
    configuration adapter rather than editing upstream.

## Primary source checked

[TI ADS1292R datasheet SBAS502C](https://www.ti.com/lit/ds/symlink/ads1292r.pdf),
sections 6.6, 8.5.1.3–5, 8.5.2.10 and 8.6.1.1. Preserve distinction between
SCLK and AFE CLK. A deliberately conservative project margin may be retained,
but must not be labelled as the datasheet minimum.

## Next work

Use `docs/plans/2026-10-06-ecg-soc-baseline-recovery.md`. First recover the
spec/evidence baseline; next prove CVA6 feasibility and repair the peripheral
tests/data path. Target a firmware-produced 500 Hz, two-channel raw stream at
50 MHz before adding optional DMA or neural acceleration. Synthesis, routed
timing and board results remain independent gates.
