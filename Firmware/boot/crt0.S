/* Copyright 2026 RISC-V ECG Project
   SPDX-License-Identifier: Apache-2.0

   CV32E40P Startup and Fast Interrupt Vector Table (crt0.S)
   Supports CORE-V / PULP Xpulpv2 hardware loops and direct fast-vectored IRQs.
   Fixed-width 4-byte vector table slots and complete context save/restore.
*/

  /* =========================================================================
     [1] Boot Entry Point at 0x0000_0000
     ========================================================================= */
  .section .boot, "ax"
  .global _start
  .option push
  .option norvc
_start:
  /* 1. Initialize Stack Pointer in D-TCM */
  la    sp, _stack_top

  /* 2. Set Vector Base Address (MTVEC) to vectored mode (0x0000_0101: Base 0x0100, Mode 01) */
  la    t0, _vector_table
  ori   t0, t0, 1         /* Vectored Mode (bit 0 = 1) */
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

  /* 5. Enable Machine Timer (bit 7) and Fast Interrupts (bits 16-20) in MIE CSR */
  li    t0, 0x001F0080    /* Bit 7: MTIE, Bits [20:16]: Fast IRQs 16..20 */
  csrs  mie, t0

  /* 6. Enable Global Interrupts in MSTATUS (MIE bit 3) */
  csrsi mstatus, 0x8

  /* 7. Jump to Main C Application */
  call  main

  /* 8. Hang in WFI on Exit */
_loop:
  wfi
  j     _loop
  .option pop

  /* =========================================================================
     [2] Vectored Interrupt Table starting at 256-byte aligned base (0x0000_0100)
     ========================================================================= */
  .section .vectors, "ax"
  .global _vector_table
  .align 8
  .option push
  .option norvc
_vector_table:
  /* Standard RISC-V Traps & Interrupts (0 - 15) */
  j _trap_handler             /* 0: Synchronous trap handler (0x0100) */
  j _trap_handler             /* 1: Supervisor software (0x0104) */
  j _trap_handler             /* 2: Reserved (0x0108) */
  j _trap_handler             /* 3: Machine software IRQ (0x010C) */
  j _trap_handler             /* 4: User timer (0x0110) */
  j _trap_handler             /* 5: Supervisor timer (0x0114) */
  j _trap_handler             /* 6: Reserved (0x0118) */
  j _isr_timer_wrapper        /* 7: Machine Timer IRQ (mtvec + 4*7 = 0x0000_011C) */
  j _trap_handler             /* 8: User external (0x0120) */
  j _trap_handler             /* 9: Supervisor external (0x0124) */
  j _trap_handler             /* 10: Reserved (0x0128) */
  j _trap_handler             /* 11: Machine external IRQ (0x012C) */
  j _trap_handler             /* 12-15: Reserved (0x0130 - 0x013C) */
  j _trap_handler
  j _trap_handler
  j _trap_handler

  /* CV32E40P Fast Vectored Interrupts (irq_fast_i[15:0] -> irq_i[31:16]) */
  j _isr_uart_rx_wrapper      /* 16: Fast IRQ 16 - UART RX (0x0140) */
  j _isr_uart_tx_wrapper      /* 17: Fast IRQ 17 - UART TX (0x0144) */
  j _isr_afe_drdy_wrapper     /* 18: Fast IRQ 18 - SPI / AFE Diagnostic (0x0148) */
  j _isr_buffer_ready_wrapper /* 19: Fast IRQ 19 - DMA Ping-Pong Buffer Ready (0x014C) */
  j _isr_gpio_wrapper         /* 20: Fast IRQ 20 - GPIO Alert (0x0150) */
  j _default_isr              /* 21: (0x0154) */
  j _default_isr              /* 22: (0x0158) */
  j _default_isr              /* 23: (0x015C) */
  j _default_isr              /* 24: (0x0160) */
  j _default_isr              /* 25: (0x0164) */
  j _default_isr              /* 26: (0x0168) */
  j _default_isr              /* 27: (0x016C) */
  j _default_isr              /* 28: (0x0170) */
  j _default_isr              /* 29: (0x0174) */
  j _default_isr              /* 30: (0x0178) */
  j _default_isr              /* 31: (0x017C) */
  .option pop

  .section .text

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
  .weak dma_isr
  .set dma_isr, isr_buffer_ready
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
