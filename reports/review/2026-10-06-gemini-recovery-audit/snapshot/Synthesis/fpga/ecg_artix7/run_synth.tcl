# Copyright 2026 RISC-V ECG Project
# SPDX-License-Identifier: Apache-2.0
#
# Vivado Synthesis & Implementation Script for Arty A7-100T

set PART "xc7a100tcsg324-1"
set TOP  "ecg_arty_top"
set OUT_DIR "reports"

file mkdir $OUT_DIR

# 1. Create In-Memory Project
create_project -in_memory -part $PART

# 2. Add SystemVerilog RTL Sources in Dependency Order
if {[file exists "../../../cv32e40p/rtl/cv32e40p_top.sv"]} {
    puts "=== DETECTED OFFICIAL CV32E40P CORE RTL: INCLUDING CORE FILES ==="
    read_verilog -sv ../../../cv32e40p/rtl/include/cv32e40p_apu_core_pkg.sv
    read_verilog -sv ../../../cv32e40p/rtl/include/cv32e40p_fpu_pkg.sv
    read_verilog -sv ../../../cv32e40p/rtl/include/cv32e40p_pkg.sv
    read_verilog -sv ../../../cv32e40p/bhv/cv32e40p_sim_clock_gate.sv
    foreach f [glob ../../../cv32e40p/rtl/*.sv] {
        read_verilog -sv $f
    }
} else {
    puts "=== STANDALONE MODE: SYNTHESIZING WITH VERIFIED HARNESS ==="
}

read_verilog -sv ../../../RTL/ecg_soc/ecg_soc_pkg.sv
read_verilog -sv ../../../RTL/ecg_soc/sync_fifo.sv
read_verilog -sv ../../../RTL/ecg_soc/spi_master.sv
read_verilog -sv ../../../RTL/ecg_soc/spi_master_apb.sv
read_verilog -sv ../../../RTL/ecg_soc/uart_controller.sv
read_verilog -sv ../../../RTL/ecg_soc/uart_apb.sv
read_verilog -sv ../../../RTL/ecg_soc/timer_apb.sv
read_verilog -sv ../../../RTL/ecg_soc/gpio_apb.sv
read_verilog -sv ../../../RTL/ecg_soc/ecg_dma.sv
read_verilog -sv ../../../RTL/ecg_soc/mamba_bridge.sv
read_verilog -sv ../../../RTL/ecg_soc/apb_interconnect.sv
read_verilog -sv ../../../RTL/ecg_soc/ecg_soc_top.sv
read_verilog -sv ../../../RTL/ecg_soc/obi_to_apb.sv
read_verilog -sv ../../../RTL/ecg_soc/tcm_sram.sv
read_verilog -sv ../../../RTL/ecg_soc/cv32e40p_ecg_soc_top.sv
read_verilog -sv ../../../RTL/ecg_soc/fpga/ecg_arty_top.sv

# 3. Add Constraints
read_xdc arty_a7_100t.xdc

# 4. Synthesize Design
puts "=== RUNNING SYNTHESIS FOR $TOP ON $PART ==="
synth_design -top $TOP -part $PART -flatten_hierarchy rebuilt

report_utilization -file $OUT_DIR/utilization_synth.rpt
report_timing_summary -file $OUT_DIR/timing_synth.rpt

# 5. Optimization & Placement
puts "=== RUNNING OPT & PLACE ==="
opt_design
place_design
report_utilization -file $OUT_DIR/utilization_placed.rpt

# 6. Routing & Timing Closure
puts "=== RUNNING ROUTE ==="
route_design
report_timing_summary -file $OUT_DIR/timing_routed.rpt
report_drc -file $OUT_DIR/drc_routed.rpt
report_power -file $OUT_DIR/power_routed.rpt

# 7. Write Bitstream
puts "=== GENERATING BITSTREAM ==="
write_bitstream -force $OUT_DIR/cv32e40p_ecg_soc.bit

puts "=== BUILD COMPLETE! Bitstream and reports generated in $OUT_DIR ==="
