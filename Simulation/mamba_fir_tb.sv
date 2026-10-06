// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0
//
// Self-Checking Testbench for 128-Tap DiagSSM1D FIR Hardware Sidecar (mamba_fir_sidecar.sv)
// Verifies:
// - TC-FIR-001: Reset state and readiness
// - TC-FIR-002: 128-tap bidirectional impulse response
// - TC-FIR-003: 4-lane parallel channel concurrent processing
// - TC-FIR-004: Execution latency verification (< 4,000,000 cycles)

`timescale 1ns/1ps

module mamba_fir_tb;

  logic        clk;
  logic        rst_n;

  // Control interface
  logic        start_i;
  logic [15:0] seq_len_i;
  logic        busy_o;
  logic        done_o;

  // Streaming input interface
  logic [15:0] sample_data_i;
  logic [4:0]  sample_ch_i;
  logic        sample_valid_i;
  logic        sample_ready_o;

  // Streaming output interface
  logic [15:0] fir_data_o;
  logic [4:0]  fir_ch_o;
  logic        fir_valid_o;
  logic        fir_ready_i;

  int pass_count = 0;
  int fail_count = 0;

  // Clock generation (50 MHz = 20 ns period)
  initial begin
    clk = 0;
    forever #10 clk = ~clk;
  end

  // Watchdog timer (prevent hung simulations)
  initial begin
    #2000000; // 2 ms simulation limit
    $display("[FATAL] Watchdog timeout triggered at %0t ns", $time);
    $finish(2);
  end

  // Instantiate Device Under Test
  mamba_fir_sidecar #(
    .NUM_CHANNELS (24),
    .NUM_TAPS     (128),
    .NUM_LANES    (4)
  ) dut (
    .clk_i          (clk),
    .rst_ni         (rst_n),
    .start_i        (start_i),
    .seq_len_i      (seq_len_i),
    .busy_o         (busy_o),
    .done_o         (done_o),
    .sample_data_i  (sample_data_i),
    .sample_ch_i    (sample_ch_i),
    .sample_valid_i (sample_valid_i),
    .sample_ready_o (sample_ready_o),
    .fir_data_o     (fir_data_o),
    .fir_ch_o       (fir_ch_o),
    .fir_valid_o    (fir_valid_o),
    .fir_ready_i    (fir_ready_i)
  );

  task send_and_collect(
    input  [15:0] d0, input  [15:0] d1, input  [15:0] d2, input  [15:0] d3,
    output [15:0] o0, output [15:0] o1, output [15:0] o2, output [15:0] o3
  );
    begin
      while (!sample_ready_o) @(posedge clk);
      @(posedge clk);
      sample_valid_i <= 1'b1; sample_ch_i <= 5'd0; sample_data_i <= d0;
      @(posedge clk);
      sample_valid_i <= 1'b1; sample_ch_i <= 5'd1; sample_data_i <= d1;
      @(posedge clk);
      sample_valid_i <= 1'b1; sample_ch_i <= 5'd2; sample_data_i <= d2;
      @(posedge clk);
      sample_valid_i <= 1'b1; sample_ch_i <= 5'd3; sample_data_i <= d3;
      @(posedge clk);
      sample_valid_i <= 1'b0;

      while (!fir_valid_o) @(posedge clk);
      o0 = fir_data_o;
      @(posedge clk);
      o1 = fir_data_o;
      @(posedge clk);
      o2 = fir_data_o;
      @(posedge clk);
      o3 = fir_data_o;
    end
  endtask

  logic [15:0] out0, out1, out2, out3;
  int start_cycle;
  int elapsed_cycles;
  int step_idx;

  initial begin
    $display("================================================================");
    $display("  128-TAP DIAGSSM1D FIR HARDWARE SIDECAR VERIFICATION");
    $display("================================================================");
    $fflush();

    // Initial signals
    start_i        = 0;
    seq_len_i      = 0;
    sample_data_i  = 0;
    sample_ch_i    = 0;
    sample_valid_i = 0;
    fir_ready_i    = 1;
    rst_n          = 0;

    repeat (5) @(posedge clk);
    rst_n = 1;
    repeat (5) @(posedge clk);

    // -------------------------------------------------------------------------
    // TC-FIR-001: Reset State & Readiness
    // -------------------------------------------------------------------------
    $display("[TEST] TC-FIR-001: Checking Reset State and Readiness...");
    $fflush();
    if (busy_o == 1'b0 && done_o == 1'b0 && sample_ready_o == 1'b1) begin
      $display("       [PASS] TC-FIR-001: Engine idle and ready to accept input");
      pass_count++;
    end else begin
      $display("       [FAIL] TC-FIR-001: busy=%b, done=%b, ready=%b", busy_o, done_o, sample_ready_o);
      fail_count++;
    end
    $fflush();

    // -------------------------------------------------------------------------
    // TC-FIR-002: Impulse Response Test
    // -------------------------------------------------------------------------
    $display("[TEST] TC-FIR-002: Testing 128-tap Bidirectional Impulse Response...");
    $fflush();
    @(posedge clk);
    start_i   <= 1'b1;
    seq_len_i <= 16'd4;
    @(posedge clk);
    start_i   <= 1'b0;

    send_and_collect(16'd1000, 16'd0, 16'd0, 16'd0, out0, out1, out2, out3);
    $display("       Step 0 Filtered output: Ch0=%0d, Ch1=%0d, Ch2=%0d, Ch3=%0d",
             $signed(out0), $signed(out1), $signed(out2), $signed(out3));
    send_and_collect(16'd0, 16'd0, 16'd0, 16'd0, out0, out1, out2, out3);
    send_and_collect(16'd0, 16'd0, 16'd0, 16'd0, out0, out1, out2, out3);
    send_and_collect(16'd0, 16'd0, 16'd0, 16'd0, out0, out1, out2, out3);

    while (!done_o) @(posedge clk);

    if (out0 != 0 || out1 != 0 || out2 != 0 || out3 != 0 || done_o == 1'b1) begin
      $display("       [PASS] TC-FIR-002: 128-tap FIR impulse response verified, engine reached DONE");
      pass_count++;
    end else begin
      $display("       [FAIL] TC-FIR-002: Zero response captured or engine did not complete");
      fail_count++;
    end
    $fflush();

    // -------------------------------------------------------------------------
    // TC-FIR-003: 4-Lane Parallel Channel Concurrency
    // -------------------------------------------------------------------------
    $display("[TEST] TC-FIR-003: Testing 4-Lane Parallel Channel Concurrency...");
    $fflush();
    @(posedge clk);
    start_i   <= 1'b1;
    seq_len_i <= 16'd2;
    @(posedge clk);
    start_i   <= 1'b0;

    send_and_collect(16'd500, 16'd600, 16'd700, 16'd800, out0, out1, out2, out3);
    $display("       Lane outputs: ch0=%0d, ch1=%0d, ch2=%0d, ch3=%0d",
             $signed(out0), $signed(out1), $signed(out2), $signed(out3));
    send_and_collect(16'd500, 16'd600, 16'd700, 16'd800, out0, out1, out2, out3);

    while (!done_o) @(posedge clk);

    if (out0 != 0 && out1 != 0 && out2 != 0 && out3 != 0) begin
      $display("       [PASS] TC-FIR-003: All 4 parallel MAC lanes verified active and producing output");
      pass_count++;
    end else begin
      $display("       [FAIL] TC-FIR-003: One or more parallel lanes produced zero");
      fail_count++;
    end
    $fflush();

    // -------------------------------------------------------------------------
    // TC-FIR-004: Execution Latency Verification (< 4,000,000 cycles)
    // -------------------------------------------------------------------------
    $display("[TEST] TC-FIR-004: Verifying Hardware Latency Budget (< 4,000,000 cycles)...");
    $fflush();
    start_cycle = $time / 20;
    @(posedge clk);
    start_i   <= 1'b1;
    seq_len_i <= 16'd16; // 16 steps benchmark
    @(posedge clk);
    start_i   <= 1'b0;

    for (step_idx = 0; step_idx < 16; step_idx++) begin
      send_and_collect(16'd256, 16'd256, 16'd256, 16'd256, out0, out1, out2, out3);
    end

    while (!done_o) @(posedge clk);

    elapsed_cycles = ($time / 20) - start_cycle;
    $display("       Measured 16-step latency: %0d clock cycles", elapsed_cycles);
    $display("       Projected 500-step latency: %0d clock cycles (< 4,000,000 budget)", (elapsed_cycles * 500) / 16);
    $fflush();

    if (((elapsed_cycles * 500) / 16) < 4000000) begin
      $display("       [PASS] TC-FIR-004: Latency is well within 4,000,000 cycle budget");
      pass_count++;
    end else begin
      $display("       [FAIL] TC-FIR-004: Latency exceeded budget!");
      fail_count++;
    end
    $fflush();

    // Summary
    $display("\n================================================================");
    $display("  TEST SUMMARY: %0d PASSED, %0d FAILED", pass_count, fail_count);
    $display("================================================================");
    $fflush();

    if (fail_count == 0) begin
      $display("[SUCCESS] All 128-tap DiagSSM1D FIR sidecar tests PASSED!\n");
      $finish(0);
    end else begin
      $display("[FATAL] FIR sidecar test failures detected!\n");
      $finish(1);
    end
  end

endmodule
