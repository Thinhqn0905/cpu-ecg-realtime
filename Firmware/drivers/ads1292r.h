// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0

#ifndef ADS1292R_H
#define ADS1292R_H

#include <stdint.h>
#include <stdbool.h>

// ADS1292R Register Map & Commands
#define ADS_CMD_WAKEUP     0x02
#define ADS_CMD_STANDBY    0x04
#define ADS_CMD_RESET      0x06
#define ADS_CMD_START      0x08
#define ADS_CMD_STOP       0x0A
#define ADS_CMD_RDATAC     0x10
#define ADS_CMD_SDATAC     0x11
#define ADS_CMD_RDATA      0x12
#define ADS_CMD_RREG       0x20
#define ADS_CMD_WREG       0x40

#define ADS_REG_ID         0x00
#define ADS_REG_CONFIG1    0x01
#define ADS_REG_CONFIG2    0x02
#define ADS_REG_LOFF       0x03
#define ADS_REG_CH1SET     0x04
#define ADS_REG_CH2SET     0x05
#define ADS_REG_RLD_SENS   0x06
#define ADS_REG_LOFF_SENS  0x07
#define ADS_REG_LOFF_STAT  0x08
#define ADS_REG_RESP1      0x09
#define ADS_REG_RESP2      0x0A

// Hardware Base Addresses & Registers (Matching ecg_soc_pkg.sv)
#define SPI_BASE_ADDR      0x10001000
#define SPI_REG_CTRL       (*(volatile uint32_t*)(SPI_BASE_ADDR + 0x00))
#define SPI_REG_STATUS     (*(volatile uint32_t*)(SPI_BASE_ADDR + 0x04))
#define SPI_REG_TXDATA     (*(volatile uint32_t*)(SPI_BASE_ADDR + 0x08))
#define SPI_REG_RXDATA     (*(volatile uint32_t*)(SPI_BASE_ADDR + 0x0C))
#define SPI_REG_CLKDIV     (*(volatile uint32_t*)(SPI_BASE_ADDR + 0x10))
#define SPI_REG_CH1_DATA   (*(volatile uint32_t*)(SPI_BASE_ADDR + 0x14))
#define SPI_REG_CH2_DATA   (*(volatile uint32_t*)(SPI_BASE_ADDR + 0x18))
#define SPI_REG_SAMPLE_CNT (*(volatile uint32_t*)(SPI_BASE_ADDR + 0x1C))

// Control Register Bit Masks
#define SPI_CTRL_START         (1U << 0)
#define SPI_CTRL_AUTO_MODE     (1U << 1)
#define SPI_CTRL_FRAME_MODE    (1U << 2)

// Status Register Bit Masks
#define SPI_STATUS_BUSY        (1U << 0)
#define SPI_STATUS_DONE        (1U << 1)
#define SPI_STATUS_FRAME_VALID (1U << 2)

typedef struct {
    uint8_t  status;
    int32_t  ch1;
    int32_t  ch2;
} ads1292r_sample_t;

void ads1292r_init(void);
void ads1292r_send_cmd(uint8_t cmd);
uint8_t ads1292r_read_reg(uint8_t reg_addr);
void ads1292r_write_reg(uint8_t reg_addr, uint8_t value);
bool ads1292r_read_sample(ads1292r_sample_t *sample);

#endif // ADS1292R_H
