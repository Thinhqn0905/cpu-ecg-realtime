#!/usr/bin/env python3
"""
Firmware Build Automation for CV32E40P ECG SoC
Strict Toolchain Enforcement per Instruction/claim_integrity.md and docs/plans/2026-10-06-gemini-recovery-followup.md

Requires real RISC-V cross-compiler toolchain.
Zero synthetic or handwritten machine-code fallbacks.

Outputs per run:
- hello.elf (ELF32 RISC-V executable)
- hello.bin (flat binary)
- hello.hex (32-bit word Verilog hex for $readmemh)
- hello.dump (disassembly)
- hello.map (linker memory map)
- hello.nm (ordered symbol table)
- hello.readelf (ELF program and section headers)
- hello.sha256 (SHA-256 digests of all generated artifacts)
"""

import os
import sys
import shutil
import subprocess
import hashlib
import argparse
from datetime import datetime, timezone
from pathlib import Path

FIRMWARE_DIR = Path(__file__).resolve().parent
BOOT_DIR = FIRMWARE_DIR / "boot"


def find_toolchain(prefix_override: str = None) -> tuple:
    """Find and validate required RISC-V cross-compilation binaries."""
    pio_path = Path.home() / ".platformio" / "packages" / "toolchain-riscv32-esp" / "bin"
    if pio_path.exists() and str(pio_path) not in os.environ.get("PATH", ""):
        os.environ["PATH"] = f"{pio_path}{os.pathsep}{os.environ.get('PATH', '')}"

    candidates = []
    if prefix_override:
        candidates.append(prefix_override)
    elif "RISCV_PREFIX" in os.environ:
        candidates.append(os.environ["RISCV_PREFIX"])
    else:
        candidates.extend([
            "riscv32-unknown-elf-",
            "riscv-none-elf-",
            "riscv64-unknown-elf-",
            "riscv32-none-elf-",
            "riscv32-esp-elf-",
        ])

    required_tools = ["gcc", "objcopy", "objdump", "nm", "readelf"]

    for prefix in candidates:
        tools = {}
        missing = []
        for t in required_tools:
            tool_name = f"{prefix}{t}"
            # Check executable in PATH or direct path
            p = shutil.which(tool_name)
            if p:
                tools[t] = p
            else:
                missing.append(tool_name)

        if not missing:
            return prefix, tools

    return None, {}


def calculate_sha256(filepath: Path) -> str:
    h = hashlib.sha256()
    with open(filepath, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()


def build_firmware(out_dir: Path, prefix_override: str = None) -> int:
    prefix, tools = find_toolchain(prefix_override)

    if not prefix:
        searched = prefix_override if prefix_override else "riscv32-unknown-elf-, riscv-none-elf-, riscv64-unknown-elf-"
        print(f"[FAIL] Compiler not found in PATH: Required RISC-V toolchain ({searched}) is missing.", file=sys.stderr)
        print("       Install riscv32-unknown-elf-gcc or provide --prefix <path/to/prefix->", file=sys.stderr)
        return 127

    print(f"[build] Using RISC-V toolchain prefix: {prefix}")
    for t_name, t_path in tools.items():
        print(f"        {t_name:8s}: {t_path}")

    # Prepare fresh run output directory
    out_dir.mkdir(parents=True, exist_ok=True)

    elf_file = out_dir / "hello.elf"
    map_file = out_dir / "hello.map"
    bin_file = out_dir / "hello.bin"
    hex_file = out_dir / "hello.hex"
    dump_file = out_dir / "hello.dump"
    nm_file = out_dir / "hello.nm"
    readelf_file = out_dir / "hello.readelf"
    sha256_file = out_dir / "hello.sha256"

    # Step 1: Compile with GCC (detect ISA support for _zicsr)
    isa = "-march=rv32imc_zicsr"
    probe_proc = subprocess.run([tools["gcc"], isa, "-E", "-x", "c", os.devnull], capture_output=True)
    if probe_proc.returncode != 0:
        isa = "-march=rv32imc"

    c_flags = [
        tools["gcc"],
        isa,
        "-mabi=ilp32",
        "-O2",
        "-g",
        "-Wall",
        "-Wextra",
        "-ffreestanding",
        "-nostdlib",
        "-nostartfiles",
        "-T", str(BOOT_DIR / "link.ld"),
        str(BOOT_DIR / "crt0.S"),
        str(BOOT_DIR / "hello.c"),
        f"-Wl,-Map={map_file}",
        "-Wl,--gc-sections",
        "-o", str(elf_file),
    ]

    print(f"[build] [1/6] Compiling firmware: {' '.join(c_flags)}")
    compile_proc = subprocess.run(c_flags, capture_output=True, text=True)
    if compile_proc.returncode != 0:
        print(f"[FAIL] Compilation failed with exit code {compile_proc.returncode}:", file=sys.stderr)
        print(compile_proc.stderr, file=sys.stderr)
        return compile_proc.returncode
    print(f"[build] [PASS] ELF generated: {elf_file}")

    # Step 2: Disassembly with objdump
    print(f"[build] [2/6] Generating disassembly: {dump_file}")
    with open(dump_file, "w", encoding="utf-8") as f:
        dump_proc = subprocess.run([tools["objdump"], "-d", "-S", str(elf_file)], stdout=f, stderr=subprocess.PIPE, text=True)
    if dump_proc.returncode != 0:
        print(f"[FAIL] objdump failed: {dump_proc.stderr}", file=sys.stderr)
        return dump_proc.returncode

    # Step 3: Symbol table with nm
    print(f"[build] [3/6] Generating symbol table: {nm_file}")
    with open(nm_file, "w", encoding="utf-8") as f:
        nm_proc = subprocess.run([tools["nm"], "-n", str(elf_file)], stdout=f, stderr=subprocess.PIPE, text=True)
    if nm_proc.returncode != 0:
        print(f"[FAIL] nm failed: {nm_proc.stderr}", file=sys.stderr)
        return nm_proc.returncode

    # Step 4: Headers with readelf
    print(f"[build] [4/6] Generating ELF headers: {readelf_file}")
    with open(readelf_file, "w", encoding="utf-8") as f:
        readelf_proc = subprocess.run([tools["readelf"], "-l", "-S", str(elf_file)], stdout=f, stderr=subprocess.PIPE, text=True)
    if readelf_proc.returncode != 0:
        print(f"[FAIL] readelf failed: {readelf_proc.stderr}", file=sys.stderr)
        return readelf_proc.returncode

    # Step 5: Binary extraction with objcopy and hex generation
    print(f"[build] [5/6] Extracting binary and generating hex: {bin_file} -> {hex_file}")
    objcopy_proc = subprocess.run([tools["objcopy"], "-O", "binary", str(elf_file), str(bin_file)], capture_output=True, text=True)
    if objcopy_proc.returncode != 0:
        print(f"[FAIL] objcopy failed: {objcopy_proc.stderr}", file=sys.stderr)
        return objcopy_proc.returncode

    # Convert binary to Verilog hex
    sys.path.insert(0, str(FIRMWARE_DIR))
    from bin_to_hex import bin_to_hex
    bin_to_hex(str(bin_file), str(hex_file), 32768)

    # Step 6: Artifact integrity hashing
    print(f"[build] [6/6] Generating artifact SHA-256 manifest: {sha256_file}")
    artifact_names = ["hello.elf", "hello.bin", "hello.hex", "hello.dump", "hello.map", "hello.nm", "hello.readelf"]
    hash_lines = []
    for fname in artifact_names:
        fpath = out_dir / fname
        if not fpath.is_file() or fpath.stat().st_size == 0:
            print(f"[FAIL] Generated artifact {fpath} is missing or 0 bytes!", file=sys.stderr)
            return 1
        digest = calculate_sha256(fpath)
        hash_lines.append(f"{digest}  {fname}\n")
        print(f"        {digest}  {fname} ({fpath.stat().st_size} bytes)")

    sha256_file.write_text("".join(hash_lines), encoding="ascii")

    # Update canonical build/ directory
    canonical_build = FIRMWARE_DIR / "build"
    canonical_build.mkdir(parents=True, exist_ok=True)
    for fname in artifact_names + ["hello.sha256"]:
        src = out_dir / fname
        dst = canonical_build / fname
        shutil.copy2(src, dst)

    print(f"[SUCCESS] Real firmware build verified. Output: {out_dir}")
    print(f"          Canonical build directory updated: {canonical_build}")
    return 0


def main():
    parser = argparse.ArgumentParser(description="Firmware Build Automation for CV32E40P ECG SoC")
    parser.add_argument("--prefix", type=str, default=None, help="RISC-V toolchain prefix (e.g. riscv32-unknown-elf-)")
    parser.add_argument("--out-dir", type=str, default=None, help="Output directory for build artifacts")

    args = parser.parse_args()

    if args.out_dir:
        out_dir = Path(args.out_dir)
    else:
        run_id = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
        out_dir = FIRMWARE_DIR / "build_runs" / f"run_{run_id}"

    ret = build_firmware(out_dir, args.prefix)
    sys.exit(ret)


if __name__ == "__main__":
    main()
