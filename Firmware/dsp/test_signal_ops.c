// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0
//
// Unit test for Fixed-Point Biosignal Conditioning & Preprocessing Library
// Verifies:
// 1. TC-SIG-001: 45-tap 0.5-30 Hz FIR Bandpass Filter impulse & frequency response
// 2. TC-SIG-002: Fixed-point Z-Score normalization (zero mean, unit variance)
// 3. TC-SIG-003: 3-Lead multi-channel pipeline end-to-end execution

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <math.h>
#include "signal_ops.h"

int test_fir_bandpass(void) {
    printf("[TEST] TC-SIG-001: Testing 45-tap 0.5-30 Hz FIR Bandpass Filter...\n");
    // Generate synthetic 10 Hz sine wave (in passband) and 60 Hz hum (in stopband)
    const int N = 250; // 1 second @ 250 Hz
    int16_t input_10hz[250];
    int16_t input_60hz[250];
    int16_t output_10hz[250];
    int16_t output_60hz[250];

    for (int i = 0; i < N; i++) {
        double t = (double)i / 250.0;
        input_10hz[i] = (int16_t)(1000.0 * sin(2.0 * M_PI * 10.0 * t));
        input_60hz[i] = (int16_t)(1000.0 * sin(2.0 * M_PI * 60.0 * t));
    }

    ecg_bandpass_filter(input_10hz, output_10hz, N);
    ecg_bandpass_filter(input_60hz, output_60hz, N);

    // Calculate RMS energy after transient (samples 50..200)
    double energy_pass = 0.0, energy_stop = 0.0;
    for (int i = 50; i < 200; i++) {
        energy_pass += (double)output_10hz[i] * (double)output_10hz[i];
        energy_stop += (double)output_60hz[i] * (double)output_60hz[i];
    }
    double attenuation_db = 10.0 * log10((energy_stop + 1e-6) / (energy_pass + 1e-6));
    printf("       10 Hz energy: %.1f, 60 Hz energy: %.1f, Attenuation: %.2f dB\n",
           energy_pass, energy_stop, attenuation_db);

    if (attenuation_db < -15.0 && energy_pass > 1e6) {
        printf("[PASS] TC-SIG-001: 60 Hz noise attenuated by > 15 dB (%.2f dB)\n", attenuation_db);
        return 1;
    } else {
        printf("[FAIL] TC-SIG-001: Inadequate attenuation or signal loss!\n");
        return 0;
    }
}

int test_zscore_normalize(void) {
    printf("[TEST] TC-SIG-002: Testing Fixed-Point Z-Score Normalization...\n");
    const int N = 500;
    int16_t in[500];
    int16_t out[500];

    // Input with offset = 2000, amplitude = 500
    for (int i = 0; i < N; i++) {
        in[i] = (int16_t)(2000 + (i % 50) * 10);
    }

    ecg_zscore_normalize(in, out, N);

    // Verify mean is approximately 0
    int64_t sum = 0;
    for (int i = 0; i < N; i++) sum += out[i];
    double mean_out = (double)sum / (double)N;

    // Verify variance in Q4.11 format (expected scale ~2048)
    int64_t sum_sq = 0;
    for (int i = 0; i < N; i++) sum_sq += (int64_t)out[i] * (int64_t)out[i];
    double std_out = sqrt((double)sum_sq / (double)N);

    printf("       Normalized Mean: %.3f (target ~0.0), Std: %.1f (target ~2048)\n", mean_out, std_out);

    if (fabs(mean_out) < 5.0 && fabs(std_out - 2048.0) < 100.0) {
        printf("[PASS] TC-SIG-002: Fixed-point Z-score normalization verified\n");
        return 1;
    } else {
        printf("[FAIL] TC-SIG-002: Normalization mean/std out of bounds\n");
        return 0;
    }
}

int test_3lead_preprocess(void) {
    printf("[TEST] TC-SIG-003: Testing 3-Lead Preprocessing Pipeline...\n");
    const int N = 250;
    int16_t raw_3ch[250 * 3];
    int16_t out_3ch[250 * 3];

    for (int i = 0; i < N; i++) {
        raw_3ch[i * 3 + 0] = (int16_t)(500 * sin(2.0 * M_PI * 1.2 * i / 250.0));
        raw_3ch[i * 3 + 1] = (int16_t)(400 * sin(2.0 * M_PI * 1.2 * i / 250.0 + 0.5));
        raw_3ch[i * 3 + 2] = (int16_t)(300 * sin(2.0 * M_PI * 1.2 * i / 250.0 + 1.0));
    }

    ecg_lead_preprocess_3ch(raw_3ch, out_3ch, N);

    // Verify output is non-zero and stable across all 3 leads
    int valid = 1;
    for (int ch = 0; ch < 3; ch++) {
        int64_t energy = 0;
        for (int i = 0; i < N; i++) {
            energy += abs(out_3ch[i * 3 + ch]);
        }
        if (energy == 0) valid = 0;
    }

    if (valid) {
        printf("[PASS] TC-SIG-003: 3-Lead multi-channel preprocessing pipeline passed\n");
        return 1;
    } else {
        printf("[FAIL] TC-SIG-003: 3-Lead output contains silent channels\n");
        return 0;
    }
}

int main(void) {
    printf("================================================================\n");
    printf("  BIOSIGNAL CONDITIONING UNIT TESTS (signal_ops)\n");
    printf("================================================================\n");

    int pass = 0;
    pass += test_fir_bandpass();
    pass += test_zscore_normalize();
    pass += test_3lead_preprocess();

    printf("\nSUMMARY: %d / 3 tests PASSED\n", pass);
    if (pass == 3) {
        printf("[SUCCESS] All signal conditioning unit tests PASSED!\n");
        return 0;
    } else {
        printf("[FATAL] Signal conditioning tests failed!\n");
        return 1;
    }
}
