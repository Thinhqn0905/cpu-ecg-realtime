// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0
//
// Description: Bind file attaching SVA assertions to spi_master.

`ifndef SYNTHESIS

bind spi_master spi_master_sva #(
  .WORD_LEN(WORD_LEN),
  .CPOL(CPOL),
  .CPHA(CPHA)
) u_spi_master_sva (
  .clk_i     (clk_i),
  .rst_ni    (rst_ni),
  .cs_no     (cs_no),
  .sclk_o    (sclk_o),
  .mosi_o    (mosi_o),
  .miso_i    (miso_i),
  .drdy_ni   (drdy_ni),
  .busy_o    (busy_o),
  .done_o    (done_o),
  .tx_data_i (tx_data_i),
  .rx_data_o (rx_data_o)
);

`endif
