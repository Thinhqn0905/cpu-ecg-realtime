# Copyright 2026 RISC-V ECG Project
# SPDX-License-Identifier: Apache-2.0
#
# Firmware Build System for CV32E40P Real-Time ECG SoC
# Enforces reproducible ELF, map, disassembly, and Verilog hex generation per Instruction/claim_integrity.md

RISCV_PREFIX ?= riscv32-unknown-elf-
CC      := $(RISCV_PREFIX)gcc
OBJCOPY := $(RISCV_PREFIX)objcopy
OBJDUMP := $(RISCV_PREFIX)objdump
NM      := $(RISCV_PREFIX)nm
READELF := $(RISCV_PREFIX)readelf
PYTHON  ?= python

ARCH    ?= rv32imc_zicsr
ABI     ?= ilp32

CFLAGS  ?= -march=$(ARCH) -mabi=$(ABI) -O2 -g -Wall -Wextra -ffreestanding -fno-builtin -nostdlib
LDFLAGS ?= -T boot/link.ld -nostartfiles -Wl,-Map=build/hello.map -Wl,--gc-sections

BUILD_DIR = build

.PHONY: all hello clean check-toolchain dsp-test dsp-test-host kernel-benchmark kernel-benchmark-host

all: hello

check-toolchain:
	@$(PYTHON) -c "import shutil, os, sys; p = sys.argv[1]; found = shutil.which(p) or shutil.which(p + '.exe') or os.path.isfile(p) or os.path.isfile(p + '.exe'); (sys.exit(0) if found else (print(f'[FAIL] Compiler {p} not found in PATH', file=sys.stderr), sys.exit(127)))" $(CC)
	@$(PYTHON) -c "import shutil, os, sys; p = sys.argv[1]; found = shutil.which(p) or shutil.which(p + '.exe') or os.path.isfile(p) or os.path.isfile(p + '.exe'); (sys.exit(0) if found else (print(f'[FAIL] Tool {p} not found in PATH', file=sys.stderr), sys.exit(127)))" $(OBJCOPY)
	@$(PYTHON) -c "import shutil, os, sys; p = sys.argv[1]; found = shutil.which(p) or shutil.which(p + '.exe') or os.path.isfile(p) or os.path.isfile(p + '.exe'); (sys.exit(0) if found else (print(f'[FAIL] Tool {p} not found in PATH', file=sys.stderr), sys.exit(127)))" $(OBJDUMP)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

hello: check-toolchain $(BUILD_DIR) $(BUILD_DIR)/hello.elf $(BUILD_DIR)/hello.bin $(BUILD_DIR)/hello.hex $(BUILD_DIR)/hello.dump $(BUILD_DIR)/hello.nm $(BUILD_DIR)/hello.readelf $(BUILD_DIR)/hello.sha256
	@echo "================================================================"
	@echo "  FIRMWARE BUILD COMPLETE: $(BUILD_DIR)/hello.elf"
	@echo "  Hex Image:               $(BUILD_DIR)/hello.hex"
	@echo "  Disassembly:             $(BUILD_DIR)/hello.dump"
	@echo "  Map File:                $(BUILD_DIR)/hello.map"
	@echo "  Symbols:                 $(BUILD_DIR)/hello.nm"
	@echo "  ELF Headers:             $(BUILD_DIR)/hello.readelf"
	@echo "================================================================"

$(BUILD_DIR)/crt0.o: boot/crt0.S | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/hello.o: boot/hello.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/hello.elf: $(BUILD_DIR)/crt0.o $(BUILD_DIR)/hello.o boot/link.ld | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(BUILD_DIR)/crt0.o $(BUILD_DIR)/hello.o $(LDFLAGS) -o $@

$(BUILD_DIR)/hello.dump: $(BUILD_DIR)/hello.elf | $(BUILD_DIR)
	$(OBJDUMP) -d -S $< > $@

$(BUILD_DIR)/hello.nm: $(BUILD_DIR)/hello.elf | $(BUILD_DIR)
	$(NM) -n $< > $@

$(BUILD_DIR)/hello.readelf: $(BUILD_DIR)/hello.elf | $(BUILD_DIR)
	$(READELF) -l -S $< > $@

$(BUILD_DIR)/hello.bin: $(BUILD_DIR)/hello.elf | $(BUILD_DIR)
	$(OBJCOPY) -O binary $< $@

$(BUILD_DIR)/hello.hex: $(BUILD_DIR)/hello.bin | $(BUILD_DIR)
	$(PYTHON) bin_to_hex.py $< $@ 32768

$(BUILD_DIR)/hello.sha256: $(BUILD_DIR)/hello.elf $(BUILD_DIR)/hello.bin $(BUILD_DIR)/hello.hex $(BUILD_DIR)/hello.dump $(BUILD_DIR)/hello.nm $(BUILD_DIR)/hello.readelf | $(BUILD_DIR)
	$(PYTHON) -c "import hashlib, sys; from pathlib import Path; [print(f'{hashlib.sha256(Path(f).read_bytes()).hexdigest()}  {Path(f).name}') for f in sys.argv[1:]]" $^ $(BUILD_DIR)/hello.map > $@

# -----------------------------------------------------------------------------
# DSP Verification & Benchmark Targets (Task 4 & 5 per docs/plans)
# -----------------------------------------------------------------------------
DSP_SRCS = dsp/dsp_test.c dsp/fir_reference.c dsp/pan_tompkins.c dsp/ecg_fir_pulp.S dsp/dsp_runtime.c
DSP_CFLAGS ?= $(CFLAGS) -I dsp

dsp-test: check-toolchain $(BUILD_DIR) $(BUILD_DIR)/dsp_test.elf $(BUILD_DIR)/dsp_test.dump $(BUILD_DIR)/dsp_test.sha256
	@echo "================================================================"
	@echo "  DSP FIR & PAN-TOMPKINS BUILD COMPLETE: $(BUILD_DIR)/dsp_test.elf"
	@echo "================================================================"

$(BUILD_DIR)/dsp_test.elf: $(DSP_SRCS) | $(BUILD_DIR)
	$(CC) $(DSP_CFLAGS) -T boot/link.ld -nostartfiles -Wl,-Map=$(BUILD_DIR)/dsp_test.map -Wl,--gc-sections boot/crt0.S $^ -o $@

$(BUILD_DIR)/dsp_test.dump: $(BUILD_DIR)/dsp_test.elf | $(BUILD_DIR)
	$(OBJDUMP) -d -S $< > $@

$(BUILD_DIR)/dsp_test.sha256: $(BUILD_DIR)/dsp_test.elf $(BUILD_DIR)/dsp_test.dump | $(BUILD_DIR)
	$(PYTHON) -c "import hashlib, sys; from pathlib import Path; [print(f'{hashlib.sha256(Path(f).read_bytes()).hexdigest()}  {Path(f).name}') for f in sys.argv[1:]]" $^ > $@

KBENCH_SRCS = dsp/kernel_benchmark.c dsp/fir_reference.c dsp/pan_tompkins.c dsp/ecg_fir_pulp.S dsp/dsp_runtime.c

kernel-benchmark: check-toolchain $(BUILD_DIR) $(BUILD_DIR)/kernel_benchmark.elf $(BUILD_DIR)/kernel_benchmark.hex $(BUILD_DIR)/kernel_benchmark.dump $(BUILD_DIR)/kernel_benchmark.sha256
	@echo "================================================================"
	@echo "  KERNEL BENCHMARK BUILD COMPLETE: $(BUILD_DIR)/kernel_benchmark.elf"
	@echo "  Hex Image:                       $(BUILD_DIR)/kernel_benchmark.hex"
	@echo "================================================================"

$(BUILD_DIR)/kernel_benchmark.elf: $(KBENCH_SRCS) | $(BUILD_DIR)
	$(CC) $(DSP_CFLAGS) -T boot/link.ld -nostartfiles -Wl,-Map=$(BUILD_DIR)/kernel_benchmark.map -Wl,--gc-sections boot/crt0.S $^ -o $@

$(BUILD_DIR)/kernel_benchmark.bin: $(BUILD_DIR)/kernel_benchmark.elf | $(BUILD_DIR)
	$(OBJCOPY) -O binary $< $@

$(BUILD_DIR)/kernel_benchmark.hex: $(BUILD_DIR)/kernel_benchmark.bin | $(BUILD_DIR)
	$(PYTHON) bin_to_hex.py $< $@ 32768

$(BUILD_DIR)/kernel_benchmark.dump: $(BUILD_DIR)/kernel_benchmark.elf | $(BUILD_DIR)
	$(OBJDUMP) -d -S $< > $@

$(BUILD_DIR)/kernel_benchmark.sha256: $(BUILD_DIR)/kernel_benchmark.elf $(BUILD_DIR)/kernel_benchmark.dump $(BUILD_DIR)/kernel_benchmark.hex | $(BUILD_DIR)
	$(PYTHON) -c "import hashlib, sys; from pathlib import Path; [print(f'{hashlib.sha256(Path(f).read_bytes()).hexdigest()}  {Path(f).name}') for f in sys.argv[1:]]" $^ > $@

HOST_CC ?= gcc
dsp-test-host: $(BUILD_DIR)
	$(HOST_CC) -O2 -Wall -Wextra -I dsp dsp/dsp_test.c dsp/fir_reference.c dsp/pan_tompkins.c dsp/dsp_runtime.c -o $(BUILD_DIR)/dsp_test_host
	$(BUILD_DIR)/dsp_test_host

kernel-benchmark-host: $(BUILD_DIR)
	$(HOST_CC) -O2 -Wall -Wextra -I dsp dsp/kernel_benchmark.c dsp/fir_reference.c dsp/pan_tompkins.c dsp/dsp_runtime.c -o $(BUILD_DIR)/kernel_benchmark_host
	$(BUILD_DIR)/kernel_benchmark_host

clean:
	rm -rf $(BUILD_DIR)
