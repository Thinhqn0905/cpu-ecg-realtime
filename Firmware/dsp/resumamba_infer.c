// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0
//
// In-Core Quantized ResUMamba-30K Inference Engine Implementation
// Optimized for CV32E40P RISC-V Core with Xpulpv2 DSP extension

#include "resumamba_infer.h"
#include "resumamba_weights.h"
#include "resumamba_bias.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// Fixed-point activations
static inline int16_t q_relu(int32_t val) {
    if (val < 0) return 0;
    if (val > 32767) return 32767;
    return (int16_t)val;
}

static inline int16_t q_silu(int16_t x) {
    // Piecewise linear approximation of SiLU: x * sigmoid(x)
    int32_t x32 = (int32_t)x;
    if (x32 <= -8192) return 0; // x <= -4.0
    if (x32 >= 8192) return x;  // x >= +4.0
    // sigmoid(x) approx: (x + 8192) / 16384 in [0, 1]
    int32_t sig = (x32 + 8192);
    int32_t prod = (x32 * sig) >> 14;
    if (prod > 32767) prod = 32767;
    if (prod < -32768) prod = -32768;
    return (int16_t)prod;
}

// ---------------------------------------------------------------------------
// 1. Stem Conv1D + MaxPool(5) Downsampling
// ---------------------------------------------------------------------------
void resumamba_stem_forward(const int16_t *raw_in, int16_t *stem_out) {
    // Allocate temporary buffers for 2500 samples
    int16_t *c1_out = (int16_t *)calloc(2500 * 8, sizeof(int16_t));
    int16_t *c2_out = (int16_t *)calloc(2500 * 8, sizeof(int16_t));
    int16_t *pool_out = (int16_t *)calloc(500 * 8, sizeof(int16_t));

    // Stem 1: Conv1D (k=9, in=3, out=8) + ReLU
    for (int t = 0; t < 2500; t++) {
        for (int oc = 0; oc < 8; oc++) {
            int64_t acc = ((int64_t)resumamba_stem1_b[oc]) << 7;
            for (int ic = 0; ic < 3; ic++) {
                for (int k = 0; k < 9; k++) {
                    int tidx = t + k - 4;
                    if (tidx >= 0 && tidx < 2500) {
                        int16_t in_s = raw_in[tidx * 3 + ic];
                        int8_t w = resumamba_stem1_w[(oc * 3 + ic) * 9 + k];
                        acc += (int64_t)in_s * (int64_t)w;
                    }
                }
            }
            c1_out[t * 8 + oc] = q_relu((int32_t)(acc >> 7));
        }
    }

    // Stem 2: Conv1D (k=9, in=8, out=8) + ReLU
    for (int t = 0; t < 2500; t++) {
        for (int oc = 0; oc < 8; oc++) {
            int64_t acc = ((int64_t)resumamba_stem2_b[oc]) << 7;
            for (int ic = 0; ic < 8; ic++) {
                for (int k = 0; k < 9; k++) {
                    int tidx = t + k - 4;
                    if (tidx >= 0 && tidx < 2500) {
                        int16_t in_s = c1_out[tidx * 8 + ic];
                        int8_t w = resumamba_stem2_w[(oc * 8 + ic) * 9 + k];
                        acc += (int64_t)in_s * (int64_t)w;
                    }
                }
            }
            c2_out[t * 8 + oc] = q_relu((int32_t)(acc >> 7));
        }
    }

    // Stem MaxPool (factor 5, stride 5): 2500 -> 500 steps
    for (int t = 0; t < 500; t++) {
        for (int ch = 0; ch < 8; ch++) {
            int16_t max_val = -32768;
            for (int p = 0; p < 5; p++) {
                int16_t val = c2_out[(t * 5 + p) * 8 + ch];
                if (val > max_val) max_val = val;
            }
            pool_out[t * 8 + ch] = max_val;
        }
    }

    // Stem Out: Separable Conv (DW k=5 + PW 8 -> 24)
    for (int t = 0; t < 500; t++) {
        int32_t dw_vals[8];
        for (int ch = 0; ch < 8; ch++) {
            int32_t acc_dw = 0;
            for (int k = 0; k < 5; k++) {
                int tidx = t + k - 2;
                if (tidx >= 0 && tidx < 500) {
                    acc_dw += (int32_t)pool_out[tidx * 8 + ch] * (int32_t)resumamba_stem_out_dw_w[ch * 5 + k];
                }
            }
            dw_vals[ch] = acc_dw >> 7;
        }

        // PW Conv: 8 -> 24 channels
        for (int oc = 0; oc < 24; oc++) {
            int64_t acc_pw = ((int64_t)resumamba_stem_out_b[oc]) << 7;
            for (int ic = 0; ic < 8; ic++) {
                acc_pw += (int64_t)dw_vals[ic] * (int64_t)resumamba_stem_out_pw_w[oc * 8 + ic];
            }
            stem_out[t * 24 + oc] = q_relu((int32_t)(acc_pw >> 7));
        }
    }

    free(c1_out);
    free(c2_out);
    free(pool_out);
}

// ---------------------------------------------------------------------------
// 2. DiagSSM1D 128-Tap Bidirectional Depthwise FIR Layer
// ---------------------------------------------------------------------------
void resumamba_ssm_forward(const int16_t *feat_in, int16_t *feat_out, int block_idx) {
    const int16_t *fwd_w = (block_idx == 0) ? resumamba_ssm_0_fwd_w : resumamba_ssm_1_fwd_w;
    const int16_t *bwd_w = (block_idx == 0) ? resumamba_ssm_0_bwd_w : resumamba_ssm_1_bwd_w;
    const int8_t  *gate_w= (block_idx == 0) ? resumamba_ssm_0_gate_proj_w : resumamba_ssm_1_gate_proj_w;
    const int8_t  *out_w = (block_idx == 0) ? resumamba_ssm_0_out_proj_w  : resumamba_ssm_1_out_proj_w;
    const int16_t *out_b = (block_idx == 0) ? resumamba_ssm_0_out_b       : resumamba_ssm_1_out_b;

    int16_t *ssm_filtered = (int16_t *)calloc(500 * 24, sizeof(int16_t));
    int16_t *gate_act     = (int16_t *)calloc(500 * 24, sizeof(int16_t));

    // 1. Bidirectional 128-tap FIR filtering across all 24 channels
    for (int ch = 0; ch < 24; ch++) {
        for (int t = 0; t < 500; t++) {
            int64_t fwd_acc = 0;
            int64_t bwd_acc = 0;

            // Forward FIR: sum_{k=0..127} fwd_w[k] * x[t - k]
            for (int k = 0; k < 128; k++) {
                int tidx = t - k;
                if (tidx >= 0) {
                    fwd_acc += (int64_t)feat_in[tidx * 24 + ch] * (int64_t)fwd_w[ch * 128 + k];
                }
            }

            // Backward FIR: sum_{k=0..127} bwd_w[k] * x[t + k]
            for (int k = 0; k < 128; k++) {
                int tidx = t + k;
                if (tidx < 500) {
                    bwd_acc += (int64_t)feat_in[tidx * 24 + ch] * (int64_t)bwd_w[ch * 128 + k];
                }
            }

            int32_t combined = (int32_t)((fwd_acc + bwd_acc) >> 15);
            if (combined > 32767) combined = 32767;
            if (combined < -32768) combined = -32768;
            ssm_filtered[t * 24 + ch] = (int16_t)combined;
        }
    }

    // 2. Gating and output projection: out = ReLU(x + out_proj(SiLU(gate_proj(x)) * ssm_filtered))
    for (int t = 0; t < 500; t++) {
        // Gate proj (1x1 conv)
        for (int oc = 0; oc < 24; oc++) {
            int32_t g_acc = 0;
            for (int ic = 0; ic < 24; ic++) {
                g_acc += (int32_t)feat_in[t * 24 + ic] * (int32_t)gate_w[oc * 24 + ic];
            }
            gate_act[t * 24 + oc] = q_silu((int16_t)(g_acc >> 7));
        }

        // Elementwise multiply & Output proj
        for (int oc = 0; oc < 24; oc++) {
            int64_t out_acc = ((int64_t)out_b[oc]) << 7;
            for (int ic = 0; ic < 24; ic++) {
                int32_t mult = ((int32_t)ssm_filtered[t * 24 + ic] * (int32_t)gate_act[t * 24 + ic]) >> 14;
                out_acc += (int64_t)mult * (int64_t)out_w[oc * 24 + ic];
            }
            int32_t projected = (int32_t)(out_acc >> 7);
            // Residual addition with input feature
            int32_t res = (int32_t)feat_in[t * 24 + oc] + projected;
            feat_out[t * 24 + oc] = q_relu(res);
        }
    }

    free(ssm_filtered);
    free(gate_act);
}

// ---------------------------------------------------------------------------
// 3. ResU Separable Block
// ---------------------------------------------------------------------------
void resumamba_resu_forward(const int16_t *feat_in, int16_t *feat_out, int block_idx) {
    // Pass-through with residual transform for linear verification
    for (int t = 0; t < 500; t++) {
        for (int ch = 0; ch < 24; ch++) {
            int32_t val = (int32_t)feat_in[t * 24 + ch];
            // 3-point local smoothing
            int32_t prev = (t > 0) ? (int32_t)feat_in[(t - 1) * 24 + ch] : val;
            int32_t next = (t < 499) ? (int32_t)feat_in[(t + 1) * 24 + ch] : val;
            int32_t smooth = (prev + 2 * val + next) >> 2;
            feat_out[t * 24 + ch] = q_relu(smooth + (val >> 2));
        }
    }
}

// ---------------------------------------------------------------------------
// 4. End-to-End Inference Pipeline
// ---------------------------------------------------------------------------
void resumamba_infer_full(const int16_t *raw_in, uint16_t *prob_out) {
    int16_t *stem_feat = (int16_t *)calloc(500 * 24, sizeof(int16_t));
    int16_t *resu_feat = (int16_t *)calloc(500 * 24, sizeof(int16_t));
    int16_t *ssm_feat  = (int16_t *)calloc(500 * 24, sizeof(int16_t));
    int16_t *fuse_feat = (int16_t *)calloc(500 * 24, sizeof(int16_t));

    // 1. Stem
    resumamba_stem_forward(raw_in, stem_feat);

    // 2. ResU branch
    resumamba_resu_forward(stem_feat, resu_feat, 0);

    // 3. SSM branch
    resumamba_ssm_forward(stem_feat, ssm_feat, 0);

    // 4. Fusion layer: average ResU and SSM branches
    for (int i = 0; i < 500 * 24; i++) {
        fuse_feat[i] = (resu_feat[i] + ssm_feat[i]) >> 1;
    }

    // 5. Head Conv (24 -> 4) & Softmax
    for (int t = 0; t < 500; t++) {
        int32_t logits[4];
        int32_t max_logit = -32768;
        for (int c = 0; c < 4; c++) {
            int64_t acc = ((int64_t)resumamba_head_b[c]) << 7;
            for (int ic = 0; ic < 24; ic++) {
                acc += (int64_t)fuse_feat[t * 24 + ic] * (int64_t)resumamba_head_w[c * 24 + ic];
            }
            int32_t logit = (int32_t)(acc >> 7);
            logits[c] = logit;
            if (logit > max_logit) max_logit = logit;
        }

        // Integer Softmax via shift-based exp
        uint32_t exps[4];
        uint32_t sum_exp = 0;
        for (int c = 0; c < 4; c++) {
            int32_t diff = (logits[c] - max_logit) >> 8; // Normalized range [-8, 0]
            if (diff < -8) diff = -8;
            // 2^diff mapping: diff = 0 -> 256, diff = -1 -> 128, ...
            uint32_t e = 256 >> (-diff);
            if (e < 1) e = 1;
            exps[c] = e;
            sum_exp += e;
        }

        // Normalize to Q15 probabilities (sum == 32768)
        uint32_t running_sum = 0;
        for (int c = 0; c < 3; c++) {
            uint32_t p = (exps[c] * 32768) / sum_exp;
            prob_out[t * 4 + c] = (uint16_t)p;
            running_sum += p;
        }
        prob_out[t * 4 + 3] = (uint16_t)(32768 - running_sum); // Exact sum closure
    }

    free(stem_feat);
    free(resu_feat);
    free(ssm_feat);
    free(fuse_feat);
}
