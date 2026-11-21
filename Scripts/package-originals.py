#!/usr/bin/env python3
"""Packages FoldPlay Originals ROMs for the app bundle (see Services/Originals.swift).

    Scripts/package-originals.py <rom.nds>... <output dir>

Format: b"FPG1", 16-byte nonce (= first 16 bytes of the ROM's SHA-256), then the ROM XORed with
SHA-256(key | nonce | counter as u64 little-endian), one 32-byte block per counter. This only
stops the file being copied out of the app by accident; it is not encryption.
"""
import hashlib
import os
import sys

KEY = b"FoldPlay Originals v1"


def package(rom: bytes) -> bytes:
    nonce = hashlib.sha256(rom).digest()[:16]
    out = bytearray(rom)
    for block in range(0, len(out), 32):
        stream = hashlib.sha256(KEY + nonce + (block // 32).to_bytes(8, "little")).digest()
        for i in range(min(32, len(out) - block)):
            out[block + i] ^= stream[i]
    return b"FPG1" + nonce + bytes(out)


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(2)
    *roms, outdir = sys.argv[1:]
    os.makedirs(outdir, exist_ok=True)
    for path in roms:
        name = os.path.splitext(os.path.basename(path))[0] + ".fpg"
        with open(path, "rb") as f:
            data = package(f.read())
        with open(os.path.join(outdir, name), "wb") as f:
            f.write(data)
        print(f"packaged {os.path.basename(path)} -> {name} ({len(data)} bytes)")


if __name__ == "__main__":
    main()
