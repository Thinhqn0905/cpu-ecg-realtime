## Copyright 2026 RISC-V ECG Project
## SPDX-License-Identifier: Apache-2.0
##
## Xilinx Design Constraints (XDC) for Digilent Arty A7-100T (Official Rev C/D Master XDC)
## Target Device: xc7a100tcsg324-1
## Target Top Module: ecg_arty_top
## Reference: Digilent Arty A7 Reference Manual & Schematic Rev C.0

# ------------------------------------------------------------------------------
# 100 MHz System Clock Oscillator (Pin E3)
# ------------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { clk_100m_i }];
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { clk_100m_i }];

# Reset Button (CPU Reset active low, Pin C2)
set_property -dict { PACKAGE_PIN C2    IOSTANDARD LVCMOS33 } [get_ports { rst_sys_ni }];
set_false_path -from [get_ports { rst_sys_ni }]

# ------------------------------------------------------------------------------
# USB-UART Interface (Host PC Telemetry)
# ------------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN D10   IOSTANDARD LVCMOS33 } [get_ports { uart_tx_o }];
set_property -dict { PACKAGE_PIN A9    IOSTANDARD LVCMOS33 } [get_ports { uart_rx_i }];

# ------------------------------------------------------------------------------
# PMOD Header JA (ADS1292R Biopotential AFE Interface)
# ------------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN G13   IOSTANDARD LVCMOS33 } [get_ports { afe_cs_no }];   # JA[1]
set_property -dict { PACKAGE_PIN B11   IOSTANDARD LVCMOS33 } [get_ports { afe_mosi_o }];  # JA[2]
set_property -dict { PACKAGE_PIN A11   IOSTANDARD LVCMOS33 } [get_ports { afe_miso_i }];  # JA[3]
set_property -dict { PACKAGE_PIN D12   IOSTANDARD LVCMOS33 } [get_ports { afe_sclk_o }];  # JA[4]
set_property -dict { PACKAGE_PIN D13   IOSTANDARD LVCMOS33 } [get_ports { afe_drdy_ni }]; # JA[7]
set_property -dict { PACKAGE_PIN B18   IOSTANDARD LVCMOS33 } [get_ports { afe_reset_no }];# JA[8]
set_property -dict { PACKAGE_PIN A18   IOSTANDARD LVCMOS33 } [get_ports { afe_start_o }]; # JA[9]
set_property -dict { PACKAGE_PIN K16   IOSTANDARD LVCMOS33 } [get_ports { afe_pwdn_no }]; # JA[10]

# Static/Asynchronous Control Lines to AFE
set_false_path -to [get_ports { afe_reset_no afe_start_o afe_pwdn_no }]
set_false_path -from [get_ports { afe_drdy_ni }]

# ------------------------------------------------------------------------------
# User LEDs (Heartbeat, QRS Event, Arrhythmia Warning)
# ------------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN H5    IOSTANDARD LVCMOS33 } [get_ports { gpio_out_o[0] }]; # LED0: Heartbeat
set_property -dict { PACKAGE_PIN J5    IOSTANDARD LVCMOS33 } [get_ports { gpio_out_o[1] }]; # LED1: QRS Pulse
set_property -dict { PACKAGE_PIN T9    IOSTANDARD LVCMOS33 } [get_ports { gpio_out_o[2] }]; # LED2: DMA Block Ready
set_property -dict { PACKAGE_PIN T10   IOSTANDARD LVCMOS33 } [get_ports { gpio_out_o[3] }]; # LED3: Arrhythmia Alert
set_false_path -to [get_ports { gpio_out_o[*] }]

# ------------------------------------------------------------------------------
# Push Buttons (Input GPIO)
# ------------------------------------------------------------------------------
set_property -dict { PACKAGE_PIN D9    IOSTANDARD LVCMOS33 } [get_ports { gpio_in_i[0] }]; # BTN0
set_property -dict { PACKAGE_PIN C9    IOSTANDARD LVCMOS33 } [get_ports { gpio_in_i[1] }]; # BTN1
set_property -dict { PACKAGE_PIN B9    IOSTANDARD LVCMOS33 } [get_ports { gpio_in_i[2] }]; # BTN2
set_property -dict { PACKAGE_PIN B8    IOSTANDARD LVCMOS33 } [get_ports { gpio_in_i[3] }]; # BTN3
set_false_path -from [get_ports { gpio_in_i[*] }]

# ------------------------------------------------------------------------------
# Configuration & Voltage Settings for Artix-7
# ------------------------------------------------------------------------------
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
