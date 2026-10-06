# Checklist 2 (checklist_2): CV32E40P Full Implementation Flow (Phase A to Z)

**Target Architecture:** OpenHW Group CV32E40P (RV32IMC + CORE-V Xpulpv2 DSP Extensions)  
**Implementation Mode:** Dual-Track (FPGA Prototyping on Artix-7/Gowin + Silicon ASIC on GF180MCU/Sky130)  
**Reference Document:** `Instruction/cv32e40p_implementation_plan_a_to_z.md`

---

## Deliverables & Gates Status

- [complete] **Phase A: Core Subsystem & Parameters:** CV32E40P subsystem instantiated with `COREV_PULP=1`, `FPU=0`, dual OBI ports, and direct `irq_fast_i[14:0]` fast vectoring. Evidence: `RTL/ecg_soc/cv32e40p_ecg_soc_top.sv`.
- [complete] **Phase B: Bus Protocol Translation:** Open Bus Interface to APB3 bridge translating pipelined OBI data requests into 2-cycle APB3 transactions with zero wait-state grant. Evidence: `RTL/ecg_soc/obi_to_apb.sv`, `RTL/ecg_soc/sva/obi_to_apb_sva.sv`, `RTL/ecg_soc/sva/obi_to_apb_bind.sv`.
- [complete] **Phase C: Dual-Target Harvard SRAM:** 32 KB I-TCM (`0x0000_0000`) + 32 KB D-TCM (`0x0001_0000`) with 4-byte write-enable lanes, synthesizable for FPGA BRAM inference or ASIC SRAM compiler macros. Evidence: `RTL/ecg_soc/tcm_sram.sv`.
- [complete] **Phase D: ECG Biosignal Ingress Suite:** ADS1292R SPI Master, Ping-Pong DMA Buffer (32 samples/bank), 8N1 UART, 32-bit Timer, 8-bit GPIO. Evidence: `RTL/ecg_soc/ecg_soc_top.sv`.
- [complete] **Phase E: CNN-MAMBA Coprocessor Integration:** Control plane mapped at `0x2000_0000`, AXI4-Stream data ingress from Ping-Pong DMA, and arrhythmia alert interrupt mapped to `irq_fast_i[6]`. Evidence: `RTL/ecg_soc/mamba_bridge.sv`.
- [complete] **Phase F: Firmware & Xpulp DSP Stack:**
  * Linker script for Harvard 32KB I-TCM / 32KB D-TCM: `Firmware/boot/link.ld`
  * PULP vector table and startup code: `Firmware/boot/crt0.S`
  * ADS1292R AFE driver: `Firmware/drivers/ads1292r.h`, `Firmware/drivers/ads1292r.c`
  * UART telemetry packetizer with CRC-8: `Firmware/drivers/uart.h`, `Firmware/drivers/uart.c`
  * Ping-Pong DMA buffer driver: `Firmware/drivers/dma.h`, `Firmware/drivers/dma.c`
  * 45-tap FIR lowpass using Hardware Loops and Packed SIMD: `Firmware/dsp/ecg_fir_pulp.S`
  * 2nd-order notch biquad using single-cycle MAC: `Firmware/dsp/ecg_iir_pulp.S`
  * Real-time Pan-Tompkins QRS complex detector: `Firmware/dsp/pan_tompkins.h`, `Firmware/dsp/pan_tompkins.c`
  * Real-time acquisition & classification main loop: `Firmware/main.c`
- [complete] **Phase G: Full-System Co-Simulation:** Complete testbench exercising processor boot, AFE DRDY capture, SPI transfer, Ping-Pong DMA, UART telemetry, and MAMBA coprocessor binding. Evidence: `Simulation/soc_tb.sv`.
- [complete] **Phase H1: FPGA Physical Flow:** Vivado synthesis, placement, routing, timing closure at 50–100 MHz, and Arty A7-100T pinout constraints. Evidence: `Synthesis/fpga/ecg_artix7/run_synth.tcl`, `Synthesis/fpga/ecg_artix7/arty_a7_100t.xdc`.
- [complete] **Phase H2: Silicon ASIC Flow:** OpenLane physical design configuration for GF180MCU / Sky130 tapeout (synthesis, floorplan, PDN, TritonCTS, route, DRC/LVS). Evidence: `Synthesis/asic/openlane/config.json`, `Synthesis/asic/run_openlane.sh`.
- [complete] **Gate 5 Sign-off:** 100% Requirement Traceability Matrix coverage across 26 requirements. Evidence: `reports/verification/rtm_dashboard.md`.
