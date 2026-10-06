// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0
//
// Description: Ping-Pong BRAM Buffer Manager and Autonomous Ingress DMA.
//              Absorbs real-time 72-bit samples from SPI master into alternating
//              Ping-Pong BRAM banks, formatting them into standardized 12-byte ECG frames:
//              - Word 0: status[31:0]  (bits [31:24] = 0, bits [23:0] = Status word)
//              - Word 1: int32_t ch1   (32-bit sign-extended from 24 bits)
//              - Word 2: int32_t ch2   (32-bit sign-extended from 24 bits)
//              Asserts BUFFER_DONE interrupt (irq_i[19]) on buffer boundary.
//              Supports dual access:
//              - APB3 slave interface for control plane (0x1A10_4000 / 0x1000_4000)
//              - D-OBI slave interface for high-speed direct memory readout (0x2000_0000 / 0x2000_1000)

module ecg_dma
  import ecg_soc_pkg::*;
#(
  parameter int unsigned SAMPLES_PER_BANK = 256
) (
  input  logic        clk_i,
  input  logic        rst_ni,

  // APB3 Slave Interface (for Control Plane & Fallback Readout)
  input  logic        psel_i,
  input  logic        penable_i,
  input  logic        pwrite_i,
  input  logic [11:0] paddr_i,
  input  logic [31:0] pwdata_i,
  output logic [31:0] prdata_o,
  output logic        pready_o,
  output logic        pslverr_o,

  // D-OBI Direct High-Speed Memory Read Port (Window: 0x2000_0000 - 0x2000_1FFF)
  input  logic        dobi_req_i,
  output logic        dobi_gnt_o,
  input  logic [31:0] dobi_addr_i,
  output logic        dobi_rvalid_o,
  output logic [31:0] dobi_rdata_o,

  // Sample Ingress from SPI Master
  input  logic        sample_valid_i,
  input  logic [7:0]  sample_status_i,
  input  logic [23:0] sample_ch1_i,
  input  logic [23:0] sample_ch2_i,

  // Interrupts & Events
  output logic        buffer_ready_irq_o,
  output logic        overflow_err_o
);

  localparam int unsigned WORDS_PER_BANK = SAMPLES_PER_BANK * 3;
  localparam int unsigned IDX_WIDTH      = (SAMPLES_PER_BANK > 1) ? $clog2(SAMPLES_PER_BANK) : 1;

  // Ping-Pong Memory Banks: 2 banks x SAMPLES_PER_BANK x 3 words
  logic [31:0] bank0_mem [WORDS_PER_BANK-1:0];
  logic [31:0] bank1_mem [WORDS_PER_BANK-1:0];

  // Bank pointers and state
  logic                 active_bank_q, active_bank_d; // 0: Bank0 (Buffer A), 1: Bank1 (Buffer B)
  logic [IDX_WIDTH-1:0] wr_idx_q, wr_idx_d;
  logic                 bank0_ready_q, bank0_ready_d;
  logic                 bank1_ready_q, bank1_ready_d;
  logic                 overflow_q, overflow_d;
  logic [31:0]          total_samples_q, total_samples_d;
  logic                 ready_pulse;

  assign pready_o           = 1'b1;
  assign pslverr_o          = 1'b0;
  assign buffer_ready_irq_o = bank0_ready_q || bank1_ready_q;
  assign overflow_err_o     = overflow_q;

  // D-OBI Zero-Wait Grant
  assign dobi_gnt_o         = dobi_req_i;

  // Unused bits sink for lint
  wire _unused_bits = &{1'b0, pwdata_i[31:3]};

  // Standardized 12-byte ECG frame words
  wire [31:0] frame_w0_status = {24'h0000_00, sample_status_i};
  wire [31:0] frame_w1_ch1    = {{8{sample_ch1_i[23]}}, sample_ch1_i}; // Sign-extended 32-bit int
  wire [31:0] frame_w2_ch2    = {{8{sample_ch2_i[23]}}, sample_ch2_i}; // Sign-extended 32-bit int

  // Ingress Write & Bank Switch Logic
  always_comb begin
    active_bank_d   = active_bank_q;
    wr_idx_d        = wr_idx_q;
    bank0_ready_d   = bank0_ready_q;
    bank1_ready_d   = bank1_ready_q;
    overflow_d      = overflow_q;
    ready_pulse     = 1'b0;
    total_samples_d = total_samples_q;

    if (sample_valid_i) begin
      total_samples_d = total_samples_q + 1'b1;

      if (wr_idx_q == IDX_WIDTH'(SAMPLES_PER_BANK - 1)) begin
        wr_idx_d      = '0;
        active_bank_d = ~active_bank_q;
        ready_pulse   = 1'b1;

        if (active_bank_q == 1'b0) begin
          bank0_ready_d = 1'b1;
          if (bank1_ready_q) overflow_d = 1'b1; // Buffer B was not released before swap
        end else begin
          bank1_ready_d = 1'b1;
          if (bank0_ready_q) overflow_d = 1'b1; // Buffer A was not released before swap
        end
      end else begin
        wr_idx_d = wr_idx_q + 1'b1;
      end
    end

    // CPU clearing bank ready / overflow flags via APB write to DMA_REG_CTRL
    if (psel_i && penable_i && pwrite_i && (paddr_i == DMA_REG_CTRL)) begin
      if (pwdata_i[0]) bank0_ready_d = 1'b0; // Acknowledge/Release Bank 0 (Buffer A)
      if (pwdata_i[1]) bank1_ready_d = 1'b0; // Acknowledge/Release Bank 1 (Buffer B)
      if (pwdata_i[2]) overflow_d    = 1'b0; // Clear overflow error
    end
  end

  // Memory write updates
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      active_bank_q   <= 1'b0;
      wr_idx_q        <= '0;
      bank0_ready_q   <= 1'b0;
      bank1_ready_q   <= 1'b0;
      overflow_q      <= 1'b0;
      total_samples_q <= '0;
    end else begin
      active_bank_q   <= active_bank_d;
      wr_idx_q        <= wr_idx_d;
      bank0_ready_q   <= bank0_ready_d;
      bank1_ready_q   <= bank1_ready_d;
      overflow_q      <= overflow_d;
      total_samples_q <= total_samples_d;

      // Sample write to BRAM: 3 consecutive 32-bit words per 12-byte frame
      if (sample_valid_i) begin
        if (active_bank_q == 1'b0) begin
          bank0_mem[wr_idx_q * 3 + 0] <= frame_w0_status;
          bank0_mem[wr_idx_q * 3 + 1] <= frame_w1_ch1;
          bank0_mem[wr_idx_q * 3 + 2] <= frame_w2_ch2;
        end else begin
          bank1_mem[wr_idx_q * 3 + 0] <= frame_w0_status;
          bank1_mem[wr_idx_q * 3 + 1] <= frame_w1_ch1;
          bank1_mem[wr_idx_q * 3 + 2] <= frame_w2_ch2;
        end
      end
    end
  end

  // ---------------------------------------------------------------------------
  // [1] D-OBI Direct High-Speed Readout Port (1-Cycle Latency)
  // ---------------------------------------------------------------------------
  logic        dobi_rvalid_q;
  logic [31:0] dobi_rdata_q;

  wire        dobi_bank_sel = dobi_addr_i[12]; // 0: Buffer A (0x2000_0xxx), 1: Buffer B (0x2000_1xxx)
  wire [9:0]  dobi_word_idx = dobi_addr_i[11:2]; // Word index (0..767)

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      dobi_rvalid_q <= 1'b0;
      dobi_rdata_q  <= 32'h0;
    end else begin
      dobi_rvalid_q <= dobi_req_i;
      if (dobi_req_i) begin
        if (dobi_bank_sel == 1'b0) begin
          dobi_rdata_q <= (dobi_word_idx < WORDS_PER_BANK) ? bank0_mem[dobi_word_idx] : 32'h0;
        end else begin
          dobi_rdata_q <= (dobi_word_idx < WORDS_PER_BANK) ? bank1_mem[dobi_word_idx] : 32'h0;
        end
      end
    end
  end

  assign dobi_rvalid_o = dobi_rvalid_q;
  assign dobi_rdata_o  = dobi_rdata_q;

  // ---------------------------------------------------------------------------
  // [2] APB3 Control Plane & Fallback Readout Interface
  // ---------------------------------------------------------------------------
  wire [8:0] apb_word_idx = paddr_i[10:2];

  always_comb begin
    prdata_o = 32'h0000_0000;

    if (psel_i && !pwrite_i) begin
      case (paddr_i[11:8])
        4'h0: begin // Registers
          case (paddr_i)
            DMA_REG_CTRL:         prdata_o = {28'h0, 1'b0, overflow_q, bank1_ready_q, bank0_ready_q};
            DMA_REG_STATUS:       prdata_o = {28'h0, bank1_ready_q, bank0_ready_q, overflow_q, active_bank_q};
            DMA_REG_BANK_ADDR:    prdata_o = {31'h0, ~active_bank_q}; // Idle bank available for read
            DMA_REG_SAMPLE_COUNT: prdata_o = total_samples_q;
            default:              prdata_o = 32'h0000_0000;
          endcase
        end

        // Fallback APB word read windows
        4'h1, 4'h2, 4'h3, 4'h4: begin // Buffer A (Bank 0) Readout
          prdata_o = (apb_word_idx < WORDS_PER_BANK) ? bank0_mem[apb_word_idx] : 32'h0;
        end

        4'h5, 4'h6, 4'h7, 4'h8: begin // Buffer B (Bank 1) Readout
          prdata_o = (apb_word_idx < WORDS_PER_BANK) ? bank1_mem[apb_word_idx] : 32'h0;
        end

        default: prdata_o = 32'h0000_0000;
      endcase
    end
  end

endmodule : ecg_dma
