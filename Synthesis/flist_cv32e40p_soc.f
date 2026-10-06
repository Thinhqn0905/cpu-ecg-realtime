// Filelist for CV32E40P Real-Time ECG SoC
// Top Module: cv32e40p_ecg_soc_top

// Include directories
+incdir+cv32e40p/rtl/include
+incdir+cv32e40p/bhv
+incdir+cv32e40p/bhv/include
+incdir+RTL/ecg_soc

// Packages (in strict dependency order)
cv32e40p/rtl/include/cv32e40p_apu_core_pkg.sv
cv32e40p/rtl/include/cv32e40p_fpu_pkg.sv
cv32e40p/rtl/include/cv32e40p_pkg.sv
RTL/ecg_soc/ecg_soc_pkg.sv

// CV32E40P Core Pipeline & Submodules
cv32e40p/rtl/cv32e40p_if_stage.sv
cv32e40p/rtl/cv32e40p_cs_registers.sv
cv32e40p/rtl/cv32e40p_register_file_ff.sv
cv32e40p/rtl/cv32e40p_load_store_unit.sv
cv32e40p/rtl/cv32e40p_id_stage.sv
cv32e40p/rtl/cv32e40p_aligner.sv
cv32e40p/rtl/cv32e40p_decoder.sv
cv32e40p/rtl/cv32e40p_compressed_decoder.sv
cv32e40p/rtl/cv32e40p_fifo.sv
cv32e40p/rtl/cv32e40p_prefetch_buffer.sv
cv32e40p/rtl/cv32e40p_hwloop_regs.sv
cv32e40p/rtl/cv32e40p_mult.sv
cv32e40p/rtl/cv32e40p_int_controller.sv
cv32e40p/rtl/cv32e40p_ex_stage.sv
cv32e40p/rtl/cv32e40p_alu_div.sv
cv32e40p/rtl/cv32e40p_alu.sv
cv32e40p/rtl/cv32e40p_ff_one.sv
cv32e40p/rtl/cv32e40p_popcnt.sv
cv32e40p/rtl/cv32e40p_apu_disp.sv
cv32e40p/rtl/cv32e40p_controller.sv
cv32e40p/rtl/cv32e40p_obi_interface.sv
cv32e40p/rtl/cv32e40p_prefetch_controller.sv
cv32e40p/bhv/cv32e40p_sim_clock_gate.sv
cv32e40p/rtl/cv32e40p_sleep_unit.sv
cv32e40p/rtl/cv32e40p_core.sv
cv32e40p/rtl/cv32e40p_top.sv

// ECG SoC Bus & Memory Subsystem
RTL/ecg_soc/obi_to_apb.sv
RTL/ecg_soc/tcm_sram.sv

// ECG Biosignal Peripherals & Interconnect
RTL/ecg_soc/sync_fifo.sv
RTL/ecg_soc/spi_master.sv
RTL/ecg_soc/spi_master_apb.sv
RTL/ecg_soc/uart_controller.sv
RTL/ecg_soc/uart_apb.sv
RTL/ecg_soc/timer_apb.sv
RTL/ecg_soc/gpio_apb.sv
RTL/ecg_soc/ecg_dma.sv
RTL/ecg_soc/mamba_fir_sidecar.sv
RTL/ecg_soc/mamba_bridge.sv
RTL/ecg_soc/apb_interconnect.sv
RTL/ecg_soc/ecg_soc_top.sv

// Master Top-Level SoC
RTL/ecg_soc/cv32e40p_ecg_soc_top.sv
