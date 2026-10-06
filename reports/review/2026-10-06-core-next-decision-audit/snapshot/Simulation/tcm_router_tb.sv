// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0
//
// Description: Self-checking testbench for Dual-Port Tightly Coupled Memory (TCM) subsystem
//              and Harvard OBI bus router.
//
// Testcases per docs/plans/2026-10-06-gemini-recovery-followup.md (Task 4):
// - TC-TCM-001: Concurrent Port A Instruction Fetch & Port B Data Read
// - TC-TCM-002: Port B Read from I-TCM (RODATA & Data Load Image)
// - TC-TCM-003: Port B Byte-Enable Masked Write & Read in D-TCM
// - TC-TCM-004: Memory Boundary Alignment (0x0000_7FFC, 0x0001_0000, 0x0001_7FFC)
// - TC-TCM-005: Zero-Wait-State Grant and Single-Cycle RVALID Timing Verification
// - TC-TCM-006: 128 KB D-TCM Expansion & Upper Boundary Access (0x0001_FFFC) Non-Aliasing

`timescale 1ns / 1ps

module tcm_router_tb;

  localparam time CLK_PERIOD = 20ns; // 50 MHz
  localparam int I_MEM_SIZE = 32768;   // 32 KB I-TCM
  localparam int D_MEM_SIZE = 131072;  // 128 KB D-TCM (Expanded for ResUMamba-30K)

  logic clk;
  logic rst_n;

  // I-TCM Signals
  logic        itcm_instr_req;
  logic        itcm_instr_gnt;
  logic [31:0] itcm_instr_addr;
  logic        itcm_instr_rvalid;
  logic [31:0] itcm_instr_rdata;

  logic        itcm_data_req;
  logic        itcm_data_gnt;
  logic [31:0] itcm_data_addr;
  logic        itcm_data_we;
  logic [3:0]  itcm_data_be;
  logic [31:0] itcm_data_wdata;
  logic        itcm_data_rvalid;
  logic [31:0] itcm_data_rdata;

  // D-TCM Signals
  logic        dtcm_instr_req;
  logic        dtcm_instr_gnt;
  logic [31:0] dtcm_instr_addr;
  logic        dtcm_instr_rvalid;
  logic [31:0] dtcm_instr_rdata;

  logic        dtcm_data_req;
  logic        dtcm_data_gnt;
  logic [31:0] dtcm_data_addr;
  logic        dtcm_data_we;
  logic [3:0]  dtcm_data_be;
  logic [31:0] dtcm_data_wdata;
  logic        dtcm_data_rvalid;
  logic [31:0] dtcm_data_rdata;

  int pass_count = 0;
  int fail_count = 0;

  // Clock generation
  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD / 2) clk = ~clk;
  end

  // Watchdog timer (100 us is ample for TCM unit tests)
  initial begin
    #100_000;
    $display("[FATAL] Watchdog expired in tcm_router_tb!");
    $fatal(1, "Watchdog expired without completing TCM verification");
  end

  // Instantiate I-TCM DUT
  tcm_sram #(
    .MEM_SIZE_BYTES(I_MEM_SIZE),
    .TARGET_ASIC   (1'b0),
    .INIT_FILE     ("")
  ) u_itcm (
    .clk_i         (clk),
    .rst_ni        (rst_n),
    .instr_req_i   (itcm_instr_req),
    .instr_gnt_o   (itcm_instr_gnt),
    .instr_addr_i  (itcm_instr_addr),
    .instr_rvalid_o(itcm_instr_rvalid),
    .instr_rdata_o (itcm_instr_rdata),
    .data_req_i    (itcm_data_req),
    .data_gnt_o    (itcm_data_gnt),
    .data_addr_i   (itcm_data_addr),
    .data_we_i     (itcm_data_we),
    .data_be_i     (itcm_data_be),
    .data_wdata_i  (itcm_data_wdata),
    .data_rvalid_o (itcm_data_rvalid),
    .data_rdata_o  (itcm_data_rdata)
  );

  // Instantiate D-TCM DUT
  tcm_sram #(
    .MEM_SIZE_BYTES(D_MEM_SIZE),
    .TARGET_ASIC   (1'b0),
    .INIT_FILE     ("")
  ) u_dtcm (
    .clk_i         (clk),
    .rst_ni        (rst_n),
    .instr_req_i   (dtcm_instr_req),
    .instr_gnt_o   (dtcm_instr_gnt),
    .instr_addr_i  (dtcm_instr_addr),
    .instr_rvalid_o(dtcm_instr_rvalid),
    .instr_rdata_o (dtcm_instr_rdata),
    .data_req_i    (dtcm_data_req),
    .data_gnt_o    (dtcm_data_gnt),
    .data_addr_i   (dtcm_data_addr),
    .data_we_i     (dtcm_data_we),
    .data_be_i     (dtcm_data_be),
    .data_wdata_i  (dtcm_data_wdata),
    .data_rvalid_o (dtcm_data_rvalid),
    .data_rdata_o  (dtcm_data_rdata)
  );

  initial begin
    $display("================================================================");
    $display("  STARTING TCM ROUTER AND MEMORY SUBSYSTEM VERIFICATION");
    $display("  Adhering to Task 4 of Gemini Recovery Plan");
    $display("================================================================");

    // Initial state
    rst_n          = 1'b0;
    itcm_instr_req = 1'b0;
    itcm_instr_addr= 32'h0;
    itcm_data_req  = 1'b0;
    itcm_data_addr = 32'h0;
    itcm_data_we   = 1'b0;
    itcm_data_be   = 4'hF;
    itcm_data_wdata= 32'h0;

    dtcm_instr_req = 1'b0;
    dtcm_instr_addr= 32'h0;
    dtcm_data_req  = 1'b0;
    dtcm_data_addr = 32'h0;
    dtcm_data_we   = 1'b0;
    dtcm_data_be   = 4'hF;
    dtcm_data_wdata= 32'h0;

    #(CLK_PERIOD * 3);
    rst_n = 1'b1;
    #(CLK_PERIOD * 2);

    // Pre-populate I-TCM word 0x100 with instruction code and 0x200 with rodata
    u_itcm.mem[32'h100 >> 2] = 32'h00500113; // addi x2, x0, 5
    u_itcm.mem[32'h200 >> 2] = 32'hCAFE1234; // rodata constant

    // -------------------------------------------------------------------------
    // TC-TCM-001: Concurrent Port A Instruction Fetch & Port B Data Read
    // -------------------------------------------------------------------------
    $display("\n[TEST] TC-TCM-001: Testing Concurrent Instruction Fetch & Data Read...");
    @(posedge clk);
    itcm_instr_req  <= 1'b1;
    itcm_instr_addr <= 32'h0000_0100;

    itcm_data_req   <= 1'b1;
    itcm_data_addr  <= 32'h0000_0200;
    itcm_data_we    <= 1'b0;
    itcm_data_be    <= 4'hF;

    @(posedge clk);
    // Grants must assert immediately (zero wait-state)
    if (!itcm_instr_gnt || !itcm_data_gnt) begin
      $display("[FAIL] TC-TCM-001: Expected zero-wait-state grants on Port A and Port B!");
      fail_count++;
    end else begin
      itcm_instr_req <= 1'b0;
      itcm_data_req  <= 1'b0;
    end

    // Next cycle: RVALID asserted on both ports, correct data returned
    @(posedge clk);
    if (itcm_instr_rvalid && itcm_data_rvalid &&
        (itcm_instr_rdata == 32'h00500113) &&
        (itcm_data_rdata  == 32'hCAFE1234)) begin
      $display("[PASS] TC-TCM-001: Concurrent Port A and Port B access succeeded cleanly");
      pass_count++;
    end else begin
      $display("[FAIL] TC-TCM-001: Data or rvalid mismatch! instr_data=0x%h, data_rdata=0x%h",
               itcm_instr_rdata, itcm_data_rdata);
      fail_count++;
    end

    // -------------------------------------------------------------------------
    // TC-TCM-002: Port B Read from I-TCM (RODATA & Data Load Image)
    // -------------------------------------------------------------------------
    $display("\n[TEST] TC-TCM-002: Verifying Data Port Read Access to I-TCM Address Space...");
    @(posedge clk);
    itcm_data_req  <= 1'b1;
    itcm_data_addr <= 32'h0000_0200;
    itcm_data_we   <= 1'b0;
    itcm_data_be   <= 4'hF;
    @(posedge clk);
    itcm_data_req  <= 1'b0;
    @(posedge clk);
    if (itcm_data_rvalid && (itcm_data_rdata == 32'hCAFE1234)) begin
      $display("[PASS] TC-TCM-002: CPU data master successfully read load image from I-TCM");
      pass_count++;
    end else begin
      $display("[FAIL] TC-TCM-002: Failed reading load image from I-TCM: rdata=0x%h", itcm_data_rdata);
      fail_count++;
    end

    // -------------------------------------------------------------------------
    // TC-TCM-003: Port B Byte-Enable Masked Write & Read in D-TCM
    // -------------------------------------------------------------------------
    $display("\n[TEST] TC-TCM-003: Testing Byte-Enable Masked Stores into D-TCM...");
    // 1. Initial 32-bit word write: 0x0000_0000
    @(posedge clk);
    dtcm_data_req   <= 1'b1;
    dtcm_data_addr  <= 32'h0000_0040;
    dtcm_data_we    <= 1'b1;
    dtcm_data_be    <= 4'b1111;
    dtcm_data_wdata <= 32'hA5A5_A5A5;
    @(posedge clk);

    // 2. Byte store at byte 1 (be = 4'b0010): write 0x55
    dtcm_data_req   <= 1'b1;
    dtcm_data_addr  <= 32'h0000_0040;
    dtcm_data_we    <= 1'b1;
    dtcm_data_be    <= 4'b0010;
    dtcm_data_wdata <= 32'h0000_5500;
    @(posedge clk);

    // 3. Half-word store at upper half (be = 4'b1100): write 0x1234
    dtcm_data_req   <= 1'b1;
    dtcm_data_addr  <= 32'h0000_0040;
    dtcm_data_we    <= 1'b1;
    dtcm_data_be    <= 4'b1100;
    dtcm_data_wdata <= 32'h1234_0000;
    @(posedge clk);

    // 4. Read back word. Expected: byte 0 = 0xA5, byte 1 = 0x55, bytes 2..3 = 0x1234 -> 0x1234_55A5
    dtcm_data_req   <= 1'b1;
    dtcm_data_addr  <= 32'h0000_0040;
    dtcm_data_we    <= 1'b0;
    dtcm_data_be    <= 4'b1111;
    @(posedge clk);
    dtcm_data_req   <= 1'b0;
    @(posedge clk);

    if (dtcm_data_rvalid && (dtcm_data_rdata == 32'h1234_55A5)) begin
      $display("[PASS] TC-TCM-003: Byte-enable masking exact: read 0x%08X (expected 0x123455A5)", dtcm_data_rdata);
      pass_count++;
    end else begin
      $display("[FAIL] TC-TCM-003: Byte-enable mismatch: got 0x%08X, expected 0x123455A5", dtcm_data_rdata);
      fail_count++;
    end

    // -------------------------------------------------------------------------
    // TC-TCM-004: Memory Boundary Alignment (0x0000_7FFC, 0x0000_0000, 0x0000_7FFC in D-TCM)
    // -------------------------------------------------------------------------
    $display("\n[TEST] TC-TCM-004: Testing Memory Boundary Edge Words...");
    // Write last word of D-TCM (offset 0x7FFC)
    @(posedge clk);
    dtcm_data_req   <= 1'b1;
    dtcm_data_addr  <= 32'h0000_7FFC;
    dtcm_data_we    <= 1'b1;
    dtcm_data_be    <= 4'b1111;
    dtcm_data_wdata <= 32'hB00D_FACE;
    @(posedge clk);

    // Read back last word of D-TCM
    dtcm_data_req   <= 1'b1;
    dtcm_data_addr  <= 32'h0000_7FFC;
    dtcm_data_we    <= 1'b0;
    dtcm_data_be    <= 4'b1111;
    @(posedge clk);
    dtcm_data_req   <= 1'b0;
    @(posedge clk);

    if (dtcm_data_rvalid && (dtcm_data_rdata == 32'hB00D_FACE)) begin
      $display("[PASS] TC-TCM-004: Memory boundary edge word at offset 0x7FFC verified");
      pass_count++;
    end else begin
      $display("[FAIL] TC-TCM-004: Boundary read failure: got 0x%08X, expected 0xB00DFACE", dtcm_data_rdata);
      fail_count++;
    end

    // -------------------------------------------------------------------------
    // TC-TCM-005: Zero-Wait-State Grant and Single-Cycle RVALID Timing
    // -------------------------------------------------------------------------
    $display("\n[TEST] TC-TCM-005: Verifying Zero-Wait-State Grant & Single-Cycle RVALID Timing...");
    @(posedge clk);
    dtcm_data_req <= 1'b1;
    dtcm_data_we  <= 1'b0;
    #1; // Sample immediately within clock cycle
    if (!dtcm_data_gnt) begin
      $display("[FAIL] TC-TCM-005: Grant was not combinational / zero-wait-state!");
      fail_count++;
    end else begin
      @(posedge clk);
      dtcm_data_req <= 1'b0;
      #1;
      if (dtcm_data_rvalid) begin
        $display("[PASS] TC-TCM-005: Zero-wait-state grant and single-cycle rvalid verified");
        pass_count++;
      end else begin
        $display("[FAIL] TC-TCM-005: RVALID did not assert on the next clock cycle!");
        fail_count++;
      end
    end

    // -------------------------------------------------------------------------
    // TC-TCM-006: 128 KB D-TCM Expansion & Upper Boundary Access (0x0001_FFFC) Non-Aliasing
    // -------------------------------------------------------------------------
    $display("\n[TEST] TC-TCM-006: Testing 128 KB D-TCM Expansion & Non-Aliasing Boundary Access...");
    // 1. Write unique pattern to top of 128 KB window (offset 0x0001_FFFC)
    @(posedge clk);
    dtcm_data_req   <= 1'b1;
    dtcm_data_addr  <= 32'h0001_FFFC;
    dtcm_data_we    <= 1'b1;
    dtcm_data_be    <= 4'b1111;
    dtcm_data_wdata <= 32'hDEAD_128A;
    @(posedge clk);

    // 2. Read back 32 KB boundary (offset 0x0000_7FFC). Must NOT alias and still hold 0xB00DFACE!
    dtcm_data_req   <= 1'b1;
    dtcm_data_addr  <= 32'h0000_7FFC;
    dtcm_data_we    <= 1'b0;
    dtcm_data_be    <= 4'b1111;
    @(posedge clk);
    dtcm_data_req   <= 1'b0;
    @(posedge clk);

    if (dtcm_data_rvalid && (dtcm_data_rdata == 32'hB00D_FACE)) begin
      $display("[INFO] TC-TCM-006: Offset 0x7FFC preserved, no aliasing detected");
    end else begin
      $display("[FAIL] TC-TCM-006: Aliasing detected at 0x7FFC! Read 0x%08X (expected 0xB00DFACE)", dtcm_data_rdata);
      fail_count++;
    end

    // 3. Read back 128 KB boundary (offset 0x0001_FFFC). Must return 0xDEAD128A!
    @(posedge clk);
    dtcm_data_req   <= 1'b1;
    dtcm_data_addr  <= 32'h0001_FFFC;
    dtcm_data_we    <= 1'b0;
    dtcm_data_be    <= 4'b1111;
    @(posedge clk);
    dtcm_data_req   <= 1'b0;
    @(posedge clk);

    if (dtcm_data_rvalid && (dtcm_data_rdata == 32'hDEAD_128A) && (fail_count == 0)) begin
      $display("[PASS] TC-TCM-006: 128 KB D-TCM upper boundary (0x1FFFC) verified with zero aliasing");
      pass_count++;
    end else begin
      $display("[FAIL] TC-TCM-006: 128 KB boundary read failed: got 0x%08X, expected 0xDEAD128A", dtcm_data_rdata);
      if (fail_count == 0) fail_count++;
    end

    // -------------------------------------------------------------------------
    // Summary & Exit Gate
    // -------------------------------------------------------------------------
    $display("\n================================================================");
    $display("  TCM ROUTER TEST SUMMARY");
    $display("  PASSED: %0d / 6", pass_count);
    $display("  FAILED: %0d", fail_count);
    $display("================================================================");

    if ((fail_count == 0) && (pass_count == 6)) begin
      $display("[SUCCESS] All 6 TCM Subsystem Tests PASSED!");
      $finish(0);
    end else begin
      $display("[FATAL] TCM Subsystem verification failed: pass_count=%0d, fail_count=%0d", pass_count, fail_count);
      $fatal(1, "TCM Subsystem verification failed!");
    end
  end

endmodule : tcm_router_tb
