#!/usr/bin/env python3
"""Exact, length-preserving S55 Android 11 healthd voltage path patch.

Prepare a *private* candidate for verified crDroid 7.16 healthd. Does not
contact a phone or change mounted partitions. Binds to a known SHA-256.
"""
from __future__ import annotations
import argparse
from hashlib import sha256
from pathlib import Path
import sys

SOURCE_SHA = "14f0dbbb8ae722df2da8f1b040a6412cc6541e0ac20fd37cc4b782e98a845ef3"
OLD = b"voltage_now"
NEW = b"batt_vol\x00\x00\x00"
assert len(OLD) == len(NEW)

def patch(data: bytes) -> bytes:
    if sha256(data).hexdigest() != SOURCE_SHA:
        raise ValueError("Unknown healthd image: refusing to patch")
    if data[:4] != b"\x7fELF":
        raise ValueError("Not an ELF image")
    if len(data) != 79960 or data.count(OLD) != 2:
        raise ValueError("Unexpected binary layout or paths")
    if (b"/sys/class/power_supply/battery/voltage_now" not in data
            or b"%s/%s/voltage_now" not in data):
        raise ValueError("Required fallback and power-supply discovery paths are missing")
    output = data.replace(OLD, NEW)
    if len(output) != len(data) or output.count(NEW) != 2:
        raise ValueError("Patch postcondition failed")
    return output

def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("source", type=Path, help="Private backed-up original healthd ELF")
    p.add_argument("destination", type=Path, help="Private patched copy, not on a phone")
    args = p.parse_args()
    if args.source.resolve() == args.destination.resolve():
        raise SystemExit("Input and output must differ")
    data = args.source.read_bytes()
    result = patch(data)
    args.destination.write_bytes(result)
    args.destination.chmod(0o600)
    print("ORIGINAL_SHA256", sha256(data).hexdigest())
    print("PATCHED_SHA256", sha256(result).hexdigest())
    print("PATCHED_BYTES", sum(x != y for x, y in zip(data, result)))
    print("BINARY_LENGTH", len(result))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
