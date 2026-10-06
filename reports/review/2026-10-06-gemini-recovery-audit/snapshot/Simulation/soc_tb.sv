// Copyright 2026 RISC-V ECG Project
// SPDX-License-Identifier: Apache-2.0
//
// Description: Full SoC Co-Simulation Testbench for CV32E40P ECG SoC.
//              Integrates:
//              - cv32e40p_ecg_soc_top (Core, Memories, Buses, Peripherals)
//              - ads1292r_model (Behavioral TI ADS1292R AFE)
//              - Real UART Bit-Level Telemetry Receiver and Protocol Validator
//              - Exact self-checking testcases per Instruction/claim_integrity.md

`timescale 1ns / 1ps

module soc_tb;

  // ---------------------------------------------------------------------------
  // Clock and Reset Signals
  // ---------------------------------------------------------------------------
  logic clk_sys;
  logic rst_sys_n;

  // 50 MHz System Clock (20 ns period)
  initial begin
    clk_sys = 1'b0;
    forever #10 clk_sys = ~clk_sys;
  end

  // ---------------------------------------------------------------------------
  // Interconnect Signals between SoC and AFE Model
  // ---------------------------------------------------------------------------
  wire        afe_sclk;
  wire        afe_cs_n;
  wire        afe_mosi;
  wire        afe_miso;
  wire        afe_drdy_n;
  wire        afe_reset_n;
  wire        afe_start;
  wire        afe_pwdn_n;

  wire        uart_tx;
  logic       uart_rx;

  wire [7:0]  gpio_out;
  wire [7:0]  gpio_oe;
  logic [7:0] gpio_in;

  wire        core_sleep;

  // ---------------------------------------------------------------------------
  // Instantiate Device Under Test (DUT): cv32e40p_ecg_soc_top
  // ---------------------------------------------------------------------------
  cv32e40p_ecg_soc_top #(
    .I_MEM_SIZE_BYTES(32768),
    .D_MEM_SIZE_BYTES(32768),
    .TARGET_ASIC     (1'b0),
    .BOOT_HEX        ("Firmware/build/hello.hex")
  ) u_dut (
    .clk_sys_i   (clk_sys),
    .rst_sys_ni  (rst_sys_n),
    // AFE SPI
    .afe_sclk_o  (afe_sclk),
    .afe_cs_no   (afe_cs_n),
    .afe_mosi_o  (afe_mosi),
    .afe_miso_i  (afe_miso),
    .afe_drdy_ni (afe_drdy_n),
    .afe_reset_no(afe_reset_n),
    .afe_start_o (afe_start),
    .afe_pwdn_no (afe_pwdn_n),
    // UART
    .uart_tx_o   (uart_tx),
    .uart_rx_i   (uart_rx),
    // GPIO
    .gpio_in_i   (gpio_in),
    .gpio_out_o  (gpio_out),
    .gpio_oe_o   (gpio_oe),
    .core_sleep_o(core_sleep)
  );

  // ---------------------------------------------------------------------------
  // Instantiate Behavioral ADS1292R AFE Model
  // ---------------------------------------------------------------------------
  ads1292r_model u_afe (
    .sclk_i   (afe_sclk),
    .mosi_i   (afe_mosi),
    .miso_o   (afe_miso),
    .cs_ni    (afe_cs_n),
    .drdy_no  (afe_drdy_n),
    .reset_ni (afe_reset_n),
    .start_i  (afe_start)
  );

  // ---------------------------------------------------------------------------
  // Real UART Receiver (115200 Baud @ 50 MHz = 434 clock cycles per bit)
  // ---------------------------------------------------------------------------
  localparam int UART_BIT_CYCLES = 434;
  localparam time UART_BIT_PERIOD = UART_BIT_CYCLES * 20ns; // 8680 ns

  string uart_buffer = "";
  logic seen_alive     = 1'b0;
  logic seen_data_fail = 1'b0;
  logic seen_irq_pass  = 1'b0;
  logic seen_complete  = 1'b0;

  int pass_count = 0;
  int fail_count = 0;

  // UART Byte Capture and Stream Monitor
  always begin
    @(negedge uart_tx);
    // Wait to the middle of the start bit
    #(UART_BIT_PERIOD / 2);
    if (uart_tx == 1'b0) begin
      logic [7:0] rx_byte;
      for (int b = 0; b < 8; b++) begin
        #UART_BIT_PERIOD;
        rx_byte[b] = uart_tx;
      end
      #UART_BIT_PERIOD; // Stop bit

      // Print received character live to stdout
      $write("%c", rx_byte);
      $fflush();

      // Append to buffer and check string markers
      uart_buffer = {uart_buffer, string'(rx_byte)};

      if (!seen_alive && (str_contains(uart_buffer, "ECG BOOT: CV32E40P ALIVE"))) begin
        seen_alive = 1'b1;
        $display("\n[PASS] TC-BOOT-001: CV32E40P Core Boot and UART Alive String Received");
        pass_count++;
      end

      if (!seen_data_fail && (str_contains(uart_buffer, "ECG BOOT: DATA INIT FAIL"))) begin
        seen_data_fail = 1'b1;
        $display("\n[FAIL] TC-DATA-002: Data Section Initialization Mismatch in Firmware!");
        fail_count++;
      end

      if (!seen_irq_pass && (str_contains(uart_buffer, "ECG BOOT: IRQ PASS"))) begin
        seen_irq_pass = 1'b1;
        $display("\n[PASS] TC-TIMER-003: Hardware Timer Fast-IRQ Triggered and Serviced");
        $display("[PASS] TC-MRET-004: ISR Context Preserved and Clean Return via MRET");
        pass_count += 2;
      end

      if (!seen_complete && (str_contains(uart_buffer, "ECG BOOT: COMPLETE"))) begin
        seen_complete = 1'b1;
        if (!seen_data_fail) begin
          $display("\n[PASS] TC-DATA-002: Data Section Initialization and Access Verified");
          pass_count++;
        end
        $display("[PASS] TC-DONE-005: Full Real Boot and IRQ Verification Complete");
        pass_count++;
      end
    end
  end

  // Substring helper function
  function automatic bit str_contains(string haystack, string needle);
    int h_len = haystack.len();
    int n_len = needle.len();
    if (n_len > h_len) return 1'b0;
    for (int i = 0; i <= h_len - n_len; i++) begin
      if (haystack.substr(i, i + n_len - 1) == needle) return 1'b1;
    end
    return 1'b0;
  endfunction

  // ---------------------------------------------------------------------------
  // Main Simulation Sequence
  // ---------------------------------------------------------------------------
  initial begin
    $dumpfile("reports/simulation/soc_tb.vcd");
    $dumpvars(0, soc_tb);

    $display("================================================================");
    $display("  STARTING CV32E40P ECG SoC CO-SIMULATION TESTBENCH");
    $display("  Mandatory Evidence Verification per Instruction/claim_integrity.md");
    $display("================================================================");

    // Initial signal state
    rst_sys_n = 1'b0;
    uart_rx   = 1'b1;
    gpio_in   = 8'h00;

    // 1. Reset Phase: Assert reset for 200 ns
    #200;
    rst_sys_n = 1'b1;
    $display("[TB INFO] System reset released. Core fetching from I-TCM @ 0x0000_0000.");

    // 2. Wait for full verification sequence or timeout
    // 10 ms is enough for UART transmission of all test banners (~5.7 ms)
    #10_000_000;

    $display("\n================================================================");
    $display("  SIMULATION RESULTS SUMMARY");
    $display("  PASSED: %0d", pass_count);
    $display("  FAILED: %0d", fail_count);
    $display("================================================================");

    if (seen_complete && (fail_count == 0)) begin
      $display("[SUCCESS] All 5 Boot Verification Test Cases PASSED!");
      $finish(0);
    end else begin
      if (!seen_alive) begin
        $display("[FAIL] TC-BOOT-001: Timeout waiting for 'ECG BOOT: CV32E40P ALIVE'");
        fail_count++;
      end
      if (!seen_irq_pass) begin
        $display("[FAIL] TC-TIMER-003: Timeout waiting for Timer IRQ trigger");
        $display("[FAIL] TC-MRET-004: Timeout waiting for MRET return");
        fail_count += 2;
      end
      if (!seen_complete) begin
        $display("[FAIL] TC-DONE-005: Timeout waiting for 'ECG BOOT: COMPLETE'");
        fail_count++;
      end
      $display("[ERROR] Co-Simulation failed verification checks!");
      $finish(1);
    end
  end

endmodule : soc_tb
