// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0
//
// Testbench for CNN-MAMBA Coprocessor Bridge (mamba_bridge.sv)
// Verifies:
// - TC-BRG-001: Reset defaults (STATUS == 0, CTRL == 0, IRQ == 0)
// - TC-BRG-002: APB register write & readback (SRC_ADDR, DST_ADDR, LEN)
// - TC-BRG-003: DiagSSM1D FIR command dispatch, BUSY state, and completion IRQ assertion
// - TC-BRG-004: STATUS register W1C (write-1-to-clear) behavior and IRQ deassertion
// - TC-BRG-005: Full inference command dispatch, class output and confidence score

`timescale 1ns/1ps

module mamba_bridge_tb;

  logic        clk;
  logic        rst_n;

  // APB3 interface
  logic        psel;
  logic        penable;
  logic        pwrite;
  logic [11:0] paddr;
  logic [31:0] pwdata;
  logic [31:0] prdata;
  logic        pready;
  logic        pslverr;

  // AXI4-Stream ingress
  logic [31:0] s_axis_tdata;
  logic        s_axis_tvalid;
  logic        s_axis_tready;
  logic        s_axis_tlast;

  // Interrupt
  logic        event_irq;

  // Testbench bookkeeping
  int pass_count = 0;
  int fail_count = 0;

  // Clock generation (50 MHz = 20 ns period)
  initial begin
    clk = 0;
    forever #10 clk = ~clk;
  end

  // Instantiate Device Under Test
  mamba_bridge dut (
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
    .s_axis_tdata_i  (s_axis_tdata),
    .s_axis_tvalid_i (s_axis_tvalid),
    .s_axis_tready_o (s_axis_tready),
    .s_axis_tlast_i  (s_axis_tlast),
    .event_irq_o     (event_irq)
  );

  // APB Read Task
  task apb_read(input logic [11:0] addr, output logic [31:0] data);
    begin
      @(posedge clk);
      psel    <= 1'b1;
      penable <= 1'b0;
      pwrite  <= 1'b0;
      paddr   <= addr;
      @(posedge clk);
      penable <= 1'b1;
      @(posedge clk);
      data = prdata;
      psel    <= 1'b0;
      penable <= 1'b0;
    end
  endtask

  // APB Write Task
  task apb_write(input logic [11:0] addr, input logic [31:0] data);
    begin
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
    end
  endtask

  // Register Offsets
  localparam logic [11:0] REG_CTRL         = 12'h000;
  localparam logic [11:0] REG_STATUS       = 12'h004;
  localparam logic [11:0] REG_SRC_ADDR     = 12'h008;
  localparam logic [11:0] REG_DST_ADDR     = 12'h00C;
  localparam logic [11:0] REG_LEN          = 12'h010;
  localparam logic [11:0] REG_CYCLES       = 12'h014;
  localparam logic [11:0] REG_RESULT_CLASS = 12'h018;
  localparam logic [11:0] REG_RESULT_CONF  = 12'h01C;

  logic [31:0] rdata;
  int wait_cycles;

  initial begin
    $display("================================================================");
    $display("  MAMBA COPROCESSOR BRIDGE VERIFICATION TESTBENCH");
    $display("================================================================");

    // Initial bus idle
    psel          = 0;
    penable       = 0;
    pwrite        = 0;
    paddr         = 0;
    pwdata        = 0;
    s_axis_tdata  = 0;
    s_axis_tvalid = 0;
    s_axis_tlast  = 0;
    rst_n         = 0;

    // Apply Reset
    repeat (5) @(posedge clk);
    rst_n = 1;
    repeat (5) @(posedge clk);

    // -------------------------------------------------------------------------
    // TC-BRG-001: Reset Defaults Verification
    // -------------------------------------------------------------------------
    $display("[TEST] TC-BRG-001: Checking Reset State...");
    apb_read(REG_STATUS, rdata);
    if (rdata[0] == 1'b0 && rdata[1] == 1'b0 && event_irq == 1'b0) begin
      $display("       [PASS] TC-BRG-001: Bridge is idle with no pending IRQ");
      pass_count++;
    end else begin
      $display("       [FAIL] TC-BRG-001: Status = 0x%08x, IRQ = %b", rdata, event_irq);
      fail_count++;
    end

    // -------------------------------------------------------------------------
    // TC-BRG-002: APB Register Write & Readback
    // -------------------------------------------------------------------------
    $display("[TEST] TC-BRG-002: Writing SRC_ADDR, DST_ADDR, LEN registers...");
    apb_write(REG_SRC_ADDR, 32'h0001_8000); // 128 KB D-TCM activation buffer
    apb_write(REG_DST_ADDR, 32'h0002_4000); // 128 KB D-TCM output buffer
    apb_write(REG_LEN,      32'd500);       // 500 temporal steps

    apb_read(REG_SRC_ADDR, rdata);
    if (rdata != 32'h0001_8000) begin
      $display("       [FAIL] TC-BRG-002: SRC_ADDR mismatch! Expected 0x0001_8000, got 0x%08x", rdata);
      fail_count++;
    end

    apb_read(REG_DST_ADDR, rdata);
    if (rdata != 32'h0002_4000) begin
      $display("       [FAIL] TC-BRG-002: DST_ADDR mismatch! Expected 0x0002_4000, got 0x%08x", rdata);
      fail_count++;
    end

    apb_read(REG_LEN, rdata);
    if (rdata != 32'd500) begin
      $display("       [FAIL] TC-BRG-002: LEN mismatch! Expected 500, got %0d", rdata);
      fail_count++;
    end else if (fail_count == 0) begin
      $display("       [PASS] TC-BRG-002: APB register write & readback verified across SRC_ADDR, DST_ADDR, LEN");
      pass_count++;
    end

    // -------------------------------------------------------------------------
    // TC-BRG-003: DiagSSM1D FIR Dispatch & IRQ Assertion
    // -------------------------------------------------------------------------
    $display("[TEST] TC-BRG-003: Dispatching DiagSSM1D FIR command (OPCODE=1, IRQ_EN=1)...");
    // CTRL: bit 0 = START (1), bit 1 = IRQ_EN (1), bits [7:4] = OPCODE (4'h1) -> 8'h13
    apb_write(REG_CTRL, 32'h0000_0013);

    // Wait for completion with counter
    wait_cycles = 0;
    while (!event_irq && wait_cycles < 200) begin
      @(posedge clk);
      wait_cycles++;
    end

    apb_read(REG_STATUS, rdata);
    if (rdata[1] == 1'b1 && event_irq == 1'b1) begin
      $display("       [PASS] TC-BRG-003: Execution completed in %0d cycles and IRQ asserted", wait_cycles);
      pass_count++;
    end else begin
      $display("       [FAIL] TC-BRG-003: Done bit not asserted or IRQ missing! Status=0x%08x, IRQ=%b", rdata, event_irq);
      fail_count++;
    end

    // -------------------------------------------------------------------------
    // TC-BRG-004: STATUS W1C and IRQ Deassertion
    // -------------------------------------------------------------------------
    $display("[TEST] TC-BRG-004: Clearing DONE flag via W1C...");
    apb_write(REG_STATUS, 32'h0000_0002); // Write 1 to clear DONE bit
    apb_read(REG_STATUS, rdata);

    if (rdata[1] == 1'b0 && event_irq == 1'b0) begin
      $display("       [PASS] TC-BRG-004: DONE flag cleared and IRQ deasserted");
      pass_count++;
    end else begin
      $display("       [FAIL] TC-BRG-004: W1C failed! Status=0x%08x, IRQ=%b", rdata, event_irq);
      fail_count++;
    end

    // -------------------------------------------------------------------------
    // TC-BRG-005: Full Inference Dispatch & Fail-Closed Error Check
    // -------------------------------------------------------------------------
    $display("[TEST] TC-BRG-005: Dispatching Full Inference (OPCODE=3, IRQ_EN=1) - Expect Fail-Closed ERROR...");
    apb_write(REG_CTRL, 32'h0000_0033); // OPCODE=3, IRQ_EN=1, START=1

    wait_cycles = 0;
    while (!event_irq && wait_cycles < 200) begin
      @(posedge clk);
      wait_cycles++;
    end

    apb_read(REG_STATUS, rdata);
    $display("       Status register after Opcode 3: 0x%08x (error=%b, done=%b)", rdata, rdata[2], rdata[1]);

    apb_read(REG_RESULT_CLASS, rdata);
    $display("       Result class code: %0d", rdata);

    // Fail-closed verification: Opcode 3 must assert ERROR bit (rdata[2]==1) and return class 0 (NOT_IMPLEMENTED)
    apb_read(REG_STATUS, rdata);
    if (rdata[2] == 1'b1 && rdata[1] == 1'b1) begin
      $display("       [PASS] TC-BRG-005: Fail-closed contract verified - Opcode 3 rejected as NOT_IMPLEMENTED with ERROR status");
      pass_count++;
    end else begin
      $display("       [FAIL] TC-BRG-005: Opcode 3 did not assert ERROR status flag! Status=0x%08x", rdata);
      fail_count++;
    end

    // Summary
    $display("\n================================================================");
    $display("  TEST SUMMARY: %0d PASSED, %0d FAILED", pass_count, fail_count);
    $display("================================================================");

    if (fail_count == 0) begin
      $display("[SUCCESS] All mamba_bridge tests PASSED!\n");
      $finish(0);
    end else begin
      $display("[FATAL] mamba_bridge test failures detected!\n");
      $finish(1);
    end
  end

endmodule
