// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0
//
// Description: Global package defining register offsets, base addresses,
//              and status bit positions for the ECG SoC peripherals.

package ecg_soc_pkg;

  // ---------------------------------------------------------------------------
  // Peripheral Memory Map Base Addresses (32-bit aligned, 4 KB boundaries)
  // ---------------------------------------------------------------------------
  localparam logic [31:0] UART_BASE_ADDR        = 32'h1000_0000;
  localparam logic [31:0] SPI_BASE_ADDR         = 32'h1000_1000;
  localparam logic [31:0] TIMER_BASE_ADDR       = 32'h1000_2000;
  localparam logic [31:0] GPIO_BASE_ADDR        = 32'h1000_3000;
  localparam logic [31:0] DMA_BASE_ADDR         = 32'h1000_4000;
  localparam logic [31:0] MAMBA_ACCEL_BASE_ADDR = 32'h2000_0000;

  // ---------------------------------------------------------------------------
  // Register Offsets within Peripherals
  // ---------------------------------------------------------------------------
  // SPI Master Registers
  localparam logic [11:0] SPI_REG_CTRL          = 12'h000; // Control (Enable, Auto, Frame Mode)
  localparam logic [11:0] SPI_REG_STATUS        = 12'h004; // Status (Busy, Done, Frame Valid)
  localparam logic [11:0] SPI_REG_TXDATA        = 12'h008; // Write TX data (24-bit command/register)
  localparam logic [11:0] SPI_REG_RXDATA        = 12'h00C; // Read RX data (Status word in frame mode)
  localparam logic [11:0] SPI_REG_CLKDIV        = 12'h010; // Clock divider setting
  localparam logic [11:0] SPI_REG_CH1_DATA      = 12'h014; // Read CH1 24-bit word
  localparam logic [11:0] SPI_REG_CH2_DATA      = 12'h018; // Read CH2 24-bit word
  localparam logic [11:0] SPI_REG_SAMPLE_CNT    = 12'h01C; // Captured sample counter

  // UART Registers
  localparam logic [11:0] UART_REG_TXDATA       = 12'h000; // Write TX character
  localparam logic [11:0] UART_REG_RXDATA       = 12'h004; // Read RX character
  localparam logic [11:0] UART_REG_STATUS       = 12'h008; // TX/RX FIFO status, frame err
  localparam logic [11:0] UART_REG_CTRL         = 12'h00C; // TX/RX enable, IRQ enable
  localparam logic [11:0] UART_REG_BAUDDIV      = 12'h010; // Baud rate divider

  // Timer Registers
  localparam logic [11:0] TIMER_REG_COUNTER     = 12'h000; // Current counter value
  localparam logic [11:0] TIMER_REG_RELOAD      = 12'h004; // Compare/Reload value
  localparam logic [11:0] TIMER_REG_CTRL        = 12'h008; // Enable, Auto-restart, IRQ enable
  localparam logic [11:0] TIMER_REG_STATUS      = 12'h00C; // Match event flag

  // GPIO Registers
  localparam logic [11:0] GPIO_REG_DATA_IN      = 12'h000; // Read pin state
  localparam logic [11:0] GPIO_REG_DATA_OUT     = 12'h004; // Write output pins
  localparam logic [11:0] GPIO_REG_DIR          = 12'h008; // Direction (1=Out, 0=In)
  localparam logic [11:0] GPIO_REG_INT_EN       = 12'h00C; // Interrupt enable mask
  localparam logic [11:0] GPIO_REG_INT_STATUS   = 12'h010; // Interrupt event flags

  // Ping-Pong DMA Buffer Registers
  localparam logic [11:0] DMA_REG_CTRL          = 12'h000; // DMA enable, bank switch
  localparam logic [11:0] DMA_REG_STATUS        = 12'h004; // Bank ready, overflow flag
  localparam logic [11:0] DMA_REG_BANK_ADDR     = 12'h008; // Current active readout bank
  localparam logic [11:0] DMA_REG_SAMPLE_COUNT  = 12'h00C; // Total samples transferred

  // ---------------------------------------------------------------------------
  // Interrupt Vector IDs (PLIC Mapping)
  // ---------------------------------------------------------------------------
  localparam int unsigned IRQ_ID_UART_TX        = 1;
  localparam int unsigned IRQ_ID_UART_RX        = 2;
  localparam int unsigned IRQ_ID_AFE_DRDY       = 3; // Highest priority
  localparam int unsigned IRQ_ID_BUFFER_READY   = 4;
  localparam int unsigned IRQ_ID_TIMER          = 5;
  localparam int unsigned IRQ_ID_GPIO           = 6;
  localparam int unsigned IRQ_ID_MAMBA_EVENT    = 7;

  // ---------------------------------------------------------------------------
  // Type Definitions
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic [7:0]  status;
    logic [23:0] ch1_data;
    logic [23:0] ch2_data;
  } ads1292r_sample_t;

endpackage : ecg_soc_pkg
