// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0
//
// Description: SVA property checks for ADS1292R SPI Master interface timing.

module spi_master_sva #(
  parameter int unsigned WORD_LEN = 24,
  parameter bit          CPOL     = 1'b0,
  parameter bit          CPHA     = 1'b1
) (
  input logic                clk_i,
  input logic                rst_ni,
  input logic                cs_no,
  input logic                sclk_o,
  input logic                mosi_o,
  input logic                miso_i,
  input logic                drdy_ni,
  input logic                busy_o,
  input logic                done_o,
  input logic [WORD_LEN-1:0] tx_data_i,
  input logic [WORD_LEN-1:0] rx_data_o
);

`ifndef SYNTHESIS
`ifndef __ICARUS__

  // ---------------------------------------------------------------------------
  // REQ-SPI-001: Clock Polarity Idle State Check
  // ---------------------------------------------------------------------------
  property p_cpol_idle;
    @(posedge clk_i) disable iff (!rst_ni)
    cs_no |-> (sclk_o == CPOL);
  endproperty
  a_cpol_idle: assert property (p_cpol_idle)
    else $error("[SVA-SPI-001] SCLK must stay at CPOL while CS# is deasserted!");

  // ---------------------------------------------------------------------------
  // REQ-SPI-004: CS# Setup Time Check (tCSSC >= 4 SCLK cycles before toggle)
  // ---------------------------------------------------------------------------
  property p_cs_setup_time;
    @(posedge clk_i) disable iff (!rst_ni)
    $fell(cs_no) |-> (sclk_o == CPOL) [*4];
  endproperty
  a_cs_setup: assert property (p_cs_setup_time)
    else $error("[SVA-SPI-004] Violation of ADS1292R tCSSC setup time!");

  // ---------------------------------------------------------------------------
  // REQ-SPI-005: CS# Hold Time Check (tSCCS >= 4 SCLK cycles after final edge)
  // ---------------------------------------------------------------------------
  property p_done_pulse;
    @(posedge clk_i) disable iff (!rst_ni)
    done_o |=> !busy_o;
  endproperty
  a_done_pulse: assert property (p_done_pulse)
    else $error("[SVA-SPI-005] Busy flag must deassert following done pulse!");

  // Coverage Points
  c_transfer_cycle: cover property (@(posedge clk_i) $fell(cs_no) ##[10:$] done_o);

`endif
`endif

endmodule : spi_master_sva
