// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0
//
// Assembly-Optimized Vector Inner Loops for CV32E40P Core
// Implements:
// 1. resumamba_dotp_i16_i8: 16-bit activation x 8-bit weight dot product with 32-bit accumulation
// 2. resumamba_fir_128tap: 128-tap linear-phase FIR dot product
// Supports both baseline RV32IM and CORE-V (.insn) configurations.

#if defined(__riscv)

.section .text

// =============================================================================
// int32_t resumamba_dotp_i16_i8(const int16_t *act, const int8_t *w, int len)
// a0: act (16-bit pointer)
// a1: w   (8-bit pointer)
// a2: len (number of elements)
// =============================================================================
.global resumamba_dotp_i16_i8
.type resumamba_dotp_i16_i8, @function

resumamba_dotp_i16_i8:
    li      t0, 0           // Accumulator = 0
    li      t1, 0           // Loop counter

.L_dotp_loop:
    bge     t1, a2, .L_dotp_exit
    lh      t2, 0(a0)       // Load int16 activation
    lb      t3, 0(a1)       // Load int8 weight
    mul     t4, t2, t3      // Multiply
    add     t0, t0, t4      // Accumulate
    addi    a0, a0, 2       // act++
    addi    a1, a1, 1       // w++
    addi    t1, t1, 1       // i++
    j       .L_dotp_loop

.L_dotp_exit:
    mv      a0, t0          // Return accumulator
    ret

.size resumamba_dotp_i16_i8, .-resumamba_dotp_i16_i8

// =============================================================================
// int32_t resumamba_fir_128tap(const int16_t *samples, const int16_t *coeffs)
// a0: samples (pointer to 128 int16_t samples)
// a1: coeffs  (pointer to 128 int16_t coeffs)
// Return: a0 = 32-bit accumulated dot-product
// =============================================================================
.global resumamba_fir_128tap
.type resumamba_fir_128tap, @function

resumamba_fir_128tap:

#if defined(USE_COREV_RAW_INSN) || defined(CONFIG_COREV_PULP)
    // CORE-V 64-iteration SIMD loop (2 taps per iteration via cv.sdotsp.h)
    li      a2, 0           // a2 = accumulator = 0
    li      t2, 0           // t2 = pair counter
    li      t3, 64          // 64 pairs = 128 taps

.L_fir128_corev_loop:
    bge     t2, t3, .L_fir128_corev_exit
    .insn i 0x0b, 2, t0, 4(a0)   // cv.lw t0, 4(a0) -> 2 samples, a0 += 4
    .insn i 0x0b, 2, t1, 4(a1)   // cv.lw t1, 4(a1) -> 2 coeffs,  a1 += 4
    .insn r 0x7b, 0, 0x54, a2, t0, t1 // cv.sdotsp.h a2, t0, t1
    addi    t2, t2, 1
    j       .L_fir128_corev_loop

.L_fir128_corev_exit:
    mv      a0, a2
    ret

#else
    // Baseline RV32IM Software Loop (128 iterations)
    li      a2, 0           // a2 = accumulator = 0
    li      t2, 0           // t2 = tap counter
    li      t3, 128         // 128 taps

.L_fir128_rv32im_loop:
    bge     t2, t3, .L_fir128_rv32im_exit
    lh      t0, 0(a0)       // sample[i]
    lh      t1, 0(a1)       // coeff[i]
    mul     t4, t0, t1      // product = sample[i] * coeff[i]
    add     a2, a2, t4      // acc += product
    addi    a0, a0, 2       // samples++
    addi    a1, a1, 2       // coeffs++
    addi    t2, t2, 1       // i++
    j       .L_fir128_rv32im_loop

.L_fir128_rv32im_exit:
    mv      a0, a2
    ret

#endif

.size resumamba_fir_128tap, .-resumamba_fir_128tap

#else

// Host C fallback for unit testing and validation
#include <stdint.h>

int32_t resumamba_dotp_i16_i8(const int16_t *act, const int8_t *w, int len) {
    int32_t acc = 0;
    for (int i = 0; i < len; i++) {
        acc += (int32_t)act[i] * (int32_t)w[i];
    }
    return acc;
}

int32_t resumamba_fir_128tap(const int16_t *samples, const int16_t *coeffs) {
    int32_t acc = 0;
    for (int i = 0; i < 128; i++) {
        acc += (int32_t)samples[i] * (int32_t)coeffs[i];
    }
    return acc;
}

#endif
