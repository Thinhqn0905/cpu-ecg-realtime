/* Copyright 2026 RISC-V ECG Project
 * SPDX-License-Identifier: Apache-2.0
 *
 * Minimal Real Boot & IRQ Verification Firmware (hello.c)
 * Verifies:
 * 1. CV32E40P CPU real instruction fetch and execution from I-TCM
 * 2. rodata string read and .data section copy (magic + multi-word array)
 * 3. .bss zero-initialization verification
 * 4. UART APB register writes and TX transmission ("ECG BOOT: CV32E40P ALIVE\r\n")
 * 5. System Timer countdown and Fast-Interrupt vectoring (irq_fast_i[4])
 * 6. Register canary preservation across ISR entry, context restore, and clean mret
 * 7. Final success markers ("ECG BOOT: IRQ PASS\r\n", "ECG BOOT: COMPLETE\r\n")
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
volatile uint32_t g_boot_magic = 0xCAFE1234;
volatile uint32_t g_data_array[4] = {
    0x11223344,
    0x55667788,
    0x99AABBCC,
    0xDDEEFF00
};
volatile uint32_t g_bss_zero_check = 0;

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
    // Clobber caller-saved registers to test context preservation in crt0.S
    asm volatile(
        "li t0, 0xDEADBEEF\n"
        "li t1, 0xFEEDFACE\n"
        "li a0, 0xBAD0F00D\n"
        ::: "t0", "t1", "a0"
    );
    // Increment global IRQ counter
    g_irq_count++;
}

int main(void) {
    // 1. Initialize UART: 115200 baud @ 50 MHz (divider = 434)
    UART_REG_BAUDDIV = 434;
    UART_REG_CTRL    = 0x01; // Enable TX

    // 2. Emit primary boot alive marker
    uart_puts("ECG BOOT: CV32E40P ALIVE\r\n");

    // 3. Verify .data section was properly copied from I-TCM to D-TCM
    bool data_ok = (g_boot_magic == 0xCAFE1234) &&
                   (g_data_array[0] == 0x11223344) &&
                   (g_data_array[1] == 0x55667788) &&
                   (g_data_array[2] == 0x99AABBCC) &&
                   (g_data_array[3] == 0xDDEEFF00) &&
                   (g_bss_zero_check == 0);

    if (!data_ok) {
        uart_puts("ECG BOOT: DATA INIT FAIL\r\n");
        while (1) { asm volatile("wfi"); }
    }

    // 4. Set up register canary values across IRQ
    register uint32_t canary_s2 asm("s2") = 0xA5A5A5A5;
    register uint32_t canary_s3 asm("s3") = 0x5A5A5A5A;
    register uint32_t canary_s4 asm("s4") = 0x12345678;
    register uint32_t canary_s5 asm("s5") = 0x87654321;

    // 5. Configure Timer for fast countdown to verify real hardware IRQ
    // Countdown = 60 cycles (~1.2 microseconds at 50 MHz)
    TIMER_REG_COUNTER = 60;
    TIMER_REG_RELOAD  = 0;
    // Enable timer (bit 0 = 1) and Enable Timer IRQ (bit 2 = 1) -> 0x05
    TIMER_REG_CTRL    = 0x05;

    // 6. Wait for timer interrupt to fire and increment g_irq_count
    uint32_t timeout = 50000;
    while ((g_irq_count == 0) && (--timeout > 0)) {
        asm volatile("nop" : "+r"(canary_s2), "+r"(canary_s3), "+r"(canary_s4), "+r"(canary_s5));
    }

    if (g_irq_count == 0) {
        uart_puts("ECG BOOT: IRQ TIMEOUT\r\n");
        while (1) { asm volatile("wfi"); }
    }

    // 7. Verify canaries were preserved across ISR and mret
    if ((canary_s2 != 0xA5A5A5A5) ||
        (canary_s3 != 0x5A5A5A5A) ||
        (canary_s4 != 0x12345678) ||
        (canary_s5 != 0x87654321)) {
        uart_puts("ECG BOOT: CANARY FAIL\r\n");
        while (1) { asm volatile("wfi"); }
    }

    // 8. IRQ handled, canaries verified, returned cleanly via mret
    uart_puts("ECG BOOT: IRQ PASS\r\n");
    uart_puts("ECG BOOT: COMPLETE\r\n");

    // 9. Success state
    while (1) {
        asm volatile("wfi");
    }

    return 0;
}
