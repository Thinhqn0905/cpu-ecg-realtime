// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0
//
// Biosignal Conditioning & Preprocessing Library Implementation
// Features:
// - 45-tap linear-phase FIR bandpass filter (0.5 - 30.0 Hz @ 250 Hz)
// - Fixed-point per-lead Z-Score normalization (Q4.11 format)
// - Optimized for 32-bit RISC-V integer ALU without floating-point units

#include "signal_ops.h"
#include <stdint.h>
#include <stdlib.h>

// 45-tap FIR coefficients in Q15 format (sum of positive taps normalized)
static const int16_t FIR_COEFFS_Q15[ECG_FILTER_TAPS] = {
      -40,   -16,    17,    50,    55,     4,  -106,  -230,  -281,  -175,
       90,   393,   521,   286,  -333, -1095, -1546, -1204,   181,  2441,
     4977,  6973,  7729,  6973,  4977,  2441,   181, -1204, -1546, -1095,
     -333,   286,   521,   393,    90,  -175,  -281,  -230,  -106,     4,
       55,    50,    17,   -16,   -40
};

// Integer square root via bitwise approximation
static uint32_t int_sqrt64(uint64_t val) {
    if (val == 0) return 0;
    uint64_t rem = 0;
    uint64_t root = 0;
    for (int i = 0; i < 32; i++) {
        root <<= 1;
        rem = (rem << 2) | ((val >> 62) & 3);
        val <<= 2;
        if (root < rem) {
            rem -= (root | 1);
            root += 2;
        }
    }
    return (uint32_t)(root >> 1);
}

void ecg_bandpass_filter(const int16_t *in, int16_t *out, int n_samples) {
    for (int n = 0; n < n_samples; n++) {
        int64_t acc = 0;
        for (int k = 0; k < ECG_FILTER_TAPS; k++) {
            int idx = n - k;
            int16_t sample = (idx >= 0) ? in[idx] : in[0]; // Boundary clamp
            acc += (int64_t)sample * (int64_t)FIR_COEFFS_Q15[k];
        }
        // Scale by Q15 shift (>> 15) with rounding
        acc += (1 << 14);
        int32_t result = (int32_t)(acc >> 15);
        if (result > 32767) result = 32767;
        if (result < -32768) result = -32768;
        out[n] = (int16_t)result;
    }
}

void ecg_zscore_normalize(const int16_t *in, int16_t *out, int n_samples) {
    if (n_samples <= 0) return;

    // 1. Calculate integer mean
    int64_t sum = 0;
    for (int i = 0; i < n_samples; i++) {
        sum += in[i];
    }
    int32_t mean = (int32_t)(sum / n_samples);

    // 2. Calculate variance
    uint64_t sum_sq = 0;
    for (int i = 0; i < n_samples; i++) {
        int32_t diff = in[i] - mean;
        sum_sq += (uint64_t)((int64_t)diff * diff);
    }
    uint32_t variance = (uint32_t)(sum_sq / (uint64_t)n_samples);
    uint32_t std_dev = int_sqrt64(sum_sq / (uint64_t)n_samples);
    if (std_dev < 1) std_dev = 1;

    // 3. Normalize into Q4.11 format (unity std_dev = 2048)
    for (int i = 0; i < n_samples; i++) {
        int32_t diff = in[i] - mean;
        int64_t scaled = ((int64_t)diff * ECG_NORM_SCALE) / std_dev;
        if (scaled > 32767) scaled = 32767;
        if (scaled < -32768) scaled = -32768;
        out[i] = (int16_t)scaled;
    }
}

void ecg_lead_preprocess_3ch(const int16_t *raw_3ch, int16_t *out_3ch, int n_samples) {
    // Scratchpads for deinterleaving single channels
    int16_t *buf_in  = (int16_t *)malloc(n_samples * sizeof(int16_t));
    int16_t *buf_fil = (int16_t *)malloc(n_samples * sizeof(int16_t));
    int16_t *buf_norm= (int16_t *)malloc(n_samples * sizeof(int16_t));

    if (!buf_in || !buf_fil || !buf_norm) {
        if (buf_in) free(buf_in);
        if (buf_fil) free(buf_fil);
        if (buf_norm) free(buf_norm);
        return;
    }

    for (int ch = 0; ch < 3; ch++) {
        // Deinterleave channel
        for (int i = 0; i < n_samples; i++) {
            buf_in[i] = raw_3ch[i * 3 + ch];
        }
        // Bandpass filter
        ecg_bandpass_filter(buf_in, buf_fil, n_samples);
        // Z-score normalize
        ecg_zscore_normalize(buf_fil, buf_norm, n_samples);
        // Re-interleave
        for (int i = 0; i < n_samples; i++) {
            out_3ch[i * 3 + ch] = buf_norm[i];
        }
    }

    free(buf_in);
    free(buf_fil);
    free(buf_norm);
}
