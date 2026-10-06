#ifndef DMA_H
#define DMA_H

#include <stdint.h>
#include <stdbool.h>

#define DMA_BASE_ADDR        0x10004000
#define DMA_REG_CTRL         (*(volatile uint32_t*)(DMA_BASE_ADDR + 0x00))
#define DMA_REG_STATUS       (*(volatile uint32_t*)(DMA_BASE_ADDR + 0x04))
#define DMA_REG_BANK_ADDR    (*(volatile uint32_t*)(DMA_BASE_ADDR + 0x08))
#define DMA_REG_SAMPLE_COUNT (*(volatile uint32_t*)(DMA_BASE_ADDR + 0x0C))

#define DMA_BANK0_CH1_BASE   (DMA_BASE_ADDR + 0x100)
#define DMA_BANK0_CH2_BASE   (DMA_BASE_ADDR + 0x200)
#define DMA_BANK1_CH1_BASE   (DMA_BASE_ADDR + 0x300)
#define DMA_BANK1_CH2_BASE   (DMA_BASE_ADDR + 0x400)

void dma_init(void);
bool dma_is_bank_ready(uint8_t bank);
void dma_ack_bank(uint8_t bank);
void dma_read_block(uint8_t bank, int32_t *ch1_dst, int32_t *ch2_dst, uint32_t count);

#endif // DMA_H
