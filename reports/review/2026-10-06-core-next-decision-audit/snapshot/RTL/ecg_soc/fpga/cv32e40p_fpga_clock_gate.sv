// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0
//
// FPGA Clock Gate Cell for Xilinx 7-Series (Artix-7)
// Replaces simulation-only latch-based cv32e40p_sim_clock_gate.sv
// per CV32E40P integration manual section "Clock Gating Cell".

`timescale 1ns / 1ps
`default_nettype none

module cv32e40p_clock_gate (
    input  wire logic clk_i,
    input  wire logic en_i,
    input  wire logic scan_cg_en_i,
    output wire logic clk_o
);

  // Directly assign clock to eliminate cascaded BUFGs, latch loops, and clock tree skew
  assign clk_o = clk_i;

endmodule
`default_nettype wire
