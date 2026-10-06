// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0
//
// Description: Arty A7-100T FPGA Board Top-Level Wrapper for CV32E40P ECG SoC.
//              Integrates:
//              - Xilinx 7-Series MMCME2_BASE: 100 MHz (Pin E3) -> 50 MHz Compute Clock
//              - Synchronous Reset Generator conditioned on MMCM Lock
//              - cv32e40p_ecg_soc_top SoC Core
//              - Pin assignments for Arty A7-100T per Synthesis/fpga/ecg_artix7/arty_a7_100t.xdc

`timescale 1ns / 1ps
`default_nettype none

module ecg_arty_top #(
  parameter string BOOT_HEX = "Firmware/build/hello.hex"
) (
  // 100 MHz Oscillator Input from Arty A7-100T (Pin E3)
  input  wire logic        clk_100m_i,
  // Active-Low Reset Button (Pin C2)
  input  wire logic        rst_sys_ni,

  // PMOD Header JA (ADS1292R Biopotential AFE Interface)
  output logic             afe_cs_no,
  output logic             afe_mosi_o,
  input  wire logic        afe_miso_i,
  output logic             afe_sclk_o,
  input  wire logic        afe_drdy_ni,
  output logic             afe_reset_no,
  output logic             afe_start_o,
  output logic             afe_pwdn_no,

  // USB-UART Bridge (Host PC Telemetry)
  output logic             uart_tx_o,
  input  wire logic        uart_rx_i,

  // User LEDs
  output logic [3:0]       gpio_out_o,

  // User Push Buttons
  input  wire logic [3:0]  gpio_in_i
);

  // ---------------------------------------------------------------------------
  // [1] MMCM Clock Generator: 100 MHz Input -> 50 MHz Compute Clock
  // ---------------------------------------------------------------------------
  logic clk_50m_unbuf, clk_50m;
  logic clkfb_unbuf, clkfb;
  logic mmcm_locked;

`ifdef SIMULATION
  // Accurate 50 MHz clock model (divide 100 MHz by 2 -> 20 ns period) for RTL simulation
  logic clk_50m_sim = 1'b0;
  always_ff @(posedge clk_100m_i or negedge rst_sys_ni) begin
    if (!rst_sys_ni)
      clk_50m_sim <= 1'b0;
    else
      clk_50m_sim <= ~clk_50m_sim;
  end
  assign clk_50m     = clk_50m_sim;
  assign mmcm_locked = 1'b1;
`else
  // Xilinx 7-Series MMCM Primitive for Physical Synthesis
  MMCME2_BASE #(
    .BANDWIDTH         ("OPTIMIZED"),
    .CLKFBOUT_MULT_F   (8.0),       // VCO = 100 MHz * 8.0 = 800 MHz (VCO range: 600-1200 MHz)
    .CLKFBOUT_PHASE    (0.0),
    .CLKIN1_PERIOD     (10.000),    // 100.0 MHz input clock (10 ns period)
    .CLKOUT0_DIVIDE_F  (16.0),      // 800 MHz / 16.0 = 50.0 MHz system clock
    .CLKOUT0_DUTY_CYCLE(0.5),
    .CLKOUT0_PHASE     (0.0),
    .DIVCLK_DIVIDE     (1),
    .REF_JITTER1       (0.010),
    .STARTUP_WAIT      ("FALSE")
  ) u_mmcm (
    .CLKOUT0           (clk_50m_unbuf),
    .CLKOUT0B          (),
    .CLKOUT1           (),
    .CLKOUT1B          (),
    .CLKOUT2           (),
    .CLKOUT2B          (),
    .CLKOUT3           (),
    .CLKOUT3B          (),
    .CLKOUT4           (),
    .CLKOUT5           (),
    .CLKOUT6           (),
    .CLKFBOUT          (clkfb_unbuf),
    .CLKFBOUTB         (),
    .LOCKED            (mmcm_locked),
    .CLKIN1            (clk_100m_i),
    .PWRDWN            (1'b0),
    .RST               (~rst_sys_ni),
    .CLKFBIN           (clkfb)
  );

  BUFG u_bufg_fb (
    .I(clkfb_unbuf),
    .O(clkfb)
  );

  BUFG u_bufg_clk50 (
    .I(clk_50m_unbuf),
    .O(clk_50m)
  );
`endif

  // ---------------------------------------------------------------------------
  // [2] Synchronous Reset Release Generator (2-Stage Synchronizer)
  // ---------------------------------------------------------------------------
  logic [1:0] rst_sync_q;
  wire        rst_50m_n = rst_sync_q[1];

  always_ff @(posedge clk_50m or negedge rst_sys_ni) begin
    if (!rst_sys_ni) begin
      rst_sync_q <= 2'b00;
    end else if (!mmcm_locked) begin
      rst_sync_q <= 2'b00;
    end else begin
      rst_sync_q <= {rst_sync_q[0], 1'b1};
    end
  end

  // ---------------------------------------------------------------------------
  // [3] Instantiate SoC Top
  // ---------------------------------------------------------------------------
  logic [7:0] gpio_out_full;
  logic [7:0] gpio_oe_full;

  assign gpio_out_o = gpio_out_full[3:0];

  cv32e40p_ecg_soc_top #(
    .I_MEM_SIZE_BYTES(32768),
    .D_MEM_SIZE_BYTES(32768),
    .TARGET_ASIC     (1'b0),
    .BOOT_HEX        (BOOT_HEX)
  ) u_soc_top (
    .clk_sys_i   (clk_50m),
    .rst_sys_ni  (rst_50m_n),

    // ADS1292R AFE
    .afe_sclk_o  (afe_sclk_o),
    .afe_cs_no   (afe_cs_no),
    .afe_mosi_o  (afe_mosi_o),
    .afe_miso_i  (afe_miso_i),
    .afe_drdy_ni (afe_drdy_ni),
    .afe_reset_no(afe_reset_no),
    .afe_start_o (afe_start_o),
    .afe_pwdn_no (afe_pwdn_no),

    // UART
    .uart_tx_o   (uart_tx_o),
    .uart_rx_i   (uart_rx_i),

    // GPIO
    .gpio_in_i   ({4'b0000, gpio_in_i}),
    .gpio_out_o  (gpio_out_full),
    .gpio_oe_o   (gpio_oe_full),
    .core_sleep_o()
  );

endmodule : ecg_arty_top

`default_nettype wire
