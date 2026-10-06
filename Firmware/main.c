/* Copyright 2026 RISC-V ECG Project
   SPDX-License-Identifier: Apache-2.0

   CV32E40P Real-Time ECG SoC Main Application
   Clinical-Grade 2-Lead Biosignal Acquisition & Arrhythmia Processing Engine
*/

#include <stdint.h>
#include <stdbool.h>
#include "drivers/ads1292r.h"
#include "drivers/uart.h"
#include "drivers/dma.h"
#include "dsp/pan_tompkins.h"

// CNN-MAMBA Memory Mapped Registers (0x2000_0000)
#define MAMBA_BASE_ADDR        0x20000000
#define MAMBA_REG_CTRL         (*(volatile uint32_t*)(MAMBA_BASE_ADDR + 0x00))
#define MAMBA_REG_STATUS       (*(volatile uint32_t*)(MAMBA_BASE_ADDR + 0x04))
#define MAMBA_REG_CONFIG       (*(volatile uint32_t*)(MAMBA_BASE_ADDR + 0x08))
#define MAMBA_REG_RESULT_CLASS (*(volatile uint32_t*)(MAMBA_BASE_ADDR + 0x0C))
#define MAMBA_REG_RESULT_CONF  (*(volatile uint32_t*)(MAMBA_BASE_ADDR + 0x10))

// External PULP Assembly Kernels
extern int32_t ecg_fir_pulp(const int16_t *samples, const int16_t *coeffs, uint32_t num_taps_div2);
extern int32_t ecg_biquad_pulp(int32_t x_in, int32_t *d1, int32_t *d2, const int32_t *coeffs);

// 45-Tap Lowpass Filter Coefficients (Linear-Phase 40 Hz Cutoff @ 500 Hz Fs, Q15)
static const int16_t fir_coeffs[45] = {
    -12, -25, -45, -58, -48,  -1,  88, 218, 375, 529,
    641, 672, 592, 389,  67, -337,-779,-1198,-1524,-1698,
  -1672,-1417, -934, -257, 563, 1459, 2341, 3117, 3698, 4016,
   4016, 3698, 3117, 2341, 1459,  563, -257, -934,-1417,-1672,
  -1698,-1524,-1198, -779, -337
};

// 50 Hz Notch Biquad Coefficients (Fs = 500 Hz, Q15 format)
static const int32_t notch_coeffs[5] = {
    31129, -50367, 31129, -50367, 29491 // b0, b1, b2, a1, a2
};

// Global Signal Processing Delay States
static int16_t fir_delay_line[48]; // 4-byte aligned for post-increment loads
static int32_t notch_d1 = 0, notch_d2 = 0;
static pan_tompkins_state_t pt_detector;

// Real-Time Event Flags set by ISRs
volatile bool g_afe_sample_ready = false;
volatile bool g_buffer_block_ready = false;
volatile bool g_mamba_event_ready = false;

// ---------------------------------------------------------------------------
// Fast Interrupt Service Routines (ISRs)
// ---------------------------------------------------------------------------
void isr_afe_drdy(void) {
    g_afe_sample_ready = true;
}

void isr_buffer_ready(void) {
    g_buffer_block_ready = true;
}

void isr_mamba_event(void) {
    g_mamba_event_ready = true;
}

void isr_uart_rx(void) {
    char cmd = uart_getc();
    if (cmd == 'R') {
        ads1292r_send_cmd(ADS_CMD_RESET);
    }
}

void isr_uart_tx(void) {}
void isr_timer(void) {}
void isr_gpio(void) {}

// ---------------------------------------------------------------------------
// Application Main
// ---------------------------------------------------------------------------
int main(void) {
    // 1. Initialize Subsystem Peripherals
    uart_init(434);      // 115200 baud @ 50 MHz
    dma_init();          // Initialize Ping-Pong BRAM buffer
    ads1292r_init();     // 500 Hz, Gain 6, Auto DRDY Mode
    pt_init(&pt_detector); // Initialize Pan-Tompkins QRS detector

    // 2. Configure CNN-MAMBA Coprocessor
    MAMBA_REG_CONFIG = 0x4000; // Q15 threshold: 0.50
    MAMBA_REG_CTRL   = 0x05;   // Enable inference and interrupt

    uint8_t packet_seq = 0;
    ads1292r_sample_t sample;
    int32_t block_ch1[32];
    int32_t block_ch2[32];

    // Transmit system ready banner
    const char ready_msg[] = "CV32E40P ECG SoC Initialized\r\n";
    uart_write((const uint8_t*)ready_msg, sizeof(ready_msg) - 1);

    // 3. Real-Time Superloop
    while (1) {
        // Low-power wait for interrupt
        asm volatile ("wfi");

        // Service single sample DRDY
        if (g_afe_sample_ready) {
            g_afe_sample_ready = false;

            if (ads1292r_read_sample(&sample)) {
                // Update FIR delay line (push newest sample)
                for (int i = 44; i > 0; i--) {
                    fir_delay_line[i] = fir_delay_line[i-1];
                }
                fir_delay_line[0] = (int16_t)(sample.ch1 >> 8);

                // Run 45-tap FIR lowpass using Xpulp hardware loop (28 cycles)
                int32_t filtered_ch1 = ecg_fir_pulp(fir_delay_line, fir_coeffs, 22);

                // Run 50 Hz powerline notch biquad (18 cycles)
                int32_t notch_ch1 = ecg_biquad_pulp(filtered_ch1, &notch_d1, &notch_d2, notch_coeffs);

                // Run Pan-Tompkins QRS Complex Detection
                bool qrs_detected = pt_process_sample(&pt_detector, notch_ch1);

                // Transmit 14-byte clinical telemetry frame over UART
                uart_send_ecg_packet(packet_seq++, sample.status, notch_ch1, sample.ch2, qrs_detected ? 0x01 : 0x00);
            }
        }

        // Service 32-sample block transfer from Ping-Pong DMA
        if (g_buffer_block_ready) {
            g_buffer_block_ready = false;

            uint8_t ready_bank = (DMA_REG_STATUS & 0x01) ? 0 : 1;
            dma_read_block(ready_bank, block_ch1, block_ch2, 32);
            dma_ack_bank(ready_bank);

            // Trigger CNN-MAMBA classification on conditioned 32-sample block
            MAMBA_REG_CTRL = 0x01; // Start inference
        }

        // Service CNN-MAMBA classification result
        if (g_mamba_event_ready) {
            g_mamba_event_ready = false;

            uint32_t detected_class = MAMBA_REG_RESULT_CLASS;
            uint32_t confidence     = MAMBA_REG_RESULT_CONF;

            if (detected_class != 0) { // Non-normal arrhythmia detected
                // Send emergency alert packet
                uart_send_ecg_packet(0xFF, 0xEE, (int32_t)detected_class, (int32_t)confidence, 0xFF);
            }
        }
    }

    return 0;
}
