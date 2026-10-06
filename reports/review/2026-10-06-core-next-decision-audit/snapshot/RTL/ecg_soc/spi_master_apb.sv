// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0
//
// Description: APB3 slave interface wrapper for the ADS1292R SPI master.
//              Provides memory-mapped registers for CPU control and status,
//              including continuous 72-bit frame acquisition (Status, CH1, CH2)
//              and direct sample streaming lines for DMA / DSP ingestion.

module spi_master_apb
  import ecg_soc_pkg::*;
(
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

  // Direct Sample Streaming Interface (to DMA / DSP)
  output logic                  sample_valid_o,
  output logic [7:0]            sample_status_o,
  output logic [23:0]           sample_ch1_o,
  output logic [23:0]           sample_ch2_o,

  // External SPI Pins
  output logic                  sclk_o,
  output logic                  mosi_o,
  input  logic                  miso_i,
  output logic                  cs_no,
  input  logic                  drdy_ni,

  // Interrupt
  output logic                  irq_o
);

  // Control and Status Registers
  logic [7:0]  clk_div_q, clk_div_d;
  logic        auto_mode_q, auto_mode_d;
  logic        frame_mode_q, frame_mode_d;
  logic        start_pulse;
  logic        frame_valid_clr;
  logic        done_q, done_d;
  logic [23:0] tx_data_q, tx_data_d;
  logic [31:0] sample_cnt_q, sample_cnt_d;

  // SPI Core Signals
  logic [23:0] rx_data_core;
  logic [23:0] rx_ch1_core;
  logic [23:0] rx_ch2_core;
  logic        busy_core;
  logic        done_core;
  logic        frame_valid_core;
  logic        drdy_irq_core;

  // APB handshake: 1-cycle access, no wait-states
  assign pready_o  = 1'b1;
  assign pslverr_o = 1'b0;

  // Instantiate SPI master core
  spi_master #(
    .DEFAULT_CLK_DIV(25),
    .WORD_LEN(24),
    .CPOL(1'b0),
    .CPHA(1'b1)
  ) u_spi_core (
    .clk_i            (clk_i),
    .rst_ni           (rst_ni),
    .clk_div_i        (clk_div_q),
    .start_i          (start_pulse),
    .auto_mode_i      (auto_mode_q),
    .frame_mode_i     (frame_mode_q),
    .tx_data_i        (tx_data_q),
    .rx_data_o        (rx_data_core),
    .rx_ch1_o         (rx_ch1_core),
    .rx_ch2_o         (rx_ch2_core),
    .busy_o           (busy_core),
    .done_o           (done_core),
    .frame_valid_o    (frame_valid_core),
    .frame_valid_clr_i(frame_valid_clr),
    .sclk_o           (sclk_o),
    .mosi_o           (mosi_o),
    .miso_i           (miso_i),
    .cs_no            (cs_no),
    .drdy_ni          (drdy_ni),
    .drdy_irq_o       (drdy_irq_core)
  );

  assign irq_o = drdy_irq_core;

  // Direct sample streaming outputs
  assign sample_valid_o  = done_core && (auto_mode_q || frame_mode_q);
  assign sample_status_o = rx_data_core[23:16];
  assign sample_ch1_o    = rx_ch1_core;
  assign sample_ch2_o    = rx_ch2_core;

  // Register Read Logic
  always_comb begin
    prdata_o = 32'h0000_0000;

    if (psel_i && !pwrite_i) begin
      case (paddr_i)
        SPI_REG_CTRL: begin
          prdata_o = {29'h0, frame_mode_q, auto_mode_q, 1'b0};
        end
        SPI_REG_STATUS: begin
          prdata_o = {29'h0, frame_valid_core, done_q, busy_core};
        end
        SPI_REG_TXDATA: begin
          prdata_o = {8'h0, tx_data_q};
        end
        SPI_REG_RXDATA: begin
          prdata_o = {8'h0, rx_data_core};
        end
        SPI_REG_CLKDIV: begin
          prdata_o = {24'h0, clk_div_q};
        end
        SPI_REG_CH1_DATA: begin
          prdata_o = {8'h0, rx_ch1_core};
        end
        SPI_REG_CH2_DATA: begin
          prdata_o = {8'h0, rx_ch2_core};
        end
        SPI_REG_SAMPLE_CNT: begin
          prdata_o = sample_cnt_q;
        end
        default: prdata_o = 32'h0000_0000;
      endcase
    end
  end

  // Register Write Logic
  always_comb begin
    clk_div_d       = clk_div_q;
    auto_mode_d     = auto_mode_q;
    frame_mode_d    = frame_mode_q;
    tx_data_d       = tx_data_q;
    start_pulse     = 1'b0;
    frame_valid_clr = 1'b0;
    sample_cnt_d    = sample_cnt_q;
    done_d          = done_q;

    if (done_core) begin
      done_d = 1'b1;
    end

    if (done_core && (auto_mode_q || frame_mode_q)) begin
      sample_cnt_d = sample_cnt_q + 1'b1;
    end

    // Writes take effect during APB ACCESS phase
    if (psel_i && penable_i && pwrite_i) begin
      case (paddr_i)
        SPI_REG_CTRL: begin
          start_pulse  = pwdata_i[0];
          auto_mode_d  = pwdata_i[1];
          frame_mode_d = pwdata_i[2];
          if (pwdata_i[0]) begin
            done_d = 1'b0; // Clear done when a new transfer starts
          end
        end
        SPI_REG_STATUS: begin
          if (pwdata_i[1]) begin
            done_d = 1'b0; // W1C to clear DONE
          end
          if (pwdata_i[2]) begin
            frame_valid_clr = 1'b1; // W1C to clear FRAME_VALID
          end
        end
        SPI_REG_TXDATA: begin
          tx_data_d = pwdata_i[23:0];
        end
        SPI_REG_CLKDIV: begin
          clk_div_d = (pwdata_i[7:0] >= 8'd2) ? pwdata_i[7:0] : 8'd2;
        end
        SPI_REG_SAMPLE_CNT: begin
          sample_cnt_d = pwdata_i;
        end
        default: ;
      endcase
    end
  end

  // Sequential register updates
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      clk_div_q    <= 8'd25; // Default 2.0 MHz at 50 MHz system clock
      auto_mode_q  <= 1'b0;
      frame_mode_q <= 1'b0;
      done_q       <= 1'b0;
      tx_data_q    <= '0;
      sample_cnt_q <= '0;
    end else begin
      clk_div_q    <= clk_div_d;
      auto_mode_q  <= auto_mode_d;
      frame_mode_q <= frame_mode_d;
      done_q       <= done_d;
      tx_data_q    <= tx_data_d;
      sample_cnt_q <= sample_cnt_d;
    end
  end

endmodule : spi_master_apb
