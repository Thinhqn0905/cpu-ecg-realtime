// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0

#include "ads1292r.h"

static void spi_wait_idle(void) {
    while (SPI_REG_STATUS & SPI_STATUS_BUSY);
}

static uint32_t spi_transfer(uint32_t tx_word) {
    spi_wait_idle();
    SPI_REG_TXDATA = tx_word;
    SPI_REG_CTRL   = SPI_CTRL_START; // Trigger single 24-bit command transfer
    spi_wait_idle();
    return SPI_REG_RXDATA;
}

void ads1292r_init(void) {
    // 1. Configure SPI clock divider: 50 MHz / 25 = 2.0 MHz SCLK
    SPI_REG_CLKDIV = 25;

    // 2. Hardware reset pulse & wakeup
    ads1292r_send_cmd(ADS_CMD_RESET);
    for (volatile int i = 0; i < 2000; i++); // Wait 40 us

    // 3. Stop continuous read mode to configure registers
    ads1292r_send_cmd(ADS_CMD_SDATAC);

    // 4. Configure sampling rate to 500 Hz (CONFIG1 = 0x01)
    ads1292r_write_reg(ADS_REG_CONFIG1, 0x01);

    // 5. Enable internal reference (CONFIG2 = 0xA0)
    ads1292r_write_reg(ADS_REG_CONFIG2, 0xA0);

    // 6. Set Channel 1 & 2 Gain = 6, Normal Electrode (CHxSET = 0x00)
    ads1292r_write_reg(ADS_REG_CH1SET, 0x00);
    ads1292r_write_reg(ADS_REG_CH2SET, 0x00);

    // 7. Restart continuous read mode and start conversion
    ads1292r_send_cmd(ADS_CMD_RDATAC);
    ads1292r_send_cmd(ADS_CMD_START);

    // 8. Enable auto-capture on DRDY# with continuous 72-bit frame mode in hardware SPI master
    SPI_REG_CTRL = SPI_CTRL_AUTO_MODE | SPI_CTRL_FRAME_MODE;
}

void ads1292r_send_cmd(uint8_t cmd) {
    spi_transfer(((uint32_t)cmd) << 16);
}

uint8_t ads1292r_read_reg(uint8_t reg_addr) {
    uint32_t cmd = ((uint32_t)(ADS_CMD_RREG | (reg_addr & 0x1F))) << 16;
    spi_transfer(cmd);
    return (uint8_t)(spi_transfer(0x000000) & 0xFF);
}

void ads1292r_write_reg(uint8_t reg_addr, uint8_t value) {
    uint32_t cmd = (((uint32_t)(ADS_CMD_WREG | (reg_addr & 0x1F))) << 16) | (((uint32_t)value) << 8);
    spi_transfer(cmd);
}

bool ads1292r_read_sample(ads1292r_sample_t *sample) {
    // Check if hardware SPI master has captured a complete 72-bit frame
    if (!(SPI_REG_STATUS & SPI_STATUS_FRAME_VALID)) {
        return false;
    }

    uint32_t status_word = SPI_REG_RXDATA;
    uint32_t ch1_word    = SPI_REG_CH1_DATA;
    uint32_t ch2_word    = SPI_REG_CH2_DATA;

    // Status byte is in bits [23:16] of the status word
    sample->status = (uint8_t)(status_word >> 16);

    // Sign-extend 24-bit two's complement ADC words to signed 32-bit integers
    int32_t ch1_raw = (int32_t)(ch1_word & 0x00FFFFFF);
    if (ch1_raw & 0x00800000) ch1_raw |= 0xFF000000;
    sample->ch1 = ch1_raw;

    int32_t ch2_raw = (int32_t)(ch2_word & 0x00FFFFFF);
    if (ch2_raw & 0x00800000) ch2_raw |= 0xFF000000;
    sample->ch2 = ch2_raw;

    // Clear FRAME_VALID flag (W1C)
    SPI_REG_STATUS = SPI_STATUS_FRAME_VALID;

    return true;
}
