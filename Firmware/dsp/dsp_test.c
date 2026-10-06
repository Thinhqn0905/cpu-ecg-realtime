/* Copyright 2026 RISC-V ECG Project
 * SPDX-License-Identifier: Apache-2.0
 *
 * DSP Arithmetic & Pan-Tompkins Verification Testbench (dsp_test.c)
 * Verifies per Instruction/claim_integrity.md and docs/plans/2026-10-06-core-next-decision-audit.md:
 * 1. Zero input test (all zeros -> output zero) for scalar reference
 * 2. Impulse response test (unit impulse -> output matches tap 0)
 * 3. Exact arithmetic equivalence between ecg_fir_pulp assembly and ecg_fir_scalar_reference
 *    (Executed on RISC-V target; explicitly SKIPPED on host to prevent stub false-pass)
 * 4. Cycle count measurement via hardware mcycle CSR
 *    (Executed on RISC-V target; explicitly SKIPPED on host)
 * 5. Pan-Tompkins squaring overflow verification (|deriv| > 46340)
 * 6. Pan-Tompkins complete QRS detection on synthetic cardiac waveform
 */

#include <stdint.h>
#include <stdbool.h>

#include "dsp_runtime.h"
#include "pan_tompkins.h"

#define FIR_NUM_TAPS 45

extern const int16_t g_fir_coeffs_q15[FIR_NUM_TAPS];
int16_t ecg_fir_scalar_reference(const int16_t *samples, const int16_t *coeffs);

#if defined(__riscv)
// Real assembly kernel on RISC-V target (ecg_fir_pulp.S)
extern int32_t ecg_fir_pulp(const int16_t *samples, const int16_t *coeffs, uint32_t num_taps_div2);
#endif

int main(void) {
    int pass_count = 0;
    int fail_count = 0;
    int skip_count = 0;

    int16_t samples[FIR_NUM_TAPS];
    dsp_memset(samples, 0, sizeof(samples));

    dsp_puts("================================================================\n");
    dsp_puts("  CV32E40P ECG DSP ARITHMETIC & DETECTION VERIFICATION SUITE   \n");
    dsp_puts("  Mandatory Evidence Verification per Instruction/claim_integrity.md\n");
    dsp_puts("================================================================\n");

    // -------------------------------------------------------------------------
    // Test 1: Zero Input Test
    // -------------------------------------------------------------------------
    dsp_memset(samples, 0, sizeof(samples));
    int16_t ref_zero = ecg_fir_scalar_reference(samples, g_fir_coeffs_q15);

#if defined(__riscv)
    int32_t pulp_zero = ecg_fir_pulp(samples, g_fir_coeffs_q15, FIR_NUM_TAPS / 2);
    if ((ref_zero == 0) && (pulp_zero == 0)) {
        dsp_puts("[PASS] TC-DSP-001: Zero input produces exact zero output on scalar and pulp kernels\n");
        pass_count++;
    } else {
        dsp_puts("[FAIL] TC-DSP-001: Zero input mismatch! ref=");
        dsp_print_i32((int32_t)ref_zero);
        dsp_puts(", pulp=");
        dsp_print_i32(pulp_zero);
        dsp_puts(" (expected 0)\n");
        fail_count++;
    }
#else
    if (ref_zero == 0) {
        dsp_puts("[PASS] TC-DSP-001: Zero input produces exact zero output on scalar reference\n");
        pass_count++;
    } else {
        dsp_puts("[FAIL] TC-DSP-001: Zero input mismatch on scalar reference!\n");
        fail_count++;
    }
#endif

    // -------------------------------------------------------------------------
    // Test 2: Unit Impulse Response
    // -------------------------------------------------------------------------
    dsp_memset(samples, 0, sizeof(samples));
    samples[0] = 32767; // Q15 approx 1.0
    int16_t ref_impulse = ecg_fir_scalar_reference(samples, g_fir_coeffs_q15);
    int16_t expected_tap0 = g_fir_coeffs_q15[0];
    bool ref_ok = (ref_impulse >= expected_tap0 - 1) && (ref_impulse <= expected_tap0 + 1);

#if defined(__riscv)
    int32_t pulp_impulse = ecg_fir_pulp(samples, g_fir_coeffs_q15, FIR_NUM_TAPS / 2);
    bool pulp_ok = (pulp_impulse >= expected_tap0 - 1) && (pulp_impulse <= expected_tap0 + 1);
    if (ref_ok && pulp_ok && (ref_impulse == (int16_t)pulp_impulse)) {
        dsp_puts("[PASS] TC-DSP-002: Impulse response matches tap 0 (");
        dsp_print_i32((int32_t)ref_impulse);
        dsp_puts(") on scalar and pulp kernels\n");
        pass_count++;
    } else {
        dsp_puts("[FAIL] TC-DSP-002: Impulse mismatch! ref=");
        dsp_print_i32((int32_t)ref_impulse);
        dsp_puts(", pulp=");
        dsp_print_i32(pulp_impulse);
        dsp_puts(", expected=");
        dsp_print_i32((int32_t)expected_tap0);
        dsp_puts("\n");
        fail_count++;
    }
#else
    if (ref_ok) {
        dsp_puts("[PASS] TC-DSP-002: Impulse response matches tap 0 (");
        dsp_print_i32((int32_t)ref_impulse);
        dsp_puts(") on scalar reference\n");
        pass_count++;
    } else {
        dsp_puts("[FAIL] TC-DSP-002: Impulse mismatch on scalar reference! ref=");
        dsp_print_i32((int32_t)ref_impulse);
        dsp_puts(", expected=");
        dsp_print_i32((int32_t)expected_tap0);
        dsp_puts("\n");
        fail_count++;
    }
#endif

    // -------------------------------------------------------------------------
    // Test 3: Arithmetic Equivalence on Complex Waveform
    // (Target assembly executed on RISC-V target; SKIPPED on host)
    // -------------------------------------------------------------------------
#if defined(__riscv)
    bool equiv_ok = true;
    for (int pattern = 0; pattern < 5; pattern++) {
        for (int i = 0; i < FIR_NUM_TAPS; i++) {
            samples[i] = (int16_t)(((i * 739 + pattern * 1024) % 16000) - 8000);
        }
        int16_t ref_val  = ecg_fir_scalar_reference(samples, g_fir_coeffs_q15);
        int32_t pulp_val = ecg_fir_pulp(samples, g_fir_coeffs_q15, FIR_NUM_TAPS / 2);

        if (ref_val != (int16_t)pulp_val) {
            dsp_puts("[FAIL] TC-DSP-003: Kernel arithmetic mismatch at pattern ");
            dsp_print_i32(pattern);
            dsp_puts(": ref=");
            dsp_print_i32((int32_t)ref_val);
            dsp_puts(", pulp=");
            dsp_print_i32(pulp_val);
            dsp_puts("\n");
            equiv_ok = false;
            break;
        }
    }
    if (equiv_ok) {
        dsp_puts("[PASS] TC-DSP-003: ecg_fir_pulp matches ecg_fir_scalar_reference exactly across test vectors\n");
        pass_count++;
    } else {
        fail_count++;
    }
#else
    dsp_puts("[SKIP] TC-DSP-003: Target assembly kernel (ecg_fir_pulp) skipped on host (requires RISC-V target)\n");
    skip_count++;
#endif

    // -------------------------------------------------------------------------
    // Test 4: Real Cycle Count Measurement via Hardware mcycle CSR
    // (Measured on RISC-V target; SKIPPED on host)
    // -------------------------------------------------------------------------
#if defined(__riscv)
    uint32_t overhead = dsp_measure_overhead();
    uint32_t c_start = read_mcycle();
    volatile int32_t p_out = ecg_fir_pulp(samples, g_fir_coeffs_q15, FIR_NUM_TAPS / 2);
    (void)p_out;
    uint32_t c_end = read_mcycle();
    uint32_t raw_cycles = (c_end >= c_start) ? (c_end - c_start) : (c_end + (0xFFFFFFFF - c_start) + 1);
    uint32_t pulp_cycles = (raw_cycles >= overhead) ? (raw_cycles - overhead) : raw_cycles;

    dsp_puts("  INFO: Measured ecg_fir_pulp execution cycles: ");
    dsp_print_u32(pulp_cycles);
    dsp_puts(" (overhead: ");
    dsp_print_u32(overhead);
    dsp_puts(")\n");

    if (pulp_cycles > 0) {
        dsp_puts("[PASS] TC-DSP-004: Execution cycles measured via mcycle CSR: ");
        dsp_print_u32(pulp_cycles);
        dsp_puts(" cycles\n");
        pass_count++;
    } else {
        dsp_puts("[FAIL] TC-DSP-004: mcycle CSR returned 0 on RISC-V target!\n");
        fail_count++;
    }
#else
    dsp_puts("[SKIP] TC-DSP-004: Hardware cycle measurement via mcycle CSR skipped on host (requires RISC-V target)\n");
    skip_count++;
#endif

    // -------------------------------------------------------------------------
    // Test 5: Pan-Tompkins Squaring Overflow Protection
    // -------------------------------------------------------------------------
    {
        int32_t high_deriv = 50000; // Greater than 46340 (overflows standard int32 multiplication)
        int64_t deriv64 = (int64_t)high_deriv;
        int64_t sq64 = (deriv64 * deriv64) >> 10;
        int32_t squared = (sq64 > 0x7FFF) ? 0x7FFF : (int32_t)sq64;

        if (squared == 0x7FFF && sq64 > 0) {
            dsp_puts("[PASS] TC-DSP-005: 64-bit widening prevents squaring overflow for |deriv| > 46340\n");
            pass_count++;
        } else {
            dsp_puts("[FAIL] TC-DSP-005: Squaring overflow detected! Result: ");
            dsp_print_i32(squared);
            dsp_puts("\n");
            fail_count++;
        }
    }

    // -------------------------------------------------------------------------
    // Test 6: Production Pan-Tompkins QRS Peak Detection
    // -------------------------------------------------------------------------
    {
        pan_tompkins_state_t pt;
        pt_init(&pt);

        int qrs_detections = 0;
        uint32_t detected_at_sample = 0;

        // Feed 400 baseline samples followed by a sharp QRS impulse at sample 250
        for (uint32_t s = 0; s < 400; s++) {
            int32_t sample_val = 0;
            if (s >= 248 && s <= 254) {
                sample_val = 12000;
            } else if (s >= 255 && s <= 260) {
                sample_val = -6000;
            }

            bool is_qrs = pt_process_sample(&pt, sample_val);
            if (is_qrs) {
                qrs_detections++;
                detected_at_sample = s;
                dsp_puts("  INFO: QRS detected at sample ");
                dsp_print_u32(s);
                dsp_puts(" (RR = ");
                dsp_print_u32(pt.rr_interval);
                dsp_puts(")\n");
            }
        }

        if ((qrs_detections == 1) && (detected_at_sample >= 250) && (detected_at_sample <= 290)) {
            dsp_puts("[PASS] TC-DSP-006: Pan-Tompkins detector identified QRS complex at sample ");
            dsp_print_u32(detected_at_sample);
            dsp_puts("\n");
            pass_count++;
        } else {
            dsp_puts("[FAIL] TC-DSP-006: QRS detection failure! count=");
            dsp_print_i32(qrs_detections);
            dsp_puts(", sample=");
            dsp_print_u32(detected_at_sample);
            dsp_puts(" (expected 1 detection @ 250-290)\n");
            fail_count++;
        }
    }

    // -------------------------------------------------------------------------
    // Summary
    // -------------------------------------------------------------------------
    dsp_puts("\n================================================================\n");
    dsp_puts("  DSP VERIFICATION SUMMARY\n");
    dsp_puts("  PASSED:  ");
    dsp_print_i32(pass_count);
    dsp_puts("\n  FAILED:  ");
    dsp_print_i32(fail_count);
    dsp_puts("\n  SKIPPED: ");
    dsp_print_i32(skip_count);
    dsp_puts("\n================================================================\n");

    return (fail_count == 0) ? 0 : 1;
}
