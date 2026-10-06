/* Copyright 2026 RISC-V ECG Project
 * SPDX-License-Identifier: Apache-2.0
 *
 * Minimal Real Boot & IRQ Verification Firmware (hello.c)
 * Verifies:
 * 1. CV32E40P CPU real instruction fetch and execution from I-TCM
 * 2. rodata string read and .data section copy
 * 3. UART APB register writes and TX transmission ("ECG BOOT: CV32E40P ALIVE\r\n")
 * 4. System Timer countdown and Fast-Interrupt vectoring (irq_fast_i[4])
 * 5. Complete ISR entry, context preservation, and clean return via mret
 * 6. Final success markers ("ECG BOOT: IRQ PASS\r\n", "ECG BOOT: COMPLETE\r\n")
 */

#include <stdint.h>
#include <stdbool.h>

// Peripheral Base Addresses
#define UART_BASE_ADDR   0x10000000
#define TIMER_BASE_ADDR  0x10002000

// UART Registers
#define UART_REG_TXDATA  (*(volatile uint32_t*)(UART_BASE_ADDR + 0x00))
#define UART_REG_STATUS  (*(volatile uint32_t*)(UART_BASE_ADDR + 0x08))
#define UART_REG_CTRL    (*(volatile uint32_t*)(UART_BASE_ADDR + 0x0C))
#define UART_REG_BAUDDIV (*(volatile uint32_t*)(UART_BASE_ADDR + 0x10))

// Timer Registers
#define TIMER_REG_COUNTER (*(volatile uint32_t*)(TIMER_BASE_ADDR + 0x00))
#define TIMER_REG_RELOAD  (*(volatile uint32_t*)(TIMER_BASE_ADDR + 0x04))
#define TIMER_REG_CTRL    (*(volatile uint32_t*)(TIMER_BASE_ADDR + 0x08))
#define TIMER_REG_STATUS  (*(volatile uint32_t*)(TIMER_BASE_ADDR + 0x0C))

// Global test variables (located in .data and .bss in D-TCM)
volatile uint32_t g_irq_count = 0;
volatile uint32_t g_boot_magic = 0xCAFE1234; // .data section initialized value test

// UART transmit helpers
static void uart_putc(char c) {
    // Wait until TX FIFO is not full (bit 1 of STATUS is tx_fifo_full)
    while (UART_REG_STATUS & 0x02);
    UART_REG_TXDATA = (uint32_t)c;
}

static void uart_puts(const char *str) {
    while (*str) {
        uart_putc(*str++);
    }
}

// Timer Interrupt Service Routine (called from _isr_timer_wrapper in crt0.S)
void isr_timer(void) {
    // Acknowledge and clear timer interrupt (Write 1 to clear bit 0)
    TIMER_REG_STATUS = 0x01;
    // Disable timer to stop repeated firing in this test
    TIMER_REG_CTRL = 0x00;
    // Increment global IRQ counter
    g_irq_count++;
}

int main(void) {
    // 1. Initialize UART: 115200 baud @ 50 MHz (divider = 434)
    UART_REG_BAUDDIV = 434;
    UART_REG_CTRL    = 0x01; // Enable TX

    // 2. Emit primary boot alive marker
    uart_puts("ECG BOOT: CV32E40P ALIVE\r\n");

    // 3. Verify .data section was properly initialized by crt0.S
    if (g_boot_magic != 0xCAFE1234) {
        uart_puts("ECG BOOT: DATA INIT FAIL\r\n");
        while (1);
    }

    // 4. Configure Timer for fast countdown to verify real hardware IRQ
    // Countdown = 60 cycles (~1.2 microseconds at 50 MHz)
    TIMER_REG_COUNTER = 60;
    TIMER_REG_RELOAD  = 0;
    // Enable timer (bit 0 = 1) and Enable Timer IRQ (bit 2 = 1) -> 0x05
    TIMER_REG_CTRL    = 0x05;

    // 5. Wait for timer interrupt to fire and increment g_irq_count
    uint32_t timeout = 50000;
    while ((g_irq_count == 0) && (--timeout > 0)) {
        // Interrupted instruction location
        asm volatile("nop");
    }

    if (g_irq_count == 0) {
        uart_puts("ECG BOOT: IRQ TIMEOUT\r\n");
        while (1);
    }

    // 6. IRQ handled and returned cleanly via mret
    uart_puts("ECG BOOT: IRQ PASS\r\n");
    uart_puts("ECG BOOT: COMPLETE\r\n");

    // 7. Success state
    while (1) {
        asm volatile("wfi");
    }

    return 0;
}
