// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0
//
// Description: 8N1 UART Controller with programmable baud rate generator,
//              16-byte TX/RX FIFOs, and framing error detection.

module uart_controller #(
  parameter int unsigned FIFO_DEPTH = 16
) (
  input  logic        clk_i,
  input  logic        rst_ni,

  // Configuration
  input  logic [15:0] baud_div_i,   // e.g. 434 for 115200 baud @ 50 MHz

  // Host TX Data Interface
  input  logic [7:0]  tx_data_i,
  input  logic        tx_valid_i,
  output logic        tx_ready_o,

  // Host RX Data Interface
  output logic [7:0]  rx_data_o,
  output logic        rx_valid_o,
  input  logic        rx_ready_i,

  // Physical UART Signals
  output logic        tx_o,
  input  logic        rx_i,

  // Status & Interrupts
  output logic        tx_fifo_empty_o,
  output logic        tx_fifo_full_o,
  output logic        rx_fifo_empty_o,
  output logic        rx_fifo_full_o,
  output logic        frame_err_o,
  output logic        tx_irq_o,
  output logic        rx_irq_o
);

  // ---------------------------------------------------------------------------
  // TX and RX FIFOs
  // ---------------------------------------------------------------------------
  logic [7:0] tx_fifo_rdata;
  logic       tx_fifo_pop;
  logic       tx_fifo_empty;
  logic       tx_fifo_full;

  /* verilator lint_off PINCONNECTEMPTY */
  sync_fifo #(
    .DATA_WIDTH(8),
    .FIFO_DEPTH(FIFO_DEPTH)
  ) u_tx_fifo (
    .clk_i          (clk_i),
    .rst_ni         (rst_ni),
    .push_i         (tx_valid_i),
    .data_i         (tx_data_i),
    .full_o         (tx_fifo_full),
    .almost_full_o  (),
    .overflow_err_o (),
    .pop_i          (tx_fifo_pop),
    .data_o         (tx_fifo_rdata),
    .empty_o        (tx_fifo_empty),
    .almost_empty_o (),
    .underflow_err_o(),
    .level_o        ()
  );

  logic [7:0] rx_fifo_wdata;
  logic       rx_fifo_push;
  logic       rx_fifo_empty;
  logic       rx_fifo_full;

  sync_fifo #(
    .DATA_WIDTH(8),
    .FIFO_DEPTH(FIFO_DEPTH)
  ) u_rx_fifo (
    .clk_i          (clk_i),
    .rst_ni         (rst_ni),
    .push_i         (rx_fifo_push),
    .data_i         (rx_fifo_wdata),
    .full_o         (rx_fifo_full),
    .almost_full_o  (),
    .overflow_err_o (),
    .pop_i          (rx_ready_i),
    .data_o         (rx_data_o),
    .empty_o        (rx_fifo_empty),
    .almost_empty_o (),
    .underflow_err_o(),
    .level_o        ()
  );
  /* verilator lint_on PINCONNECTEMPTY */

  assign tx_ready_o      = !tx_fifo_full;
  assign rx_valid_o      = !rx_fifo_empty;
  assign tx_fifo_empty_o = tx_fifo_empty;
  assign tx_fifo_full_o  = tx_fifo_full;
  assign rx_fifo_empty_o = rx_fifo_empty;
  assign rx_fifo_full_o  = rx_fifo_full;
  assign tx_irq_o        = tx_fifo_empty;
  assign rx_irq_o        = !rx_fifo_empty;

  // ---------------------------------------------------------------------------
  // Transmitter FSM
  // ---------------------------------------------------------------------------
  typedef enum logic [1:0] {
    TX_IDLE  = 2'b00,
    TX_START = 2'b01,
    TX_DATA  = 2'b10,
    TX_STOP  = 2'b11
  } tx_state_e;

  tx_state_e tx_state_q, tx_state_d;
  logic [15:0] tx_baud_cnt_q, tx_baud_cnt_d;
  logic [2:0]  tx_bit_cnt_q, tx_bit_cnt_d;
  logic [7:0]  tx_shreg_q, tx_shreg_d;
  logic        tx_bit_q, tx_bit_d;

  assign tx_o = tx_bit_q;

  always_comb begin
    tx_state_d    = tx_state_q;
    tx_baud_cnt_d = tx_baud_cnt_q;
    tx_bit_cnt_d  = tx_bit_cnt_q;
    tx_shreg_d    = tx_shreg_q;
    tx_bit_d      = tx_bit_q;
    tx_fifo_pop   = 1'b0;

    case (tx_state_q)
      TX_IDLE: begin
        tx_bit_d = 1'b1; // Mark state (idle high)
        if (!tx_fifo_empty) begin
          tx_fifo_pop   = 1'b1;
          tx_shreg_d    = tx_fifo_rdata;
          tx_state_d    = TX_START;
          tx_baud_cnt_d = '0;
        end
      end

      TX_START: begin
        tx_bit_d = 1'b0; // Start bit
        if (tx_baud_cnt_q >= baud_div_i - 1'b1) begin
          tx_baud_cnt_d = '0;
          tx_state_d    = TX_DATA;
          tx_bit_cnt_d  = '0;
        end else begin
          tx_baud_cnt_d = tx_baud_cnt_q + 1'b1;
        end
      end

      TX_DATA: begin
        tx_bit_d = tx_shreg_q[0];
        if (tx_baud_cnt_q >= baud_div_i - 1'b1) begin
          tx_baud_cnt_d = '0;
          tx_shreg_d    = {1'b0, tx_shreg_q[7:1]};
          if (tx_bit_cnt_q >= 3'd7) begin
            tx_state_d = TX_STOP;
          end else begin
            tx_bit_cnt_d = tx_bit_cnt_q + 1'b1;
          end
        end else begin
          tx_baud_cnt_d = tx_baud_cnt_q + 1'b1;
        end
      end

      TX_STOP: begin
        tx_bit_d = 1'b1; // Stop bit
        if (tx_baud_cnt_q >= baud_div_i - 1'b1) begin
          tx_baud_cnt_d = '0;
          tx_state_d    = TX_IDLE;
        end else begin
          tx_baud_cnt_d = tx_baud_cnt_q + 1'b1;
        end
      end

      default: tx_state_d = TX_IDLE;
    endcase
  end

  // ---------------------------------------------------------------------------
  // Receiver FSM with 3-Stage Synchronizer & Mid-Bit Sampling
  // ---------------------------------------------------------------------------
  logic [2:0] rx_sync_q;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rx_sync_q <= 3'b111;
    end else begin
      rx_sync_q <= {rx_sync_q[1:0], rx_i};
    end
  end
  wire rx_filtered = rx_sync_q[2];

  typedef enum logic [1:0] {
    RX_IDLE  = 2'b00,
    RX_START = 2'b01,
    RX_DATA  = 2'b10,
    RX_STOP  = 2'b11
  } rx_state_e;

  rx_state_e rx_state_q, rx_state_d;
  logic [15:0] rx_baud_cnt_q, rx_baud_cnt_d;
  logic [2:0]  rx_bit_cnt_q, rx_bit_cnt_d;
  logic [7:0]  rx_shreg_q, rx_shreg_d;
  logic        frame_err_q, frame_err_d;

  assign frame_err_o = frame_err_q;

  always_comb begin
    rx_state_d    = rx_state_q;
    rx_baud_cnt_d = rx_baud_cnt_q;
    rx_bit_cnt_d  = rx_bit_cnt_q;
    rx_shreg_d    = rx_shreg_q;
    rx_fifo_push  = 1'b0;
    rx_fifo_wdata = rx_shreg_q;
    frame_err_d   = 1'b0;

    case (rx_state_q)
      RX_IDLE: begin
        if (!rx_filtered) begin // Start bit edge detected
          rx_state_d    = RX_START;
          rx_baud_cnt_d = '0;
        end
      end

      RX_START: begin
        // Sample at mid-point of start bit
        if (rx_baud_cnt_q >= (baud_div_i >> 1) - 1'b1) begin
          rx_baud_cnt_d = '0;
          if (!rx_filtered) begin
            rx_state_d   = RX_DATA;
            rx_bit_cnt_d = '0;
          end else begin
            rx_state_d   = RX_IDLE; // False start glitch
          end
        end else begin
          rx_baud_cnt_d = rx_baud_cnt_q + 1'b1;
        end
      end

      RX_DATA: begin
        if (rx_baud_cnt_q >= baud_div_i - 1'b1) begin
          rx_baud_cnt_d = '0;
          rx_shreg_d    = {rx_filtered, rx_shreg_q[7:1]};
          if (rx_bit_cnt_q >= 3'd7) begin
            rx_state_d = RX_STOP;
          end else begin
            rx_bit_cnt_d = rx_bit_cnt_q + 1'b1;
          end
        end else begin
          rx_baud_cnt_d = rx_baud_cnt_q + 1'b1;
        end
      end

      RX_STOP: begin
        if (rx_baud_cnt_q >= baud_div_i - 1'b1) begin
          rx_baud_cnt_d = '0;
          if (rx_filtered) begin // Valid stop bit
            rx_fifo_push  = 1'b1;
            rx_fifo_wdata = rx_shreg_q;
          end else begin
            frame_err_d   = 1'b1;
          end
          rx_state_d = RX_IDLE;
        end else begin
          rx_baud_cnt_d = rx_baud_cnt_q + 1'b1;
        end
      end

      default: rx_state_d = RX_IDLE;
    endcase
  end

  // Sequential updates
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      tx_state_q    <= TX_IDLE;
      tx_baud_cnt_q <= '0;
      tx_bit_cnt_q  <= '0;
      tx_shreg_q    <= '0;
      tx_bit_q      <= 1'b1;

      rx_state_q    <= RX_IDLE;
      rx_baud_cnt_q <= '0;
      rx_bit_cnt_q  <= '0;
      rx_shreg_q    <= '0;
      frame_err_q   <= 1'b0;
    end else begin
      tx_state_q    <= tx_state_d;
      tx_baud_cnt_q <= tx_baud_cnt_d;
      tx_bit_cnt_q  <= tx_bit_cnt_d;
      tx_shreg_q    <= tx_shreg_d;
      tx_bit_q      <= tx_bit_d;

      rx_state_q    <= rx_state_d;
      rx_baud_cnt_q <= rx_baud_cnt_d;
      rx_bit_cnt_q  <= rx_bit_cnt_d;
      rx_shreg_q    <= rx_shreg_d;
      frame_err_q   <= frame_err_d;
    end
  end

endmodule : uart_controller
