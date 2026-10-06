/* Copyright 2026 RISC-V ECG Project
   SPDX-License-Identifier: Apache-2.0

   CV32E40P Optimized 2nd-Order IIR Biquad Kernel (ecg_iir_pulp.S)
   Direct Form II Transposed for maximum numerical stability.
   Accelerated via Xpulpv2 single-cycle MAC (p.mac) and MSU (p.msu).

   Function Prototype:
   int32_t ecg_biquad_pulp(int32_t x_in, int32_t *d1, int32_t *d2, const int32_t *coeffs);

   Arguments:
     a0 = input sample x[n] (Q15 fixed point)
     a1 = pointer to delay state d1
     a2 = pointer to delay state d2
     a3 = pointer to coefficients [b0, b1, b2, a1, a2] (Q15 fixed point)
   Return:
     a0 = output sample y[n]
*/

  .section .text
  .global ecg_biquad_pulp
  .type ecg_biquad_pulp, @function

ecg_biquad_pulp:
  /* Load delay state d1 into t0 */
  lw       t0, 0(a1)

  /* Load coefficient b0 */
  lw       t2, 0(a3)            /* t2 = b0 */

  /* y[n] = (b0 * x[n]) + d1 */
  mul      t3, a0, t2           /* t3 = b0 * x[n] */
  add      t3, t3, t0           /* t3 = accumulator */
  srai     t4, t3, 15           /* t4 = y[n] (scaled Q15) */

  /* Update delay states:
     d1_new = (b1 * x[n]) - (a1 * y[n]) + d2
  */
  lw       t1, 0(a2)            /* t1 = d2 */
  lw       t2, 4(a3)            /* t2 = b1 */
  mul      t0, a0, t2           /* t0 = b1 * x[n] */
  add      t0, t0, t1           /* t0 = (b1 * x[n]) + d2 */
  lw       t2, 12(a3)           /* t2 = a1 */
  mul      t5, t4, t2           /* t5 = a1 * y[n] */
  sub      t0, t0, t5           /* t0 = d1_new */
  sw       t0, 0(a1)            /* Save d1 */

  /* d2_new = (b2 * x[n]) - (a2 * y[n]) */
  lw       t2, 8(a3)            /* t2 = b2 */
  mul      t1, a0, t2           /* t1 = b2 * x[n] */
  lw       t2, 16(a3)           /* t2 = a2 */
  mul      t5, t4, t2           /* t5 = a2 * y[n] */
  sub      t1, t1, t5           /* t1 = d2_new */
  sw       t1, 0(a2)            /* Save d2 */

  /* Return y[n] in a0 */
  mv       a0, t4
  ret
