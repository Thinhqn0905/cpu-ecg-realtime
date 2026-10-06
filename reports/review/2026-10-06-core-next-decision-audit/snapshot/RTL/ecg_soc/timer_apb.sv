// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0
//
// Description: 32-bit programmable APB countdown/periodic timer with
//              interrupt generation on terminal count.

module timer_apb
  import ecg_soc_pkg::*;
(
  input  logic        clk_i,
  input  logic        rst_ni,

  // APB3 Slave Interface
  input  logic        psel_i,
  input  logic        penable_i,
  input  logic        pwrite_i,
  input  logic [11:0] paddr_i,
  input  logic [31:0] pwdata_i,
  output logic [31:0] prdata_o,
  output logic        pready_o,
  output logic        pslverr_o,

  // Interrupt
  output logic        irq_o
);

  logic [31:0] counter_q, counter_d;
  logic [31:0] reload_q, reload_d;
  logic [2:0]  ctrl_q, ctrl_d; // [0]: Enable, [1]: Auto-reload, [2]: IRQ enable
  logic        match_flag_q, match_flag_d;

  assign pready_o  = 1'b1;
  assign pslverr_o = 1'b0;
  assign irq_o     = match_flag_q && ctrl_q[2];

  // Register Read Logic
  always_comb begin
    prdata_o = 32'h0000_0000;

    if (psel_i && !pwrite_i) begin
      case (paddr_i)
        TIMER_REG_COUNTER: prdata_o = counter_q;
        TIMER_REG_RELOAD:  prdata_o = reload_q;
        TIMER_REG_CTRL:    prdata_o = {29'h0, ctrl_q};
        TIMER_REG_STATUS:  prdata_o = {31'h0, match_flag_q};
        default:           prdata_o = 32'h0000_0000;
      endcase
    end
  end

  // Counter and Register Write Logic
  always_comb begin
    counter_d    = counter_q;
    reload_d     = reload_q;
    ctrl_d       = ctrl_q;
    match_flag_d = match_flag_q;

    // Timer decrement logic
    if (ctrl_q[0]) begin // Enabled
      if (counter_q == 32'd0) begin
        match_flag_d = 1'b1;
        if (ctrl_q[1]) begin // Auto-reload
          counter_d = reload_q;
        end else begin
          ctrl_d[0] = 1'b0; // Stop
        end
      end else begin
        counter_d = counter_q - 1'b1;
      end
    end

    // APB Write
    if (psel_i && penable_i && pwrite_i) begin
      case (paddr_i)
        TIMER_REG_COUNTER: counter_d    = pwdata_i;
        TIMER_REG_RELOAD:  reload_d     = pwdata_i;
        TIMER_REG_CTRL:    ctrl_d       = pwdata_i[2:0];
        TIMER_REG_STATUS:  if (pwdata_i[0]) match_flag_d = 1'b0; // W1C
        default: ;
      endcase
    end
  end

  // Sequential updates
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      counter_q    <= '0;
      reload_q     <= 32'd500_000; // Default 10ms at 50MHz
      ctrl_q       <= 3'b000;
      match_flag_q <= 1'b0;
    end else begin
      counter_q    <= counter_d;
      reload_q     <= reload_d;
      ctrl_q       <= ctrl_d;
      match_flag_q <= match_flag_d;
    end
  end

endmodule : timer_apb
