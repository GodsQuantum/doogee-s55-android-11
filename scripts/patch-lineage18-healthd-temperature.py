#!/usr/bin/env python3
"""Prepare a guarded, binary-identical-sized ARM64 healthd battery-temp fix.

LineageOS 18.1 GSI healthd searches /sys/class/power_supply/battery/temp,
but the DOOGEE S55 MTK kernel provides batt_temp in tenths of a Celsius degree.
Patches exactly one ARM64 ADRP + ADD reference and extends the existing R-only
PT_LOAD segment into pre-existing zero padding. Does not edit a phone.
"""
from __future__ import annotations
import hashlib
import struct
import sys
from pathlib import Path

SOURCE_SHA = "5f66b4c372d09eb84f2b23dadedaad0a53242bc44f31fdd7787a5467bee9e3ee"
EXPECTED_LENGTH = 84096
ADRP_OFF = 0x108FC
ADD_OFF = 0x10908
FORMAT_OFF = 0x4903
NEW_OFF = 0x6400
NEW_FORMAT = b"%s/%s/batt_temp\0"
SEGMENT_HDR = 0xB0  # third ELF64 phdr (PT_LOAD R, original 0x0..0x63f4)
SEGMENT_END = 0x6420
OLD_ADRP = 0x90FFFFA1
OLD_ADD = 0x91240C21


def sha256(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def program_header_length(b: bytes, offset: int) -> int:
    return struct.unpack_from("<Q", b, offset)[0]


def decode_adrp(word: int, pc: int) -> int:
    assert (word & 0x9F000000) == 0x90000000 and word & 31 == 1
    imm21 = (((word >> 5) & 0x7FFFF) << 2) | ((word >> 29) & 3)
    if imm21 & (1 << 20):
        imm21 -= 1 << 21
    return (pc & ~0xFFF) + (imm21 << 12)


def encode_adrp(word: int, pc: int, addr: int) -> int:
    delta = (addr >> 12) - (pc >> 12)
    assert -(1 << 20) <= delta < (1 << 20)
    imm = delta & 0x1FFFFF
    return ((word & ~((3 << 29) | (0x7FFFF << 5))) |
            ((imm & 3) << 29) | (((imm >> 2) & 0x7FFFF) << 5))


def main(src: Path, dest: Path) -> None:
    if src.resolve() == dest.resolve():
        raise ValueError("Input and output cannot be the same file")
    raw = src.read_bytes()
    if len(raw) != EXPECTED_LENGTH or sha256(raw) != SOURCE_SHA:
        raise ValueError("Unknown healthd ELF input; refusing")
    if raw[:4] != b"\x7fELF" or raw[4:6] != b"\x02\x01":
        raise ValueError("Not a little-endian ELF64")
    if struct.unpack_from("<H", raw, 18)[0] != 183:
        raise ValueError("Not AArch64")
    if raw[FORMAT_OFF:FORMAT_OFF+len(b"%s/%s/temp\0")] != b"%s/%s/temp\0":
        raise ValueError("Expected original temp path not found")
    if raw.count(b"%s/%s/temp\0") != 1:
        raise ValueError("Unexpected temp path reference count")
    assert struct.unpack_from("<I", raw, ADRP_OFF)[0] == OLD_ADRP
    assert struct.unpack_from("<I", raw, ADD_OFF)[0] == OLD_ADD
    assert decode_adrp(OLD_ADRP, ADRP_OFF) + 0x903 == FORMAT_OFF
    assert raw[NEW_OFF:SEGMENT_END] == bytes(SEGMENT_END - NEW_OFF)
    assert program_header_length(raw, SEGMENT_HDR+32) == 0x63F4
    assert program_header_length(raw, SEGMENT_HDR+40) == 0x63F4
    assert struct.unpack_from("<I", raw, SEGMENT_HDR)[0] == 1
    assert struct.unpack_from("<I", raw, SEGMENT_HDR+4)[0] == 4  # read-only
    assert struct.unpack_from("<Q", raw, SEGMENT_HDR+16)[0] == 0

    b = bytearray(raw)
    b[NEW_OFF:NEW_OFF+len(NEW_FORMAT)] = NEW_FORMAT
    struct.pack_into("<Q", b, SEGMENT_HDR+32, SEGMENT_END)
    struct.pack_into("<Q", b, SEGMENT_HDR+40, SEGMENT_END)
    new_adrp = encode_adrp(OLD_ADRP, ADRP_OFF, NEW_OFF)
    struct.pack_into("<I", b, ADRP_OFF, new_adrp)
    new_add = (OLD_ADD & ~(0xFFF << 10)) | ((NEW_OFF & 0xFFF) << 10)
    struct.pack_into("<I", b, ADD_OFF, new_add)
    assert decode_adrp(new_adrp, ADRP_OFF) + ((new_add >> 10) & 0xFFF) == NEW_OFF
    assert len(b) == len(raw)
    assert b[FORMAT_OFF:FORMAT_OFF+len(b"%s/%s/temp\0")] == b"%s/%s/temp\0"
    assert b[NEW_OFF:NEW_OFF+len(NEW_FORMAT)] == NEW_FORMAT
    allowed = set(range(NEW_OFF, NEW_OFF+len(NEW_FORMAT)))
    allowed.update(range(ADRP_OFF, ADRP_OFF+4))
    allowed.update(range(ADD_OFF, ADD_OFF+4))
    allowed.update(range(SEGMENT_HDR+32, SEGMENT_HDR+48))
    assert all(i in allowed for i,(x,y) in enumerate(zip(raw,b)) if x!=y)
    dest.write_bytes(b)
    dest.chmod(0o600)
    print("INPUT_SHA256", SOURCE_SHA)
    print("OUTPUT_SHA256", sha256(b))
    print("OUTPUT_SIZE", len(b))
    print("ADRP",hex(OLD_ADRP),"->",hex(new_adrp))
    print("ADD",hex(OLD_ADD),"->",hex(new_add))
    print("R_LOAD_END",hex(0x63f4),"->",hex(SEGMENT_END))
    print("NEW_BATTERY_PATH",NEW_FORMAT.decode())


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(f"Usage: {sys.argv[0]} INPUT_VOLTAGED_HEALTHD OUTPUT_PRIVATE_HEALTHD")
    main(Path(sys.argv[1]), Path(sys.argv[2]))
