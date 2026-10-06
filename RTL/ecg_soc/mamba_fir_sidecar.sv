// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0
//
// Description: 128-Tap DiagSSM1D Bidirectional FIR Hardware Sidecar Accelerator.
//              Features 4-lane parallel pipelined MAC units for depthwise convolution
//              across all 24 channels, using frozen trained INT16 Q15 coefficients
//              from mamba_coeff_pkg, mapping directly to DSP48E1 slices on Xilinx Artix-7.
//              Computes bidirectional State-Space FIR filtering:
//                y[t, c] = clamp_i16((sum_{k=0..127} (w_fwd[c, k] * x[t-k, c] + w_bwd[c, k] * x[t+k, c])) >> 15)
//              Features strict valid/ready handshake with backpressure stall support.

import mamba_coeff_pkg::*;

module mamba_fir_sidecar #(
  parameter int unsigned NUM_CHANNELS = 24,
  parameter int unsigned NUM_TAPS     = 128,
  parameter int unsigned NUM_LANES    = 4
) (
  input  logic        clk_i,
  input  logic        rst_ni,

  // Control Interface
  input  logic        start_i,
  input  logic [15:0] seq_len_i,
  output logic        busy_o,
  output logic        done_o,

  // Streaming Input Sample Port (Ingests 24 channels per temporal step)
  input  logic [15:0] sample_data_i,
  input  logic [4:0]  sample_ch_i,
  input  logic        sample_valid_i,
  output logic        sample_ready_o,

  // Streaming Filtered Output Port (Emits 24 channels per temporal step)
  output logic [15:0] fir_data_o,
  output logic [4:0]  fir_ch_o,
  output logic        fir_valid_o,
  input  logic        fir_ready_i
);

  // ---------------------------------------------------------------------------
  // State Machine Definitions
  // ---------------------------------------------------------------------------
  typedef enum logic [2:0] {
    ST_IDLE,
    ST_INGEST,
    ST_MAC_STEP,
    ST_EMIT,
    ST_DONE
  } fir_state_t;

  fir_state_t state_q;

  // ---------------------------------------------------------------------------
  // History Buffers for all 24 Channels (128 taps per channel)
  // ---------------------------------------------------------------------------
  logic signed [15:0] history_buf [0:NUM_CHANNELS-1][0:NUM_TAPS-1];
  logic [6:0]         history_head [0:NUM_CHANNELS-1];

  // 24-Channel 40-bit Accumulators (DSP48E1 precision)
  logic signed [39:0] accumulators_q [0:NUM_CHANNELS-1];

  // Counters and Indices
  logic [15:0] total_samples_q;
  logic [15:0] current_step_q;
  logic [4:0]  ingest_ch_cnt_q;
  logic [2:0]  group_idx_q;      // 6 groups of 4 lanes (0..5)
  logic [6:0]  tap_idx_q;        // 128 taps (0..127)
  logic [4:0]  emit_ch_q;        // Emission channel index (0..23)

  assign fir_data_o     = clamped_val;
  assign fir_ch_o       = emit_ch_q;
  assign fir_valid_o    = (state_q == ST_EMIT);
  assign busy_o         = (state_q != ST_IDLE && state_q != ST_DONE);
  assign done_o         = (state_q == ST_DONE);
  assign sample_ready_o = (state_q == ST_INGEST);

  integer c_init, t_init;

  // ---------------------------------------------------------------------------
  // 4-Lane Parallel MAC Signals
  // ---------------------------------------------------------------------------
  logic [4:0]         lane_ch [0:NUM_LANES-1];
  logic [6:0]         lane_h_idx [0:NUM_LANES-1];
  logic signed [15:0] lane_sample [0:NUM_LANES-1];
  logic signed [15:0] lane_fwd [0:NUM_LANES-1];
  logic signed [15:0] lane_bwd [0:NUM_LANES-1];
  logic signed [16:0] lane_coeff [0:NUM_LANES-1];
  logic signed [32:0] lane_prod [0:NUM_LANES-1];

  genvar gl;
  generate
    for (gl = 0; gl < NUM_LANES; gl = gl + 1) begin : gen_mac_lanes
      assign lane_ch[gl]     = 5'({group_idx_q, 2'(gl)});
      assign lane_h_idx[gl]  = history_head[lane_ch[gl]] - 1'b1 - tap_idx_q;
      assign lane_sample[gl] = history_buf[lane_ch[gl]][lane_h_idx[gl]];
      assign lane_fwd[gl]    = mamba_coeff_pkg::get_fwd_coeff(lane_ch[gl], tap_idx_q);
      assign lane_bwd[gl]    = mamba_coeff_pkg::get_bwd_coeff(lane_ch[gl], tap_idx_q);
      assign lane_coeff[gl]  = lane_fwd[gl] + lane_bwd[gl];
      assign lane_prod[gl]   = $signed(lane_sample[gl]) * $signed(lane_coeff[gl]);
    end
  endgenerate

  // ---------------------------------------------------------------------------
  // Clamping and Scaling for Emission Channel
  // ---------------------------------------------------------------------------
  logic signed [39:0] curr_acc;
  logic signed [31:0] scaled_acc;
  logic [15:0]        clamped_val;

  assign curr_acc   = accumulators_q[emit_ch_q];
  assign scaled_acc = 32'(curr_acc >>> 15);

  always_comb begin
    if (scaled_acc > 32'sd32767)
      clamped_val = 16'sd32767;
    else if (scaled_acc < -32'sd32768)
      clamped_val = -16'sd32768;
    else
      clamped_val = 16'(scaled_acc);
  end

  // ---------------------------------------------------------------------------
  // Execution Logic & State Machine
  // ---------------------------------------------------------------------------
  integer l_idx, c_idx;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q         <= ST_IDLE;
      total_samples_q <= 16'd0;
      current_step_q  <= 16'd0;
      ingest_ch_cnt_q <= 5'd0;
      group_idx_q     <= 3'd0;
      tap_idx_q       <= 7'd0;
      emit_ch_q       <= 5'd0;

      for (c_idx = 0; c_idx < NUM_CHANNELS; c_idx = c_idx + 1) begin
        history_head[c_idx]   <= 7'd0;
        accumulators_q[c_idx] <= 40'sd0;
        for (t_init = 0; t_init < NUM_TAPS; t_init = t_init + 1) begin
          history_buf[c_idx][t_init] <= 16'sd0;
        end
      end
    end else begin
      case (state_q)
        ST_IDLE: begin
          if (start_i) begin
            state_q         <= ST_INGEST;
            total_samples_q <= (seq_len_i > 0) ? seq_len_i : 16'd128;
            current_step_q  <= 16'd0;
            ingest_ch_cnt_q <= 5'd0;
            group_idx_q     <= 3'd0;
            tap_idx_q       <= 7'd0;
            emit_ch_q       <= 5'd0;

            for (c_idx = 0; c_idx < NUM_CHANNELS; c_idx = c_idx + 1) begin
              history_head[c_idx]   <= 7'd0;
              accumulators_q[c_idx] <= 40'sd0;
              for (t_init = 0; t_init < NUM_TAPS; t_init = t_init + 1) begin
                history_buf[c_idx][t_init] <= 16'sd0;
              end
            end
          end
        end

        ST_INGEST: begin
          if (sample_valid_i && (sample_ch_i < NUM_CHANNELS)) begin
            history_buf[sample_ch_i][history_head[sample_ch_i]] <= $signed(sample_data_i);
            history_head[sample_ch_i] <= history_head[sample_ch_i] + 1'b1;
            ingest_ch_cnt_q <= ingest_ch_cnt_q + 1'b1;

            if (ingest_ch_cnt_q + 1'b1 >= 5'(NUM_CHANNELS)) begin
              ingest_ch_cnt_q <= 5'd0;
              group_idx_q     <= 3'd0;
              tap_idx_q       <= 7'd0;
              state_q         <= ST_MAC_STEP;
            end
          end
        end

        ST_MAC_STEP: begin
          // 4-Lane Parallel Multiply-Accumulate
          for (l_idx = 0; l_idx < NUM_LANES; l_idx = l_idx + 1) begin
            accumulators_q[lane_ch[l_idx]] <= accumulators_q[lane_ch[l_idx]] + 40'(lane_prod[l_idx]);
          end

          tap_idx_q <= tap_idx_q + 1'b1;

          if (tap_idx_q == 7'd127) begin
            tap_idx_q <= 7'd0;
            if (group_idx_q + 1'b1 >= 3'd6) begin
              // All 6 groups completed (all 24 channels accumulated)
              group_idx_q <= 3'd0;
              state_q     <= ST_EMIT;
              emit_ch_q   <= 5'd0;
            end else begin
              group_idx_q <= group_idx_q + 1'b1;
            end
          end
        end

        ST_EMIT: begin
          // Backpressure handshake: only advance when downstream asserts fir_ready_i
          if (fir_ready_i) begin
            accumulators_q[emit_ch_q] <= 40'sd0;

            if (emit_ch_q + 1'b1 >= 5'(NUM_CHANNELS)) begin
              // All 24 channels emitted for current step
              emit_ch_q      <= 5'd0;
              current_step_q <= current_step_q + 1'b1;

              if (current_step_q + 1'b1 >= total_samples_q) begin
                state_q <= ST_DONE;
              end else begin
                state_q         <= ST_INGEST;
                ingest_ch_cnt_q <= 5'd0;
              end
            end else begin
              emit_ch_q <= emit_ch_q + 1'b1;
            end
          end
          // If !fir_ready_i: stall, fir_data_o, fir_ch_o, fir_valid_o remain stable
        end

        ST_DONE: begin
          if (start_i) begin
            state_q         <= ST_INGEST;
            total_samples_q <= (seq_len_i > 0) ? seq_len_i : 16'd128;
            current_step_q  <= 16'd0;
            ingest_ch_cnt_q <= 5'd0;
            group_idx_q     <= 3'd0;
            tap_idx_q       <= 7'd0;
            emit_ch_q       <= 5'd0;

            for (c_idx = 0; c_idx < NUM_CHANNELS; c_idx = c_idx + 1) begin
              history_head[c_idx]   <= 7'd0;
              accumulators_q[c_idx] <= 40'sd0;
              for (t_init = 0; t_init < NUM_TAPS; t_init = t_init + 1) begin
                history_buf[c_idx][t_init] <= 16'sd0;
              end
            end
          end
        end

        default: state_q <= ST_IDLE;
      endcase
    end
  end

endmodule : mamba_fir_sidecar
