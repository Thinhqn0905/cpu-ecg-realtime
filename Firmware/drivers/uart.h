#ifndef UART_H
#define UART_H

#include <stdint.h>
#include <stdbool.h>

#define UART_BASE_ADDR   0x10000000
#define UART_REG_TXDATA  (*(volatile uint32_t*)(UART_BASE_ADDR + 0x00))
#define UART_REG_RXDATA  (*(volatile uint32_t*)(UART_BASE_ADDR + 0x04))
#define UART_REG_STATUS  (*(volatile uint32_t*)(UART_BASE_ADDR + 0x08))
#define UART_REG_CTRL    (*(volatile uint32_t*)(UART_BASE_ADDR + 0x0C))
#define UART_REG_BAUDDIV (*(volatile uint32_t*)(UART_BASE_ADDR + 0x10))

void uart_init(uint32_t baud_div);
void uart_putc(char c);
char uart_getc(void);
void uart_write(const uint8_t *buffer, uint32_t len);
void uart_send_ecg_packet(uint8_t seq, uint8_t status, int32_t ch1, int32_t ch2, uint8_t qrs_flag);

#endif // UART_H
