// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0
//
// Biosignal Conditioning & Preprocessing Library Header

#ifndef SIGNAL_OPS_H
#define SIGNAL_OPS_H

#include <stdint.h>

#define ECG_FILTER_TAPS 45
#define ECG_NORM_SCALE  2048 // Q4.11 unity variance (std = 2048)

#ifdef __cplusplus
extern "C" {
#endif

// 45-tap 0.5-30 Hz linear-phase FIR bandpass filter for single channel
void ecg_bandpass_filter(const int16_t *in, int16_t *out, int n_samples);

// Fixed-point per-lead Z-score normalization mapping to Q4.11 format
void ecg_zscore_normalize(const int16_t *in, int16_t *out, int n_samples);

// Complete 3-lead preprocessing: Bandpass + Z-Score across interleaved channels
void ecg_lead_preprocess_3ch(const int16_t *raw_3ch, int16_t *out_3ch, int n_samples);

#ifdef __cplusplus
}
#endif

#endif // SIGNAL_OPS_H
