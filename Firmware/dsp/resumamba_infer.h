// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0
//
// In-Core Quantized ResUMamba-30K Inference Engine Header

#ifndef RESUMAMBA_INFER_H
#define RESUMAMBA_INFER_H

#include <stdint.h>

#define RESUMAMBA_INPUT_SAMPLES 2500
#define RESUMAMBA_INPUT_CHANNELS 3
#define RESUMAMBA_OUTPUT_STEPS  500
#define RESUMAMBA_NUM_CLASSES   4
#define RESUMAMBA_WIDTH         24
#define RESUMAMBA_SSM_TAPS      128

#ifdef __cplusplus
extern "C" {
#endif

// Stem Conv1D + MaxPool(5) downsampling: (2500 x 3) -> (500 x 24)
void resumamba_stem_forward(const int16_t *raw_in, int16_t *stem_out);

// State-Space DiagSSM1D 128-tap bidirectional FIR block: (500 x 24) -> (500 x 24)
void resumamba_ssm_forward(const int16_t *feat_in, int16_t *feat_out, int block_idx);

// ResU separable U-Net block: (500 x 24) -> (500 x 24)
void resumamba_resu_forward(const int16_t *feat_in, int16_t *feat_out, int block_idx);

// Full end-to-end model inference pipeline returning Q15 Softmax probabilities (500 x 4)
void resumamba_infer_full(const int16_t *raw_in, uint16_t *prob_out);

#ifdef __cplusplus
}
#endif

#endif // RESUMAMBA_INFER_H
