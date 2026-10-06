#include "dma.h"

void dma_init(void) {
    DMA_REG_CTRL = 0x03; // Clear ready flags and enable DMA
}

bool dma_is_bank_ready(uint8_t bank) {
    uint32_t ctrl = DMA_REG_CTRL;
    return (bank == 0) ? (ctrl & 0x01) : (ctrl & 0x02);
}

void dma_ack_bank(uint8_t bank) {
    // Write 1 to acknowledge and release bank for hardware writing
    DMA_REG_CTRL = (bank == 0) ? 0x01 : 0x02;
}

void dma_read_block(uint8_t bank, int32_t *ch1_dst, int32_t *ch2_dst, uint32_t count) {
    volatile uint32_t *ch1_src = (volatile uint32_t*)((bank == 0) ? DMA_BANK0_CH1_BASE : DMA_BANK1_CH1_BASE);
    volatile uint32_t *ch2_src = (volatile uint32_t*)((bank == 0) ? DMA_BANK0_CH2_BASE : DMA_BANK1_CH2_BASE);

    for (uint32_t i = 0; i < count; i++) {
        ch1_dst[i] = (int32_t)ch1_src[i];
        ch2_dst[i] = (int32_t)ch2_src[i];
    }
}
