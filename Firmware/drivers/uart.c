#include "uart.h"

// Polynomial x^8 + x^2 + x + 1 (0x07)
static uint8_t crc8_calc(const uint8_t *data, uint32_t len) {
    uint8_t crc = 0x00;
    for (uint32_t i = 0; i < len; i++) {
        crc ^= data[i];
        for (uint8_t j = 0; j < 8; j++) {
            if (crc & 0x80) {
                crc = (crc << 1) ^ 0x07;
            } else {
                crc <<= 1;
            }
        }
    }
    return crc;
}

void uart_init(uint32_t baud_div) {
    // e.g. 434 for 115200 baud @ 50 MHz
    UART_REG_BAUDDIV = (baud_div >= 4) ? baud_div : 434;
    UART_REG_CTRL    = 0x03; // Enable TX & RX IRQ
}

void uart_putc(char c) {
    while (UART_REG_STATUS & 0x02); // Wait while TX FIFO is full
    UART_REG_TXDATA = (uint32_t)c;
}

char uart_getc(void) {
    while (UART_REG_STATUS & 0x04); // Wait while RX FIFO is empty
    return (char)(UART_REG_RXDATA & 0xFF);
}

void uart_write(const uint8_t *buffer, uint32_t len) {
    for (uint32_t i = 0; i < len; i++) {
        uart_putc((char)buffer[i]);
    }
}

void uart_send_ecg_packet(uint8_t seq, uint8_t status, int32_t ch1, int32_t ch2, uint8_t qrs_flag) {
    // 14-Byte Telemetry Frame:
    // [0..1] Sync 0xAA 0x55
    // [2]    Sequence Counter
    // [3]    AFE Status Byte
    // [4..6] CH1 24-bit Word (Big-Endian)
    // [7..9] CH2 24-bit Word (Big-Endian)
    // [10]   QRS / Arrhythmia Event Flag
    // [11]   Battery / Temperature / Status
    // [12]   CRC-8 Checksum
    // [13]   Frame End 0x0D (\r)
    uint8_t frame[14];
    frame[0]  = 0xAA;
    frame[1]  = 0x55;
    frame[2]  = seq;
    frame[3]  = status;
    frame[4]  = (uint8_t)(ch1 >> 16);
    frame[5]  = (uint8_t)(ch1 >> 8);
    frame[6]  = (uint8_t)(ch1);
    frame[7]  = (uint8_t)(ch2 >> 16);
    frame[8]  = (uint8_t)(ch2 >> 8);
    frame[9]  = (uint8_t)(ch2);
    frame[10] = qrs_flag;
    frame[11] = 0x00;
    frame[12] = crc8_calc(&frame[2], 10);
    frame[13] = 0x0D;

    uart_write(frame, 14);
}
