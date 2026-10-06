# RTL Design Rules — RISC-V ECG SoC

## General Coding Style

Match CVA6 SystemVerilog conventions for consistency:

1. Use `always_ff @(posedge clk_i)` for all sequential logic. Never use
   `always @(posedge clk)` or blocking assignments in sequential blocks.
2. Use `always_comb` for all combinational logic. Never use `always @(*)`.
3. Suffix conventions: `_i` input, `_o` output, `_n` active-low, `_q`
   registered, `_d` next-state combinational.
4. One module per file. Filename matches module name.
5. Module ports in ANSI style with explicit direction and width.
6. Parameters at module level, localparam for derived constants.
7. No `initial` blocks in synthesizable RTL (testbench only).
8. No `real`, `shortreal`, DPI math, or behavioral division in
   synthesizable logic.

## SoC Integration Rules

9. New peripherals connect via APB bus to the existing CVA6 APB bridge.
   Memory-mapped register interface with standard APB signals
   (PSEL, PENABLE, PWRITE, PADDR, PWDATA, PRDATA, PREADY, PSLVERR).
10. Interrupt lines connect to PLIC via dedicated interrupt IDs.
    Document the interrupt map in `Instruction/architecture.md`.
11. Clock and reset follow the SoC-wide scheme: single clock domain
    unless explicitly justified. Clock domain crossings use proper
    synchronizers (2-FF minimum).
12. AXI interfaces follow AXI4/AXI4-Lite protocol with proper
    handshaking. No protocol violations (RVALID without ARREADY, etc.).

## SPI Master Rules

13. SPI clock divider is parameterized (minimum divide-by-2).
14. Support CPOL=0/1, CPHA=0/1 (all four SPI modes).
15. Transfer width configurable: 8, 16, 24 bits (ADS1292R uses 24-bit).
16. CS assertion/deassertion timing meets ADS1292R datasheet minimums
    (tCSSC, tSCCS, tCSH — at least 4 SCLK cycles).
17. DRDY is active-low, directly connected to PLIC interrupt input.
    No glitch filtering in RTL — the ADS1292R guarantees clean edges.
18. SPI TX/RX FIFOs: parameterized depth (default 8 entries).

## UART Rules

19. Baud rate generator with configurable divider from system clock.
20. TX/RX FIFOs: parameterized depth (default 16 entries).
21. Interrupt on: TX FIFO empty, RX FIFO not empty, RX FIFO full,
    frame error, overrun error.
22. 8N1 format standard. Optional parity support.

## FIFO Rules

23. FIFOs are synchronous, parameterized depth and width.
24. Full/empty/almost-full/almost-empty status signals.
25. Overflow and underflow protection (writes to full FIFO are dropped,
    reads from empty FIFO return last value + error flag).
26. BRAM inference for depth ≥ 16. Distributed RAM for smaller.

## Verification Rules

27. Every new module has a corresponding testbench under `Simulation/`.
28. Testbenches use `$display`/`$error`/`$fatal` for pass/fail.
29. Self-checking testbenches with golden comparison, not manual
    waveform inspection.
30. Coverage: exercise all register fields, all FIFO boundary conditions
    (empty, full, one-from-full), all error conditions.

## FPGA-Specific Rules

31. Never add Xilinx primitives or attributes to `cva6/` source.
    FPGA adaptations use wrapper modules under `RTL/ecg_soc/fpga/`.
32. Clock management: MMCM/PLL instantiation only in top-level FPGA
    wrapper. All compute logic sees a single clock from BUFG output.
33. I/O buffers: IBUF/OBUF only in top-level FPGA wrapper.
34. BRAM inference: use standard register-file coding patterns.
    Avoid Xilinx-specific BRAM primitives unless resource-critical.
35. Timing constraints: all clocks, I/O delays, and false paths
    documented in XDC with comments explaining each constraint.

## Naming Conventions

```
ecg_soc_top         — top-level FPGA wrapper
ecg_soc_core        — SoC core (CVA6 + interconnect + peripherals)
spi_master          — SPI master controller
spi_master_apb      — SPI master with APB slave interface
uart_controller     — UART with FIFO
uart_apb            — UART with APB slave interface
timer_apb           — Timer/counter with APB interface
gpio_apb            — GPIO with APB interface
ecg_dma             — Optional DMA controller
ecg_filter_hw       — Optional hardware filter accelerator
sync_fifo           — Synchronous FIFO (parameterized)
apb_interconnect    — APB address decoder/mux
```
