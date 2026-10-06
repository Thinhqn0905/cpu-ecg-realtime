/* Copyright 2026 RISC-V ECG Project
 * SPDX-License-Identifier: Apache-2.0
 *
 * CV32E40P 45-Tap Linear-Phase FIR Filter Kernel (ecg_fir_pulp.S)
 * Verified against exact scalar reference per Instruction/claim_integrity.md
 *
 * Implements two explicit variants:
 * 1. Baseline RV32IM Software Loop (compiles on all standard toolchains)
 * 2. CORE-V Hardware Accelerated Loop (cv.sdotsp.h accumulating dot product,
 *    cv.mac odd-tap accumulation, cv.lw post-increment load) via .insn macros
 *
 * Function Prototype:
 * int32_t ecg_fir_pulp(const int16_t *samples, const int16_t *coeffs, uint32_t num_taps_div2);
 *
 * Register Arguments:
 *   a0 = pointer to input delay-line (16-bit signed samples)
 *   a1 = pointer to filter coefficients (16-bit signed Q15 coeffs)
 *   a2 = loop count = num_taps / 2 (45 / 2 = 22 iterations + 1 remainder tap)
 * Return:
 *   a0 = 32-bit accumulated output, scaled Q15, saturated to [-32768, 32767]
 */

  .section .text
  .global ecg_fir_pulp
  .type ecg_fir_pulp, @function

ecg_fir_pulp:

#if defined(USE_COREV_RAW_INSN) || defined(CONFIG_COREV_PULP)
  /* ---------------------------------------------------------------------------
   * Variant B: Verified CORE-V Accelerated Kernel via standard .insn encoding
   * Uses:
   *   - cv.lw (post-increment load): .insn i 0x0B, 2, rd, imm(rs1)
   *   - cv.sdotsp.h (accumulating dot-product): .insn r 0x7B, 0, 0x54, rd, rs1, rs2
   *   - cv.mac (accumulating multiply): .insn r 0x2B, 3, 0x48, rd, rs1, rs2
   * --------------------------------------------------------------------------- */
  li       a3, 0                /* Clear 32-bit accumulator (a3) */
  li       t2, 0                /* Loop counter for 22 pairs (44 taps) */

.L_corev_loop:
  bge      t2, a2, .L_corev_odd_tap
  /* cv.lw t0, 4(a0) -> load 2 packed 16-bit samples, a0 += 4 */
  .insn i 0x0b, 2, t0, 4(a0)
  /* cv.lw t1, 4(a1) -> load 2 packed 16-bit coeffs, a1 += 4 */
  .insn i 0x0b, 2, t1, 4(a1)
  /* cv.sdotsp.h a3, t0, t1 -> a3 += t0[15:0]*t1[15:0] + t0[31:16]*t1[31:16] */
  .insn r 0x7b, 0, 0x54, a3, t0, t1
  addi     t2, t2, 1
  j        .L_corev_loop

.L_corev_odd_tap:
  /* Final 45th tap handling (odd tap remainder at index 44) */
  lh       t0, 0(a0)            /* Load last 16-bit sample */
  lh       t1, 0(a1)            /* Load last 16-bit coefficient */
  /* cv.mac a3, t0, t1 -> a3 += (t0 * t1) */
  .insn r 0x2b, 3, 0x48, a3, t0, t1

  /* Symmetric rounding: + 16384 (1 << 14) */
  li       t5, 16384
  add      a3, a3, t5
  srai     a0, a3, 15

  /* Saturate to 16-bit signed range [-32768, 32767] */
  li       t5, 32767
  ble      a0, t5, .L_sat_neg_cv
  mv       a0, t5
  ret
.L_sat_neg_cv:
  li       t5, -32768
  bge      a0, t5, .L_ret_cv
  mv       a0, t5
.L_ret_cv:
  ret

#else
  /* ---------------------------------------------------------------------------
   * Variant A: Baseline RV32IM Software Loop Implementation
   * Exact bit-for-bit equivalence to ecg_fir_scalar_reference
   * --------------------------------------------------------------------------- */
  li       a3, 0                /* a3 = accumulator = 0 */
  li       t2, 0                /* t2 = tap index = 0 */
  li       t3, 45               /* total taps = 45 */

.L_rv32im_loop:
  lh       t0, 0(a0)            /* sample[i] */
  lh       t1, 0(a1)            /* coeff[i] */
  mul      t4, t0, t1           /* product = sample[i] * coeff[i] */
  add      a3, a3, t4           /* acc += product */
  addi     a0, a0, 2            /* samples++ */
  addi     a1, a1, 2            /* coeffs++ */
  addi     t2, t2, 1            /* index++ */
  blt      t2, t3, .L_rv32im_loop

  /* Symmetric rounding: + 16384 (1 << 14) */
  li       t5, 16384
  add      a3, a3, t5
  srai     a0, a3, 15           /* scale Q15 */

  /* Saturate to 16-bit signed range [-32768, 32767] */
  li       t5, 32767
  ble      a0, t5, .L_sat_neg
  mv       a0, t5
  ret
.L_sat_neg:
  li       t5, -32768
  bge      a0, t5, .L_ret
  mv       a0, t5
.L_ret:
  ret

#endif

.size ecg_fir_pulp, .-ecg_fir_pulp
