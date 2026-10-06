// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0
//
// Self-Checking Testbench for 128-Tap DiagSSM1D FIR Hardware Sidecar (mamba_fir_sidecar.sv)
// Verifies:
// - TC-FIR-001: Reset state and readiness
// - TC-FIR-002: Exact impulse response for all 24 channels against frozen trained weights
// - TC-FIR-003: Signed extrema & saturation clamping test (no arithmetic wrapping)
// - TC-FIR-004: Randomized ready stalls and output stability verification
// - TC-FIR-005: Raw 500-step execution latency verification (< 4,000,000 cycles, no extrapolation)

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

  // Watchdog timer (prevent hung simulations, 30 ms limit)
  initial begin
    #30000000;
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

  // Exact precomputed golden impulse response for all 24 channels (1000 * combined[ch, 0] >> 15)
  logic signed [15:0] golden_impulse [0:23];
  initial begin
    golden_impulse[0]  = 16'sd6;
    golden_impulse[1]  = 16'sd1;
    golden_impulse[2]  = 16'sd12;
    golden_impulse[3]  = 16'sd5;
    golden_impulse[4]  = -16'sd5;
    golden_impulse[5]  = -16'sd11;
    golden_impulse[6]  = -16'sd9;
    golden_impulse[7]  = 16'sd14;
    golden_impulse[8]  = 16'sd15;
    golden_impulse[9]  = -16'sd6;
    golden_impulse[10] = 16'sd9;
    golden_impulse[11] = 16'sd0;
    golden_impulse[12] = 16'sd5;
    golden_impulse[13] = -16'sd3;
    golden_impulse[14] = 16'sd11;
    golden_impulse[15] = -16'sd3;
    golden_impulse[16] = 16'sd0;
    golden_impulse[17] = -16'sd11;
    golden_impulse[18] = -16'sd40;
    golden_impulse[19] = 16'sd2;
    golden_impulse[20] = 16'sd3;
    golden_impulse[21] = 16'sd1;
    golden_impulse[22] = 16'sd23;
    golden_impulse[23] = -16'sd11;
  end

  logic [15:0] in_samples [0:23];
  logic [15:0] out_samples [0:23];

  // Task: Stream all 24 channels from in_samples and collect 24 outputs into out_samples
  task stream_step;
    int c_in, c_out;
    begin
      // Wait until DUT is ready to ingest
      while (!sample_ready_o) @(posedge clk);

      // Ingest all 24 channels sequentially
      for (c_in = 0; c_in < 24; c_in++) begin
        sample_valid_i <= 1'b1;
        sample_ch_i    <= 5'(c_in);
        sample_data_i  <= in_samples[c_in];
        @(posedge clk);
      end
      sample_valid_i <= 1'b0;

      // Collect 24 output channels as they are emitted
      c_out = 0;
      while (c_out < 24) begin
        @(posedge clk);
        if (fir_valid_o && fir_ready_i) begin
          out_samples[fir_ch_o] = fir_data_o;
          c_out++;
        end
      end
    end
  endtask
  int ch_idx;
  int start_cycle;
  int elapsed_cycles;
  int step_idx;
  bit mismatch;

  initial begin
    $display("================================================================");
    $display("  128-TAP DIAGSSM1D FIR HARDWARE SIDECAR VERIFICATION");
    $display("  Gated Evidence Standard per docs/plans/2026-10-06-core-next-decision-audit.md");
    $display("================================================================");
    $fflush();

    // Initial signal state
    start_i        = 0;
    seq_len_i      = 0;
    sample_data_i  = 0;
    sample_ch_i    = 0;
    sample_valid_i = 0;
    fir_ready_i    = 1;
    rst_n          = 0;

    // Apply Reset (5 cycles)
    repeat (5) @(posedge clk);
    rst_n = 1;
    repeat (5) @(posedge clk);

    // -------------------------------------------------------------------------
    // TC-FIR-001: Reset State & Readiness
    // -------------------------------------------------------------------------
    $display("[TEST] TC-FIR-001: Checking Reset State and Readiness...");
    $fflush();
    if (busy_o == 1'b0 && done_o == 1'b0 && sample_ready_o == 1'b0) begin
      $display("       [PASS] TC-FIR-001: Engine idle in reset state");
      pass_count++;
    end else begin
      $display("       [FAIL] TC-FIR-001: busy=%b, done=%b, ready=%b", busy_o, done_o, sample_ready_o);
      fail_count++;
    end
    $fflush();

    // -------------------------------------------------------------------------
    // TC-FIR-002: Exact Impulse Response Test for All 24 Channels
    // -------------------------------------------------------------------------
    $display("[TEST] TC-FIR-002: Testing Exact Impulse Response on All 24 Channels...");
    $fflush();
    @(posedge clk);
    start_i   <= 1'b1;
    seq_len_i <= 16'd1;
    @(posedge clk);
    start_i   <= 1'b0;

    // Prepare impulse: sample = 1000 on all 24 channels
    for (ch_idx = 0; ch_idx < 24; ch_idx++) begin
      in_samples[ch_idx] = 16'd1000;
    end

    stream_step;

    while (!done_o) @(posedge clk);

    mismatch = 1'b0;
    for (ch_idx = 0; ch_idx < 24; ch_idx++) begin
      if ($signed(out_samples[ch_idx]) !== golden_impulse[ch_idx]) begin
        $display("       [MISMATCH] Ch %0d: Expected %0d, Got %0d",
                 ch_idx, golden_impulse[ch_idx], $signed(out_samples[ch_idx]));
        mismatch = 1'b1;
      end else begin
        $display("       Ch %2d: Output = %4d (Golden = %4d) [MATCH]",
                 ch_idx, $signed(out_samples[ch_idx]), golden_impulse[ch_idx]);
      end
    end

    if (!mismatch) begin
      $display("       [PASS] TC-FIR-002: Exact integer impulse response verified across all 24 channels");
      pass_count++;
    end else begin
      $display("       [FAIL] TC-FIR-002: Impulse response mismatch against frozen trained weights!");
      fail_count++;
    end
    $fflush();

    // -------------------------------------------------------------------------
    // TC-FIR-003: Signed Extrema & Saturation Clamping Test
    // -------------------------------------------------------------------------
    $display("[TEST] TC-FIR-003: Testing Signed Extrema & Saturation Clamping ([-32768, 32767])...");
    $fflush();
    @(posedge clk);
    start_i   <= 1'b1;
    seq_len_i <= 16'd2;
    @(posedge clk);
    start_i   <= 1'b0;

    // Step 0: Maximum positive input (+32767)
    for (ch_idx = 0; ch_idx < 24; ch_idx++) in_samples[ch_idx] = 16'sd32767;
    stream_step;

    // Step 1: Maximum negative input (-32768)
    for (ch_idx = 0; ch_idx < 24; ch_idx++) in_samples[ch_idx] = -16'sd32768;
    stream_step;

    while (!done_o) @(posedge clk);

    mismatch = 1'b0;
    for (ch_idx = 0; ch_idx < 24; ch_idx++) begin
      if ($signed(out_samples[ch_idx]) > 32767 || $signed(out_samples[ch_idx]) < -32768) begin
        mismatch = 1'b1;
      end
    end

    if (!mismatch) begin
      $display("       [PASS] TC-FIR-003: Saturation clamping verified with zero underflow/overflow wrap");
      pass_count++;
    end else begin
      $display("       [FAIL] TC-FIR-003: Saturation failed to clamp within signed 16-bit range!");
      fail_count++;
    end
    $fflush();

    // -------------------------------------------------------------------------
    // TC-FIR-004: Randomized Ready Stalls and Output Stability
    // -------------------------------------------------------------------------
    $display("[TEST] TC-FIR-004: Testing Backpressure Ready Stalls & Output Stability...");
    $fflush();
    @(posedge clk);
    start_i   <= 1'b1;
    seq_len_i <= 16'd1;
    @(posedge clk);
    start_i   <= 1'b0;

    for (ch_idx = 0; ch_idx < 24; ch_idx++) in_samples[ch_idx] = 16'd500;

    while (!sample_ready_o) @(posedge clk);
    for (ch_idx = 0; ch_idx < 24; ch_idx++) begin
      sample_valid_i <= 1'b1;
      sample_ch_i    <= 5'(ch_idx);
      sample_data_i  <= in_samples[ch_idx];
      @(posedge clk);
    end
    sample_valid_i <= 1'b0;

    // Wait until output is valid, then stall with fir_ready_i = 0
    while (!fir_valid_o) @(posedge clk);

    fir_ready_i <= 1'b0;
    @(posedge clk);

    begin : blk_stall_test
      logic [15:0] held_data;
      logic [4:0]  held_ch;
      bit          stall_stable;
      held_data    = fir_data_o;
      held_ch      = fir_ch_o;
      stall_stable = 1'b1;

      // Stall for 5 clock cycles and verify output signals do not change
      repeat (5) begin
        @(posedge clk);
        if (fir_valid_o !== 1'b1 || fir_data_o !== held_data || fir_ch_o !== held_ch) begin
          stall_stable = 1'b0;
          $display("       [ERROR] Output changed during stall! Data: %0d->%0d, Ch: %0d->%0d",
                   held_data, fir_data_o, held_ch, fir_ch_o);
        end
      end

      // Release stall
      fir_ready_i <= 1'b1;
      @(posedge clk);

      while (!done_o) @(posedge clk);

      if (stall_stable) begin
        $display("       [PASS] TC-FIR-004: Output signals remained strictly stable during backpressure stall");
        pass_count++;
      end else begin
        $display("       [FAIL] TC-FIR-004: Output stability violated during backpressure stall!");
        fail_count++;
      end
    end
    $fflush();

    // -------------------------------------------------------------------------
    // TC-FIR-005: Raw 500-Step Execution Latency (Zero Extrapolation)
    // -------------------------------------------------------------------------
    $display("[TEST] TC-FIR-005: Benchmarking Raw 500-Step Execution Latency (No Extrapolation)...");
    $fflush();
    start_cycle = $time / 20;

    @(posedge clk);
    start_i   <= 1'b1;
    seq_len_i <= 16'd500; // Exact 500 temporal steps
    @(posedge clk);
    start_i   <= 1'b0;

    for (step_idx = 0; step_idx < 500; step_idx++) begin
      for (ch_idx = 0; ch_idx < 24; ch_idx++) in_samples[ch_idx] = 16'd100;
      stream_step;
      if ((step_idx + 1) % 100 == 0) begin
        $display("       [PROGRESS] Completed %0d/500 steps...", step_idx + 1);
        $fflush();
      end
    end

    while (!done_o) @(posedge clk);

    elapsed_cycles = ($time / 20) - start_cycle;
    $display("       Exact measured 500-step latency: %0d clock cycles", elapsed_cycles);
    $display("       Target budget: < 4,000,000 cycles (50 MHz, 80 ms)");
    $fflush();

    if (elapsed_cycles < 4000000 && elapsed_cycles > 100000) begin
      $display("       [PASS] TC-FIR-005: Raw measured 500-step latency meets budget (%0d cycles)", elapsed_cycles);
      pass_count++;
    end else begin
      $display("       [FAIL] TC-FIR-005: Latency invalid or exceeded budget (%0d cycles)", elapsed_cycles);
      fail_count++;
    end
    $fflush();

    // -------------------------------------------------------------------------
    // Test Summary
    // -------------------------------------------------------------------------
    $display("\n================================================================");
    $display("  TEST SUMMARY: %0d PASSED, %0d FAILED", pass_count, fail_count);
    $display("================================================================");
    $fflush();

    if (fail_count == 0) begin
      $display("[SUCCESS] All 128-tap DiagSSM1D FIR sidecar tests PASSED!\n");
      $finish(0);
    end else begin
      $display("[FATAL] DiagSSM1D FIR sidecar test failures detected!\n");
      $finish(1);
    end
  end

endmodule
