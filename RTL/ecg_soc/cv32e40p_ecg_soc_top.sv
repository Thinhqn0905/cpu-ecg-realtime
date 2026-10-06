// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0
//
// Description: Top-Level CV32E40P Real-Time ECG SoC.
//              Integrates:
//              - OpenHW CV32E40P 4-Stage In-Order Core (RV32IMC + Xpulpv2 DSP)
//              - Dual 32 KB Tightly-Coupled Memories (I-TCM and D-TCM)
//              - OBI-to-APB3 Protocol Bridge
//              - ECG Biosignal Peripherals (SPI Master, Ping-Pong DMA, UART, Timer, GPIO)
//              - CNN-MAMBA Coprocessor Integration Bridge
//              - Direct Fast-Interrupt Matrix (irq_fast_i[14:0])

`default_nettype none

module cv32e40p_ecg_soc_top
  import ecg_soc_pkg::*;
#(
  parameter int unsigned I_MEM_SIZE_BYTES = 32768, // 32 KB Instruction Memory
  parameter int unsigned D_MEM_SIZE_BYTES = 32768, // 32 KB Data Memory
  parameter bit          TARGET_ASIC      = 1'b0,  // 0: FPGA, 1: ASIC
  parameter bit          USE_REAL_CORE    = 1'b1,  // 0: Synthesizable bus harness, 1: cv32e40p_top
  parameter string       BOOT_HEX         = ""     // Boot hex image file path
) (
  input  wire logic        clk_sys_i,
  input  wire logic        rst_sys_ni,

  // External ADS1292R AFE SPI Signals
  output logic             afe_sclk_o,
  output logic             afe_cs_no,
  output logic             afe_mosi_o,
  input  wire logic        afe_miso_i,
  input  wire logic        afe_drdy_ni,
  output logic             afe_reset_no,
  output logic             afe_start_o,
  output logic             afe_pwdn_no,

  // External Host UART Telemetry
  output logic             uart_tx_o,
  input  wire logic        uart_rx_i,

  // External GPIO Pins (Status LEDs, Debug Probes)
  input  wire logic [7:0]  gpio_in_i,
  output logic [7:0]       gpio_out_o,
  output logic [7:0]       gpio_oe_o,

  // Optional External OBI/Debug Monitor Interface
  output logic             core_sleep_o
);

  // ---------------------------------------------------------------------------
  // Internal Core OBI Signals
  // ---------------------------------------------------------------------------
  // Instruction OBI Bus
  logic        instr_req;
  logic        instr_gnt;
  logic [31:0] instr_addr;
  logic        instr_rvalid;
  logic [31:0] instr_rdata;
  logic        instr_err;

  // Data OBI Bus
  logic        data_req;
  logic        data_gnt;
  logic [31:0] data_addr;
  logic        data_we;
  logic [3:0]  data_be;
  logic [31:0] data_wdata;
  logic        data_rvalid;
  logic [31:0] data_rdata;
  logic        data_err;

  // Fast Interrupts and Core Interrupt Bus (irq_i[31:0])
  logic [31:0] core_irq;
  logic        irq_external;

  assign irq_external = 1'b0;
  wire   _unused_err  = &{1'b0, instr_err, data_err};

  // ---------------------------------------------------------------------------
  // [1] Data OBI Address Decode
  // ---------------------------------------------------------------------------
  // I-TCM:    0x0000_0000 - 0x0000_7FFF (32 KB, supports code fetch + rodata/data load reads)
  // D-TCM:    0x0001_0000 - 0x0001_7FFF (32 KB, strictly bounded, no 64 KB aliasing)
  // DMA BRAM: 0x2000_0000 - 0x2000_1FFF (Buffer A: 0x2000_0000, Buffer B: 0x2000_1000)
  // APB:      0x1000_0000 - 0x1FFF_FFFF (decodes 0x1000_xxxx and 0x1A10_xxxx peripherals)
  wire is_itcm_addr    = (data_addr < I_MEM_SIZE_BYTES);
  wire is_dtcm_addr    = (data_addr >= 32'h0001_0000) && (data_addr < (32'h0001_0000 + D_MEM_SIZE_BYTES));
  wire is_dma_buf_addr = (data_addr[31:16] == 16'h2000);
  wire is_apb_addr     = (data_addr[31:28] == 4'h1);

  logic        itcm_data_req, itcm_data_gnt, itcm_data_rvalid;
  logic [31:0] itcm_data_rdata;

  logic        dtcm_req, dtcm_gnt, dtcm_rvalid;
  logic [31:0] dtcm_rdata;

  logic        dma_dobi_req, dma_dobi_gnt, dma_dobi_rvalid;
  logic [31:0] dma_dobi_rdata;

  logic        apb_bridge_req, apb_bridge_gnt, apb_bridge_rvalid, apb_bridge_err;
  logic [31:0] apb_bridge_rdata;

  // Track accepted transaction target to route rvalid and rdata
  typedef enum logic [2:0] {
    TARGET_NONE,
    TARGET_ITCM,
    TARGET_DTCM,
    TARGET_APB,
    TARGET_DMA_BUF
  } data_target_e;

  data_target_e pending_target_q, pending_target_d;
  logic         unmapped_rvalid_q;

  // Serialize multi-target OBI transactions: do not grant a new transaction
  // while a multi-cycle transaction is still awaiting rvalid
  wire data_bus_busy = (pending_target_q != TARGET_NONE) && !data_rvalid;

  assign itcm_data_req  = data_req && is_itcm_addr    && !data_bus_busy;
  assign dtcm_req       = data_req && is_dtcm_addr    && !data_bus_busy;
  assign dma_dobi_req   = data_req && is_dma_buf_addr && !data_bus_busy;
  assign apb_bridge_req = data_req && is_apb_addr     && !data_bus_busy;

  always_comb begin
    pending_target_d = pending_target_q;
    if (data_req && data_gnt) begin
      if (is_itcm_addr)
        pending_target_d = TARGET_ITCM;
      else if (is_dtcm_addr)
        pending_target_d = TARGET_DTCM;
      else if (is_dma_buf_addr)
        pending_target_d = TARGET_DMA_BUF;
      else if (is_apb_addr)
        pending_target_d = TARGET_APB;
      else
        pending_target_d = TARGET_NONE;
    end else if (data_rvalid) begin
      pending_target_d = TARGET_NONE;
    end
  end

  always_ff @(posedge clk_sys_i or negedge rst_sys_ni) begin
    if (!rst_sys_ni) begin
      pending_target_q  <= TARGET_NONE;
      unmapped_rvalid_q <= 1'b0;
    end else begin
      pending_target_q  <= pending_target_d;
      unmapped_rvalid_q <= (data_req && data_gnt && !is_itcm_addr && !is_dtcm_addr && !is_dma_buf_addr && !is_apb_addr);
    end
  end

  assign data_gnt    = data_bus_busy   ? 1'b0 :
                       is_itcm_addr    ? itcm_data_gnt :
                       is_dtcm_addr    ? dtcm_gnt :
                       is_dma_buf_addr ? dma_dobi_gnt :
                       is_apb_addr     ? apb_bridge_gnt : 1'b1;

  assign data_rvalid = (pending_target_q == TARGET_ITCM)    ? itcm_data_rvalid :
                       (pending_target_q == TARGET_DTCM)    ? dtcm_rvalid :
                       (pending_target_q == TARGET_DMA_BUF) ? dma_dobi_rvalid :
                       (pending_target_q == TARGET_APB)     ? apb_bridge_rvalid :
                       unmapped_rvalid_q;

  assign data_rdata  = (pending_target_q == TARGET_ITCM)    ? itcm_data_rdata :
                       (pending_target_q == TARGET_DTCM)    ? dtcm_rdata :
                       (pending_target_q == TARGET_DMA_BUF) ? dma_dobi_rdata :
                       (pending_target_q == TARGET_APB)     ? apb_bridge_rdata :
                       32'h0000_0000;

  assign data_err    = (pending_target_q == TARGET_APB) ? apb_bridge_err : 1'b0;

  // ---------------------------------------------------------------------------
  // [2] Instruction Tightly Coupled Memory (I-TCM) (32 KB @ 0x0000_0000)
  // ---------------------------------------------------------------------------
  tcm_sram #(
    .MEM_SIZE_BYTES(I_MEM_SIZE_BYTES),
    .TARGET_ASIC   (TARGET_ASIC),
    .INIT_FILE     (BOOT_HEX)
  ) u_i_tcm (
    .clk_i         (clk_sys_i),
    .rst_ni        (rst_sys_ni),
    // Instruction port (Port A: Fetch)
    .instr_req_i   (instr_req),
    .instr_gnt_o   (instr_gnt),
    .instr_addr_i  (instr_addr),
    .instr_rvalid_o(instr_rvalid),
    .instr_rdata_o (instr_rdata),
    // Data port (Port B: rodata & load source access)
    .data_req_i    (itcm_data_req),
    .data_gnt_o    (itcm_data_gnt),
    .data_addr_i   (data_addr),
    .data_we_i     (data_we),
    .data_be_i     (data_be),
    .data_wdata_i  (data_wdata),
    .data_rvalid_o (itcm_data_rvalid),
    .data_rdata_o  (itcm_data_rdata)
  );

  // ---------------------------------------------------------------------------
  // [3] Data Tightly Coupled Memory (D-TCM) (32 KB @ 0x0001_0000)
  // ---------------------------------------------------------------------------
  tcm_sram #(
    .MEM_SIZE_BYTES(D_MEM_SIZE_BYTES),
    .TARGET_ASIC   (TARGET_ASIC),
    .INIT_FILE     ("")
  ) u_d_tcm (
    .clk_i         (clk_sys_i),
    .rst_ni        (rst_sys_ni),
    // Instruction port unused
    .instr_req_i   (1'b0),
    .instr_gnt_o   (),
    .instr_addr_i  (32'h0),
    .instr_rvalid_o(),
    .instr_rdata_o (),
    // Data port
    .data_req_i    (dtcm_req),
    .data_gnt_o    (dtcm_gnt),
    .data_addr_i   (data_addr - 32'h0001_0000),
    .data_we_i     (data_we),
    .data_be_i     (data_be),
    .data_wdata_i  (data_wdata),
    .data_rvalid_o (dtcm_rvalid),
    .data_rdata_o  (dtcm_rdata)
  );

  // ---------------------------------------------------------------------------
  // [4] OBI to APB3 Protocol Bridge
  // ---------------------------------------------------------------------------
  logic        m_psel;
  logic        m_penable;
  logic        m_pwrite;
  logic [31:0] m_paddr;
  logic [31:0] m_pwdata;
  logic [31:0] m_prdata;
  logic        m_pready;
  logic        m_pslverr;

  obi_to_apb u_obi_to_apb (
    .clk_i        (clk_sys_i),
    .rst_ni       (rst_sys_ni),
    // OBI slave
    .obi_req_i    (apb_bridge_req),
    .obi_gnt_o    (apb_bridge_gnt),
    .obi_addr_i   (data_addr),
    .obi_we_i     (data_we),
    .obi_be_i     (data_be),
    .obi_wdata_i  (data_wdata),
    .obi_rvalid_o (apb_bridge_rvalid),
    .obi_rdata_o  (apb_bridge_rdata),
    .obi_err_o    (apb_bridge_err),
    // APB3 master
    .apb_psel_o   (m_psel),
    .apb_penable_o(m_penable),
    .apb_pwrite_o (m_pwrite),
    .apb_paddr_o  (m_paddr),
    .apb_pwdata_o (m_pwdata),
    .apb_prdata_i (m_prdata),
    .apb_pready_i (m_pready),
    .apb_pslverr_i(m_pslverr)
  );

  // ---------------------------------------------------------------------------
  // [5] Peripheral Subsystem Top (UART, SPI, Timer, GPIO, DMA)
  // ---------------------------------------------------------------------------
  logic [7:1] irq_bundle;

  ecg_soc_top #(
    .ENABLE_MAMBA(1'b0)
  ) u_peripherals (
    .clk_sys_i   (clk_sys_i),
    .rst_sys_ni  (rst_sys_ni),
    // Upstream APB3 Slave Port
    .apb_m_psel_i    (m_psel),
    .apb_m_penable_i (m_penable),
    .apb_m_pwrite_i  (m_pwrite),
    .apb_m_paddr_i   (m_paddr),
    .apb_m_pwdata_i  (m_pwdata),
    .apb_m_prdata_o  (m_prdata),
    .apb_m_pready_o  (m_pready),
    .apb_m_pslverr_o (m_pslverr),
    // High-Speed D-OBI DMA Memory Read Port (Window: 0x2000_0000 - 0x2000_1FFF)
    .dma_dobi_req_i   (dma_dobi_req),
    .dma_dobi_gnt_o   (dma_dobi_gnt),
    .dma_dobi_addr_i  (data_addr),
    .dma_dobi_rvalid_o(dma_dobi_rvalid),
    .dma_dobi_rdata_o (dma_dobi_rdata),
    // External Pins
    .spi_sclk_o  (afe_sclk_o),
    .spi_cs_no   (afe_cs_no),
    .spi_mosi_o  (afe_mosi_o),
    .spi_miso_i  (afe_miso_i),
    .afe_drdy_ni (afe_drdy_ni),
    .afe_reset_no(afe_reset_no),
    .afe_start_o (afe_start_o),
    .afe_pwdn_no (afe_pwdn_no),
    .uart_tx_o   (uart_tx_o),
    .uart_rx_i   (uart_rx_i),
    .gpio_in_i   (gpio_in_i),
    .gpio_out_o  (gpio_out_o),
    .gpio_oe_o   (gpio_oe_o),
    // Interrupt output bundle [7:1]
    .irq_bundle_o(irq_bundle)
  );

  // ---------------------------------------------------------------------------
  // [6] Interrupt Line Routing to CV32E40P (irq_i[31:0])
  // ---------------------------------------------------------------------------
  // Standard RISC-V & OpenHW CV32E40P interrupt mapping:
  //   irq_i[3]  : Machine Software IRQ (tied low)
  //   irq_i[7]  : Machine Timer IRQ (Vectors to mtvec + 4*7 = 0x011C)
  //   irq_i[11] : Machine External IRQ (irq_external)
  // CORE-V Fast Local Interrupts (irq_fast_i[15:0] -> irq_i[31:16]):
  //   irq_i[16] : Fast IRQ 16 - UART RX
  //   irq_i[17] : Fast IRQ 17 - UART TX
  //   irq_i[18] : Fast IRQ 18 - SPI / AFE Diagnostic
  //   irq_i[19] : Fast IRQ 19 - DMA Ping-Pong Buffer Ready (BUFFER_DONE)
  //   irq_i[20] : Fast IRQ 20 - GPIO Alert
  //   irq_i[31:21] & Reserved lines (0..2, 4..6, 8..10, 12..15) tied low.
  always_comb begin
    core_irq      = 32'b0;
    core_irq[7]   = irq_bundle[IRQ_ID_TIMER];        // Machine Timer IRQ -> 0x011C
    core_irq[11]  = irq_external;                    // Machine External IRQ
    core_irq[16]  = irq_bundle[IRQ_ID_UART_RX];      // Fast 16: UART RX
    core_irq[17]  = irq_bundle[IRQ_ID_UART_TX];      // Fast 17: UART TX
    core_irq[18]  = irq_bundle[IRQ_ID_AFE_DRDY];     // Fast 18: SPI / AFE Error
    core_irq[19]  = irq_bundle[IRQ_ID_BUFFER_READY]; // Fast 19: DMA Buffer Done
    core_irq[20]  = irq_bundle[IRQ_ID_GPIO];         // Fast 20: GPIO Alert
  end

  // ---------------------------------------------------------------------------
  // [7] Processor Core Integration (Real CV32E40P or Synthesizable Harness)
  // ---------------------------------------------------------------------------
  generate
    if (USE_REAL_CORE) begin : gen_cv32e40p_core
      cv32e40p_top #(
        .COREV_PULP       (1),       // Enable CORE-V PULP Xpulpv2 DSP extensions
        .COREV_CLUSTER    (0),
        .FPU              (0),       // Fixed-point Q1.15
        .NUM_MHPMCOUNTERS (1)
      ) u_core (
        .clk_i               (clk_sys_i),
        .rst_ni              (rst_sys_ni),
        .pulp_clock_en_i     (1'b1),
        .scan_cg_en_i        (1'b0),
        .boot_addr_i         (32'h0000_0000),
        .mtvec_addr_i        (32'h0000_0100),
        .dm_halt_addr_i      (32'h0000_0800),
        .hart_id_i           (32'h0000_0000),
        .dm_exception_addr_i (32'h0000_0808),

        // Instruction OBI
        .instr_req_o         (instr_req),
        .instr_gnt_i         (instr_gnt),
        .instr_rvalid_i      (instr_rvalid),
        .instr_addr_o        (instr_addr),
        .instr_rdata_i       (instr_rdata),

        // Data OBI
        .data_req_o          (data_req),
        .data_gnt_i          (data_gnt),
        .data_rvalid_i       (data_rvalid),
        .data_we_o           (data_we),
        .data_be_o           (data_be),
        .data_addr_o         (data_addr),
        .data_wdata_o        (data_wdata),
        .data_rdata_i        (data_rdata),

        // Interrupts: standard RISC-V and fast local lines per OpenHW spec
        .irq_i               (core_irq),
        .irq_ack_o           (),
        .irq_id_o            (),

        // Debug interface
        .debug_req_i         (1'b0),
        .debug_havereset_o   (),
        .debug_running_o     (),
        .debug_halted_o      (),

        // CPU Control & Status
        .fetch_enable_i      (1'b1),
        .core_sleep_o        (core_sleep_o)
      );
    end else begin : gen_bus_model
      logic [31:0] pc_q, pc_d;
      logic        fetch_pending_q, fetch_pending_d;

      assign instr_addr   = pc_q;
      assign instr_req    = !fetch_pending_q;
      assign instr_err    = 1'b0;
      assign core_sleep_o = 1'b0;

      wire _unused_core_sigs = &{1'b0, irq_external, core_irq, instr_rdata};

      always_comb begin
        pc_d            = pc_q;
        fetch_pending_d = fetch_pending_q;

        if (instr_req && instr_gnt) begin
          fetch_pending_d = 1'b1;
        end
        if (instr_rvalid) begin
          fetch_pending_d = 1'b0;
          pc_d            = pc_q + 32'd4;
        end
      end

      always_ff @(posedge clk_sys_i or negedge rst_sys_ni) begin
        if (!rst_sys_ni) begin
          pc_q            <= 32'h0000_0000;
          fetch_pending_q <= 1'b0;
          data_req        <= 1'b0;
          data_addr       <= 32'h0;
          data_we         <= 1'b0;
          data_be         <= 4'hF;
          data_wdata      <= 32'h0;
        end else begin
          pc_q            <= pc_d;
          fetch_pending_q <= fetch_pending_d;
        end
      end
    end
  endgenerate

endmodule : cv32e40p_ecg_soc_top

`default_nettype wire
