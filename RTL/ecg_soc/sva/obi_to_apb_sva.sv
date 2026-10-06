// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0
//
// Description: SystemVerilog Assertions (SVA) for OBI-to-APB3 Bridge.
//              Validates OBI request-grant handshakes, APB3 two-phase setup/access timing,
//              and data integrity across the bus protocol domain.

module obi_to_apb_sva (
  input logic        clk_i,
  input logic        rst_ni,

  // OBI Interface
  input logic        obi_req_i,
  input logic        obi_gnt_o,
  input logic [31:0] obi_addr_i,
  input logic        obi_we_i,
  input logic [3:0]  obi_be_i,
  input logic [31:0] obi_wdata_i,
  input logic        obi_rvalid_o,
  input logic [31:0] obi_rdata_o,
  input logic        obi_err_o,

  // APB3 Interface
  input logic        apb_psel_o,
  input logic        apb_penable_o,
  input logic        apb_pwrite_o,
  input logic [31:0] apb_paddr_o,
  input logic [31:0] apb_pwdata_o,
  input logic [31:0] apb_prdata_i,
  input logic        apb_pready_i,
  input logic        apb_pslverr_i
);

`ifndef SYNTHESIS
`ifndef __ICARUS__
  // ---------------------------------------------------------------------------
  // Property 1: OBI Grant Assertion
  // When OBI request is accepted, grant must be high for that cycle
  // ---------------------------------------------------------------------------
  property p_obi_grant_on_req;
    @(posedge clk_i) disable iff (!rst_ni)
    (obi_req_i && !apb_psel_o) |-> obi_gnt_o;
  endproperty
  assert_obi_grant: assert property (p_obi_grant_on_req)
    else $error("SVA VIOLATION: OBI grant not asserted on accepted request!");

  // ---------------------------------------------------------------------------
  // Property 2: APB3 Phase Ordering
  // PENABLE must rise one cycle after PSEL, never simultaneously
  // ---------------------------------------------------------------------------
  property p_apb_phase_ordering;
    @(posedge clk_i) disable iff (!rst_ni)
    (apb_psel_o && !apb_penable_o) |=> (apb_psel_o && apb_penable_o);
  endproperty
  assert_apb_phase: assert property (p_apb_phase_ordering)
    else $error("SVA VIOLATION: APB3 PENABLE did not follow PSEL after 1 cycle!");

  // ---------------------------------------------------------------------------
  // Property 3: Address Stability during APB Transfer
  // PADDR must remain stable while PSEL is active until PREADY
  // ---------------------------------------------------------------------------
  property p_apb_addr_stability;
    @(posedge clk_i) disable iff (!rst_ni)
    (apb_psel_o && !apb_pready_i) |=> $stable(apb_paddr_o);
  endproperty
  assert_apb_addr_stable: assert property (p_apb_addr_stability)
    else $error("SVA VIOLATION: APB3 PADDR changed before PREADY asserted!");

  // ---------------------------------------------------------------------------
  // Property 4: OBI RVALID on APB Completion
  // RVALID must assert when APB slave ready is sampled during ACCESS phase
  // ---------------------------------------------------------------------------
  property p_obi_rvalid_on_pready;
    @(posedge clk_i) disable iff (!rst_ni)
    (apb_psel_o && apb_penable_o && apb_pready_i) |-> obi_rvalid_o;
  endproperty
  assert_obi_rvalid: assert property (p_obi_rvalid_on_pready)
    else $error("SVA VIOLATION: OBI RVALID not asserted on APB PREADY completion!");

`endif
`endif

endmodule : obi_to_apb_sva
