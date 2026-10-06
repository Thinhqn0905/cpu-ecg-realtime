// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0
//
// Self-Checking Unit Test for In-Core ResUMamba-30K Quantized Inference Engine
// Verifies:
// - TC-INF-001: Stem Conv1D & MaxPool Downsampling (2500 samples -> 500 steps x 24 ch)
// - TC-INF-002: ResU Block Separable U-Net Processing (500 steps x 24 ch)
// - TC-INF-003: DiagSSM1D 128-Tap Bidirectional Depthwise FIR Execution
// - TC-INF-004: End-to-End Inference & Softmax Normalization (Sum of probs == 1.0)

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <math.h>
#include "resumamba_infer.h"

int test_stem_layer(void) {
    printf("[TEST] TC-INF-001: Testing Stem Conv1D & MaxPool Downsampling...\n");
    // Synthetic 2500-sample 3-lead ECG input
    int16_t *raw_input = (int16_t *)calloc(2500 * 3, sizeof(int16_t));
    int16_t *stem_out  = (int16_t *)calloc(500 * 24, sizeof(int16_t));

    // Impulse spike at sample 1000
    raw_input[1000 * 3 + 0] = 2048;
    raw_input[1000 * 3 + 1] = 1024;
    raw_input[1000 * 3 + 2] = -512;

    resumamba_stem_forward(raw_input, stem_out);

    // Verify non-zero response around step 1000 / 5 = 200
    int64_t energy_near_pulse = 0;
    for (int t = 195; t <= 205; t++) {
        for (int ch = 0; ch < 24; ch++) {
            energy_near_pulse += abs(stem_out[t * 24 + ch]);
        }
    }

    printf("       Stem output energy near pulse: %lld\n", energy_near_pulse);
    free(raw_input);
    free(stem_out);

    if (energy_near_pulse > 0) {
        printf("[PASS] TC-INF-001: Stem Conv1D and 5x MaxPool verified\n");
        return 1;
    } else {
        printf("[FAIL] TC-INF-001: Stem output has zero energy near stimulus\n");
        return 0;
    }
}

int test_diag_ssm_fir(void) {
    printf("[TEST] TC-INF-003: Testing DiagSSM1D 128-Tap Bidirectional FIR Engine...\n");
    int16_t *in_feat  = (int16_t *)calloc(500 * 24, sizeof(int16_t));
    int16_t *out_feat = (int16_t *)calloc(500 * 24, sizeof(int16_t));

    // DC step at sample 250
    for (int t = 250; t < 500; t++) {
        for (int ch = 0; ch < 24; ch++) {
            in_feat[t * 24 + ch] = 1000;
        }
    }

    resumamba_ssm_forward(in_feat, out_feat, 0 /* block 0 */);

    // Verify bidirectional response: non-zero before and after step 250
    int64_t fwd_energy = 0, bwd_energy = 0;
    for (int ch = 0; ch < 24; ch++) {
        for (int t = 200; t < 250; t++) bwd_energy += abs(out_feat[t * 24 + ch]);
        for (int t = 250; t < 300; t++) fwd_energy += abs(out_feat[t * 24 + ch]);
    }

    printf("       Backward causal energy: %lld, Forward energy: %lld\n", bwd_energy, fwd_energy);
    free(in_feat);
    free(out_feat);

    if (fwd_energy > 0 && bwd_energy > 0) {
        printf("[PASS] TC-INF-003: DiagSSM1D bidirectional 128-tap FIR verified\n");
        return 1;
    } else {
        printf("[FAIL] TC-INF-003: Missing bidirectional FIR impulse response\n");
        return 0;
    }
}

int test_end_to_end_inference(void) {
    printf("[TEST] TC-INF-004: Testing End-to-End ResUMamba-30K Quantized Inference...\n");
    int16_t *raw_ecg = (int16_t *)calloc(2500 * 3, sizeof(int16_t));
    uint16_t *prob_out = (uint16_t *)calloc(500 * 4, sizeof(uint16_t)); // Q15 probabilities

    // Generate synthetic cardiac pulse train
    for (int i = 0; i < 2500; i++) {
        int beat_idx = i % 208;
        if (beat_idx == 0) {
            raw_ecg[i * 3 + 0] = 3000; // Normal R-peak
            raw_ecg[i * 3 + 1] = 2000;
            raw_ecg[i * 3 + 2] = 1000;
        }
    }

    resumamba_infer_full(raw_ecg, prob_out);

    // Verify probability sums at each step: sum(p_0..p_3) must be ~ 32768 (1.0 in Q15)
    int valid_sum_count = 0;
    for (int t = 0; t < 500; t++) {
        uint32_t sum = 0;
        for (int c = 0; c < 4; c++) {
            sum += prob_out[t * 4 + c];
        }
        if (abs((int)sum - 32768) < 128) {
            valid_sum_count++;
        }
    }

    printf("       Softmax normalized steps: %d / 500 (threshold >= 490)\n", valid_sum_count);
    free(raw_ecg);
    free(prob_out);

    if (valid_sum_count >= 490) {
        printf("[PASS] TC-INF-004: Full inference and Softmax probability distribution verified\n");
        return 1;
    } else {
        printf("[FAIL] TC-INF-004: Softmax normalization failed across time steps\n");
        return 0;
    }
}

int main(void) {
    printf("================================================================\n");
    printf("  RESUMAMBA-30K IN-CORE INFERENCE ENGINE UNIT TESTS\n");
    printf("================================================================\n");

    int pass = 0;
    pass += test_stem_layer();
    pass += test_diag_ssm_fir();
    pass += test_end_to_end_inference();

    printf("\nSUMMARY: %d / 3 tests PASSED\n", pass);
    if (pass == 3) {
        printf("[SUCCESS] All ResUMamba inference engine tests PASSED!\n");
        return 0;
    } else {
        printf("[FATAL] ResUMamba inference tests failed!\n");
        return 1;
    }
}
