// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0
//
// Description: Open Bus Interface (OBI) to APB3 Master Bridge.
//              Converts CV32E40P pipelined OBI data requests into
//              standard 2-cycle AMBA APB3 transactions with zero wait-state grant.

module obi_to_apb (
  input  logic        clk_i,
  input  logic        rst_ni,

  // OBI Slave Interface (Connected to CV32E40P data_* port)
  input  logic        obi_req_i,
  output logic        obi_gnt_o,
  input  logic [31:0] obi_addr_i,
  input  logic        obi_we_i,
  input  logic [3:0]  obi_be_i,
  input  logic [31:0] obi_wdata_i,
  output logic        obi_rvalid_o,
  output logic [31:0] obi_rdata_o,
  output logic        obi_err_o,

  // APB3 Master Interface (Connected to SoC Peripherals)
  output logic        apb_psel_o,
  output logic        apb_penable_o,
  output logic        apb_pwrite_o,
  output logic [31:0] apb_paddr_o,
  output logic [31:0] apb_pwdata_o,
  input  logic [31:0] apb_prdata_i,
  input  logic        apb_pready_i,
  input  logic        apb_pslverr_i
);

  typedef enum logic [1:0] {
    ST_IDLE   = 2'b00,
    ST_SETUP  = 2'b01,
    ST_ACCESS = 2'b10
  } state_e;

  state_e state_q, state_d;

  // Latch request parameters
  logic [31:0] addr_q, addr_d;
  logic [31:0] wdata_q, wdata_d;
  logic        we_q, we_d;

  always_comb begin
    state_d      = state_q;
    addr_d       = addr_q;
    wdata_d      = wdata_q;
    we_d         = we_q;

    obi_gnt_o    = 1'b0;
    obi_rvalid_o = 1'b0;
    obi_rdata_o  = apb_prdata_i;
    obi_err_o    = 1'b0;

    apb_psel_o    = 1'b0;
    apb_penable_o = 1'b0;
    apb_pwrite_o  = we_q;
    apb_paddr_o   = addr_q;
    apb_pwdata_o  = wdata_q;

    case (state_q)
      ST_IDLE: begin
        if (obi_req_i) begin
          obi_gnt_o = 1'b1; // Grant immediately on acceptance
          addr_d    = obi_addr_i;
          wdata_d   = obi_wdata_i;
          we_d      = obi_we_i;
          state_d   = ST_SETUP;
        end
      end

      ST_SETUP: begin
        apb_psel_o    = 1'b1;
        apb_penable_o = 1'b0;
        state_d       = ST_ACCESS;
      end

      ST_ACCESS: begin
        apb_psel_o    = 1'b1;
        apb_penable_o = 1'b1;

        if (apb_pready_i) begin
          obi_rvalid_o = 1'b1;
          obi_rdata_o  = apb_prdata_i;
          obi_err_o    = apb_pslverr_i;

          // Pipeline next incoming OBI request if present
          if (obi_req_i) begin
            obi_gnt_o = 1'b1;
            addr_d    = obi_addr_i;
            wdata_d   = obi_wdata_i;
            we_d      = obi_we_i;
            state_d   = ST_SETUP;
          end else begin
            state_d   = ST_IDLE;
          end
        end
      end

      default: state_d = ST_IDLE;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= ST_IDLE;
      addr_q  <= '0;
      wdata_q <= '0;
      we_q    <= 1'b0;
    end else begin
      state_q <= state_d;
      addr_q  <= addr_d;
      wdata_q <= wdata_d;
      we_q    <= we_d;
    end
  end

endmodule : obi_to_apb
