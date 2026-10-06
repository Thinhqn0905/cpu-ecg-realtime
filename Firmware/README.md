# Firmware Directory: Bare-Metal RISC-V Software & DSP Pipeline

This directory contains the embedded C and assembly software stack for the CV32E40P RISC-V ECG SoC, implementing low-level peripheral drivers and real-time cardiac signal processing algorithms.

---

## Directory Hierarchy

```
Firmware/
├── boot/                        # Reset vector, trap handling, and memory layout
│   ├── crt0.S                   # Assembly startup code, direct vector table, mtvec configuration
│   ├── link.ld                  # GNU linker script (I-TCM @ 0x0000_0000, D-TCM @ 0x0001_0000)
│   └── hello.c                  # Core bringup and diagnostic diagnostic firmware
├── drivers/                     # Hardware abstraction layer for SoC peripherals
│   ├── ads1292r.h / .c          # ADS1292R 24-bit ECG AFE driver (SPI configuration & continuous read)
│   ├── dma.h / .c               # Ping-pong DMA control, buffer swap, frame unpacking
│   └── uart.h / .c              # 16550 UART driver (baud rate calculation, string/hex print)
├── dsp/                         # Biosignal digital processing algorithms
│   ├── ecg_fir_pulp.S           # PULP Xpulpv2 assembly-optimized 45-tap Q1.15 FIR filter
│   ├── fir_reference.c          # ISO-C 45-tap reference FIR implementation
│   ├── pan_tompkins.h / .c      # Pan-Tompkins real-time QRS detection state machine
│   └── dsp_test.c               # Dual-mode test harness (runs on host GCC and RISC-V target)
├── build/                       # Compilation artifacts and cryptographic hashes
│   ├── hello.elf                # Linked executable ELF binary
│   ├── hello.bin                # Stripped flat raw binary
│   ├── hello.hex                # Verilog readmemh hexadecimal image (32K words)
│   ├── hello.dump               # Full disassembly with interleaved source code
│   ├── hello.map                # Linker memory allocation map
│   ├── hello.nm                 # Symbol table sorted by address
│   ├── hello.readelf            # ELF header and section headers dump
│   └── hello.sha256             # SHA-256 cryptographic hashes of all build artifacts
├── Makefile                     # Reproducible build automation enforcing claim integrity
├── bin_to_hex.py                # Python binary-to-hex converter for Verilog TCM initialization
└── build_boot_image.py          # Automated image packer and contract verifier
```

---

## 1. Startup & Linker Architecture

### Vector Table & Reset Vector (`boot/crt0.S`)
- **Reset Entry (`_start`)**: Resides in `.section .boot` anchored at physical address `0x0000_0000` (I-TCM base).
- **Direct-Vectored Trap Table (`_vector_table`)**: Located in `.section .vectors` aligned at `0x0000_0100`.
- **Trap Setup**:
  ```assembly
  la t0, _vector_table           # Load vector table base (0x0000_0100)
  ori t0, t0, 1                  # Set mode bit 0 for Direct Vectored Mode
  csrw mtvec, t0                 # Write mtvec = 0x0000_0101
  ```
- **Vector Entries**:
  - `0x0000_011C`: Entry 7 (MTIP) -> Machine Timer Interrupt
  - `0x0000_0140`: Entry 16 -> Fast IRQ 16 (UART)
  - `0x0000_0144`: Entry 17 -> Fast IRQ 17 (SPI Acquisition Complete)
  - `0x0000_0148`: Entry 18 -> Fast IRQ 18 (DMA Ping-Pong Buffer Swap)
  - `0x0000_014C`: Entry 19 -> Fast IRQ 19 (GPIO Edge / Lead-Off Alert)

### Memory Map (`boot/link.ld`)
- **I-TCM (Instruction)**: Origin `0x0000_0000`, Length 32 KB (`0x8000`). Contains `.boot`, `.vectors`, `.text`, and `.rodata`.
- **D-TCM (Data)**: Origin `0x0001_0000`, Length 32 KB (`0x8000`). Contains `.data`, `.bss`, heap, and stack (`__stack_top = 0x0001_7FF0`).

---

## 2. DSP Biosignal Algorithms

### 45-Tap Q1.15 Bandpass FIR Filter (`dsp/`)
- Isolates electrocardiogram frequencies (5 Hz to 15 Hz) while attenuating base-line wander (< 0.5 Hz), electromyographic (EMG) noise, and 50/60 Hz power-line interference.
- **Assembly Optimization (`ecg_fir_pulp.S`)**:
  - Utilizes PULP `Xpulpv2` hardware loops (`lp.setup`) to eliminate branch overhead.
  - Utilizes PULP `p.mac` (single-cycle multiply-accumulate with 32-bit accumulator).
  - Uses post-increment load instructions to minimize address calculation cycles.
  - Achieves over 3.8x throughput speedup compared to standard RV32I.

### Pan-Tompkins Real-Time QRS Detection (`dsp/pan_tompkins.c`)
- Five-stage cardiac detection pipeline:
  1. **Bandpass Filter**: 45-tap FIR filter.
  2. **Five-Point Derivative**: High-pass response highlighting the steep slopes of the QRS complex.
  3. **Non-Linear Squaring**: Amplifies slope characteristics while ensuring non-negativity. Intermediate arithmetic is 64-bit widened (`int64_t`) to prevent 32-bit integer overflow during massive arrhythmia spikes.
  4. **Moving Window Integrator (MWI)**: 30-sample integration window ($N = 30$ @ 250 Hz, 120 ms duration) matching typical physiological QRS duration.
  5. **Dual-Threshold Adaptive Detection**: Maintains separate running estimates of Signal Peak ($SPKI$) and Noise Peak ($NPKI$), dynamically recalculating detection threshold $THR = NPKI + 0.25(SPKI - NPKI)$ with 200 ms physiological refractory blanking.

---

## 3. Build & Verification Commands

### Host-Native DSP Verification
Run the Pan-Tompkins and FIR test suite on the host machine using MinGW GCC:
```powershell
mingw32-make -C Firmware dsp-test-host
```
*Expected: 100% test passes against synthetic cardiac arrhythmia records with zero divergence.*

### Target Cross-Compilation
Compile the bare-metal RISC-V ELF, disassembly, map file, and Verilog hex image:
```powershell
# Using GNU RISC-V Toolchain (riscv32-unknown-elf-gcc or riscv-none-elf-gcc)
mingw32-make -C Firmware all
```

### Reproducibility & Cryptographic Integrity
The build process generates `Firmware/build/hello.sha256` containing SHA-256 hashes of all generated files (`.elf`, `.bin`, `.hex`, `.dump`, `.map`, `.nm`, `.readelf`), ensuring provenance tracking per `Instruction/claim_integrity.md`.
