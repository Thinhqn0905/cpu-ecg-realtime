/* Copyright 2026 RISC-V ECG Project
   SPDX-License-Identifier: Apache-2.0

   CV32E40P 45-Tap Linear-Phase FIR Filter Kernel (ecg_fir_pulp.S)
   Accelerated via CORE-V / PULP Xpulpv2:
   - Hardware Loop (lp.setup 0, a2, end_label)
   - Post-Increment Addressing (p.lw rd, imm(rs1!))
   - Packed 16-bit SIMD ACCUMULATING Dot-Product (pv.sdotsp.h rd, rs1, rs2)
   - Fallback to RV32IM instructions for standard toolchains

   Function Prototype:
   int32_t ecg_fir_pulp(const int16_t *samples, const int16_t *coeffs, uint32_t num_taps_div2);

   Register Arguments:
     a0 = pointer to input delay-line (packed 16-bit pairs)
     a1 = pointer to filter coefficients (packed 16-bit pairs)
     a2 = loop count = num_taps / 2 (e.g. 45 / 2 = 22 iterations + 1 tail)
   Return:
     a0 = 32-bit accumulated filtered output (scaled Q15, saturated to 16-bit signed)
*/

  .section .text
  .global ecg_fir_pulp
  .type ecg_fir_pulp, @function

ecg_fir_pulp:
#if defined(__riscv_xpulpv2) || defined(USE_XPULPV2) || defined(CONFIG_COREV_PULP)
  /* Clear 32-bit accumulator (a3) */
  li       a3, 0

  /* Zero-Overhead Hardware Loop 0 Setup:
     Loops 'a2' times over the 3 inner instructions.
     Uses ACCUMULATING dot product (pv.sdotsp.h / cv.sdotsp.h).
  */
  lp.setup 0, a2, .fir_loop_end
    p.lw        t0, 4(a0!)      /* Load 2 packed 16-bit samples into t0, post-increment +4 */
    p.lw        t1, 4(a1!)      /* Load 2 packed 16-bit coefficients into t1, post-increment +4 */
#if defined(USE_COREV_CV_MNEMONIC)
    cv.sdotsp.h a3, t0, t1      /* OpenHW CORE-V accumulating signed dot product */
#else
    pv.sdotsp.h a3, t0, t1      /* PULP Xpulpv2 accumulating signed dot product */
#endif
.fir_loop_end:

  /* Final 45th tap handling (odd tap remainder) */
  lh       t0, 0(a0)            /* Load last 16-bit sample */
  lh       t1, 0(a1)            /* Load last 16-bit coefficient */
  p.mac    a3, t0, t1           /* Single-cycle 32-bit MAC: a3 = a3 + (t0 * t1) */

  /* Scale Q15 output back to 16-bit dynamic range with rounding */
  li       t5, 16384            /* Symmetric rounding: + (1 << 14) */
  add      a3, a3, t5
  srai     a0, a3, 15

  /* Saturate to 16-bit signed range [-32768, 32767] using Xpulpv2 p.clip */
  p.clip   a0, a0, 15
  ret

#else
  /* Standard RV32IM Software Loop Implementation */
  li       a3, 0                /* a3 = accumulator */
  li       t2, 0                /* t2 = tap index */
  li       t3, 45               /* total taps = 45 */

.fir_rv32im_loop:
  lh       t0, 0(a0)            /* sample[i] */
  lh       t1, 0(a1)            /* coeff[i] */
  mul      t4, t0, t1           /* product = sample[i] * coeff[i] */
  add      a3, a3, t4           /* acc += product */
  addi     a0, a0, 2            /* samples++ */
  addi     a1, a1, 2            /* coeffs++ */
  addi     t2, t2, 1            /* index++ */
  blt      t2, t3, .fir_rv32im_loop

  /* Scale Q15 with rounding */
  li       t5, 16384
  add      a3, a3, t5
  srai     a0, a3, 15

  /* Saturate to 16-bit signed range [-32768, 32767] */
  li       t5, 32767
  ble      a0, t5, 1f
  mv       a0, t5
  j        2f
1:
  li       t5, -32768
  bge      a0, t5, 2f
  mv       a0, t5
2:
  ret
#endif
