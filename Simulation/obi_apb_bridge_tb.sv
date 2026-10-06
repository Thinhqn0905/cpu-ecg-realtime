// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0
//
// Description: Directed unit testbench for OBI-to-APB3 Bridge and Interconnect.
//              Verifies:
//              - TC-APB-001: Peripheral Address Decoding (UART, SPI, Timer, GPIO, DMA)
//                            under both 0x1000_xxxx and 0x1A10_xxxx maps
//              - TC-APB-002: Variable Wait-State Acceptance via PREADY
//              - TC-APB-003: Back-to-Back OBI Request Backpressure (gnt deassertion)
//              - TC-APB-004: Unmapped Address Handling (graceful zero return, no hang)

`timescale 1ns / 1ps

module obi_apb_bridge_tb;

  localparam time CLK_PERIOD = 20ns; // 50 MHz

  logic clk;
  logic rst_n;

  // OBI Master Signals (Driving Bridge Slave Port)
  logic        obi_req;
  logic        obi_gnt;
  logic [31:0] obi_addr;
  logic        obi_we;
  logic [3:0]  obi_be;
  logic [31:0] obi_wdata;
  logic        obi_rvalid;
  logic [31:0] obi_rdata;
  logic        obi_err;

  // Bridge to APB Interconnect
  logic        m_psel;
  logic        m_penable;
  logic        m_pwrite;
  logic [31:0] m_paddr;
  logic [31:0] m_pwdata;
  logic [31:0] m_prdata;
  logic        m_pready;
  logic        m_pslverr;

  // Interconnect to Mock Peripherals (5 Slaves)
  localparam int NUM_SLAVES = 5;
  logic [NUM_SLAVES-1:0]        s_psel;
  logic [NUM_SLAVES-1:0]        s_penable;
  logic [NUM_SLAVES-1:0]        s_pwrite;
  logic [NUM_SLAVES-1:0][11:0]  s_paddr;
  logic [NUM_SLAVES-1:0][31:0]  s_pwdata;
  logic [NUM_SLAVES-1:0][31:0]  s_prdata;
  logic [NUM_SLAVES-1:0]        s_pready;
  logic [NUM_SLAVES-1:0]        s_pslverr;

  int pass_count = 0;
  int fail_count = 0;

  // Clock generation
  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD / 2) clk = ~clk;
  end

  // Watchdog
  initial begin
    #100_000;
    $display("[FATAL] Watchdog expired in obi_apb_bridge_tb!");
    $fatal(1, "Watchdog expired without completing OBI-APB bridge verification");
  end

  // DUT: OBI-to-APB3 Bridge
  obi_to_apb u_bridge (
    .clk_i        (clk),
    .rst_ni       (rst_n),
    .obi_req_i    (obi_req),
    .obi_gnt_o    (obi_gnt),
    .obi_addr_i   (obi_addr),
    .obi_we_i     (obi_we),
    .obi_be_i     (obi_be),
    .obi_wdata_i  (obi_wdata),
    .obi_rvalid_o (obi_rvalid),
    .obi_rdata_o  (obi_rdata),
    .obi_err_o    (obi_err),
    .apb_psel_o   (m_psel),
    .apb_penable_o(m_penable),
    .apb_pwrite_o (m_pwrite),
    .apb_paddr_o  (m_paddr),
    .apb_pwdata_o (m_pwdata),
    .apb_prdata_i (m_prdata),
    .apb_pready_i (m_pready),
    .apb_pslverr_i(m_pslverr)
  );

  // APB Interconnect
  apb_interconnect #(
    .NUM_SLAVES(NUM_SLAVES)
  ) u_interconnect (
    .clk_i       (clk),
    .rst_ni      (rst_n),
    .m_psel_i    (m_psel),
    .m_penable_i (m_penable),
    .m_pwrite_i  (m_pwrite),
    .m_paddr_i   (m_paddr),
    .m_pwdata_i  (m_pwdata),
    .m_prdata_o  (m_prdata),
    .m_pready_o  (m_pready),
    .m_pslverr_o (m_pslverr),
    .s_psel_o    (s_psel),
    .s_penable_o (s_penable),
    .s_pwrite_o  (s_pwrite),
    .s_paddr_o   (s_paddr),
    .s_pwdata_o  (s_pwdata),
    .s_prdata_i  (s_prdata),
    .s_pready_i  (s_pready),
    .s_pslverr_i (s_pslverr)
  );

  // Bind SVA monitor
  bind u_bridge obi_to_apb_sva u_sva (
    .clk_i        (clk_i),
    .rst_ni       (rst_ni),
    .obi_req_i    (obi_req_i),
    .obi_gnt_o    (obi_gnt_o),
    .obi_addr_i   (obi_addr_i),
    .obi_we_i     (obi_we_i),
    .obi_be_i     (obi_be_i),
    .obi_wdata_i  (obi_wdata_i),
    .obi_rvalid_o (obi_rvalid_o),
    .obi_rdata_o  (obi_rdata_o),
    .obi_err_o    (obi_err_o),
    .apb_psel_o   (apb_psel_o),
    .apb_penable_o(apb_penable_o),
    .apb_pwrite_o (apb_pwrite_o),
    .apb_paddr_o  (apb_paddr_o),
    .apb_pwdata_o (apb_pwdata_o),
    .apb_prdata_i (apb_prdata_i),
    .apb_pready_i (apb_pready_i),
    .apb_pslverr_i(apb_pslverr_i)
  );

  // Behavioral Slave Models
  // Slave 0 (UART): immediate ready
  // Slave 1 (SPI): immediate ready
  // Slave 2 (Timer): configurable wait-state
  // Slave 3 (GPIO): immediate ready
  // Slave 4 (DMA Control): immediate ready
  int timer_wait_cycles = 0;
  int timer_cnt = 0;

  always_comb begin
    for (int i = 0; i < NUM_SLAVES; i++) begin
      s_psel[i] = u_interconnect.s_psel_o[i];
      s_pslverr[i] = 1'b0;
    end

    // Slave 0: UART returns 0x1111_0000 + addr
    s_prdata[0] = 32'h1111_0000 | {20'h0, s_paddr[0]};
    s_pready[0] = 1'b1;

    // Slave 1: SPI returns 0x2222_0000 + addr
    s_prdata[1] = 32'h2222_0000 | {20'h0, s_paddr[1]};
    s_pready[1] = 1'b1;

    // Slave 2: Timer with wait-states
    s_prdata[2] = 32'h3333_0000 | {20'h0, s_paddr[2]};
    s_pready[2] = (timer_cnt >= timer_wait_cycles);

    // Slave 3: GPIO returns 0x4444_0000 + addr
    s_prdata[3] = 32'h4444_0000 | {20'h0, s_paddr[3]};
    s_pready[3] = 1'b1;

    // Slave 4: DMA Control returns 0x5555_0000 + addr
    s_prdata[4] = 32'h5555_0000 | {20'h0, s_paddr[4]};
    s_pready[4] = 1'b1;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      timer_cnt <= 0;
    end else begin
      if (s_psel[2] && s_penable[2]) begin
        if (timer_cnt < timer_wait_cycles) begin
          timer_cnt <= timer_cnt + 1;
        end else begin
          timer_cnt <= 0;
        end
      end else begin
        timer_cnt <= 0;
      end
    end
  end

  // Helper task: perform single OBI read
  task automatic obi_read(input logic [31:0] addr, output logic [31:0] data);
    @(posedge clk);
    obi_req   <= 1'b1;
    obi_addr  <= addr;
    obi_we    <= 1'b0;
    obi_be    <= 4'hF;
    obi_wdata <= 32'h0;

    // Wait for grant
    do begin
      @(posedge clk);
    end while (!obi_gnt);

    obi_req <= 1'b0;

    // Wait for rvalid
    while (!obi_rvalid) begin
      @(posedge clk);
    end
    data = obi_rdata;
  endtask

  // Main test sequence
  initial begin
    $display("================================================================");
    $display("  STARTING OBI-TO-APB3 BRIDGE & INTERCONNECT VERIFICATION");
    $display("  Mandatory Evidence Verification per Instruction/claim_integrity.md");
    $display("================================================================");

    rst_n     = 1'b0;
    obi_req   = 1'b0;
    obi_addr  = 32'h0;
    obi_we    = 1'b0;
    obi_be    = 4'hF;
    obi_wdata = 32'h0;

    #(CLK_PERIOD * 3);
    rst_n = 1'b1;
    #(CLK_PERIOD * 2);

    // -------------------------------------------------------------------------
    // TC-APB-001: Peripheral Address Decoding
    // -------------------------------------------------------------------------
    $display("\n[TEST] TC-APB-001: Verifying Address Decoding across all 5 Slaves...");
    begin
      logic [31:0] rd;
      bit all_decode_ok = 1'b1;

      // 1. UART (0x1000_0000 & 0x1A10_0000)
      obi_read(32'h1000_0004, rd);
      if (rd != 32'h1111_0004) all_decode_ok = 1'b0;
      obi_read(32'h1A10_0008, rd);
      if (rd != 32'h1111_0008) all_decode_ok = 1'b0;

      // 2. SPI (0x1000_1000 & 0x1A10_1000)
      obi_read(32'h1000_1010, rd);
      if (rd != 32'h2222_0010) all_decode_ok = 1'b0;
      obi_read(32'h1A10_1014, rd);
      if (rd != 32'h2222_0014) all_decode_ok = 1'b0;

      // 3. Timer (0x1000_2000 & 0x1A10_2000)
      obi_read(32'h1000_2000, rd);
      if (rd != 32'h3333_0000) all_decode_ok = 1'b0;
      obi_read(32'h1A10_2004, rd);
      if (rd != 32'h3333_0004) all_decode_ok = 1'b0;

      // 4. GPIO (0x1000_3000 & 0x1A10_3000)
      obi_read(32'h1000_3000, rd);
      if (rd != 32'h4444_0000) all_decode_ok = 1'b0;
      obi_read(32'h1A10_3004, rd);
      if (rd != 32'h4444_0004) all_decode_ok = 1'b0;

      // 5. DMA Control (0x1000_4000 & 0x1A10_4000)
      obi_read(32'h1000_400C, rd);
      if (rd != 32'h5555_000C) all_decode_ok = 1'b0;
      obi_read(32'h1A10_4008, rd);
      if (rd != 32'h5555_0008) all_decode_ok = 1'b0;

      if (all_decode_ok) begin
        $display("[PASS] TC-APB-001: All 5 peripherals decoded correctly under both address maps");
        pass_count++;
      end else begin
        $display("[FAIL] TC-APB-001: Address decoding mismatch!");
        fail_count++;
      end
    end

    // -------------------------------------------------------------------------
    // TC-APB-002: Variable Wait-State Acceptance via PREADY
    // -------------------------------------------------------------------------
    $display("\n[TEST] TC-APB-002: Testing Variable Wait-State Acceptance (PREADY delay)...");
    begin
      logic [31:0] rd;
      timer_wait_cycles = 3; // 3 extra wait cycles

      obi_read(32'h1000_2004, rd);
      if (rd == 32'h3333_0004) begin
        $display("[PASS] TC-APB-002: Variable wait-state handled cleanly, data returned correctly");
        pass_count++;
      end else begin
        $display("[FAIL] TC-APB-002: Wait-state read failed: rd=0x%h", rd);
        fail_count++;
      end
      timer_wait_cycles = 0;
    end

    // -------------------------------------------------------------------------
    // TC-APB-003: Back-to-Back OBI Request Backpressure (gnt deassertion)
    // -------------------------------------------------------------------------
    $display("\n[TEST] TC-APB-003: Testing Backpressure on Back-to-Back OBI Requests...");
    begin
      bit backpressure_verified = 1'b0;
      timer_wait_cycles = 2; // Timer delays completion

      @(posedge clk);
      obi_req   <= 1'b1;
      obi_addr  <= 32'h1000_2000;
      obi_we    <= 1'b0;

      // First request granted
      @(posedge clk);
      if (obi_gnt) begin
        // Keep obi_req asserted with next address while APB is in SETUP/ACCESS
        obi_addr <= 32'h1000_0000;
      end

      // Next cycle: bridge is in ST_SETUP or ST_ACCESS with APB busy. obi_gnt MUST be 0!
      @(posedge clk);
      if (!obi_gnt) begin
        backpressure_verified = 1'b1;
      end

      // Wait until first completes and second is granted
      while (!obi_gnt) begin
        @(posedge clk);
      end
      obi_req <= 1'b0;

      while (!obi_rvalid) begin
        @(posedge clk);
      end

      if (backpressure_verified) begin
        $display("[PASS] TC-APB-003: Backpressure deasserted gnt while APB transfer was busy");
        pass_count++;
      end else begin
        $display("[FAIL] TC-APB-003: Bridge failed to backpressure second request!");
        fail_count++;
      end
      timer_wait_cycles = 0;
    end

    // -------------------------------------------------------------------------
    // TC-APB-004: Unmapped Address Handling (graceful zero return, no hang)
    // -------------------------------------------------------------------------
    $display("\n[TEST] TC-APB-004: Testing Unmapped Address Decoding...");
    begin
      logic [31:0] rd;
      obi_read(32'h1000_7000, rd); // Unmapped peripheral slot 7
      if (rd == 32'h0000_0000) begin
        $display("[PASS] TC-APB-004: Unmapped address returned zero gracefully without hanging");
        pass_count++;
      end else begin
        $display("[FAIL] TC-APB-004: Unmapped address returned nonzero: rd=0x%h", rd);
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

    if (fail_count == 0 && pass_count == 4) begin
      $display("[SUCCESS] All 4 OBI-APB Bridge Test Cases PASSED!");
      $finish(0);
    end else begin
      $display("[FATAL] OBI-APB Bridge verification failed!");
      $fatal(1, "OBI-APB Bridge verification failed!");
    end
  end

endmodule : obi_apb_bridge_tb
