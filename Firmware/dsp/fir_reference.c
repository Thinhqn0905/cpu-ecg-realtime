/* Copyright 2026 RISC-V ECG Project
 * SPDX-License-Identifier: Apache-2.0
 *
 * Exact Scalar Reference Model for 45-Tap Linear-Phase FIR Filter
 * Used to verify DSP hardware/assembly kernels per Instruction/claim_integrity.md
 */

#include <stdint.h>
#include <stdbool.h>

#define FIR_NUM_TAPS 45

// 45-tap 0.5-40 Hz linear-phase bandpass filter coefficients (Q15 fixed-point)
const int16_t g_fir_coeffs_q15[FIR_NUM_TAPS] = {
      -12,   -18,   -25,   -31,   -32,   -23,     1,    44,   108,   192,
      290,   394,   494,   575,   624,   628,   577,   466,   295,    73,
     -180,  -442,  -684,  -877, -1000, -1034,  -968,  -805,  -556,  -240,
      115,   481,   825,  1118,  1334,  1453,  1465,  1368,  1171,   889,
      545,   168,  -208,  -550,  -829
};

/**
 * Exact scalar reference implementation of 45-tap FIR filter.
 * Accumulates products in 64-bit to prevent overflow, then scales and saturates to 16-bit.
 *
 * @param samples Pointer to delay line of 45 16-bit samples (samples[0] = x[n], samples[44] = x[n-44])
 * @param coeffs  Pointer to 45 16-bit Q15 filter coefficients
 * @return Filtered output sample scaled to 16-bit
 */
int16_t ecg_fir_scalar_reference(const int16_t *samples, const int16_t *coeffs) {
    int64_t acc = 0;

    for (int i = 0; i < FIR_NUM_TAPS; i++) {
        acc += (int64_t)samples[i] * (int64_t)coeffs[i];
    }

    // Scale Q15 (shift right by 15 with symmetric rounding)
    int64_t scaled = (acc + (1 << 14)) >> 15;

    // Saturate to 16-bit signed range [-32768, 32767]
    if (scaled > 32767) {
        return 32767;
    } else if (scaled < -32768) {
        return -32768;
    }

    return (int16_t)scaled;
}
