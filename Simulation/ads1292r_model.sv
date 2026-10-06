// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0
//
// Description: Behavioral simulation model of the Texas Instruments ADS1292R
//              2-channel 24-bit ECG AFE with SPI Mode 1 interface and DRDY# timing.
//              Outputs the Task 3 Golden Frame:
//              Status = 0xC00000, CH1 = 0x123456 (+1193046), CH2 = 0xFEDCBA (-74566)
//              with race-free SPI Mode 1 edge timing (drive on posedge, sample on negedge).

`timescale 1ns/1ps

module ads1292r_model #(
  parameter real SAMPLE_RATE_HZ = 500.0,
  parameter bit  USE_GOLDEN_FRAME = 1'b1
) (
  input  logic sclk_i,
  input  logic mosi_i,
  output logic miso_o,
  input  logic cs_ni,
  output logic drdy_no,
  input  logic reset_ni,
  input  logic start_i
);

  // ---------------------------------------------------------------------------
  // Internal Registers & Memory Map
  // ---------------------------------------------------------------------------
  logic [7:0] regs [12];
  initial begin
    regs[0]  = 8'h73; // ID register: ADS1292R Device ID (0x73)
    regs[1]  = 8'h02; // CONFIG1: 500 SPS
    regs[2]  = 8'hE0; // CONFIG2: Test signal / reference
    regs[3]  = 8'h10; // LOFF: Lead-off control
    regs[4]  = 8'h00; // CH1SET: Channel 1 active, gain 6
    regs[5]  = 8'h00; // CH2SET: Channel 2 active, gain 6
    regs[6]  = 8'h00; // RLD_SENS
    regs[7]  = 8'h00; // LOFF_SENS
    regs[8]  = 8'h00; // LOFF_STAT
    regs[9]  = 8'h00; // RESP1
    regs[10] = 8'h00; // RESP2
    regs[11] = 8'h00; // GPIO
  end

  // DRDY# Period Generator (2ms at 500 Hz)
  localparam time SAMPLE_PERIOD = (1.0 / SAMPLE_RATE_HZ) * 1s;

  // Task 3 Golden Frame: Status = 0xC00000, CH1 = 0x123456, CH2 = 0xFEDCBA
  localparam logic [71:0] GOLDEN_FRAME = {24'hC0_0000, 24'h12_3456, 24'hFE_DCBA};

  logic [23:0] sample_counter;
  logic        conversion_running;
  integer      frame_count;

  initial begin
    sample_counter     = 24'h00_0001;
    conversion_running = 1'b1;
    frame_count        = 0;
    drdy_no            = 1'b1;
  end

  // Periodic DRDY pulse generation
  always begin
    #(SAMPLE_PERIOD - 4us);
    if (reset_ni && (start_i || conversion_running)) begin
      drdy_no = 1'b0; // Assert DRDY# active low
      #4us;
      drdy_no = 1'b1;
      sample_counter = sample_counter + 1'b1;
      frame_count    = frame_count + 1;
    end else begin
      #4us;
    end
  end

  // ---------------------------------------------------------------------------
  // SPI Mode 1 Slave Protocol Engine (CPOL=0, CPHA=1)
  // Shift out MISO on rising SCLK edge, sample MOSI on falling SCLK edge
  // Initial MSB is driven when CS# asserts LOW
  // ---------------------------------------------------------------------------
  logic [71:0] shift_out_data;
  logic [7:0]  rx_cmd;
  logic [7:0]  rx_addr;
  integer      bit_idx;

  assign miso_o = (!cs_ni) ? shift_out_data[71] : 1'bz;

  // Latch sample payload when CS# asserts
  always @(negedge cs_ni) begin
    if (USE_GOLDEN_FRAME) begin
      shift_out_data <= GOLDEN_FRAME;
    end else begin
      shift_out_data <= {24'hC0_0000, sample_counter, ~sample_counter};
    end
    bit_idx <= 0;
    rx_cmd  <= 8'h00;
    rx_addr <= 8'h00;
  end

  // Sample MOSI on falling SCLK edge (Mode 1 trailing edge)
  always @(negedge sclk_i) begin
    if (!cs_ni) begin
      if (bit_idx < 8) begin
        rx_cmd <= {rx_cmd[6:0], mosi_i};
      end else if (bit_idx < 16) begin
        rx_addr <= {rx_addr[6:0], mosi_i};
      end

      // Command decoder
      if (bit_idx == 7) begin
        case ({rx_cmd[6:0], mosi_i})
          8'h06: ; // RESET
          8'h08: conversion_running <= 1'b1; // START
          8'h0A: conversion_running <= 1'b0; // STOP
          8'h10: ; // RDATAC
          8'h11: ; // SDATAC
          default: ;
        endcase
      end

      // Handle Register Read (RREG: 0x20 | addr)
      if (bit_idx == 15) begin
        if ((rx_cmd & 8'hE0) == 8'h20) begin
          logic [4:0] raddr;
          raddr = rx_cmd[4:0];
          if (raddr < 12) begin
            shift_out_data[71:48] <= {regs[raddr], 16'h0000};
          end
        end
      end

      bit_idx <= bit_idx + 1;
    end
  end

  // Drive next MISO bit on rising SCLK edge (Mode 1 leading edge)
  // In Mode 1, initial MSB (bit 71) is presented on CS# assertion and sampled on 1st falling edge.
  // Subsequent bits (70 down to 0) are shifted out on rising SCLK edges 2..72 (when bit_idx > 0).
  always @(posedge sclk_i) begin
    if (!cs_ni) begin
      if (bit_idx > 0) begin
        shift_out_data <= {shift_out_data[70:0], 1'b0};
      end
    end
  end

endmodule : ads1292r_model
