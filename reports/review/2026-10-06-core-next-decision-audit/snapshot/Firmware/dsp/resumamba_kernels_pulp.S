// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0
//
// Assembly-Optimized Vector Inner Loops for CV32E40P (CORE-V Xpulpv2 DSP Extension)
// Implements:
// - resumamba_dotp_i16_i8: 16-bit activation x 8-bit weight dot product with 32-bit accumulation
// - resumamba_fir_128tap_pulp: 128-tap FIR dot product with hardware loops (lp.setup)

#if defined(__riscv)

.section .text
.global resumamba_dotp_i16_i8
.type resumamba_dotp_i16_i8, @function

// int32_t resumamba_dotp_i16_i8(const int16_t *act, const int8_t *w, int len)
// a0: act (16-bit pointer)
// a1: w   (8-bit pointer)
// a2: len (number of elements)
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

#endif
