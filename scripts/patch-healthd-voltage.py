#!/usr/bin/env python3
"""Exact, length-preserving S55 Android 11 healthd voltage path patch.

Prepare a *private* candidate for an exact verified S55 Android 11 healthd
(crDroid 7.16 or LineageOS 18.1). No phone/partition interaction. Known SHA-256 only.
"""
from __future__ import annotations
import argparse
from hashlib import sha256
from pathlib import Path
import sys

KNOWN = {
    # sha256: (ELF bytes, original pattern count, required full path)
    "14f0dbbb8ae722df2da8f1b040a6412cc6541e0ac20fd37cc4b782e98a845ef3":
        (79960, 2, b"/sys/class/power_supply/battery/voltage_now"),
    "fc17574161e743e11c38e3d9d44b1c0b1bfdf04e946e78610dd69c80954c4215":
        (84096, 1, b"%s/%s/voltage_now"),
}
OLD = b"voltage_now"
NEW = b"batt_vol\x00\x00\x00"
assert len(OLD) == len(NEW)

def patch(data: bytes) -> bytes:
    spec = KNOWN.get(sha256(data).hexdigest())
    if spec is None:
        raise ValueError("Unknown healthd image: refusing to patch")
    expected_len, path_count, required_path = spec
    if data[:4] != b"\x7fELF":
        raise ValueError("Not an ELF image")
    if len(data) != expected_len or data.count(OLD) != path_count:
        raise ValueError("Unexpected binary layout or paths")
    if required_path not in data or b"%s/%s/voltage_now" not in data:
        raise ValueError("Required voltage sysfs paths are missing")
    output = data.replace(OLD, NEW)
    if len(output) != len(data) or output.count(NEW) != path_count:
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
