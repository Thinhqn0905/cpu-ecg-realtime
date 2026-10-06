// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0
//
// Description: APB3 slave wrapper for UART controller.
//              Provides memory-mapped registers for CPU serial I/O.

module uart_apb
  import ecg_soc_pkg::*;
#(
  parameter int unsigned FIFO_DEPTH = 16
) (
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

  // External UART Pins
  output logic        tx_o,
  input  logic        rx_i,

  // Interrupts
  output logic        tx_irq_o,
  output logic        rx_irq_o
);

  // Configuration and Control Registers
  logic [15:0] baud_div_q, baud_div_d;
  logic [3:0]  ctrl_q, ctrl_d; // [0]: TX IRQ en, [1]: RX IRQ en

  // Internal Core Signals
  logic [7:0]  tx_data;
  logic        tx_valid;
  logic        tx_ready;
  logic [7:0]  rx_data;
  logic        rx_valid;
  logic        rx_ready;
  logic        tx_fifo_empty;
  logic        tx_fifo_full;
  logic        rx_fifo_empty;
  logic        rx_fifo_full;
  logic        frame_err;
  logic        raw_tx_irq;
  logic        raw_rx_irq;
  wire         _unused_signals = &{1'b0, tx_ready, rx_valid, pwdata_i[31:16]};

  assign pready_o  = 1'b1;
  assign pslverr_o = 1'b0;

  // Instantiate UART Core
  uart_controller #(
    .FIFO_DEPTH(FIFO_DEPTH)
  ) u_uart_core (
    .clk_i          (clk_i),
    .rst_ni         (rst_ni),
    .baud_div_i     (baud_div_q),
    .tx_data_i      (tx_data),
    .tx_valid_i     (tx_valid),
    .tx_ready_o     (tx_ready),
    .rx_data_o      (rx_data),
    .rx_valid_o     (rx_valid),
    .rx_ready_i     (rx_ready),
    .tx_o           (tx_o),
    .rx_i           (rx_i),
    .tx_fifo_empty_o(tx_fifo_empty),
    .tx_fifo_full_o (tx_fifo_full),
    .rx_fifo_empty_o(rx_fifo_empty),
    .rx_fifo_full_o (rx_fifo_full),
    .frame_err_o    (frame_err),
    .tx_irq_o       (raw_tx_irq),
    .rx_irq_o       (raw_rx_irq)
  );

  assign tx_irq_o = raw_tx_irq && ctrl_q[0];
  assign rx_irq_o = raw_rx_irq && ctrl_q[1];

  // Register Read Logic
  always_comb begin
    prdata_o = 32'h0000_0000;
    rx_ready = 1'b0;

    if (psel_i && !pwrite_i) begin
      case (paddr_i)
        UART_REG_RXDATA: begin
          prdata_o = {24'h0, rx_data};
          // Pop byte strictly on the accepted ACCESS phase (psel && penable && pready)
          rx_ready = penable_i && pready_o;
        end
        UART_REG_STATUS: begin
          prdata_o = {27'h0, frame_err, rx_fifo_full, rx_fifo_empty, tx_fifo_full, tx_fifo_empty};
        end
        UART_REG_CTRL: begin
          prdata_o = {28'h0, ctrl_q};
        end
        UART_REG_BAUDDIV: begin
          prdata_o = {16'h0, baud_div_q};
        end
        default: prdata_o = 32'h0000_0000;
      endcase
    end
  end

  // Register Write Logic
  always_comb begin
    baud_div_d = baud_div_q;
    ctrl_d     = ctrl_q;
    tx_data    = 8'h00;
    tx_valid   = 1'b0;

    if (psel_i && penable_i && pwrite_i) begin
      case (paddr_i)
        UART_REG_TXDATA: begin
          tx_data  = pwdata_i[7:0];
          tx_valid = 1'b1;
        end
        UART_REG_CTRL: begin
          ctrl_d = pwdata_i[3:0];
        end
        UART_REG_BAUDDIV: begin
          baud_div_d = (pwdata_i[15:0] >= 16'd4) ? pwdata_i[15:0] : 16'd4;
        end
        default: ;
      endcase
    end
  end

  // Sequential updates
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      baud_div_q <= 16'd434; // 115200 baud @ 50 MHz
      ctrl_q     <= 4'b0011; // Enable TX & RX IRQ by default
    end else begin
      baud_div_q <= baud_div_d;
      ctrl_q     <= ctrl_d;
    end
  end

endmodule : uart_apb
