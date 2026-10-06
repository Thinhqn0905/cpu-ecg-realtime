# EDA Script Style Contract

Recreated 2026-10-06 during source review because the required file was absent.

- Show the exact top, ordered source filelist, include paths, tool/version,
  FPGA part, named ports, clock periods in ns and I/O assumptions.
- Vivado Tcl uses direct commands (`read_verilog`, `read_xdc`, `synth_design`,
  `opt_design`, `place_design`, `route_design`, `report_timing_summary`,
  `report_utilization`); do not conceal these behind environment wrappers or
  custom Tcl procedures.
- Constrain the Arty oscillator at 100 MHz separately from MMCM/BUFG system
  clocks. Verify generated clocks and reset/CDC constraints.
- Preserve command, exit code, stdout/stderr, failures, source SHA-256 hashes,
  tool version and boundary for each campaign. Never infer success from PASS text.
- Simulation must specify top and timeout and fail with nonzero exit on mismatch.
  Assertion-enabled and assertion-disabled runs are different evidence boundaries.
- Do not modify upstream `cva6/` to accommodate a tool. Any diagnostic source
  transformation belongs in an isolated copy and must be named in the manifest.
- Routed acceptance requires completed routing, setup/hold and unconstrained-path
  census at the named system clock. Synthesis timing is not routed timing.
- Confirm board revision, official Master XDC and AFE digital voltage before
  applying PMOD I/O constraints. Do not invent pin or electrical assumptions.
