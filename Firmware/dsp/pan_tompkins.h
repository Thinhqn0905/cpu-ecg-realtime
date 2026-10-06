#ifndef PAN_TOMPKINS_H
#define PAN_TOMPKINS_H

#include <stdint.h>
#include <stdbool.h>

#define PT_WINDOW_SIZE 30 // 30 samples at 500 Hz = 60 ms integration window

typedef struct {
    int32_t x_hist[5];     // 5-point derivative history
    int32_t win_buf[PT_WINDOW_SIZE]; // Moving window buffer
    int32_t win_sum;       // Sliding window accumulator
    uint32_t win_idx;
    int32_t spk;           // Running signal peak estimate
    int32_t npk;           // Running noise peak estimate
    int32_t threshold1;    // Primary detection threshold
    int32_t threshold2;    // Searchback threshold
    uint32_t sample_count;
    uint32_t last_qrs_sample;
    uint32_t rr_interval;  // RR interval in samples
} pan_tompkins_state_t;

void pt_init(pan_tompkins_state_t *pt);
bool pt_process_sample(pan_tompkins_state_t *pt, int32_t sample);

#endif // PAN_TOMPKINS_H
