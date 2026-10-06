/* Copyright 2026 RISC-V ECG Project
   SPDX-License-Identifier: Apache-2.0

   CV32E40P Startup and Fast Interrupt Vector Table (crt0.S)
   Supports CORE-V / PULP Xpulpv2 hardware loops and direct fast-vectored IRQs.
   Fixed-width 4-byte vector table slots and complete context save/restore.
*/

  .section .vectors, "ax"
  .global _vector_table
  .align 8
  .option push
  .option norvc
_vector_table:
  /* Standard RISC-V Traps */
  j _start               /* 0: User software / Reset */
  j _trap_handler        /* 1: Supervisor software */
  j _trap_handler        /* 2: Reserved */
  j _trap_handler        /* 3: Machine software */
  j _trap_handler        /* 4: User timer */
  j _trap_handler        /* 5: Supervisor timer */
  j _trap_handler        /* 6: Reserved */
  j _trap_handler        /* 7: Machine timer */
  j _trap_handler        /* 8: User external */
  j _trap_handler        /* 9: Supervisor external */
  j _trap_handler        /* 10: Reserved */
  j _trap_handler        /* 11: Machine external */
  j _trap_handler        /* 12-15: Reserved */
  j _trap_handler
  j _trap_handler
  j _trap_handler

  /* CV32E40P Fast Vectored Interrupts (irq_fast_i[14:0]) */
  j _isr_uart_rx_wrapper      /* 16: irq_fast_i[0]  - UART RX */
  j _isr_uart_tx_wrapper      /* 17: irq_fast_i[1]  - UART TX Empty */
  j _isr_afe_drdy_wrapper     /* 18: irq_fast_i[2]  - ADS1292R DRDY# (Highest Priority) */
  j _isr_buffer_ready_wrapper /* 19: irq_fast_i[3]  - Ping-Pong Buffer Ready (32 samples) */
  j _isr_timer_wrapper        /* 20: irq_fast_i[4]  - System Timer Tick */
  j _isr_gpio_wrapper         /* 21: irq_fast_i[5]  - GPIO Edge Alert */
  j _isr_mamba_event_wrapper  /* 22: irq_fast_i[6]  - CNN-MAMBA Arrhythmia Event */
  j _default_isr              /* 23: irq_fast_i[7] */
  j _default_isr              /* 24: irq_fast_i[8] */
  j _default_isr              /* 25: irq_fast_i[9] */
  j _default_isr              /* 26: irq_fast_i[10] */
  j _default_isr              /* 27: irq_fast_i[11] */
  j _default_isr              /* 28: irq_fast_i[12] */
  j _default_isr              /* 29: irq_fast_i[13] */
  j _default_isr              /* 30: irq_fast_i[14] */
  .option pop

  .section .text
  .global _start

  /* Macro to save caller-saved context on interrupt entry */
  .macro SAVE_CONTEXT
    addi sp, sp, -64
    sw   ra,  0(sp)
    sw   t0,  4(sp)
    sw   t1,  8(sp)
    sw   t2, 12(sp)
    sw   a0, 16(sp)
    sw   a1, 20(sp)
    sw   a2, 24(sp)
    sw   a3, 28(sp)
    sw   a4, 32(sp)
    sw   a5, 36(sp)
    sw   a6, 40(sp)
    sw   a7, 44(sp)
    sw   t3, 48(sp)
    sw   t4, 52(sp)
    sw   t5, 56(sp)
    sw   t6, 60(sp)
  .endm

  /* Macro to restore caller-saved context before mret */
  .macro RESTORE_CONTEXT
    lw   ra,  0(sp)
    lw   t0,  4(sp)
    lw   t1,  8(sp)
    lw   t2, 12(sp)
    lw   a0, 16(sp)
    lw   a1, 20(sp)
    lw   a2, 24(sp)
    lw   a3, 28(sp)
    lw   a4, 32(sp)
    lw   a5, 36(sp)
    lw   a6, 40(sp)
    lw   a7, 44(sp)
    lw   t3, 48(sp)
    lw   t4, 52(sp)
    lw   t5, 56(sp)
    lw   t6, 60(sp)
    addi sp, sp, 64
  .endm

_start:
  /* 1. Initialize Stack Pointer in D-TCM */
  la    sp, _stack_top

  /* 2. Set Vector Base Address (MTVEC) to vectored mode (mode = 1) */
  la    t0, _vector_table
  ori   t0, t0, 1         /* Direct/Vectored Mode (bit 0 = 1) */
  csrw  mtvec, t0

  /* 3. Copy Initialized Data Section from I-TCM to D-TCM */
  la    a0, _sdata
  la    a1, _edata
  la    a2, _etext
1:
  bgeu  a0, a1, 2f
  lw    t0, 0(a2)
  sw    t0, 0(a0)
  addi  a0, a0, 4
  addi  a2, a2, 4
  j     1b
2:

  /* 4. Zero BSS Section in D-TCM */
  la    a0, _sbss
  la    a1, _ebss
3:
  bgeu  a0, a1, 4f
  sw    zero, 0(a0)
  addi  a0, a0, 4
  j     3b
4:

  /* 5. Enable Fast Interrupts in MIE CSR */
  li    t0, 0x007F0000    /* Enable irq_fast_i[6:0] */
  csrs  mie, t0

  /* 6. Enable Global Interrupts in MSTATUS (MIE bit 3) */
  csrsi mstatus, 0x8

  /* 7. Jump to Main C Application */
  call  main

  /* 8. Hang in WFI on Exit */
_loop:
  wfi
  j     _loop

  /* ISR Context Wrappers */
_isr_uart_rx_wrapper:
  SAVE_CONTEXT
  call isr_uart_rx
  RESTORE_CONTEXT
  mret

_isr_uart_tx_wrapper:
  SAVE_CONTEXT
  call isr_uart_tx
  RESTORE_CONTEXT
  mret

_isr_afe_drdy_wrapper:
  SAVE_CONTEXT
  call isr_afe_drdy
  RESTORE_CONTEXT
  mret

_isr_buffer_ready_wrapper:
  SAVE_CONTEXT
  call isr_buffer_ready
  RESTORE_CONTEXT
  mret

_isr_timer_wrapper:
  SAVE_CONTEXT
  call isr_timer
  RESTORE_CONTEXT
  mret

_isr_gpio_wrapper:
  SAVE_CONTEXT
  call isr_gpio
  RESTORE_CONTEXT
  mret

_isr_mamba_event_wrapper:
  SAVE_CONTEXT
  call isr_mamba_event
  RESTORE_CONTEXT
  mret

  /* Weak default handlers if not implemented by application */
  .weak isr_uart_rx
  .weak isr_uart_tx
  .weak isr_afe_drdy
  .weak isr_buffer_ready
  .weak isr_timer
  .weak isr_gpio
  .weak isr_mamba_event

isr_uart_rx:
isr_uart_tx:
isr_afe_drdy:
isr_buffer_ready:
isr_timer:
isr_gpio:
isr_mamba_event:
_trap_handler:
_default_isr:
  mret
