# Session Checklist V0 (checklist_0): CVA6 Core Bring-Up on Artix-7

Worktree: E:\ResearchOnWork\RISC_V_CORE.
Goal: Establish CVA6 RV32IMA core running on Artix-7 FPGA with basic UART
communication as the foundation for the ECG data acquisition system.

- [pending] Task 0.1: Initialize CVA6 submodules (riscv-dbg, rv_plic, apb_uart, apb_timer, gpio) and verify clean elaboration.
- [pending] Task 0.2: Select and validate FPGA config — use cv32a6_ima_sv32_fpga_config_pkg; document resource estimates for Artix-7 100T.
- [pending] Task 0.3: Create Arty A7-100T constraint file (XDC) with clock, reset, UART TX/RX, LED, and PMOD pin mapping.
- [pending] Task 0.4: Create Vivado synthesis Tcl script targeting xc7a100tcsg324-1 with CVA6 + CLINT + PLIC + AXI interconnect.
- [pending] Task 0.5: Run initial synthesis — capture resource utilization (LUT, FF, BRAM, DSP) and timing report.
- [pending] Task 0.6: Verify UART boot console — bare-metal "Hello World" firmware via RISC-V GCC cross-compilation.
- [pending] Task 0.7: Document baseline: resource usage, max frequency achieved, boot time, UART functionality proof.

Read Instruction/claim_integrity.md before reporting or completing a gate.
Every status update requires terminal artifacts and raw locators.
