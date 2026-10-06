// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0

#include "pan_tompkins.h"

void pt_init(pan_tompkins_state_t *pt) {
    for (int i = 0; i < 5; i++) pt->x_hist[i] = 0;
    for (int i = 0; i < PT_WINDOW_SIZE; i++) pt->win_buf[i] = 0;
    pt->win_sum         = 0;
    pt->win_idx         = 0;
    pt->spk             = 5000;  // Initial expected QRS peak
    pt->npk             = 1000;  // Initial noise floor
    pt->threshold1      = 2000;
    pt->threshold2      = 1000;
    pt->sample_count    = 0;
    pt->last_qrs_sample = 0;
    pt->rr_interval     = 500;   // 1.0 second (60 BPM) default
}

bool pt_process_sample(pan_tompkins_state_t *pt, int32_t sample) {
    pt->sample_count++;

    // 1. Five-Point Derivative:
    // y[n] = (1/8) * (2*x[n] + x[n-1] - x[n-3] - 2*x[n-4])
    int32_t deriv = (2 * sample + pt->x_hist[0] - pt->x_hist[2] - 2 * pt->x_hist[3]) >> 3;

    // Shift delay line
    pt->x_hist[3] = pt->x_hist[2];
    pt->x_hist[2] = pt->x_hist[1];
    pt->x_hist[1] = pt->x_hist[0];
    pt->x_hist[0] = sample;

    // 2. Non-linear Squaring with 64-bit Widening (prevents 32-bit overflow when |deriv| > 46340)
    int64_t deriv64 = (int64_t)deriv;
    int64_t sq64 = (deriv64 * deriv64) >> 10;
    int32_t squared = (sq64 > 0x7FFF) ? 0x7FFF : (int32_t)sq64;

    // 3. Moving Window Integration (30 samples)
    int32_t oldest = pt->win_buf[pt->win_idx];
    pt->win_buf[pt->win_idx] = squared;
    pt->win_sum = pt->win_sum + squared - oldest;
    pt->win_idx = (pt->win_idx + 1) % PT_WINDOW_SIZE;

    int32_t integrated = pt->win_sum / PT_WINDOW_SIZE;

    // 4. Adaptive Thresholding with 200 ms Refractory Blanking
    bool qrs_detected = false;
    uint32_t blanking_samples = 100; // 200 ms @ 500 Hz

    if ((pt->sample_count - pt->last_qrs_sample) > blanking_samples) {
        if (integrated > pt->threshold1) {
            qrs_detected = true;
            pt->rr_interval     = pt->sample_count - pt->last_qrs_sample;
            pt->last_qrs_sample = pt->sample_count;

            // Update Signal Peak running average: SPK = 0.125 * PEAK + 0.875 * SPK
            pt->spk = (integrated >> 3) + pt->spk - (pt->spk >> 3);
        } else {
            // Update Noise Peak running average: NPK = 0.125 * PEAK + 0.875 * NPK
            pt->npk = (integrated >> 3) + pt->npk - (pt->npk >> 3);
        }

        // Recalculate adaptive thresholds:
        // THRESHOLD1 = NPK + 0.25 * (SPK - NPK)
        // THRESHOLD2 = 0.5 * THRESHOLD1
        pt->threshold1 = pt->npk + ((pt->spk - pt->npk) >> 2);
        pt->threshold2 = pt->threshold1 >> 1;
    }

    return qrs_detected;
}
