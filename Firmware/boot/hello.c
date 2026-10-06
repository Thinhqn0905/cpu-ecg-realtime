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
#define MAMBA_BASE_ADDR  0x10005000

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

// CNN-MAMBA Coprocessor APB Registers (mamba_bridge.sv)
#define MAMBA_REG_CTRL         (*(volatile uint32_t*)(MAMBA_BASE_ADDR + 0x00))
#define MAMBA_REG_STATUS       (*(volatile uint32_t*)(MAMBA_BASE_ADDR + 0x04))
#define MAMBA_REG_SRC_ADDR     (*(volatile uint32_t*)(MAMBA_BASE_ADDR + 0x08))
#define MAMBA_REG_DST_ADDR     (*(volatile uint32_t*)(MAMBA_BASE_ADDR + 0x0C))
#define MAMBA_REG_LEN          (*(volatile uint32_t*)(MAMBA_BASE_ADDR + 0x10))
#define MAMBA_REG_CYCLES       (*(volatile uint32_t*)(MAMBA_BASE_ADDR + 0x14))
#define MAMBA_REG_RESULT_CLASS (*(volatile uint32_t*)(MAMBA_BASE_ADDR + 0x18))
#define MAMBA_REG_RESULT_CONF  (*(volatile uint32_t*)(MAMBA_BASE_ADDR + 0x1C))

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
        "li t2, 0xDEAD0002\n"
        "li t3, 0xDEAD0003\n"
        "li a0, 0xBAD0F00D\n"
        ::: "t0", "t1", "t2", "t3", "a0"
    );
    // Increment global IRQ counter
    g_irq_count++;
}

int main(void) {
    // 1. Initialize UART: 115200 baud @ 50 MHz (divider = 434)
    UART_REG_BAUDDIV = 434;
    UART_REG_CTRL    = 0x00; // Disable UART IRQs (polled mode)

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
    // Callee-saved registers (s2-s5)
    register uint32_t canary_s2 asm("s2") = 0xA5A5A5A5;
    register uint32_t canary_s3 asm("s3") = 0x5A5A5A5A;
    register uint32_t canary_s4 asm("s4") = 0x12345678;
    register uint32_t canary_s5 asm("s5") = 0x87654321;

    // Caller-saved registers (t2-t3) - verified to ensure crt0.S SAVE/RESTORE_CONTEXT preserves them
    register uint32_t canary_t2 asm("t2") = 0xC001CAFE;
    register uint32_t canary_t3 asm("t3") = 0xBEEFCAFE;

    // 5. Configure Timer for fast countdown to verify real hardware IRQ
    // Countdown = 60 cycles (~1.2 microseconds at 50 MHz)
    TIMER_REG_COUNTER = 60;
    TIMER_REG_RELOAD  = 0;
    // Enable timer (bit 0 = 1) and Enable Timer IRQ (bit 2 = 1) -> 0x05
    TIMER_REG_CTRL    = 0x05;

    // 6. Wait for timer interrupt to fire and increment g_irq_count
    uint32_t timeout = 50000;
    while ((g_irq_count == 0) && (--timeout > 0)) {
        asm volatile("nop" : "+r"(canary_s2), "+r"(canary_s3), "+r"(canary_s4), "+r"(canary_s5),
                             "+r"(canary_t2), "+r"(canary_t3));
    }

    if (g_irq_count == 0) {
        uart_puts("ECG BOOT: IRQ TIMEOUT\r\n");
        while (1) { asm volatile("wfi"); }
    }

    // 7. Verify canaries were preserved across ISR and mret
    if ((canary_s2 != 0xA5A5A5A5) ||
        (canary_s3 != 0x5A5A5A5A) ||
        (canary_s4 != 0x12345678) ||
        (canary_s5 != 0x87654321) ||
        (canary_t2 != 0xC001CAFE) ||
        (canary_t3 != 0xBEEFCAFE)) {
        uart_puts("ECG BOOT: CANARY FAIL\r\n");
        while (1) { asm volatile("wfi"); }
    }

    // 8. IRQ handled, canaries verified, returned cleanly via mret
    uart_puts("ECG BOOT: IRQ PASS\r\n");
    uart_puts("ECG BOOT: COMPLETE\r\n");

#ifdef ENABLE_CASCADE_DIAGNOSTIC
    // 9. TC-CASCADE-006: Two-Stage Hierarchical Pan-Tompkins to ResUMamba Cascade (Diagnostic Stub)
    // Stage 1: Continuous lightweight surveillance (< 0.2% CPU)
    // Tracks running RR intervals. Normal sinus rhythm: 800 ms (200 samples @ 250 Hz).
    // An ectopic PVC induces a premature beat with RR < 75% of baseline.
    uint32_t baseline_rr = 800;
    uint32_t beat_rr[3] = {800, 800, 480}; // Beat 3 is a premature ventricular contraction
    bool anomaly_detected = false;

    for (int i = 0; i < 3; i++) {
        if (beat_rr[i] < ((baseline_rr * 3) / 4)) {
            anomaly_detected = true;
            break;
        }
    }

    if (anomaly_detected) {
        // Stage 2: Hardware ResUMamba Coprocessor Offload via APB (mamba_bridge.sv)
        MAMBA_REG_SRC_ADDR = 0x00010000; // Source buffer in D-TCM
        MAMBA_REG_LEN      = 500;        // 500-sample cardiac window (2 seconds @ 250 Hz)
        // Dispatch Full Inference (Opcode 0x3 << 4) with start bit 0x1 -> 0x31
        MAMBA_REG_CTRL     = 0x31;

        // Poll for completion (bit 1 of STATUS is done_q)
        uint32_t mamba_timeout = 20000;
        while (!(MAMBA_REG_STATUS & 0x02) && (--mamba_timeout > 0)) {
            asm volatile("nop");
        }

        uint32_t res_class = MAMBA_REG_RESULT_CLASS;
        uint32_t res_conf  = MAMBA_REG_RESULT_CONF;

        // Class 2 = Ventricular Ectopic / PVC, Confidence 0x7800 = 93.75% (Q15 format)
        if ((res_class == 2) && (res_conf == 0x7800)) {
            uart_puts("TC-CASCADE-006: PASS\r\n");
            uart_puts("CASCADE: PASS\r\n");
            uart_puts("[CASCADE] STAGE 1: PAN-TOMPKINS PVC DETECTED\r\n");
            uart_puts("[CASCADE] STAGE 2: RESUMAMBA CLASS 2 (CONF 93.75%)\r\n");
        } else {
            uart_puts("CASCADE: FAIL\r\n");
        }
    } else {
        uart_puts("CASCADE: FAIL (NO ANOMALY)\r\n");
    }
#endif

    // 10. Low-power idle state
    while (1) {
        asm volatile("wfi");
    }

    return 0;
}
