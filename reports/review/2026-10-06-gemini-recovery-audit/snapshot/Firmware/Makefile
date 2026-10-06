# Copyright 2026 RISC-V ECG Project
# SPDX-License-Identifier: Apache-2.0
#
# Firmware Build System for CV32E40P Real-Time ECG SoC
# Enforces reproducible ELF, map, disassembly, and Verilog hex generation per Instruction/claim_integrity.md

CC      ?= riscv32-unknown-elf-gcc
OBJCOPY ?= riscv32-unknown-elf-objcopy
OBJDUMP ?= riscv32-unknown-elf-objdump
PYTHON  ?= python

ARCH    ?= rv32imc
ABI     ?= ilp32

CFLAGS  ?= -march=$(ARCH) -mabi=$(ABI) -O2 -g -Wall -Wextra -ffreestanding -fno-builtin -nostdlib
LDFLAGS ?= -T boot/link.ld -nostartfiles -Wl,-Map=build/hello.map -Wl,--gc-sections

BUILD_DIR = build

.PHONY: all hello clean

all: hello

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

hello: $(BUILD_DIR) $(BUILD_DIR)/hello.elf $(BUILD_DIR)/hello.dump $(BUILD_DIR)/hello.hex $(BUILD_DIR)/hello.sha256
	@echo "================================================================"
	@echo "  FIRMWARE BUILD COMPLETE: $(BUILD_DIR)/hello.elf"
	@echo "  Hex Image:               $(BUILD_DIR)/hello.hex"
	@echo "  Disassembly:             $(BUILD_DIR)/hello.dump"
	@echo "  Map File:                $(BUILD_DIR)/hello.map"
	@echo "================================================================"

$(BUILD_DIR)/crt0.o: boot/crt0.S | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/hello.o: boot/hello.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR)/hello.elf: $(BUILD_DIR)/crt0.o $(BUILD_DIR)/hello.o boot/link.ld | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(BUILD_DIR)/crt0.o $(BUILD_DIR)/hello.o $(LDFLAGS) -o $@

$(BUILD_DIR)/hello.dump: $(BUILD_DIR)/hello.elf | $(BUILD_DIR)
	$(OBJDUMP) -d -S $< > $@

$(BUILD_DIR)/hello.bin: $(BUILD_DIR)/hello.elf | $(BUILD_DIR)
	$(OBJCOPY) -O binary $< $@

$(BUILD_DIR)/hello.hex: $(BUILD_DIR)/hello.bin | $(BUILD_DIR)
	$(PYTHON) bin_to_hex.py $< $@ 32768

$(BUILD_DIR)/hello.sha256: $(BUILD_DIR)/hello.elf $(BUILD_DIR)/hello.hex $(BUILD_DIR)/hello.dump | $(BUILD_DIR)
	$(PYTHON) -c "import hashlib, glob, sys; [print(f'{hashlib.sha256(open(f, \"rb\").read()).hexdigest()}  {f}') for f in sys.argv[1:]]" $^ > $@

clean:
	rm -rf $(BUILD_DIR)
