#!/usr/bin/env python3
"""Offline safety checks for a proprietary-free MTK RIL callback guard."""
import hashlib
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("s55_ril_patch", root / "scripts/patch-rilproxy-networkinfo.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

assert mod.ELF_OFFSET == 0x56AA0
assert mod.BEFORE == bytes.fromhex("080d40f9")
assert mod.AFTER == bytes.fromhex("081540f9")
assert mod.CHECK_BRANCH == bytes.fromhex("c80800b4")
base = bytearray(541336)
base[:4] = b"\x7fELF"
base[mod.ELF_OFFSET:mod.ELF_OFFSET + 4] = mod.BEFORE
base[mod.ELF_OFFSET + 4:mod.ELF_OFFSET + 8] = mod.CHECK_BRANCH
off = 0x5bb4c - 0x5000
base[off:off + 4] = mod.NULL_DEREF
patched = mod.transform(bytes(base), require_original=False)
assert patched[mod.ELF_OFFSET:mod.ELF_OFFSET + 4] == mod.AFTER
assert patched[mod.ELF_OFFSET + 4:mod.ELF_OFFSET + 8] == mod.CHECK_BRANCH
assert patched[off:off + 4] == mod.NULL_DEREF
assert sum(a != b for a, b in zip(base, patched)) == 1
try:
    mod.transform(bytes(base))
except ValueError as exc:
    assert "SHA256" in str(exc)
else:
    raise AssertionError("non-pinned source unexpectedly accepted")
for at in (mod.ELF_OFFSET, mod.ELF_OFFSET + 4, off):
    broken = bytearray(base)
    broken[at] ^= 1
    try:
        mod.transform(bytes(broken), require_original=False)
    except ValueError:
        pass
    else:
        raise AssertionError(f"unexpected patched tampered offset {at}")
print("S55_RIL_NULL_GUARD_OFFLINE_TESTS_PASS")
