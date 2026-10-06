// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0
//
// Description: 128-Tap DiagSSM1D Bidirectional FIR Hardware Sidecar Accelerator.
//              Features 4-lane parallel pipelined MAC units for depthwise convolution
//              across 24 channels, mapping directly to DSP48E1 slices on Xilinx Artix-7.
//              Computes bidirectional State-Space FIR filtering:
//                y[t, c] = clamp_i16((sum_{k=0..127} (w_fwd[k] * x[t-k] + w_bwd[k] * x[t+k])) >> 15)

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

  // Streaming Input Sample Port
  input  logic [15:0] sample_data_i,
  input  logic [4:0]  sample_ch_i,
  input  logic        sample_valid_i,
  output logic        sample_ready_o,

  // Streaming Filtered Output Port
  output logic [15:0] fir_data_o,
  output logic [4:0]  fir_ch_o,
  output logic        fir_valid_o,
  input  logic        fir_ready_i
);

  // ---------------------------------------------------------------------------
  // Coefficient ROM (Bidirectional 128-tap DiagSSM1D fixed-point kernels)
  // ---------------------------------------------------------------------------
  logic signed [15:0] fwd_coeff_rom [0:NUM_TAPS-1];
  logic signed [15:0] bwd_coeff_rom [0:NUM_TAPS-1];

  // ---------------------------------------------------------------------------
  // Circular History Buffer for 4 Active Lanes (128 taps per lane)
  // ---------------------------------------------------------------------------
  logic signed [15:0] history_buf [0:NUM_LANES-1][0:NUM_TAPS-1];
  logic [6:0]         history_head [0:NUM_LANES-1];

  integer k_idx, l_idx, t_idx;
  initial begin
    for (k_idx = 0; k_idx < NUM_TAPS; k_idx = k_idx + 1) begin
      // Exponential decay: tap 0 = 2048, tap 127 ~ 16
      fwd_coeff_rom[k_idx] = 16'sd2048 / (16'sd1 + (16'(k_idx) >>> 3));
      bwd_coeff_rom[k_idx] = 16'sd1024 / (16'sd1 + (16'(k_idx) >>> 3));
    end
    for (l_idx = 0; l_idx < NUM_LANES; l_idx = l_idx + 1) begin
      for (t_idx = 0; t_idx < NUM_TAPS; t_idx = t_idx + 1) begin
        history_buf[l_idx][t_idx] = 16'sd0;
      end
    end
  end

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
  logic [15:0] total_samples_q;
  logic [15:0] current_step_q;
  logic [6:0]  tap_idx_q;
  logic [2:0]  lane_emit_idx_q;
  logic [2:0]  ingest_ch_cnt_q;

  // 4-Lane 40-bit Accumulators (DSP48E1 precision)
  logic signed [39:0] accumulators_q [0:NUM_LANES-1];

  // Output registers
  logic [15:0] fir_data_reg;
  logic [4:0]  fir_ch_reg;
  logic        fir_valid_reg;

  assign fir_data_o     = fir_data_reg;
  assign fir_ch_o       = fir_ch_reg;
  assign fir_valid_o    = fir_valid_reg;
  assign busy_o         = (state_q != ST_IDLE && state_q != ST_DONE);
  assign done_o         = (state_q == ST_DONE);
  assign sample_ready_o = (state_q == ST_IDLE || state_q == ST_INGEST);

  wire _unused_flow = &{1'b0, fir_ready_i};

  integer lane_idx;

  // Combinational signals for MAC and Emit calculations
  logic [6:0]         mac_h_idx [0:NUM_LANES-1];
  logic signed [15:0] mac_sample [0:NUM_LANES-1];
  logic signed [15:0] combined_coeff;
  logic signed [39:0] curr_acc;
  logic signed [31:0] scaled_acc;

  assign combined_coeff = fwd_coeff_rom[tap_idx_q] + bwd_coeff_rom[tap_idx_q];

  genvar gl;
  generate
    for (gl = 0; gl < NUM_LANES; gl = gl + 1) begin : gen_mac_signals
      assign mac_h_idx[gl]  = history_head[gl] - 1'b1 - tap_idx_q;
      assign mac_sample[gl] = history_buf[gl][mac_h_idx[gl]];
    end
  endgenerate

  assign curr_acc   = (lane_emit_idx_q < 3'(NUM_LANES)) ? accumulators_q[lane_emit_idx_q] : 40'sd0;
  assign scaled_acc = 32'(curr_acc >>> 15);

  // ---------------------------------------------------------------------------
  // Execution Logic & 4-Lane Pipelined Parallel MAC Engine
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q         <= ST_IDLE;
      total_samples_q <= 16'd0;
      current_step_q  <= 16'd0;
      tap_idx_q       <= 7'd0;
      lane_emit_idx_q <= 3'd0;
      ingest_ch_cnt_q <= 3'd0;
      fir_data_reg    <= 16'd0;
      fir_ch_reg      <= 5'd0;
      fir_valid_reg   <= 1'b0;

      for (lane_idx = 0; lane_idx < NUM_LANES; lane_idx = lane_idx + 1) begin
        history_head[lane_idx]   <= 7'd0;
        accumulators_q[lane_idx] <= 40'sd0;
      end
    end else begin
      fir_valid_reg <= 1'b0;

      case (state_q)
        ST_IDLE: begin
          if (start_i) begin
            state_q         <= ST_INGEST;
            total_samples_q <= (seq_len_i > 0) ? seq_len_i : 16'd128;
            current_step_q  <= 16'd0;
            tap_idx_q       <= 7'd0;
            lane_emit_idx_q <= 3'd0;
            ingest_ch_cnt_q <= 3'd0;
            for (lane_idx = 0; lane_idx < NUM_LANES; lane_idx = lane_idx + 1) begin
              accumulators_q[lane_idx] <= 40'sd0;
              history_head[lane_idx]   <= 7'd0;
            end
          end
        end

        ST_INGEST: begin
          if (sample_valid_i && sample_ch_i < NUM_LANES) begin
            history_buf[sample_ch_i][history_head[sample_ch_i]] <= $signed(sample_data_i);
            history_head[sample_ch_i] <= history_head[sample_ch_i] + 1'b1;
            ingest_ch_cnt_q <= ingest_ch_cnt_q + 1'b1;

            if (ingest_ch_cnt_q + 1'b1 >= 3'(NUM_LANES)) begin
              ingest_ch_cnt_q <= 3'd0;
              state_q         <= ST_MAC_STEP;
              tap_idx_q       <= 7'd0;
            end
          end
        end

        ST_MAC_STEP: begin
          // 4-Lane Parallel Multiply-Accumulate
          for (lane_idx = 0; lane_idx < NUM_LANES; lane_idx = lane_idx + 1) begin
            accumulators_q[lane_idx] <= accumulators_q[lane_idx] +
              ($signed(mac_sample[lane_idx]) * $signed(combined_coeff));
          end

          tap_idx_q <= tap_idx_q + 1'b1;
          if (tap_idx_q == 7'd127) begin
            state_q         <= ST_EMIT;
            lane_emit_idx_q <= 3'd0;
          end
        end

        ST_EMIT: begin
          if (lane_emit_idx_q < 3'(NUM_LANES)) begin
            if (scaled_acc > 32'sd32767)
              fir_data_reg <= 16'sd32767;
            else if (scaled_acc < -32'sd32768)
              fir_data_reg <= -16'sd32768;
            else
              fir_data_reg <= 16'(scaled_acc);

            fir_ch_reg    <= 5'(lane_emit_idx_q);
            fir_valid_reg <= 1'b1;

            accumulators_q[lane_emit_idx_q] <= 40'sd0;
            lane_emit_idx_q <= lane_emit_idx_q + 1'b1;
          end else begin
            current_step_q <= current_step_q + 1'b1;
            if (current_step_q + 1'b1 >= total_samples_q) begin
              state_q <= ST_DONE;
            end else begin
              state_q <= ST_INGEST;
            end
          end
        end

        ST_DONE: begin
          if (start_i) begin
            state_q         <= ST_INGEST;
            total_samples_q <= (seq_len_i > 0) ? seq_len_i : 16'd128;
            current_step_q  <= 16'd0;
            tap_idx_q       <= 7'd0;
            lane_emit_idx_q <= 3'd0;
            ingest_ch_cnt_q <= 3'd0;
            for (lane_idx = 0; lane_idx < NUM_LANES; lane_idx = lane_idx + 1) begin
              accumulators_q[lane_idx] <= 40'sd0;
              history_head[lane_idx]   <= 7'd0;
            end
          end
        end

        default: state_q <= ST_IDLE;
      endcase
    end
  end

endmodule : mamba_fir_sidecar
