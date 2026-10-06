#!/usr/bin/env python3
"""
Convert flat binary into 32-bit word Verilog hex file for $readmemh.
Usage: python bin_to_hex.py <input.bin> <output.hex> [mem_size_bytes]
"""

import sys
from pathlib import Path


def bin_to_hex(bin_path: str, hex_path: str, mem_size_bytes: int = 32768):
    bin_file = Path(bin_path)
    if not bin_file.is_file():
        raise FileNotFoundError(f"Input binary not found: {bin_path}")

    data = bin_file.read_bytes()
    num_words = mem_size_bytes // 4

    lines = []
    for i in range(0, len(data), 4):
        chunk = data[i : i + 4]
        # Pad chunk to 4 bytes if necessary
        if len(chunk) < 4:
            chunk = chunk + b"\x00" * (4 - len(chunk))
        # Little-endian 32-bit word: byte0 is LSB, byte3 is MSB
        word = chunk[0] | (chunk[1] << 8) | (chunk[2] << 16) | (chunk[3] << 24)
        lines.append(f"{word:08X}\n")

    # Pad remaining memory with RISC-V NOP (0x00000013)
    while len(lines) < num_words:
        lines.append("00000013\n")

    out_file = Path(hex_path)
    out_file.parent.mkdir(parents=True, exist_ok=True)
    out_file.write_text("".join(lines), encoding="ascii")
    print(f"[bin_to_hex] Converted {len(data)} bytes ({len(data)//4} words) to {hex_path}")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python bin_to_hex.py <input.bin> <output.hex> [mem_size_bytes]")
        sys.exit(1)
    size = int(sys.argv[3]) if len(sys.argv) > 3 else 32768
    bin_to_hex(sys.argv[1], sys.argv[2], size)
