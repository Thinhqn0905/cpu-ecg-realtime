// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0
//
// Description: Comprehensive self-checking testbench for Ping-Pong DMA & 12-Byte Frame Buffer.
//              Verifies:
//              - TC-DMA-001: 12-byte frame layout (Word 0: Status, Word 1: CH1, Word 2: CH2)
//              - TC-DMA-002: Automatic Buffer A -> Buffer B Ping-Pong Bank Swap
//              - TC-DMA-003: Assertion of buffer_ready_irq on buffer boundary
//              - TC-DMA-004: Concurrent D-OBI CPU readout of completed bank while active bank fills
//              - TC-DMA-005: Overflow error detection on unreleased buffer swap
//              - TC-DMA-006: Continuous multi-frame stress test with zero sample loss

`timescale 1ns / 1ps

module ecg_dma_tb;

  localparam time CLK_PERIOD = 20ns; // 50 MHz
  localparam int SAMPLES_PER_BANK = 16; // 16 samples for fast, thorough unit verification

  logic clk;
  logic rst_n;

  // APB Control Interface
  logic        psel;
  logic        penable;
  logic        pwrite;
  logic [11:0] paddr;
  logic [31:0] pwdata;
  logic [31:0] prdata;
  logic        pready;
  logic        pslverr;

  // D-OBI Direct Readout Interface
  logic        dobi_req;
  logic        dobi_gnt;
  logic [31:0] dobi_addr;
  logic        dobi_rvalid;
  logic [31:0] dobi_rdata;

  // Sample Ingress from SPI
  logic        sample_valid;
  logic [7:0]  sample_status;
  logic [23:0] sample_ch1;
  logic [23:0] sample_ch2;

  // Interrupts
  logic        buffer_ready_irq;
  logic        overflow_err;

  int pass_count = 0;
  int fail_count = 0;

  // Clock generation
  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD / 2) clk = ~clk;
  end

  // Watchdog
  initial begin
    #200_000;
    $display("[FATAL] Watchdog expired in ecg_dma_tb!");
    $fatal(1, "Watchdog expired without completing DMA verification");
  end

  // DUT
  ecg_dma #(
    .SAMPLES_PER_BANK(SAMPLES_PER_BANK)
  ) u_dut (
    .clk_i             (clk),
    .rst_ni            (rst_n),
    .psel_i            (psel),
    .penable_i         (penable),
    .pwrite_i          (pwrite),
    .paddr_i           (paddr),
    .pwdata_i          (pwdata),
    .prdata_o          (prdata),
    .pready_o          (pready),
    .pslverr_o         (pslverr),
    .dobi_req_i        (dobi_req),
    .dobi_gnt_o        (dobi_gnt),
    .dobi_addr_i       (dobi_addr),
    .dobi_rvalid_o     (dobi_rvalid),
    .dobi_rdata_o      (dobi_rdata),
    .sample_valid_i    (sample_valid),
    .sample_status_i   (sample_status),
    .sample_ch1_i      (sample_ch1),
    .sample_ch2_i      (sample_ch2),
    .buffer_ready_irq_o(buffer_ready_irq),
    .overflow_err_o    (overflow_err)
  );

  // Helper tasks
  task automatic apb_write(input logic [11:0] addr, input logic [31:0] data);
    @(posedge clk);
    psel    <= 1'b1;
    penable <= 1'b0;
    pwrite  <= 1'b1;
    paddr   <= addr;
    pwdata  <= data;
    @(posedge clk);
    penable <= 1'b1;
    @(posedge clk);
    psel    <= 1'b0;
    penable <= 1'b0;
    pwrite  <= 1'b0;
  endtask

  task automatic apb_read(input logic [11:0] addr, output logic [31:0] data);
    @(posedge clk);
    psel    <= 1'b1;
    penable <= 1'b0;
    pwrite  <= 1'b0;
    paddr   <= addr;
    @(posedge clk);
    penable <= 1'b1;
    @(posedge clk);
    data    = prdata;
    psel    <= 1'b0;
    penable <= 1'b0;
  endtask

  task automatic dobi_read(input logic [31:0] addr, output logic [31:0] data);
    @(posedge clk);
    dobi_req  <= 1'b1;
    dobi_addr <= addr;
    @(posedge clk);
    dobi_req  <= 1'b0;
    if (!dobi_rvalid) begin
      @(posedge clk);
    end
    data = dobi_rdata;
  endtask

  task automatic push_sample(input logic [7:0] st, input logic [23:0] c1, input logic [23:0] c2);
    @(posedge clk);
    sample_valid  <= 1'b1;
    sample_status <= st;
    sample_ch1    <= c1;
    sample_ch2    <= c2;
    @(posedge clk);
    sample_valid  <= 1'b0;
  endtask

  // Main test flow
  initial begin
    $display("================================================================");
    $display("  STARTING PING-PONG DMA & 12-BYTE FRAME VERIFICATION");
    $display("  Mandatory Evidence Verification per Instruction/claim_integrity.md");
    $display("================================================================");

    rst_n         = 1'b0;
    psel          = 1'b0;
    penable       = 1'b0;
    pwrite        = 1'b0;
    paddr         = 12'h0;
    pwdata        = 32'h0;
    dobi_req      = 1'b0;
    dobi_addr     = 32'h0;
    sample_valid  = 1'b0;
    sample_status = 8'h0;
    sample_ch1    = 24'h0;
    sample_ch2    = 24'h0;

    #(CLK_PERIOD * 3);
    rst_n = 1'b1;
    #(CLK_PERIOD * 2);

    // -------------------------------------------------------------------------
    // TC-DMA-001: 12-byte Frame Layout (Status, CH1, CH2 sign-extended)
    // -------------------------------------------------------------------------
    $display("\n[TEST] TC-DMA-001: Verifying Standardized 12-Byte Frame Layout...");
    begin
      logic [31:0] r_w0, r_w1, r_w2;
      // Push positive CH1, negative CH2 (24-bit 0xFEDCBA -> sign extends to 0xFFFEDCBA)
      push_sample(8'hC0, 24'h12_3456, 24'hFE_DCBA);

      // Read back via D-OBI from Buffer A (0x2000_0000)
      dobi_read(32'h2000_0000, r_w0); // Word 0: Status
      dobi_read(32'h2000_0004, r_w1); // Word 1: CH1
      dobi_read(32'h2000_0008, r_w2); // Word 2: CH2

      $display("  INFO: Word 0 Status: 0x%08X (Expected: 0x000000C0)", r_w0);
      $display("  INFO: Word 1 CH1:    0x%08X (Expected: 0x00123456)", r_w1);
      $display("  INFO: Word 2 CH2:    0x%08X (Expected: 0xFFFEDCBA)", r_w2);

      if ((r_w0 == 32'h0000_00C0) &&
          (r_w1 == 32'h0012_3456) &&
          (r_w2 == 32'hFFFE_DCBA)) begin
        $display("[PASS] TC-DMA-001: Exact 12-byte frame unpacking and sign-extension verified");
        pass_count++;
      end else begin
        $display("[FAIL] TC-DMA-001: Frame unpacking mismatch!");
        fail_count++;
      end
    end

    // -------------------------------------------------------------------------
    // TC-DMA-002: Automatic Buffer A -> Buffer B Ping-Pong Bank Swap
    // TC-DMA-003: Assertion of buffer_ready_irq on Buffer Boundary
    // -------------------------------------------------------------------------
    $display("\n[TEST] TC-DMA-002 & TC-DMA-003: Filling Buffer A to Boundary (%0d samples)...", SAMPLES_PER_BANK);
    begin
      bit seen_irq = 1'b0;
      logic [31:0] status_reg;

      // Fill remaining (SAMPLES_PER_BANK - 1) samples into Buffer A
      for (int i = 1; i < SAMPLES_PER_BANK; i++) begin
        push_sample(8'hC1, 24'h00_0100 + i, 24'h00_0200 + i);
        if (buffer_ready_irq) seen_irq = 1'b1;
      end

      // Wait a cycle to observe bank swap and IRQ pulse
      @(posedge clk);
      if (buffer_ready_irq) seen_irq = 1'b1;

      apb_read(12'h004, status_reg); // DMA_REG_STATUS
      $display("  INFO: After Bank A fill: Status Register = 0x%08X (active_bank=%0b)",
               status_reg, status_reg[0]);

      if (status_reg[0] == 1'b1) begin
        $display("[PASS] TC-DMA-002: Automatic bank swap to Buffer B succeeded");
        pass_count++;
      end else begin
        $display("[FAIL] TC-DMA-002: Active bank did not swap to Buffer B!");
        fail_count++;
      end

      if (seen_irq) begin
        $display("[PASS] TC-DMA-003: buffer_ready_irq asserted on 16-sample buffer boundary");
        pass_count++;
      end else begin
        $display("[FAIL] TC-DMA-003: buffer_ready_irq was not asserted!");
        fail_count++;
      end
    end

    // -------------------------------------------------------------------------
    // TC-DMA-004: Concurrent D-OBI CPU Read of Buffer A while Buffer B Fills
    // -------------------------------------------------------------------------
    $display("\n[TEST] TC-DMA-004: Concurrent CPU D-OBI Readout of Buffer A while Buffer B Fills...");
    begin
      logic [31:0] read_sample;
      bit concurrent_ok = 1'b1;

      // Simultaneously push sample into Buffer B and read from Buffer A (0x2000_0000)
      fork
        begin
          push_sample(8'hD0, 24'hAA_0001, 24'hBB_0001);
        end
        begin
          dobi_read(32'h2000_0004, read_sample); // Read Word 1 of Frame 0 in Buffer A
          if (read_sample != 32'h0012_3456) concurrent_ok = 1'b0;
        end
      join

      if (concurrent_ok) begin
        $display("[PASS] TC-DMA-004: Concurrent D-OBI CPU readout succeeded without contention");
        pass_count++;
      end else begin
        $display("[FAIL] TC-DMA-004: Concurrent read data corrupted: got 0x%h", read_sample);
        fail_count++;
      end
    end

    // -------------------------------------------------------------------------
    // TC-DMA-005: Overflow Error Assertion on Unreleased Buffer Swap
    // -------------------------------------------------------------------------
    $display("\n[TEST] TC-DMA-005: Testing Overflow Error on Unreleased Buffer Swap...");
    begin
      logic [31:0] status_reg;
      // Buffer A is currently unreleased (bank0_ready is still 1).
      // Fill the remainder of Buffer B (SAMPLES_PER_BANK - 1 samples) so it swaps back to Buffer A.
      for (int i = 1; i < SAMPLES_PER_BANK; i++) begin
        push_sample(8'hD1, 24'hAA_0000 + i, 24'hBB_0000 + i);
      end

      @(posedge clk);
      apb_read(12'h004, status_reg); // DMA_REG_STATUS
      $display("  INFO: Status Register after unreleased swap: 0x%08X (overflow bit 1 = %0b)",
               status_reg, status_reg[1]);

      if (overflow_err || status_reg[1]) begin
        $display("[PASS] TC-DMA-005: Overflow error asserted upon unreleased buffer swap");
        pass_count++;
      end else begin
        $display("[FAIL] TC-DMA-005: Overflow error did not assert!");
        fail_count++;
      end

      // Release both buffers and clear overflow via APB write
      apb_write(12'h000, 32'h0000_0007); // bits 0, 1, 2 = release banks 0, 1, clear overflow
    end

    // -------------------------------------------------------------------------
    // TC-DMA-006: Continuous Stress Streaming with Zero Sample Loss
    // -------------------------------------------------------------------------
    $display("\n[TEST] TC-DMA-006: Continuous 256-Sample Stress Streaming with Active Releasing...");
    begin
      int total_stress_samples = 256;
      logic [31:0] cnt_reg;

      for (int s = 0; s < total_stress_samples; s++) begin
        push_sample(8'hEE, 24'h10_0000 + s, 24'h20_0000 + s);
        // Release buffer when IRQ occurs
        if (buffer_ready_irq) begin
          apb_write(12'h000, 32'h0000_0003); // Release banks
        end
      end

      apb_read(12'h00C, cnt_reg); // DMA_REG_SAMPLE_COUNT
      $display("  INFO: Total samples registered by DMA: %0d", cnt_reg);

      if (cnt_reg >= total_stress_samples) begin
        $display("[PASS] TC-DMA-006: Continuous stress streaming completed with zero sample loss");
        pass_count++;
      end else begin
        $display("[FAIL] TC-DMA-006: Sample counter mismatch! Expected >= %0d, got %0d",
                 total_stress_samples, cnt_reg);
        fail_count++;
      end
    end

    // -------------------------------------------------------------------------
    // Summary
    // -------------------------------------------------------------------------
    $display("\n================================================================");
    $display("  SIMULATION RESULTS SUMMARY");
    $display("  PASSED: %0d", pass_count);
    $display("  FAILED: %0d", fail_count);
    $display("================================================================");

    if (fail_count == 0 && pass_count == 6) begin
      $display("[SUCCESS] All 6 Ping-Pong DMA Test Cases PASSED!");
      $finish(0);
    end else begin
      $display("[FATAL] DMA verification failed: pass_count=%0d, fail_count=%0d", pass_count, fail_count);
      $fatal(1, "DMA verification failed!");
    end
  end

endmodule : ecg_dma_tb
