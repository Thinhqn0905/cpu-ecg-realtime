// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0
//
// Description: SPI Master controller configured for ADS1292R (Mode 1: CPOL=0, CPHA=1).
//              Supports:
//              - Programmable clock divider
//              - 24-bit single-word transfers (commands and register read/write)
//              - Continuous-CS 72-bit frame transfers (Status + CH1 + CH2)
//              - Autonomous acquisition triggered on DRDY# falling edge
//              - Clean CS# hold time compliance (tCSSC and tSCCS >= 4 SCLK cycles)

module spi_master #(
  parameter int unsigned DEFAULT_CLK_DIV = 25,
  parameter int unsigned WORD_LEN        = 24,
  parameter bit          CPOL            = 1'b0,
  parameter bit          CPHA            = 1'b1
) (
  input  logic                  clk_i,
  input  logic                  rst_ni,

  // Configuration & Control
  input  logic [7:0]            clk_div_i,
  input  logic                  start_i,
  input  logic                  auto_mode_i,     // 1: trigger 72-bit transfer on DRDY# falling edge
  input  logic                  frame_mode_i,    // 1: 72-bit continuous-CS frame, 0: single 24-bit word
  input  logic [WORD_LEN-1:0]   tx_data_i,
  output logic [WORD_LEN-1:0]   rx_data_o,       // 24-bit single RX / Status word
  output logic [23:0]           rx_ch1_o,        // 24-bit Channel 1 data word
  output logic [23:0]           rx_ch2_o,        // 24-bit Channel 2 data word
  output logic                  busy_o,
  output logic                  done_o,
  output logic                  frame_valid_o,
  input  logic                  frame_valid_clr_i,

  // External ADS1292R Interface
  output logic                  sclk_o,
  output logic                  mosi_o,
  input  logic                  miso_i,
  output logic                  cs_no,
  input  logic                  drdy_ni,

  // Interrupt Output
  output logic                  drdy_irq_o
);

  typedef enum logic [2:0] {
    ST_IDLE      = 3'b000,
    ST_CS_LEAD   = 3'b001,
    ST_TRANSFER  = 3'b010,
    ST_CS_TRAIL  = 3'b011,
    ST_DONE      = 3'b100
  } state_e;

  state_e state_q, state_d;

  // Transfer mode tracker
  logic frame_active_q, frame_active_d;

  // Clock generation
  logic [7:0] clk_cnt_q, clk_cnt_d;
  logic       sclk_en;
  logic       sclk_q, sclk_d;

  // Bit and transfer counters
  logic [6:0] bit_cnt_q, bit_cnt_d;
  logic [3:0] lead_cnt_q, lead_cnt_d;

  // Shift registers
  logic [WORD_LEN-1:0] tx_shreg_q, tx_shreg_d;
  logic [23:0]         rx_status_shreg_q, rx_status_shreg_d;
  logic [23:0]         rx_ch1_shreg_q, rx_ch1_shreg_d;
  logic [23:0]         rx_ch2_shreg_q, rx_ch2_shreg_d;

  // Latched outputs
  logic [WORD_LEN-1:0] rx_data_latch_q, rx_data_latch_d;
  logic [23:0]         rx_ch1_latch_q, rx_ch1_latch_d;
  logic [23:0]         rx_ch2_latch_q, rx_ch2_latch_d;
  logic                frame_valid_q, frame_valid_d;

  // DRDY edge synchronizer & detector
  logic [2:0] drdy_sync_q;
  logic       drdy_falling_edge;

  // Synchronize DRDY#
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      drdy_sync_q <= 3'b111;
    end else begin
      drdy_sync_q <= {drdy_sync_q[1:0], drdy_ni};
    end
  end

  assign drdy_falling_edge = (drdy_sync_q[2:1] == 2'b10);
  assign drdy_irq_o        = drdy_falling_edge;

  // SCLK clock divider logic
  always_comb begin
    clk_cnt_d = clk_cnt_q + 1'b1;
    sclk_en   = 1'b0;

    if (clk_cnt_q >= ((clk_div_i > 8'd1) ? (clk_div_i >> 1) : 8'd1) - 1'b1) begin
      clk_cnt_d = '0;
      sclk_en   = 1'b1;
    end
  end

  // FSM Next-State Logic
  always_comb begin
    state_d            = state_q;
    frame_active_d     = frame_active_q;
    bit_cnt_d          = bit_cnt_q;
    lead_cnt_d         = lead_cnt_q;
    sclk_d             = sclk_q;
    tx_shreg_d         = tx_shreg_q;
    rx_status_shreg_d  = rx_status_shreg_q;
    rx_ch1_shreg_d     = rx_ch1_shreg_q;
    rx_ch2_shreg_d     = rx_ch2_shreg_q;
    rx_data_latch_d    = rx_data_latch_q;
    rx_ch1_latch_d     = rx_ch1_latch_q;
    rx_ch2_latch_d     = rx_ch2_latch_q;
    frame_valid_d      = frame_valid_q;
    done_o             = 1'b0;
    busy_o             = (state_q != ST_IDLE);

    if (frame_valid_clr_i) begin
      frame_valid_d = 1'b0;
    end

    case (state_q)
      ST_IDLE: begin
        sclk_d     = CPOL;
        lead_cnt_d = '0;
        bit_cnt_d  = '0;

        if (start_i || (auto_mode_i && drdy_falling_edge)) begin
          frame_active_d = auto_mode_i || frame_mode_i;
          tx_shreg_d     = tx_data_i;
          state_d        = ST_CS_LEAD;
          if (auto_mode_i || frame_mode_i) begin
            frame_valid_d = 1'b0; // Clear previous frame valid on new transfer
          end
        end
      end

      ST_CS_LEAD: begin
        // Guarantee tCSSC setup time (minimum 4 SCLK cycles = 8 half-periods)
        if (sclk_en) begin
          lead_cnt_d = lead_cnt_q + 1'b1;
          if (lead_cnt_q >= 4'd7) begin
            lead_cnt_d = '0;
            state_d    = ST_TRANSFER;
          end
        end
      end

      ST_TRANSFER: begin
        if (sclk_en) begin
          sclk_d = ~sclk_q;

          // Mode 1 (CPHA=1): Drive MOSI on rising edge (CPOL=0), sample MISO on falling edge
          if (sclk_q == CPOL) begin
            // Leading edge: drive next MOSI bit
            tx_shreg_d = {tx_shreg_q[WORD_LEN-2:0], 1'b0};
          end else begin
            // Trailing edge: sample MISO
            bit_cnt_d = bit_cnt_q + 1'b1;

            if (frame_active_q) begin
              // Continuous-CS 72-bit frame acquisition:
              // Bits 0..23:  Status word
              // Bits 24..47: Channel 1 word
              // Bits 48..71: Channel 2 word
              if (bit_cnt_q < 7'd24) begin
                rx_status_shreg_d = {rx_status_shreg_q[22:0], miso_i};
              end else if (bit_cnt_q < 7'd48) begin
                rx_ch1_shreg_d    = {rx_ch1_shreg_q[22:0], miso_i};
              end else begin
                rx_ch2_shreg_d    = {rx_ch2_shreg_q[22:0], miso_i};
              end

              if (bit_cnt_q == 7'd71) begin
                state_d    = ST_CS_TRAIL;
                bit_cnt_d  = '0;
              end
            end else begin
              // Single-word transfer (24 bits)
              rx_status_shreg_d = {rx_status_shreg_q[WORD_LEN-2:0], miso_i};

              if (bit_cnt_q == 7'(WORD_LEN - 1)) begin
                state_d    = ST_CS_TRAIL;
                bit_cnt_d  = '0;
              end
            end
          end
        end
      end

      ST_CS_TRAIL: begin
        // Guarantee tSCCS hold time (minimum 4 SCLK cycles = 8 half-periods)
        if (sclk_en) begin
          sclk_d     = CPOL;
          lead_cnt_d = lead_cnt_q + 1'b1;
          if (lead_cnt_q >= 4'd7) begin
            state_d = ST_DONE;
          end
        end
      end

      ST_DONE: begin
        done_o  = 1'b1;
        state_d = ST_IDLE;

        if (frame_active_q) begin
          rx_data_latch_d = rx_status_shreg_q;
          rx_ch1_latch_d  = rx_ch1_shreg_q;
          rx_ch2_latch_d  = rx_ch2_shreg_q;
          frame_valid_d   = 1'b1;
        end else begin
          rx_data_latch_d = rx_status_shreg_q;
        end
      end

      default: state_d = ST_IDLE;
    endcase
  end

  // Sequential updates
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q           <= ST_IDLE;
      frame_active_q    <= 1'b0;
      clk_cnt_q         <= '0;
      sclk_q            <= CPOL;
      bit_cnt_q         <= '0;
      lead_cnt_q        <= '0;
      tx_shreg_q        <= '0;
      rx_status_shreg_q <= '0;
      rx_ch1_shreg_q    <= '0;
      rx_ch2_shreg_q    <= '0;
      rx_data_latch_q   <= '0;
      rx_ch1_latch_q    <= '0;
      rx_ch2_latch_q    <= '0;
      frame_valid_q     <= 1'b0;
    end else begin
      state_q           <= state_d;
      frame_active_q    <= frame_active_d;
      clk_cnt_q         <= clk_cnt_d;
      sclk_q            <= sclk_d;
      bit_cnt_q         <= bit_cnt_d;
      lead_cnt_q        <= lead_cnt_d;
      tx_shreg_q        <= tx_shreg_d;
      rx_status_shreg_q <= rx_status_shreg_d;
      rx_ch1_shreg_q    <= rx_ch1_shreg_d;
      rx_ch2_shreg_q    <= rx_ch2_shreg_d;
      rx_data_latch_q   <= rx_data_latch_d;
      rx_ch1_latch_q    <= rx_ch1_latch_d;
      rx_ch2_latch_q    <= rx_ch2_latch_d;
      frame_valid_q     <= frame_valid_d;
    end
  end

  // Output mappings
  assign sclk_o        = sclk_q;
  assign mosi_o        = tx_shreg_q[WORD_LEN-1];
  // CS# stays continuously LOW during the entire transfer (Lead -> Transfer -> Trail -> Done)
  assign cs_no         = (state_q == ST_IDLE);
  assign rx_data_o     = rx_data_latch_q;
  assign rx_ch1_o      = rx_ch1_latch_q;
  assign rx_ch2_o      = rx_ch2_latch_q;
  assign frame_valid_o = frame_valid_q;

endmodule : spi_master
