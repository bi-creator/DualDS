#!/usr/bin/env python3
"""Builds dualds-test.nds from arm9.s / arm7.s (needs arm-none-eabi binutils).
Original DualDS test fixture; contains no Nintendo code, logo or data."""
import pathlib, struct, subprocess, sys, tempfile

HERE = pathlib.Path(__file__).resolve().parent
ARM9_ADDR, ARM7_ADDR = 0x02000000, 0x02380000

def assemble(src, addr, tmp):
    obj, elf, binf = tmp / (src + ".o"), tmp / (src + ".elf"), tmp / (src + ".bin")
    subprocess.run(["arm-none-eabi-as", "-mcpu=arm946e-s" if "9" in src else "-mcpu=arm7tdmi",
                    "-o", obj, HERE / src], check=True)
    subprocess.run(["arm-none-eabi-ld", f"-Ttext=0x{addr:08X}", "-o", elf, obj], check=True)
    subprocess.run(["arm-none-eabi-objcopy", "-O", "binary", elf, binf], check=True)
    return binf.read_bytes()

def crc16(data):
    crc = 0xFFFF
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = (crc >> 1) ^ 0xA001 if crc & 1 else crc >> 1
    return crc

def align(n, a=0x200):
    return (n + a - 1) & ~(a - 1)

def main(out):
    with tempfile.TemporaryDirectory() as t:
        t = pathlib.Path(t)
        arm9, arm7 = assemble("arm9.s", ARM9_ADDR, t), assemble("arm7.s", ARM7_ADDR, t)
    arm9_off = 0x200
    arm7_off = align(arm9_off + len(arm9))
    total = max(align(arm7_off + len(arm7)), 0x2000)
    rom = bytearray(total)
    hdr = bytearray(0x200)
    hdr[0x00:0x0C] = b"DUALDSTEST\0\0"
    hdr[0x0C:0x10] = b"DDST"
    hdr[0x10:0x12] = b"00"
    struct.pack_into("<IIII", hdr, 0x20, arm9_off, ARM9_ADDR, ARM9_ADDR, len(arm9))
    struct.pack_into("<IIII", hdr, 0x30, arm7_off, ARM7_ADDR, ARM7_ADDR, len(arm7))
    struct.pack_into("<II", hdr, 0x80, total, 0x200)
    struct.pack_into("<H", hdr, 0x15E, crc16(hdr[:0x15E]))
    rom[:0x200] = hdr
    rom[arm9_off:arm9_off + len(arm9)] = arm9
    rom[arm7_off:arm7_off + len(arm7)] = arm7
    pathlib.Path(out).write_bytes(rom)
    print(f"wrote {out}: {total} bytes, arm9 {len(arm9)} B, arm7 {len(arm7)} B")

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else HERE / "dualds-test.nds")
