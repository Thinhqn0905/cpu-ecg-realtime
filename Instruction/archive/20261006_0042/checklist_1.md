# Checklist 1 (checklist_1): SPI Master + ECG AFE Interface

Prerequisite: checklist_0 complete (CVA6 boots on Artix-7 with UART).
Goal: Add SPI master peripheral and establish communication with ECG analog
front-end chip (ADS1292R or equivalent).

- [complete] Task 1.1: Design SPI master RTL (APB slave interface, configurable clock divider, CPOL/CPHA modes 1/3, 8/16/24-bit transfers). Evidence: `RTL/ecg_soc/spi_master.sv`, `RTL/ecg_soc/spi_master_apb.sv`.
- [complete] Task 1.2: Create SPI master testbench with behavioral ADS1292R SPI slave model. Evidence: `Simulation/ads1292r_model.sv`, `Simulation/spi_master_tb.sv`.
- [complete] Task 1.3: Verify SPI timing: SCLK 1-4 MHz, DRDY interrupt handling, CS assertion/deassertion timing per ADS1292R datasheet. Evidence: `RTL/ecg_soc/sva/spi_master_sva.sv`, `reports/verification/rtm_dashboard.md`.
- [complete] Task 1.4: Integrate SPI master into CVA6 SoC via APB bus — assign memory-mapped registers and interrupt line to PLIC. Evidence: `RTL/ecg_soc/apb_interconnect.sv`, `RTL/ecg_soc/ecg_soc_top.sv`.
- [pending] Task 1.5: Write firmware driver: SPI init, ADS1292R register configuration, continuous conversion mode, DRDY ISR, data read.
- [pending] Task 1.6: SoC-level simulation: firmware reads 24-bit ECG samples from behavioral AFE at 500 Hz — verify data integrity.
- [pending] Task 1.7: FPGA synthesis with SPI peripheral — updated resource utilization and timing report.
- [pending] Task 1.8: Board test: SPI loopback (MOSI→MISO) on PMOD pins, then ADS1292R evaluation board communication.
- [pending] Task 1.9: Document: SPI register map, interrupt latency measurement, AFE initialization sequence, sample capture proof.

Read Instruction/claim_integrity.md before reporting or completing a gate.
