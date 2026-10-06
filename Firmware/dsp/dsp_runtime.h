/* Copyright 2026 RISC-V ECG Project
 * SPDX-License-Identifier: Apache-2.0
 *
 * Freestanding Runtime & Stdio Support for DSP Verification on CV32E40P SoC
 * Provides:
 * - Freestanding memset and memcpy for -nostdlib compilation
 * - Hardware UART character, string, integer, and hex printing for RISC-V target
 * - Host stdio fallback for native host execution
 * - Hardware mcycle CSR access and counter overhead measurement
 */

#ifndef DSP_RUNTIME_H
#define DSP_RUNTIME_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#if defined(__riscv)

// Hardware UART Register Map (CV32E40P ECG SoC @ 0x1000_0000)
#define UART_BASE_ADDR   0x10000000
#define UART_REG_TXDATA  (*(volatile uint32_t*)(UART_BASE_ADDR + 0x00))
#define UART_REG_STATUS  (*(volatile uint32_t*)(UART_BASE_ADDR + 0x08))

static inline void dsp_putc(char c) {
    while (UART_REG_STATUS & 0x02); // Wait while TX FIFO is full
    UART_REG_TXDATA = (uint32_t)c;
}

static inline void dsp_puts(const char *str) {
    while (*str) {
        if (*str == '\n') {
            dsp_putc('\r');
        }
        dsp_putc(*str++);
    }
}

static inline void dsp_print_u32(uint32_t val) {
    char buf[12];
    int i = 0;
    if (val == 0) {
        dsp_putc('0');
        return;
    }
    while (val > 0) {
        buf[i++] = (char)('0' + (val % 10));
        val /= 10;
    }
    while (i > 0) {
        dsp_putc(buf[--i]);
    }
}

static inline void dsp_print_i32(int32_t val) {
    if (val < 0) {
        dsp_putc('-');
        val = -val;
    }
    dsp_print_u32((uint32_t)val);
}

static inline void dsp_print_hex(uint32_t val) {
    const char hex_chars[] = "0123456789ABCDEF";
    dsp_puts("0x");
    for (int i = 28; i >= 0; i -= 4) {
        dsp_putc(hex_chars[(val >> i) & 0x0F]);
    }
}

static inline uint32_t read_mcycle(void) {
    uint32_t cycles;
    asm volatile("csrr %0, mcycle" : "=r"(cycles));
    return cycles;
}

// Freestanding memory routines required by compiler
static inline void *dsp_memset(void *s, int c, size_t n) {
    unsigned char *p = (unsigned char *)s;
    while (n--) {
        *p++ = (unsigned char)c;
    }
    return s;
}

static inline void *dsp_memcpy(void *dest, const void *src, size_t n) {
    unsigned char *d = (unsigned char *)dest;
    const unsigned char *s = (const unsigned char *)src;
    while (n--) {
        *d++ = *s++;
    }
    return dest;
}

#else

// Host execution using standard C library
#include <stdio.h>
#include <string.h>

static inline void dsp_putc(char c) {
    putchar(c);
}

static inline void dsp_puts(const char *str) {
    fputs(str, stdout);
}

static inline void dsp_print_u32(uint32_t val) {
    printf("%u", (unsigned int)val);
}

static inline void dsp_print_i32(int32_t val) {
    printf("%d", (int)val);
}

static inline void dsp_print_hex(uint32_t val) {
    printf("0x%08X", (unsigned int)val);
}

static inline uint32_t read_mcycle(void) {
    return 0; // Host does not have hardware RISC-V mcycle CSR
}

static inline void *dsp_memset(void *s, int c, size_t n) {
    return memset(s, c, n);
}

static inline void *dsp_memcpy(void *dest, const void *src, size_t n) {
    return memcpy(dest, src, n);
}

#endif // defined(__riscv)

// Counter overhead measurement
static inline uint32_t dsp_measure_overhead(void) {
#if defined(__riscv)
    uint32_t t0 = read_mcycle();
    uint32_t t1 = read_mcycle();
    return (t1 >= t0) ? (t1 - t0) : 0;
#else
    return 0;
#endif
}

#endif // DSP_RUNTIME_H
