#!/usr/bin/env python3
"""Offline, SHA256-guarded S55-only correction of an MTK RIL null callback.

NEVER mounts, flashes, restarts services or contacts an Android device.
Must be run against the exact captured original S55 vendor library.
"""
import argparse
import hashlib
import os
from pathlib import Path

ORIGINAL_SHA256 = "425312124514d3b87e0d8f249bb92596a2b90e6212c9484b524e761227f15f07"
ELF_OFFSET = 0x56AA0
BEFORE = bytes.fromhex("08 0d 40 f9")  # ldr x8, [x8,#0x18] (wrong callback)
AFTER = bytes.fromhex("08 15 40 f9")   # ldr x8, [x8,#0x28] (used indication callback)
CHECK_BRANCH = bytes.fromhex("c8 08 00 b4")  # cbz x8, error-return path at 0x5bbbc
NULL_DEREF = bytes.fromhex("08 00 40 f9")  # ldr x8,[x0] at 0x5bb4c

def sha(data):
    return hashlib.sha256(data).hexdigest()

def transform(data, *, require_original=True):
    if not data.startswith(b"\x7fELF") or len(data) != 541336:
        raise ValueError("Not the exact ELF64 S55 RIL library")
    if require_original and sha(data) != ORIGINAL_SHA256:
        raise ValueError("Unknown original SHA256; refusing to patch")
    if data[ELF_OFFSET:ELF_OFFSET + 4] != BEFORE:
        raise ValueError("Expected unguarded callback load missing")
    if data[ELF_OFFSET + 4:ELF_OFFSET + 8] != CHECK_BRANCH:
        raise ValueError("Expected existing null-branch missing")
    # Original crash instruction at virtual 0x5bb4c, file offset virtual-0x5000.
    crash_off = 0x5bb4c - 0x5000
    if data[crash_off:crash_off + 4] != NULL_DEREF:
        raise ValueError("Crash instruction not identical to analyzed S55 binary")
    patched = bytearray(data)
    patched[ELF_OFFSET:ELF_OFFSET + 4] = AFTER
    if sum(a != b for a, b in zip(data, patched)) != 1:
        raise AssertionError("Only one instruction-byte change is allowed")
    return bytes(patched)

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("source", type=Path)
    ap.add_argument("output", type=Path)
    args = ap.parse_args()
    source = args.source.resolve()
    output = args.output.resolve()
    if source == output:
        ap.error("source and output must differ; no in-place modification")
    data = source.read_bytes()
    patched = transform(data)
    if output.exists():
        ap.error("output already exists, refusing overwrite")
    fd = os.open(output, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(patched)
            f.flush()
            os.fsync(f.fileno())
    except BaseException:
        output.unlink(missing_ok=True)
        raise
    assert output.read_bytes() == patched
    print("S55_RIL_GUARD_CANDIDATE_ONLY_NO_DEVICE_WRITES")
    print("original_sha256", sha(data))
    print("candidate_sha256", sha(patched))
    print("patched_elf_offset", hex(ELF_OFFSET))
    print("next_step", "Disassemble/bench and review before any experimental mount")

if __name__ == "__main__":
    main()
