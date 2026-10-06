// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0
//
// Description: Parameterized synchronous FIFO with overflow/underflow
//              guarding and watermark status indicators.

module sync_fifo #(
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned FIFO_DEPTH = 16,
  parameter int unsigned ALMOST_FULL_THRESH = FIFO_DEPTH - 2,
  parameter int unsigned ALMOST_EMPTY_THRESH = 2
) (
  input  logic                      clk_i,
  input  logic                      rst_ni,

  // Write Interface
  input  logic                      push_i,
  input  logic [DATA_WIDTH-1:0]     data_i,
  output logic                      full_o,
  output logic                      almost_full_o,
  output logic                      overflow_err_o,

  // Read Interface
  input  logic                      pop_i,
  output logic [DATA_WIDTH-1:0]     data_o,
  output logic                      empty_o,
  output logic                      almost_empty_o,
  output logic                      underflow_err_o,

  // Status
  output logic [$clog2(FIFO_DEPTH):0] level_o
);

  localparam int unsigned ADDR_WIDTH = $clog2(FIFO_DEPTH);

  // Storage array
  logic [DATA_WIDTH-1:0] mem [FIFO_DEPTH-1:0];

  // Pointers and counters
  logic [ADDR_WIDTH-1:0] wr_ptr_q, wr_ptr_d;
  logic [ADDR_WIDTH-1:0] rd_ptr_q, rd_ptr_d;
  logic [ADDR_WIDTH:0]   count_q, count_d;
  logic                  overflow_q, overflow_d;
  logic                  underflow_q, underflow_d;

  assign full_o         = (count_q == (ADDR_WIDTH+1)'(FIFO_DEPTH));
  assign empty_o        = (count_q == '0);
  assign almost_full_o  = (count_q >= (ADDR_WIDTH+1)'(ALMOST_FULL_THRESH));
  assign almost_empty_o = (count_q <= (ADDR_WIDTH+1)'(ALMOST_EMPTY_THRESH) && count_q > '0);
  assign level_o        = count_q;
  assign overflow_err_o = overflow_q;
  assign underflow_err_o= underflow_q;

  // Next-state logic
  always_comb begin
    wr_ptr_d    = wr_ptr_q;
    rd_ptr_d    = rd_ptr_q;
    count_d     = count_q;
    overflow_d  = 1'b0;
    underflow_d = 1'b0;

    case ({push_i, pop_i})
      2'b10: begin // Push only
        if (!full_o) begin
          wr_ptr_d = (wr_ptr_q == ADDR_WIDTH'(FIFO_DEPTH - 1)) ? '0 : wr_ptr_q + 1'b1;
          count_d  = count_q + 1'b1;
        end else begin
          overflow_d = 1'b1;
        end
      end

      2'b01: begin // Pop only
        if (!empty_o) begin
          rd_ptr_d = (rd_ptr_q == ADDR_WIDTH'(FIFO_DEPTH - 1)) ? '0 : rd_ptr_q + 1'b1;
          count_d  = count_q - 1'b1;
        end else begin
          underflow_d = 1'b1;
        end
      end

      2'b11: begin // Simultaneous push and pop
        if (empty_o) begin
          wr_ptr_d = (wr_ptr_q == ADDR_WIDTH'(FIFO_DEPTH - 1)) ? '0 : wr_ptr_q + 1'b1;
          count_d  = count_q + 1'b1;
          underflow_d = 1'b1;
        end else if (full_o) begin
          rd_ptr_d = (rd_ptr_q == ADDR_WIDTH'(FIFO_DEPTH - 1)) ? '0 : rd_ptr_q + 1'b1;
          count_d  = count_q - 1'b1;
          overflow_d = 1'b1;
        end else begin
          wr_ptr_d = (wr_ptr_q == ADDR_WIDTH'(FIFO_DEPTH - 1)) ? '0 : wr_ptr_q + 1'b1;
          rd_ptr_d = (rd_ptr_q == ADDR_WIDTH'(FIFO_DEPTH - 1)) ? '0 : rd_ptr_q + 1'b1;
        end
      end

      default: ; // Idle
    endcase
  end

  // Sequential updates
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wr_ptr_q    <= '0;
      rd_ptr_q    <= '0;
      count_q     <= '0;
      overflow_q  <= 1'b0;
      underflow_q <= 1'b0;
    end else begin
      wr_ptr_q    <= wr_ptr_d;
      rd_ptr_q    <= rd_ptr_d;
      count_q     <= count_d;
      overflow_q  <= overflow_d;
      underflow_q <= underflow_d;

      // Memory write
      if (push_i && !full_o) begin
        mem[wr_ptr_q] <= data_i;
      end
    end
  end

  // Read data output (combinational from RAM with registered pointer)
  assign data_o = mem[rd_ptr_q];

endmodule : sync_fifo
