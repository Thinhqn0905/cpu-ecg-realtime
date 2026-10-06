// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0
//
// Description: Self-checking testbench for SPI master and ADS1292R AFE interface.
//              Exercises:
//              - TC-SPI-001: Register Read/Write Integrity Check
//              - TC-SPI-002: Manual 24-bit Command/Register Transfer
//              - TC-SPI-003: Autonomous DRDY# Capture of 72-bit Frame
//              - TC-SPI-004: Complete 72-bit Golden Frame Verification (Status, CH1, CH2)
//              - TC-SPI-005: Continuous CS# Assertion Integrity Across All 72 Bits
//              - TC-SPI-006: Frame Valid Flag W1C Clear Verification
//              - TC-SPI-007: Direct Streaming Outputs to DMA/DSP

`timescale 1ns/1ps

module spi_master_tb;

  import ecg_soc_pkg::*;

  localparam time CLK_PERIOD = 20ns; // 50 MHz system clock

  logic clk;
  logic rst_n;

  // APB Signals
  logic        psel;
  logic        penable;
  logic        pwrite;
  logic [11:0] paddr;
  logic [31:0] pwdata;
  logic [31:0] prdata;
  logic        pready;
  logic        pslverr;

  // SPI Physical Lines
  logic sclk;
  logic mosi;
  logic miso;
  logic cs_n;
  logic drdy_n;
  logic irq;

  // Direct Sample Streaming Lines
  logic        dut_sample_valid;
  logic [7:0]  dut_sample_status;
  logic [23:0] dut_sample_ch1;
  logic [23:0] dut_sample_ch2;

  // AFE Model Control
  logic afe_reset_n;
  logic afe_start;

  // Test statistics
  integer pass_count = 0;
  integer fail_count = 0;

  // Watchdog timer
  initial begin
    #20ms;
    $display("\n[FATAL] Simulation Watchdog Timeout in spi_master_tb!");
    $fatal(1, "Watchdog expired without test completion");
  end

  // Clock generation
  initial begin
    clk = 0;
    forever #(CLK_PERIOD / 2) clk = ~clk;
  end

  // Instantiate Device Under Test (DUT)
  spi_master_apb u_dut (
    .clk_i           (clk),
    .rst_ni          (rst_n),
    .psel_i          (psel),
    .penable_i       (penable),
    .pwrite_i        (pwrite),
    .paddr_i         (paddr),
    .pwdata_i        (pwdata),
    .prdata_o        (prdata),
    .pready_o        (pready),
    .pslverr_o       (pslverr),
    .sample_valid_o  (dut_sample_valid),
    .sample_status_o (dut_sample_status),
    .sample_ch1_o    (dut_sample_ch1),
    .sample_ch2_o    (dut_sample_ch2),
    .sclk_o          (sclk),
    .mosi_o          (mosi),
    .miso_i          (miso),
    .cs_no           (cs_n),
    .drdy_ni         (drdy_n),
    .irq_o           (irq)
  );

  // Instantiate Behavioral ADS1292R Model
  ads1292r_model #(
    .SAMPLE_RATE_HZ   (1000.0), // 1 kHz for simulation speed
    .USE_GOLDEN_FRAME (1'b1)    // Exact golden frame: 0xC00000, 0x123456, 0xFEDCBA
  ) u_afe_model (
    .sclk_i    (sclk),
    .mosi_i    (mosi),
    .miso_o    (miso),
    .cs_ni     (cs_n),
    .drdy_no   (drdy_n),
    .reset_ni  (afe_reset_n),
    .start_i   (afe_start)
  );

  // APB Write Task
  task apb_write(input [11:0] addr, input [31:0] data);
    begin
      @(posedge clk);
      psel    <= 1'b1;
      pwrite  <= 1'b1;
      paddr   <= addr;
      pwdata  <= data;
      penable <= 1'b0;
      @(posedge clk);
      penable <= 1'b1;
      @(posedge clk);
      psel    <= 1'b0;
      penable <= 1'b0;
    end
  endtask

  // APB Read Task
  task apb_read(input [11:0] addr, output [31:0] data);
    begin
      @(posedge clk);
      psel    <= 1'b1;
      pwrite  <= 1'b0;
      paddr   <= addr;
      penable <= 1'b0;
      @(posedge clk);
      penable <= 1'b1;
      @(posedge clk);
      data    = prdata;
      psel    <= 1'b0;
      penable <= 1'b0;
    end
  endtask

  // Monitor continuous CS# assertion during transfer
  integer sclk_pulse_count = 0;
  logic   cs_glitch_detected = 0;

  always @(posedge sclk) begin
    sclk_pulse_count <= sclk_pulse_count + 1;
    if (cs_n != 1'b0) begin
      cs_glitch_detected <= 1'b1;
    end
  end

  // Main Test Sequence
  initial begin
    $display("=========================================================");
    $display("Starting ECG SoC SPI Master Testbench Verification Suite");
    $display("Adhering to Task 3 of Gemini Recovery Plan");
    $display("=========================================================");

    // Initialization
    rst_n       = 0;
    psel        = 0;
    penable     = 0;
    pwrite      = 0;
    paddr       = 0;
    pwdata      = 0;
    afe_reset_n = 0;
    afe_start   = 0;

    #(CLK_PERIOD * 5);
    rst_n       = 1;
    afe_reset_n = 1;
    #(CLK_PERIOD * 5);

    // -------------------------------------------------------------------------
    // TC-SPI-001: Register Read/Write Integrity Check
    // -------------------------------------------------------------------------
    $display("\n[TEST] TC-SPI-001: Testing APB Register Read/Write Integrity...");
    begin
      logic [31:0] rdata;
      apb_write(SPI_REG_CLKDIV, 32'd10);
      apb_read(SPI_REG_CLKDIV, rdata);
      if (rdata[7:0] == 8'd10) begin
        $display("[PASS] TC-SPI-001A: CLKDIV register read back matches (10)");
        pass_count++;
      end else begin
        $display("[FAIL] TC-SPI-001A: CLKDIV mismatch! Expected 10, got %d", rdata[7:0]);
        fail_count++;
      end

      apb_write(SPI_REG_SAMPLE_CNT, 32'h1234_5678);
      apb_read(SPI_REG_SAMPLE_CNT, rdata);
      if (rdata == 32'h1234_5678) begin
        $display("[PASS] TC-SPI-001B: SAMPLE_CNT register read back matches (0x12345678)");
        pass_count++;
      end else begin
        $display("[FAIL] TC-SPI-001B: SAMPLE_CNT mismatch! Expected 0x12345678, got 0x%h", rdata);
        fail_count++;
      end
    end

    // -------------------------------------------------------------------------
    // TC-SPI-002: SPI Single Word Transaction (Manual 24-bit Command)
    // -------------------------------------------------------------------------
    $display("\n[TEST] TC-SPI-002: Triggering Manual 24-bit SPI Command Transfer...");
    begin
      logic [31:0] status;
      apb_write(SPI_REG_CLKDIV, 32'd4); // Fast simulation divider
      apb_write(SPI_REG_TXDATA, 32'hAA_55AA);
      apb_write(SPI_REG_CTRL, 32'h0000_0001); // Start single 24-bit transfer (Frame=0)

      status = 32'h0000_0001;
      while (status[0] == 1'b1) begin // Wait while busy
        apb_read(SPI_REG_STATUS, status);
        #(CLK_PERIOD * 2);
      end

      if (status[1] == 1'b1 && status[0] == 1'b0) begin
        $display("[PASS] TC-SPI-002: Single 24-bit SPI Transfer completed (Busy=0, Done=1)");
        pass_count++;
      end else begin
        $display("[FAIL] TC-SPI-002: Unexpected status after transfer: 0x%h", status);
        fail_count++;
      end
    end

    // -------------------------------------------------------------------------
    // TC-SPI-003: Autonomous Continuous-CS 72-bit Acquisition on DRDY#
    // -------------------------------------------------------------------------
    $display("\n[TEST] TC-SPI-003: Enabling Auto-Mode (72-bit Frame) and Verifying DRDY# Capture...");
    begin
      logic [31:0] rdata;
      logic [31:0] status;
      sclk_pulse_count   = 0;
      cs_glitch_detected = 0;

      // Enable Auto-Mode (bit 1) and Frame-Mode (bit 2) in SPI master
      apb_write(SPI_REG_CTRL, 32'h0000_0006);
      afe_start = 1; // Start AFE conversions

      // Wait for DRDY interrupt pulse
      @(posedge irq);
      $display("[PASS] TC-SPI-003: Caught DRDY# falling edge interrupt from AFE");
      pass_count++;

      // Wait for 72-bit frame transfer to complete (status bit 2: FRAME_VALID)
      status = 32'h0;
      while (!(status[2])) begin
        apb_read(SPI_REG_STATUS, status);
        #(CLK_PERIOD * 4);
      end

      $display("[PASS] TC-SPI-003B: Frame transfer finished, FRAME_VALID asserted");
      pass_count++;

      // -----------------------------------------------------------------------
      // TC-SPI-004: Complete 72-bit Golden Frame Verification
      // -----------------------------------------------------------------------
      $display("\n[TEST] TC-SPI-004: Verifying Complete 72-bit Golden Frame Content...");
      begin
        logic [31:0] w_status, w_ch1, w_ch2;
        int signed   ch1_signed, ch2_signed;

        apb_read(SPI_REG_RXDATA, w_status);
        apb_read(SPI_REG_CH1_DATA, w_ch1);
        apb_read(SPI_REG_CH2_DATA, w_ch2);

        $display("  INFO: Read Status Word: 0x%06X (Expected: 0xC00000)", w_status[23:0]);
        $display("  INFO: Read Channel 1:   0x%06X (Expected: 0x123456)", w_ch1[23:0]);
        $display("  INFO: Read Channel 2:   0x%06X (Expected: 0xFEDCBA)", w_ch2[23:0]);

        // Decode signed 24-bit to 32-bit
        ch1_signed = (w_ch1[23]) ? {8'hFF, w_ch1[23:0]} : {8'h00, w_ch1[23:0]};
        ch2_signed = (w_ch2[23]) ? {8'hFF, w_ch2[23:0]} : {8'h00, w_ch2[23:0]};
        $display("  INFO: Decoded Signed CH1: %0d (Expected: +1193046)", ch1_signed);
        $display("  INFO: Decoded Signed CH2: %0d (Expected: -74566)", ch2_signed);

        if (w_status[23:0] == 24'hC0_0000 &&
            w_ch1[23:0]    == 24'h12_3456 &&
            w_ch2[23:0]    == 24'hFE_DCBA &&
            ch1_signed     == 32'd1193046 &&
            ch2_signed     == -32'd74566) begin
          $display("[PASS] TC-SPI-004: All 72 bits and decoded signed values match exact golden frame!");
          pass_count++;
        end else begin
          $display("[FAIL] TC-SPI-004: Golden frame mismatch! w_status=0x%x, w_ch1=0x%x, w_ch2=0x%x",
                   w_status, w_ch1, w_ch2);
          fail_count++;
        end
      end

      // -----------------------------------------------------------------------
      // TC-SPI-005: Continuous CS# Assertion Integrity Across All 72 Bits
      // -----------------------------------------------------------------------
      $display("\n[TEST] TC-SPI-005: Checking CS# Continuous Assertion Across All 72 SCLK Cycles...");
      $display("  INFO: Total SCLK clock pulses observed: %0d", sclk_pulse_count);
      if (sclk_pulse_count == 72 && !cs_glitch_detected) begin
        $display("[PASS] TC-SPI-005: CS# remained continuously LOW across exactly 72 bits without glitching!");
        pass_count++;
      end else begin
        $display("[FAIL] TC-SPI-005: CS# deasserted or pulse count mismatch: pulses=%0d, glitch=%0b",
                 sclk_pulse_count, cs_glitch_detected);
        fail_count++;
      end

      // -----------------------------------------------------------------------
      // TC-SPI-006: Frame Valid Flag W1C Clear Verification
      // -----------------------------------------------------------------------
      $display("\n[TEST] TC-SPI-006: Verifying FRAME_VALID flag W1C clear...");
      begin
        logic [31:0] st;
        apb_write(SPI_REG_STATUS, 32'h0000_0004); // Write 1 to clear bit 2
        apb_read(SPI_REG_STATUS, st);
        if (!(st[2])) begin
          $display("[PASS] TC-SPI-006: FRAME_VALID flag successfully cleared by W1C");
          pass_count++;
        end else begin
          $display("[FAIL] TC-SPI-006: FRAME_VALID flag did not clear! Status=0x%h", st);
          fail_count++;
        end
      end

      // -----------------------------------------------------------------------
      // TC-SPI-007: Direct Streaming Outputs to DMA/DSP
      // -----------------------------------------------------------------------
      $display("\n[TEST] TC-SPI-007: Verifying Direct Sample Streaming Lines...");
      if (dut_sample_status == 8'hC0 &&
          dut_sample_ch1    == 24'h12_3456 &&
          dut_sample_ch2    == 24'hFE_DCBA) begin
        $display("[PASS] TC-SPI-007: Direct sample streaming outputs contain exact golden frame!");
        pass_count++;
      end else begin
        $display("[FAIL] TC-SPI-007: Direct streaming mismatch! stat=0x%x, ch1=0x%x, ch2=0x%x",
                 dut_sample_status, dut_sample_ch1, dut_sample_ch2);
        fail_count++;
      end
    end

    // Summary
    $display("\n=========================================================");
    $display("VERIFICATION RESULT: %0d PASSED, %0d FAILED", pass_count, fail_count);
    if ((fail_count == 0) && (pass_count == 9)) begin
      $display(">>> ALL TASK 3 SPI VERIFICATION GATES PASSED <<<");
      $display("[SUCCESS] All SPI testcases verified successfully.");
      $finish(0);
    end else begin
      $display(">>> VERIFICATION FAILED <<<");
      $display("[FATAL] Verification failed in spi_master_tb: pass_count=%0d, fail_count=%0d", pass_count, fail_count);
      $fatal(1, "Verification failed in spi_master_tb!");
    end
    $display("=========================================================\n");
  end

endmodule : spi_master_tb
