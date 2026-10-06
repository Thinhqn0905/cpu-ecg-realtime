// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0
//
// Description: 8-bit bidirectional GPIO controller with edge-triggered
//              interrupt generation and input synchronization.

module gpio_apb
  import ecg_soc_pkg::*;
#(
  parameter int unsigned GPIO_WIDTH = 8
) (
  input  logic                  clk_i,
  input  logic                  rst_ni,

  // APB3 Slave Interface
  input  logic                  psel_i,
  input  logic                  penable_i,
  input  logic                  pwrite_i,
  input  logic [11:0]           paddr_i,
  input  logic [31:0]           pwdata_i,
  output logic [31:0]           prdata_o,
  output logic                  pready_o,
  output logic                  pslverr_o,

  // External GPIO Pin Interface
  input  logic [GPIO_WIDTH-1:0] gpio_i,
  output logic [GPIO_WIDTH-1:0] gpio_o,
  output logic [GPIO_WIDTH-1:0] gpio_oe_o,

  // Interrupt
  output logic                  irq_o
);

  logic [GPIO_WIDTH-1:0] data_out_q, data_out_d;
  logic [GPIO_WIDTH-1:0] dir_q, dir_d;
  logic [GPIO_WIDTH-1:0] int_en_q, int_en_d;
  logic [GPIO_WIDTH-1:0] int_status_q, int_status_d;

  // 2-FF input synchronizer
  logic [GPIO_WIDTH-1:0] sync_stage1_q, sync_stage2_q, sync_prev_q;
  wire                   _unused_pwdata = &{1'b0, pwdata_i[31:GPIO_WIDTH]};

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      sync_stage1_q <= '0;
      sync_stage2_q <= '0;
      sync_prev_q   <= '0;
    end else begin
      sync_stage1_q <= gpio_i;
      sync_stage2_q <= sync_stage1_q;
      sync_prev_q   <= sync_stage2_q;
    end
  end

  // Detect rising or falling edge on input pins
  logic [GPIO_WIDTH-1:0] edge_detected;
  assign edge_detected = (sync_stage2_q ^ sync_prev_q);

  assign pready_o   = 1'b1;
  assign pslverr_o  = 1'b0;
  assign gpio_o     = data_out_q;
  assign gpio_oe_o  = dir_q;
  assign irq_o      = |(int_status_q & int_en_q);

  // Register Read Logic
  always_comb begin
    prdata_o = 32'h0000_0000;

    if (psel_i && !pwrite_i) begin
      case (paddr_i)
        GPIO_REG_DATA_IN:    prdata_o = {{(32-GPIO_WIDTH){1'b0}}, sync_stage2_q};
        GPIO_REG_DATA_OUT:   prdata_o = {{(32-GPIO_WIDTH){1'b0}}, data_out_q};
        GPIO_REG_DIR:        prdata_o = {{(32-GPIO_WIDTH){1'b0}}, dir_q};
        GPIO_REG_INT_EN:     prdata_o = {{(32-GPIO_WIDTH){1'b0}}, int_en_q};
        GPIO_REG_INT_STATUS: prdata_o = {{(32-GPIO_WIDTH){1'b0}}, int_status_q};
        default:             prdata_o = 32'h0000_0000;
      endcase
    end
  end

  // Register Write Logic
  always_comb begin
    data_out_d   = data_out_q;
    dir_d        = dir_q;
    int_en_d     = int_en_q;
    int_status_d = int_status_q | (edge_detected & int_en_q); // Latch new edges

    if (psel_i && penable_i && pwrite_i) begin
      case (paddr_i)
        GPIO_REG_DATA_OUT:   data_out_d   = pwdata_i[GPIO_WIDTH-1:0];
        GPIO_REG_DIR:        dir_d        = pwdata_i[GPIO_WIDTH-1:0];
        GPIO_REG_INT_EN:     int_en_d     = pwdata_i[GPIO_WIDTH-1:0];
        GPIO_REG_INT_STATUS: int_status_d = int_status_q & ~pwdata_i[GPIO_WIDTH-1:0]; // W1C
        default: ;
      endcase
    end
  end

  // Sequential updates
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      data_out_q   <= '0;
      dir_q        <= '0;
      int_en_q     <= '0;
      int_status_q <= '0;
    end else begin
      data_out_q   <= data_out_d;
      dir_q        <= dir_d;
      int_en_q     <= int_en_d;
      int_status_q <= int_status_d;
    end
  end

endmodule : gpio_apb
