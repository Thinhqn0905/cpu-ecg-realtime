# Copyright 2026 RISC-V ECG Project
# SPDX-License-Identifier: Apache-2.0
#
# Vivado Synthesis & Implementation Script for Arty A7-100T
# Enforces strict preflight, artifact checks, and complete timing/utilization reports
# per docs/plans/2026-10-06-gemini-recovery-followup.md (Task 6)

set SCRIPT_DIR [file normalize [file dirname [info script]]]
set ROOT_DIR   [file normalize [file join $SCRIPT_DIR "../../.."]]

set PART "xc7a100tcsg324-1"
set TOP  "ecg_arty_top"
set OUT_DIR [file join $SCRIPT_DIR "reports"]

file mkdir $OUT_DIR

puts "================================================================"
puts "  VIVADO SYNTHESIS & IMPLEMENTATION: CV32E40P ECG SOC          "
puts "  Project Root: $ROOT_DIR"
puts "  Target Part:  $PART"
puts "  Top Module:   $TOP"
puts "  Output Dir:   $OUT_DIR"
puts "================================================================"

# ------------------------------------------------------------------------------
# 1. Preflight Verification (Strict Integrity per Task 6 / Claim Integrity)
# ------------------------------------------------------------------------------
set CORE_DIR [file join $ROOT_DIR "cv32e40p"]
set CORE_TOP [file join $CORE_DIR "rtl/cv32e40p_top.sv"]
if {![file exists $CORE_TOP]} {
    puts "\[FATAL\] Pinned CV32E40P core RTL not found at '$CORE_TOP'!"
    puts "        Refusing synthetic fallback. Please ensure cv32e40p submodule is cloned."
    exit 1
}

set BOOT_HEX [file join $ROOT_DIR "Firmware/build/hello.hex"]
if {![file exists $BOOT_HEX]} {
    puts "\[FATAL\] Preflight check failed: Boot hex image not found at '$BOOT_HEX'!"
    puts "        Compile firmware via 'make -C Firmware hello' before running FPGA synthesis."
    exit 1
}
puts "\[PASS\] Preflight checks passed. Core RTL and boot image verified."

# ------------------------------------------------------------------------------
# 2. Create In-Memory Project & Add Sources
# ------------------------------------------------------------------------------
create_project -in_memory -part $PART

# Add CV32E40P Core RTL
read_verilog -sv [file join $CORE_DIR "rtl/include/cv32e40p_apu_core_pkg.sv"]
read_verilog -sv [file join $CORE_DIR "rtl/include/cv32e40p_fpu_pkg.sv"]
read_verilog -sv [file join $CORE_DIR "rtl/include/cv32e40p_pkg.sv"]
read_verilog -sv [file join $ROOT_DIR "RTL/ecg_soc/fpga/cv32e40p_fpga_clock_gate.sv"]
foreach f [glob [file join $CORE_DIR "rtl/*.sv"]] {
    set bname [file tail $f]
    if {$bname eq "cv32e40p_fp_wrapper.sv" || $bname eq "cv32e40p_register_file_latch.sv"} continue
    read_verilog -sv $f
}

# Add ECG SoC Subsystem RTL
read_verilog -sv [file join $ROOT_DIR "RTL/ecg_soc/ecg_soc_pkg.sv"]
read_verilog -sv [file join $ROOT_DIR "RTL/ecg_soc/sync_fifo.sv"]
read_verilog -sv [file join $ROOT_DIR "RTL/ecg_soc/spi_master.sv"]
read_verilog -sv [file join $ROOT_DIR "RTL/ecg_soc/spi_master_apb.sv"]
read_verilog -sv [file join $ROOT_DIR "RTL/ecg_soc/uart_controller.sv"]
read_verilog -sv [file join $ROOT_DIR "RTL/ecg_soc/uart_apb.sv"]
read_verilog -sv [file join $ROOT_DIR "RTL/ecg_soc/timer_apb.sv"]
read_verilog -sv [file join $ROOT_DIR "RTL/ecg_soc/gpio_apb.sv"]
read_verilog -sv [file join $ROOT_DIR "RTL/ecg_soc/ecg_dma.sv"]
read_verilog -sv [file join $ROOT_DIR "RTL/ecg_soc/mamba_fir_sidecar.sv"]
read_verilog -sv [file join $ROOT_DIR "RTL/ecg_soc/mamba_bridge.sv"]
read_verilog -sv [file join $ROOT_DIR "RTL/ecg_soc/apb_interconnect.sv"]
read_verilog -sv [file join $ROOT_DIR "RTL/ecg_soc/ecg_soc_top.sv"]
read_verilog -sv [file join $ROOT_DIR "RTL/ecg_soc/obi_to_apb.sv"]
read_verilog -sv [file join $ROOT_DIR "RTL/ecg_soc/tcm_sram.sv"]
read_verilog -sv [file join $ROOT_DIR "RTL/ecg_soc/cv32e40p_ecg_soc_top.sv"]
read_verilog -sv [file join $ROOT_DIR "RTL/ecg_soc/fpga/ecg_arty_top.sv"]

# Add Physical Constraints
read_xdc [file join $SCRIPT_DIR "arty_a7_100t.xdc"]

# ------------------------------------------------------------------------------
# 3. Synthesize Design
# ------------------------------------------------------------------------------
puts "=== [1/5] RUNNING SYNTHESIS FOR $TOP ON $PART ==="
synth_design -top $TOP -part $PART -flatten_hierarchy rebuilt -generic "BOOT_HEX=$BOOT_HEX"

report_utilization -file [file join $OUT_DIR "utilization_synth.rpt"]
report_timing_summary -file [file join $OUT_DIR "timing_synth.rpt"]

# ------------------------------------------------------------------------------
# 4. Optimization & Placement
# ------------------------------------------------------------------------------
puts "=== [2/5] RUNNING OPT & PLACE ==="
opt_design -directive Explore
place_design -directive Explore
phys_opt_design -directive Explore
report_utilization -file [file join $OUT_DIR "utilization_placed.rpt"]

# ------------------------------------------------------------------------------
# 5. Routing & Timing Closure
# ------------------------------------------------------------------------------
puts "=== [3/5] RUNNING ROUTE ==="
route_design -directive Explore
phys_opt_design -directive Explore

puts "=== [4/5] GENERATING TIMING & DRC REPORTS ==="
check_timing -file [file join $OUT_DIR "check_timing.rpt"]
report_timing_summary -report_unconstrained -check_timing_verbose -file [file join $OUT_DIR "timing_routed.rpt"]
report_timing -delay_type max -max_paths 20 -file [file join $OUT_DIR "timing_setup.rpt"]
report_timing -delay_type min -max_paths 20 -file [file join $OUT_DIR "timing_hold.rpt"]
report_timing -delay_type min_max -max_paths 20 -file [file join $OUT_DIR "timing_min_max.rpt"]
report_utilization -hierarchical -file [file join $OUT_DIR "utilization_hierarchical.rpt"]
report_drc -file [file join $OUT_DIR "drc_routed.rpt"]
report_power -file [file join $OUT_DIR "power_routed.rpt"]

# Save Checkpoint
write_checkpoint -force [file join $OUT_DIR "routed.dcp"]

# ------------------------------------------------------------------------------
# 6. Generate Bitstream
# ------------------------------------------------------------------------------
puts "=== [5/5] GENERATING BITSTREAM ==="
write_bitstream -force [file join $OUT_DIR "cv32e40p_ecg_soc.bit"]

puts "=== BUILD COMPLETE! Bitstream and reports generated in $OUT_DIR ==="
