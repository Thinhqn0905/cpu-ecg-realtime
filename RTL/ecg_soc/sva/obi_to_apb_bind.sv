// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0
//
// Description: SVA Bind File for OBI-to-APB3 Bridge.

bind obi_to_apb obi_to_apb_sva u_sva (
  .clk_i        (clk_i),
  .rst_ni       (rst_ni),
  .obi_req_i    (obi_req_i),
  .obi_gnt_o    (obi_gnt_o),
  .obi_addr_i   (obi_addr_i),
  .obi_we_i     (obi_we_i),
  .obi_be_i     (obi_be_i),
  .obi_wdata_i  (obi_wdata_i),
  .obi_rvalid_o (obi_rvalid_o),
  .obi_rdata_o  (obi_rdata_o),
  .obi_err_o    (obi_err_o),
  .apb_psel_o   (apb_psel_o),
  .apb_penable_o(apb_penable_o),
  .apb_pwrite_o (apb_pwrite_o),
  .apb_paddr_o  (apb_paddr_o),
  .apb_pwdata_o (apb_pwdata_o),
  .apb_prdata_i (apb_prdata_i),
  .apb_pready_i (apb_pready_i),
  .apb_pslverr_i(apb_pslverr_i)
);
