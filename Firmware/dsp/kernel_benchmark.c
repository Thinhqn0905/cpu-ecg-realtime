/* Copyright 2026 RISC-V ECG Project
 * SPDX-License-Identifier: Apache-2.0
 *
 * Real-Time Target Kernel Benchmark & Profiling Suite (kernel_benchmark.c)
 * Verifies per Task 4 / Checklist 10.7 (docs/plans/2026-10-06-core-next-decision-audit.md):
 * 1. Independent frozen integer reference verification:
 *    - TC-KBENCH-001: Zero input vector (all zeros -> exact 0)
 *    - TC-KBENCH-002: Unit impulse vector (tap 0 response match)
 *    - TC-KBENCH-003: Odd 45th tap remainder test (tap 44 response match)
 *    - TC-KBENCH-004: Positive extreme saturation (+32767 clipping)
 *    - TC-KBENCH-005: Negative extreme saturation (-32768 clipping)
 *    - TC-KBENCH-006: Exact bit-for-bit equivalence across 10 cardiac test vectors
 * 2. Real cycle count measurement via hardware mcycle CSR:
 *    - TC-KBENCH-007: Measured cycle count profiling with overhead & wrap subtraction
 *    - TC-KBENCH-008: Real-time deadline verification (<50,000 cycles / sample @ 1000 Hz)
 */

#include <stdint.h>
#include <stdbool.h>

#include "dsp_runtime.h"
#include "pan_tompkins.h"

#define FIR_NUM_TAPS 45

extern const int16_t g_fir_coeffs_q15[FIR_NUM_TAPS];
int16_t ecg_fir_scalar_reference(const int16_t *samples, const int16_t *coeffs);

#if defined(__riscv)
extern int32_t ecg_fir_pulp(const int16_t *samples, const int16_t *coeffs, uint32_t num_taps_div2);
#endif

// Benchmark results structure
typedef struct {
    uint32_t overhead_cycles;
    uint32_t scalar_cycles;
    uint32_t asm_cycles;
    uint32_t pt_cycles;
    uint32_t total_cycles_per_sample;
} dsp_benchmark_metrics_t;

static dsp_benchmark_metrics_t g_metrics;

int main(void) {
    int pass_count = 0;
    int fail_count = 0;
    int skip_count = 0;

    int16_t samples[FIR_NUM_TAPS];
    int16_t sat_coeffs[FIR_NUM_TAPS];
    dsp_memset(samples, 0, sizeof(samples));
    dsp_memset(sat_coeffs, 0, sizeof(sat_coeffs));
    dsp_memset(&g_metrics, 0, sizeof(g_metrics));

    dsp_puts("\n================================================================\n");
    dsp_puts("  CV32E40P REAL-TIME DSP KERNEL BENCHMARK & PROFILING HARNESS   \n");
    dsp_puts("  Target Frequency: 50.0 MHz | Core Architecture: RV32IMC       \n");
    dsp_puts("  Evidence Gate per Instruction/claim_integrity.md Task 4       \n");
    dsp_puts("================================================================\n\n");

    // -------------------------------------------------------------------------
    // Test 1: Zero Vector Verification
    // -------------------------------------------------------------------------
    dsp_memset(samples, 0, sizeof(samples));
    int16_t ref_zero = ecg_fir_scalar_reference(samples, g_fir_coeffs_q15);
#if defined(__riscv)
    int32_t asm_zero = ecg_fir_pulp(samples, g_fir_coeffs_q15, FIR_NUM_TAPS / 2);
    if (ref_zero == 0 && asm_zero == 0) {
        dsp_puts("[PASS] TC-KBENCH-001: Zero input produces exact 0 on scalar and assembly kernels\n");
        pass_count++;
    } else {
        dsp_puts("[FAIL] TC-KBENCH-001: Zero input mismatch! ref=");
        dsp_print_i32((int32_t)ref_zero);
        dsp_puts(", asm=");
        dsp_print_i32(asm_zero);
        dsp_puts("\n");
        fail_count++;
    }
#else
    if (ref_zero == 0) {
        dsp_puts("[PASS] TC-KBENCH-001: Zero input produces exact 0 on scalar reference\n");
        pass_count++;
    } else {
        dsp_puts("[FAIL] TC-KBENCH-001: Zero input mismatch on scalar reference!\n");
        fail_count++;
    }
#endif

    // -------------------------------------------------------------------------
    // Test 2: Unit Impulse Response (Tap 0)
    // -------------------------------------------------------------------------
    dsp_memset(samples, 0, sizeof(samples));
    samples[0] = 32767;
    int16_t ref_impulse = ecg_fir_scalar_reference(samples, g_fir_coeffs_q15);
    int16_t expected_tap0 = g_fir_coeffs_q15[0]; // -12
#if defined(__riscv)
    int32_t asm_impulse = ecg_fir_pulp(samples, g_fir_coeffs_q15, FIR_NUM_TAPS / 2);
    if ((ref_impulse == expected_tap0) && ((int16_t)asm_impulse == expected_tap0)) {
        dsp_puts("[PASS] TC-KBENCH-002: Unit impulse matches tap 0 (");
        dsp_print_i32((int32_t)expected_tap0);
        dsp_puts(") on scalar and assembly kernels\n");
        pass_count++;
    } else {
        dsp_puts("[FAIL] TC-KBENCH-002: Impulse tap 0 mismatch! ref=");
        dsp_print_i32((int32_t)ref_impulse);
        dsp_puts(", asm=");
        dsp_print_i32(asm_impulse);
        dsp_puts(", expected=");
        dsp_print_i32((int32_t)expected_tap0);
        dsp_puts("\n");
        fail_count++;
    }
#else
    if (ref_impulse == expected_tap0) {
        dsp_puts("[PASS] TC-KBENCH-002: Unit impulse matches tap 0 (");
        dsp_print_i32((int32_t)expected_tap0);
        dsp_puts(") on scalar reference\n");
        pass_count++;
    } else {
        dsp_puts("[FAIL] TC-KBENCH-002: Impulse tap 0 mismatch on scalar reference!\n");
        fail_count++;
    }
#endif

    // -------------------------------------------------------------------------
    // Test 3: Odd 45th Tap Remainder Verification (Tap 44)
    // -------------------------------------------------------------------------
    dsp_memset(samples, 0, sizeof(samples));
    samples[44] = 32767;
    int16_t ref_tap44 = ecg_fir_scalar_reference(samples, g_fir_coeffs_q15);
    int16_t expected_tap44 = g_fir_coeffs_q15[44]; // -829
#if defined(__riscv)
    int32_t asm_tap44 = ecg_fir_pulp(samples, g_fir_coeffs_q15, FIR_NUM_TAPS / 2);
    if ((ref_tap44 == expected_tap44) && ((int16_t)asm_tap44 == expected_tap44)) {
        dsp_puts("[PASS] TC-KBENCH-003: 45th odd remainder tap matches tap 44 (");
        dsp_print_i32((int32_t)expected_tap44);
        dsp_puts(") exactly\n");
        pass_count++;
    } else {
        dsp_puts("[FAIL] TC-KBENCH-003: 45th tap mismatch! ref=");
        dsp_print_i32((int32_t)ref_tap44);
        dsp_puts(", asm=");
        dsp_print_i32(asm_tap44);
        dsp_puts(", expected=");
        dsp_print_i32((int32_t)expected_tap44);
        dsp_puts("\n");
        fail_count++;
    }
#else
    if (ref_tap44 == expected_tap44) {
        dsp_puts("[PASS] TC-KBENCH-003: 45th odd remainder tap matches tap 44 (");
        dsp_print_i32((int32_t)expected_tap44);
        dsp_puts(") on scalar reference\n");
        pass_count++;
    } else {
        dsp_puts("[FAIL] TC-KBENCH-003: 45th tap mismatch on scalar reference!\n");
        fail_count++;
    }
#endif

    // -------------------------------------------------------------------------
    // Test 4: Positive Saturation Clipping (+32767)
    // Using high coefficient gain to force accumulator > 32767 << 15
    // -------------------------------------------------------------------------
    dsp_memset(sat_coeffs, 0, sizeof(sat_coeffs));
    for (int i = 0; i < 5; i++) {
        sat_coeffs[i] = 20000;
        samples[i] = 32767;
    }
    for (int i = 5; i < FIR_NUM_TAPS; i++) {
        samples[i] = 0;
    }
    int16_t ref_sat_pos = ecg_fir_scalar_reference(samples, sat_coeffs);
#if defined(__riscv)
    int32_t asm_sat_pos = ecg_fir_pulp(samples, sat_coeffs, FIR_NUM_TAPS / 2);
    if ((ref_sat_pos == 32767) && ((int16_t)asm_sat_pos == 32767)) {
        dsp_puts("[PASS] TC-KBENCH-004: Extreme positive accumulator clipped to +32767\n");
        pass_count++;
    } else {
        dsp_puts("[FAIL] TC-KBENCH-004: Positive saturation mismatch! ref=");
        dsp_print_i32((int32_t)ref_sat_pos);
        dsp_puts(", asm=");
        dsp_print_i32(asm_sat_pos);
        dsp_puts(" (expected +32767)\n");
        fail_count++;
    }
#else
    if (ref_sat_pos == 32767) {
        dsp_puts("[PASS] TC-KBENCH-004: Extreme positive accumulator clipped to +32767 on scalar reference\n");
        pass_count++;
    } else {
        dsp_puts("[FAIL] TC-KBENCH-004: Positive saturation mismatch on scalar reference! ref=");
        dsp_print_i32((int32_t)ref_sat_pos);
        dsp_puts("\n");
        fail_count++;
    }
#endif

    // -------------------------------------------------------------------------
    // Test 5: Negative Saturation Clipping (-32768)
    // -------------------------------------------------------------------------
    for (int i = 0; i < 5; i++) {
        samples[i] = -32768;
    }
    int16_t ref_sat_neg = ecg_fir_scalar_reference(samples, sat_coeffs);
#if defined(__riscv)
    int32_t asm_sat_neg = ecg_fir_pulp(samples, sat_coeffs, FIR_NUM_TAPS / 2);
    if ((ref_sat_neg == -32768) && ((int16_t)asm_sat_neg == -32768)) {
        dsp_puts("[PASS] TC-KBENCH-005: Extreme negative accumulator clipped to -32768\n");
        pass_count++;
    } else {
        dsp_puts("[FAIL] TC-KBENCH-005: Negative saturation mismatch! ref=");
        dsp_print_i32((int32_t)ref_sat_neg);
        dsp_puts(", asm=");
        dsp_print_i32(asm_sat_neg);
        dsp_puts(" (expected -32768)\n");
        fail_count++;
    }
#else
    if (ref_sat_neg == -32768) {
        dsp_puts("[PASS] TC-KBENCH-005: Extreme negative accumulator clipped to -32768 on scalar reference\n");
        pass_count++;
    } else {
        dsp_puts("[FAIL] TC-KBENCH-005: Negative saturation mismatch on scalar reference! ref=");
        dsp_print_i32((int32_t)ref_sat_neg);
        dsp_puts("\n");
        fail_count++;
    }
#endif

    // -------------------------------------------------------------------------
    // Test 6: Arithmetic Equivalence across 10 Complex Cardiac Vectors
    // -------------------------------------------------------------------------
#if defined(__riscv)
    bool eq_all = true;
    for (int pat = 0; pat < 10; pat++) {
        for (int i = 0; i < FIR_NUM_TAPS; i++) {
            samples[i] = (int16_t)(((i * 811 + pat * 1543) % 20000) - 10000);
        }
        int16_t r_v = ecg_fir_scalar_reference(samples, g_fir_coeffs_q15);
        int32_t a_v = ecg_fir_pulp(samples, g_fir_coeffs_q15, FIR_NUM_TAPS / 2);
        if (r_v != (int16_t)a_v) {
            dsp_puts("[FAIL] TC-KBENCH-006: Cardiac vector parity mismatch at pat ");
            dsp_print_i32(pat);
            dsp_puts("\n");
            eq_all = false;
            break;
        }
    }
    if (eq_all) {
        dsp_puts("[PASS] TC-KBENCH-006: Exact bit-for-bit equivalence verified across 10 cardiac vectors\n");
        pass_count++;
    } else {
        fail_count++;
    }
#else
    dsp_puts("[SKIP] TC-KBENCH-006: Target assembly comparison skipped on host build\n");
    skip_count++;
#endif

    // -------------------------------------------------------------------------
    // Test 7: Hardware Cycle Count Profiling (mcycle CSR)
    // -------------------------------------------------------------------------
#if defined(__riscv)
    g_metrics.overhead_cycles = dsp_measure_overhead();

    // 1. Profile Scalar Reference
    uint32_t t0 = read_mcycle();
    volatile int16_t r_out = ecg_fir_scalar_reference(samples, g_fir_coeffs_q15);
    (void)r_out;
    uint32_t t1 = read_mcycle();
    uint32_t raw_scalar = (t1 >= t0) ? (t1 - t0) : (t1 + (0xFFFFFFFF - t0) + 1);
    g_metrics.scalar_cycles = (raw_scalar >= g_metrics.overhead_cycles) ? (raw_scalar - g_metrics.overhead_cycles) : raw_scalar;

    // 2. Profile Assembly Kernel
    uint32_t t2 = read_mcycle();
    volatile int32_t a_out = ecg_fir_pulp(samples, g_fir_coeffs_q15, FIR_NUM_TAPS / 2);
    (void)a_out;
    uint32_t t3 = read_mcycle();
    uint32_t raw_asm = (t3 >= t2) ? (t3 - t2) : (t3 + (0xFFFFFFFF - t2) + 1);
    g_metrics.asm_cycles = (raw_asm >= g_metrics.overhead_cycles) ? (raw_asm - g_metrics.overhead_cycles) : raw_asm;

    // 3. Profile Pan-Tompkins QRS Sample Step
    pan_tompkins_state_t pt_bench;
    pt_init(&pt_bench);
    uint32_t t4 = read_mcycle();
    volatile bool pt_out = pt_process_sample(&pt_bench, (int32_t)r_out);
    (void)pt_out;
    uint32_t t5 = read_mcycle();
    uint32_t raw_pt = (t5 >= t4) ? (t5 - t4) : (t5 + (0xFFFFFFFF - t4) + 1);
    g_metrics.pt_cycles = (raw_pt >= g_metrics.overhead_cycles) ? (raw_pt - g_metrics.overhead_cycles) : raw_pt;

    g_metrics.total_cycles_per_sample = g_metrics.asm_cycles + g_metrics.pt_cycles;

    dsp_puts("\n  PROFILING RESULTS (CV32E40P @ 50.0 MHz):\n");
    dsp_puts("  - Counter Read Overhead:         ");
    dsp_print_u32(g_metrics.overhead_cycles);
    dsp_puts(" cycles\n");
    dsp_puts("  - 45-Tap FIR (Scalar C Ref):     ");
    dsp_print_u32(g_metrics.scalar_cycles);
    dsp_puts(" cycles\n");
    dsp_puts("  - 45-Tap FIR (Target Assembly):  ");
    dsp_print_u32(g_metrics.asm_cycles);
    dsp_puts(" cycles\n");
    dsp_puts("  - Pan-Tompkins Step:             ");
    dsp_print_u32(g_metrics.pt_cycles);
    dsp_puts(" cycles\n");
    dsp_puts("  - Total Processing / Sample:     ");
    dsp_print_u32(g_metrics.total_cycles_per_sample);
    dsp_puts(" cycles\n\n");

    if (g_metrics.scalar_cycles > 0 && g_metrics.asm_cycles > 0) {
        dsp_puts("[PASS] TC-KBENCH-007: Measured non-zero cycles on target via hardware mcycle CSR\n");
        pass_count++;
    } else {
        dsp_puts("[FAIL] TC-KBENCH-007: mcycle CSR returned 0 on target!\n");
        fail_count++;
    }

    // -------------------------------------------------------------------------
    // Test 8: Real-Time Sampling Deadline Margin Verification
    // -------------------------------------------------------------------------
    // At 50.0 MHz:
    // 1000 Hz budget = 50,000 cycles / sample
    // 500 Hz budget  = 100,000 cycles / sample
    // 250 Hz budget  = 200,000 cycles / sample
    uint32_t budget_1000hz = 50000;
    if (g_metrics.total_cycles_per_sample < budget_1000hz) {
        uint32_t margin_pct = ((budget_1000hz - g_metrics.total_cycles_per_sample) * 100) / budget_1000hz;
        dsp_puts("[PASS] TC-KBENCH-008: Processing latency (");
        dsp_print_u32(g_metrics.total_cycles_per_sample);
        dsp_puts(" cycles) well within 1000 Hz budget (50,000 cycles). Margin: ");
        dsp_print_u32(margin_pct);
        dsp_puts("%\n");
        pass_count++;
    } else {
        dsp_puts("[FAIL] TC-KBENCH-008: Processing latency exceeds 1000 Hz real-time budget!\n");
        fail_count++;
    }
#else
    dsp_puts("[SKIP] TC-KBENCH-007: Hardware mcycle profiling skipped on host\n");
    dsp_puts("[SKIP] TC-KBENCH-008: Real-time sampling margin verification skipped on host\n");
    skip_count += 2;
#endif

    // -------------------------------------------------------------------------
    // Summary
    // -------------------------------------------------------------------------
    dsp_puts("\n================================================================\n");
    dsp_puts("  BENCHMARK SUMMARY\n");
    dsp_puts("  PASSED:  ");
    dsp_print_i32(pass_count);
    dsp_puts("\n  FAILED:  ");
    dsp_print_i32(fail_count);
    dsp_puts("\n  SKIPPED: ");
    dsp_print_i32(skip_count);
    dsp_puts("\n================================================================\n");

    return (fail_count == 0) ? 0 : 1;
}
