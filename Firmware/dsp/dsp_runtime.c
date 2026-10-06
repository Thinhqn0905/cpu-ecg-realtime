/* Copyright 2026 RISC-V ECG Project
 * SPDX-License-Identifier: Apache-2.0
 *
 * Freestanding symbols for -nostdlib target builds.
 */

#include <stddef.h>

#if defined(__riscv)

void *memset(void *s, int c, size_t n) {
    unsigned char *p = (unsigned char *)s;
    while (n--) {
        *p++ = (unsigned char)c;
    }
    return s;
}

void *memcpy(void *dest, const void *src, size_t n) {
    unsigned char *d = (unsigned char *)dest;
    const unsigned char *s = (const unsigned char *)src;
    while (n--) {
        *d++ = *s++;
    }
    return dest;
}

#endif
