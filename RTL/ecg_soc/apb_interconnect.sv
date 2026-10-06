// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0
//
// Description: APB3 interconnect uniting CPU master with 5 SoC peripherals:
//              UART (0x1000_0xxx), SPI (0x1000_1xxx), Timer (0x1000_2xxx),
//              GPIO (0x1000_3xxx), DMA (0x1000_4xxx).

module apb_interconnect
  import ecg_soc_pkg::*;
#(
  parameter int unsigned NUM_SLAVES = 5
) (
  input  logic        clk_i,
  input  logic        rst_ni,

  // Upstream APB3 Master Port (from CVA6 / CPU bridge)
  input  logic        m_psel_i,
  input  logic        m_penable_i,
  input  logic        m_pwrite_i,
  input  logic [31:0] m_paddr_i,
  input  logic [31:0] m_pwdata_i,
  output logic [31:0] m_prdata_o,
  output logic        m_pready_o,
  output logic        m_pslverr_o,

  // Downstream APB3 Slave Ports
  // [0]: UART, [1]: SPI, [2]: Timer, [3]: GPIO, [4]: DMA, [5]: MAMBA
  output logic [NUM_SLAVES-1:0]        s_psel_o,
  output logic [NUM_SLAVES-1:0]        s_penable_o,
  output logic [NUM_SLAVES-1:0]        s_pwrite_o,
  output logic [NUM_SLAVES-1:0][11:0]  s_paddr_o,
  output logic [NUM_SLAVES-1:0][31:0]  s_pwdata_o,
  input  logic [NUM_SLAVES-1:0][31:0]  s_prdata_i,
  input  logic [NUM_SLAVES-1:0]        s_pready_i,
  input  logic [NUM_SLAVES-1:0]        s_pslverr_i
);

  // Address Decoding Logic
  logic [NUM_SLAVES-1:0] slave_sel;
  logic                  unmapped_sel;
  wire                   _unused_clk_rst = &{1'b0, clk_i, rst_ni};
  wire [15:0]            addr_hi = m_paddr_i[31:16];
  wire [3:0]             addr_slot = m_paddr_i[15:12];

  always_comb begin
    slave_sel    = '0;
    unmapped_sel = 1'b0;

    if (m_psel_i) begin
      if (addr_hi == 16'h1000 || addr_hi == 16'h1A10) begin
        case (addr_slot)
          4'h0: if (NUM_SLAVES > 0) slave_sel = (NUM_SLAVES'(1) << 0); // UART
          4'h1: if (NUM_SLAVES > 1) slave_sel = (NUM_SLAVES'(1) << 1); // SPI
          4'h2: if (NUM_SLAVES > 2) slave_sel = (NUM_SLAVES'(1) << 2); // Timer
          4'h3: if (NUM_SLAVES > 3) slave_sel = (NUM_SLAVES'(1) << 3); // GPIO
          4'h4: if (NUM_SLAVES > 4) slave_sel = (NUM_SLAVES'(1) << 4); // DMA Control Plane
          default: unmapped_sel = 1'b1;
        endcase
      end else if (NUM_SLAVES > 5 && addr_hi == 16'h2000) begin
        slave_sel = (NUM_SLAVES'(1) << 5); // CNN-MAMBA Coprocessor (deferred)
      end else begin
        unmapped_sel = 1'b1;
      end
    end
  end

  // Broadcast common master control to selected slaves
  for (genvar i = 0; i < NUM_SLAVES; i++) begin : gen_slave_bus
    assign s_psel_o[i]    = slave_sel[i];
    assign s_penable_o[i] = m_penable_i;
    assign s_pwrite_o[i]  = m_pwrite_i;
    assign s_paddr_o[i]   = m_paddr_i[11:0];
    assign s_pwdata_o[i]  = m_pwdata_i;
  end

  // Read multiplexing and response routing via continuous assigns
  assign m_prdata_o = (unmapped_sel) ? 32'h0000_0000 :
                      (slave_sel[0])  ? s_prdata_i[0] :
                      (NUM_SLAVES > 1 && slave_sel[1]) ? s_prdata_i[1] :
                      (NUM_SLAVES > 2 && slave_sel[2]) ? s_prdata_i[2] :
                      (NUM_SLAVES > 3 && slave_sel[3]) ? s_prdata_i[3] :
                      (NUM_SLAVES > 4 && slave_sel[4]) ? s_prdata_i[4] : 32'h0000_0000;

  assign m_pready_o = (unmapped_sel) ? 1'b1 :
                      (slave_sel[0])  ? s_pready_i[0] :
                      (NUM_SLAVES > 1 && slave_sel[1]) ? s_pready_i[1] :
                      (NUM_SLAVES > 2 && slave_sel[2]) ? s_pready_i[2] :
                      (NUM_SLAVES > 3 && slave_sel[3]) ? s_pready_i[3] :
                      (NUM_SLAVES > 4 && slave_sel[4]) ? s_pready_i[4] : 1'b1;

  assign m_pslverr_o = (unmapped_sel) ? 1'b0 :
                       (slave_sel[0])  ? s_pslverr_i[0] :
                       (NUM_SLAVES > 1 && slave_sel[1]) ? s_pslverr_i[1] :
                       (NUM_SLAVES > 2 && slave_sel[2]) ? s_pslverr_i[2] :
                       (NUM_SLAVES > 3 && slave_sel[3]) ? s_pslverr_i[3] :
                       (NUM_SLAVES > 4 && slave_sel[4]) ? s_pslverr_i[4] : 1'b0;

endmodule : apb_interconnect
