// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0
//
// Description: Top-level ECG SoC peripheral subsystem integrating APB interconnect,
//              ADS1292R SPI master, UART, Timer, GPIO, and Ping-Pong DMA.

module ecg_soc_top
  import ecg_soc_pkg::*;
#(
  parameter bit ENABLE_MAMBA = 1'b0 // 0: baseline (5 slaves), 1: include experimental MAMBA bridge
) (
  input  logic        clk_sys_i,
  input  logic        rst_sys_ni,

  // Upstream APB3 Master Port (from RISC-V CPU core / bus bridge)
  input  logic        apb_m_psel_i,
  input  logic        apb_m_penable_i,
  input  logic        apb_m_pwrite_i,
  input  logic [31:0] apb_m_paddr_i,
  input  logic [31:0] apb_m_pwdata_i,
  output logic [31:0] apb_m_prdata_o,
  output logic        apb_m_pready_o,
  output logic        apb_m_pslverr_o,

  // External ADS1292R PMOD Interface
  output logic        spi_sclk_o,
  output logic        spi_mosi_o,
  input  logic        spi_miso_i,
  output logic        spi_cs_no,
  input  logic        afe_drdy_ni,
  output logic        afe_reset_no,
  output logic        afe_start_o,
  output logic        afe_pwdn_no,

  // External UART Interface
  output logic        uart_tx_o,
  input  logic        uart_rx_i,

  // External GPIO & LEDs
  input  logic [7:0]  gpio_in_i,
  output logic [7:0]  gpio_out_o,
  output logic [7:0]  gpio_oe_o,

  // Consolidated Interrupt Bundle to PLIC
  output logic [7:1]  irq_bundle_o,

  // High-Speed D-OBI DMA Memory Read Port (Window: 0x2000_0000 - 0x2000_1FFF)
  input  logic        dma_dobi_req_i,
  output logic        dma_dobi_gnt_o,
  input  logic [31:0] dma_dobi_addr_i,
  output logic        dma_dobi_rvalid_o,
  output logic [31:0] dma_dobi_rdata_o
);

  // ---------------------------------------------------------------------------
  // APB Interconnect Internal Signals (5 Slaves in baseline, 6 with MAMBA)
  // ---------------------------------------------------------------------------
  localparam int unsigned NUM_SLAVES = ENABLE_MAMBA ? 6 : 5;

  logic [NUM_SLAVES-1:0]        s_psel;
  logic [NUM_SLAVES-1:0]        s_penable;
  logic [NUM_SLAVES-1:0]        s_pwrite;
  logic [NUM_SLAVES-1:0][11:0]  s_paddr;
  logic [NUM_SLAVES-1:0][31:0]  s_pwdata;
  logic [NUM_SLAVES-1:0][31:0]  s_prdata;
  logic [NUM_SLAVES-1:0]        s_pready;
  logic [NUM_SLAVES-1:0]        s_pslverr;

  apb_interconnect #(
    .NUM_SLAVES(NUM_SLAVES)
  ) u_interconnect (
    .clk_i       (clk_sys_i),
    .rst_ni      (rst_sys_ni),
    .m_psel_i    (apb_m_psel_i),
    .m_penable_i (apb_m_penable_i),
    .m_pwrite_i  (apb_m_pwrite_i),
    .m_paddr_i   (apb_m_paddr_i),
    .m_pwdata_i  (apb_m_pwdata_i),
    .m_prdata_o  (apb_m_prdata_o),
    .m_pready_o  (apb_m_pready_o),
    .m_pslverr_o (apb_m_pslverr_o),
    .s_psel_o    (s_psel),
    .s_penable_o (s_penable),
    .s_pwrite_o  (s_pwrite),
    .s_paddr_o   (s_paddr),
    .s_pwdata_o  (s_pwdata),
    .s_prdata_i  (s_prdata),
    .s_pready_i  (s_pready),
    .s_pslverr_i (s_pslverr)
  );

  // ---------------------------------------------------------------------------
  // [0] UART Controller
  // ---------------------------------------------------------------------------
  logic uart_tx_irq;
  logic uart_rx_irq;

  uart_apb #(
    .FIFO_DEPTH(16)
  ) u_uart (
    .clk_i     (clk_sys_i),
    .rst_ni    (rst_sys_ni),
    .psel_i    (s_psel[0]),
    .penable_i (s_penable[0]),
    .pwrite_i  (s_pwrite[0]),
    .paddr_i   (s_paddr[0]),
    .pwdata_i  (s_pwdata[0]),
    .prdata_o  (s_prdata[0]),
    .pready_o  (s_pready[0]),
    .pslverr_o (s_pslverr[0]),
    .tx_o      (uart_tx_o),
    .rx_i      (uart_rx_i),
    .tx_irq_o  (uart_tx_irq),
    .rx_irq_o  (uart_rx_irq)
  );

  // ---------------------------------------------------------------------------
  // [1] ADS1292R SPI Master
  // ---------------------------------------------------------------------------
  logic spi_irq;
  logic        spi_sample_valid;
  logic [7:0]  spi_sample_status;
  logic [23:0] spi_sample_ch1;
  logic [23:0] spi_sample_ch2;

  spi_master_apb u_spi_master (
    .clk_i           (clk_sys_i),
    .rst_ni          (rst_sys_ni),
    .psel_i          (s_psel[1]),
    .penable_i       (s_penable[1]),
    .pwrite_i        (s_pwrite[1]),
    .paddr_i         (s_paddr[1]),
    .pwdata_i        (s_pwdata[1]),
    .prdata_o        (s_prdata[1]),
    .pready_o        (s_pready[1]),
    .pslverr_o       (s_pslverr[1]),
    .sample_valid_o  (spi_sample_valid),
    .sample_status_o (spi_sample_status),
    .sample_ch1_o    (spi_sample_ch1),
    .sample_ch2_o    (spi_sample_ch2),
    .sclk_o          (spi_sclk_o),
    .mosi_o          (spi_mosi_o),
    .miso_i          (spi_miso_i),
    .cs_no           (spi_cs_no),
    .drdy_ni         (afe_drdy_ni),
    .irq_o           (spi_irq)
  );

  // ---------------------------------------------------------------------------
  // [2] System Timer
  // ---------------------------------------------------------------------------
  logic timer_irq;

  timer_apb u_timer (
    .clk_i     (clk_sys_i),
    .rst_ni    (rst_sys_ni),
    .psel_i    (s_psel[2]),
    .penable_i (s_penable[2]),
    .pwrite_i  (s_pwrite[2]),
    .paddr_i   (s_paddr[2]),
    .pwdata_i  (s_pwdata[2]),
    .prdata_o  (s_prdata[2]),
    .pready_o  (s_pready[2]),
    .pslverr_o (s_pslverr[2]),
    .irq_o     (timer_irq)
  );

  // ---------------------------------------------------------------------------
  // [3] GPIO Controller
  // ---------------------------------------------------------------------------
  logic gpio_irq;
  logic [7:0] gpio_out_internal;

  gpio_apb #(
    .GPIO_WIDTH(8)
  ) u_gpio (
    .clk_i     (clk_sys_i),
    .rst_ni    (rst_sys_ni),
    .psel_i    (s_psel[3]),
    .penable_i (s_penable[3]),
    .pwrite_i  (s_pwrite[3]),
    .paddr_i   (s_paddr[3]),
    .pwdata_i  (s_pwdata[3]),
    .prdata_o  (s_prdata[3]),
    .pready_o  (s_pready[3]),
    .pslverr_o (s_pslverr[3]),
    .gpio_i    (gpio_in_i),
    .gpio_o    (gpio_out_internal),
    .gpio_oe_o (gpio_oe_o),
    .irq_o     (gpio_irq)
  );

  assign gpio_out_o   = gpio_out_internal;
  // Dedicate upper GPIO output bits for AFE control lines
  assign afe_reset_no = gpio_out_internal[5];
  assign afe_start_o  = gpio_out_internal[6];
  assign afe_pwdn_no  = gpio_out_internal[7];

  // ---------------------------------------------------------------------------
  // [4] Ping-Pong BRAM Buffer DMA
  // ---------------------------------------------------------------------------
  logic buffer_ready_irq;
  logic dma_overflow_err;
  wire  _unused_top = &{1'b0, dma_overflow_err};

  ecg_dma #(
    .SAMPLES_PER_BANK(32)
  ) u_dma (
    .clk_i             (clk_sys_i),
    .rst_ni            (rst_sys_ni),
    .psel_i            (s_psel[4]),
    .penable_i         (s_penable[4]),
    .pwrite_i          (s_pwrite[4]),
    .paddr_i           (s_paddr[4]),
    .pwdata_i          (s_pwdata[4]),
    .prdata_o          (s_prdata[4]),
    .pready_o          (s_pready[4]),
    .pslverr_o         (s_pslverr[4]),
    .dobi_req_i        (dma_dobi_req_i),
    .dobi_gnt_o        (dma_dobi_gnt_o),
    .dobi_addr_i       (dma_dobi_addr_i),
    .dobi_rvalid_o     (dma_dobi_rvalid_o),
    .dobi_rdata_o      (dma_dobi_rdata_o),
    .sample_valid_i    (spi_sample_valid), // Real sample valid from continuous frame capture
    .sample_status_i   (spi_sample_status),// Real status byte from AFE frame
    .sample_ch1_i      (spi_sample_ch1),   // Real 24-bit Channel 1 biopotential sample
    .sample_ch2_i      (spi_sample_ch2),   // Real 24-bit Channel 2 biopotential sample
    .buffer_ready_irq_o(buffer_ready_irq),
    .overflow_err_o    (dma_overflow_err)
  );

  // ---------------------------------------------------------------------------
  // [5] CNN-MAMBA Coprocessor Integration Bridge (Deferred / Optional)
  // ---------------------------------------------------------------------------
  logic mamba_event_irq;

  generate
    if (ENABLE_MAMBA) begin : gen_mamba
      mamba_bridge u_mamba (
        .clk_i           (clk_sys_i),
        .rst_ni          (rst_sys_ni),
        .psel_i          (s_psel[5]),
        .penable_i       (s_penable[5]),
        .pwrite_i        (s_pwrite[5]),
        .paddr_i         (s_paddr[5]),
        .pwdata_i        (s_pwdata[5]),
        .prdata_o        (s_prdata[5]),
        .pready_o        (s_pready[5]),
        .pslverr_o       (s_pslverr[5]),
        .s_axis_tdata_i  (32'h0000_0000),
        .s_axis_tvalid_i (buffer_ready_irq),
        .s_axis_tready_o (),
        .s_axis_tlast_i  (1'b0),
        .event_irq_o     (mamba_event_irq)
      );
    end else begin : gen_no_mamba
      assign s_prdata[5]     = 32'h0000_0000;
      assign s_pready[5]     = 1'b1;
      assign s_pslverr[5]    = 1'b0;
      assign mamba_event_irq = 1'b0;
    end
  endgenerate

  // ---------------------------------------------------------------------------
  // PLIC Interrupt Assignment Mapping
  // ---------------------------------------------------------------------------
  assign irq_bundle_o[IRQ_ID_UART_TX]     = uart_tx_irq;
  assign irq_bundle_o[IRQ_ID_UART_RX]     = uart_rx_irq;
  assign irq_bundle_o[IRQ_ID_AFE_DRDY]    = spi_irq;
  assign irq_bundle_o[IRQ_ID_BUFFER_READY]= buffer_ready_irq;
  assign irq_bundle_o[IRQ_ID_TIMER]       = timer_irq;
  assign irq_bundle_o[IRQ_ID_GPIO]        = gpio_irq;
  assign irq_bundle_o[IRQ_ID_MAMBA_EVENT] = mamba_event_irq;

endmodule : ecg_soc_top
