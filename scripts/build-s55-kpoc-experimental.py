#!/usr/bin/env python3
"""EXPERIMENTAL offline S55 KPOC compatibility image builder; never touches USB.

An OEM Android 8 system declares kpoc_charger in class charger. A Lineage
18.1 GSI instead declares gsicharger in class gsicharger. The stock S55
ramdisk still triggers class charger, but contains a static /sbin/charger.
This tool prepares a reversible hypothesis for OFFLINE evaluation only.
The resulting boot image MUST NOT be flashed until the charger-mode init
path, SELinux context and restore procedure are independently validated.
"""
import argparse
import gzip
import hashlib
import os
from pathlib import Path
import struct
import tempfile

EXPECTED_SHA = "a2e6c0db60b2ecc22fe4fb42e2ca2db03b55188d44f195361e36c5dd6873f5ab"
SERVICE = b"""
# EXPERIMENTAL S55 KPOC compatibility service (not production-certified).
# OEM stock: kpoc_charger class charger; GSI: gsicharger class gsicharger.
service charger /sbin/charger
    class charger
    user root
    group root system
    seclabel u:r:charger:s0
"""

def align(n, page):
    return (n + page - 1) // page * page

def cpio_records(raw):
    records = []
    pos = 0
    while pos + 110 <= len(raw):
        h = bytearray(raw[pos:pos + 110])
        if h[:6] not in (b"070701", b"070702"):
            raise ValueError(f"Invalid newc header at {pos}")
        fields = [int(h[6 + i * 8:14 + i * 8], 16) for i in range(13)]
        size, namesize = fields[6], fields[11]
        if namesize < 2 or namesize > 4096:
            raise ValueError("Invalid cpio namesize")
        name_start = pos + 110
        name_end = name_start + namesize
        padded_end = align(name_end, 4)
        name_part = raw[name_start:padded_end]
        name = raw[name_start:name_end].rstrip(b"\0")
        data_end = padded_end + size
        next_pos = align(data_end, 4)
        if next_pos > len(raw):
            raise ValueError("Truncated cpio entry")
        payload = raw[padded_end:data_end]
        padding = raw[data_end:next_pos]
        records.append((h, name_part, name, payload, padding))
        pos = next_pos
        if name == b"TRAILER!!!":
            return records, raw[pos:]
    raise ValueError("No cpio TRAILER!!!")

def serialize_cpio(records, trailer, replace=None):
    result = bytearray()
    for header, name_part, name, payload, padding in records:
        if replace is not None and name in replace:
            payload = replace[name]
            header = header.copy()
            header[54:62] = f"{len(payload):08x}".encode()  # newc field 6: filesize
            padding = b"\0" * ((-len(payload)) % 4)
        result.extend(header)
        result.extend(name_part)
        result.extend(payload)
        result.extend(padding)
    result.extend(trailer)
    return bytes(result)

def build(original):
    if hashlib.sha256(original).hexdigest() != EXPECTED_SHA:
        raise ValueError("Boot source is not SHA-pinned active S55 2020 image")
    if original[:8] != b"ANDROID!":
        raise ValueError("Not an Android boot image")
    ks, rs = struct.unpack_from("<I", original, 8)[0], struct.unpack_from("<I", original, 16)[0]
    pg = struct.unpack_from("<I", original, 36)[0]
    if pg != 2048 or len(original) != 16 * 1024 * 1024:
        raise ValueError("Unexpected page size or boot partition size")
    if struct.unpack_from("<I", original, 24)[0] or struct.unpack_from("<I", original, 40)[0]:
        raise ValueError("Boot image has extra second-stage/DT entries")
    koff = align(1648, pg)
    roff = koff + align(ks, pg)
    orig_k = original[koff:koff + ks]
    orig_r = original[roff:roff + rs]
    if len(orig_k) != ks or len(orig_r) != rs:
        raise ValueError("Boot image truncated")
    if any(original[roff + align(rs, pg):]):
        raise ValueError("Unexpected data after ramdisk; refuse image repack")
    unpacked = gzip.decompress(orig_r)
    records, trailer = cpio_records(unpacked)
    if serialize_cpio(records, trailer) != unpacked:
        raise ValueError("CPIO round-trip byte mismatch")
    d = {name: payload for _, _, name, payload, _ in records}
    if b"init.rc" not in d or b"sbin/charger" not in d:
        raise ValueError("Missing OEM init.rc or static charger")
    rc = d[b"init.rc"]
    if b"on charger\n    class_start charger" not in rc:
        raise ValueError("No old class_start charger trigger")
    if b"service charger " in rc or b"service kpoc_charger " in rc:
        raise ValueError("Existing charger service: abort")
    if rc.count(b"on charger\n") != 1:
        raise ValueError("Ambiguous charger trigger")
    new_rc = rc.rstrip(b"\n") + b"\n" + SERVICE + b"\n"
    new_cpio = serialize_cpio(records, trailer, {b"init.rc": new_rc})
    parsed, _ = cpio_records(new_cpio)
    parsed_d = {name: payload for _, _, name, payload, _ in parsed}
    if parsed_d[b"init.rc"] != new_rc:
        raise ValueError("Modified init.rc not readable")
    if set(d) != set(parsed_d) or any(d[k] != parsed_d[k] for k in d if k != b"init.rc"):
        raise ValueError("Unexpected non-init ramdisk change")
    new_r = gzip.compress(new_cpio, compresslevel=9, mtime=0)
    if roff + align(len(new_r), pg) > len(original):
        raise ValueError("Boot image would exceed its partition")
    image = bytearray(original)
    image[roff:] = b"\0" * (len(original) - roff)
    image[roff:roff + len(new_r)] = new_r
    struct.pack_into("<I", image, 16, len(new_r))
    # Exact OEM Android boot ID verified against stock 2018-07, 2018-10,
    # and the active 2020 boot: SHA1(kernel/len + ramdisk/len + second/len).
    def boot_id(k, r):
        sha = hashlib.sha1()
        for part in (k, r, b""):
            sha.update(part)
            sha.update(struct.pack("<I", len(part)))
        return sha.digest()

    if original[576:596] != boot_id(orig_k, orig_r):
        raise ValueError("Original boot header ID failed OEM 3-image test")
    image[576:596] = boot_id(orig_k, new_r)
    if image[koff:koff + ks] != orig_k:
        raise ValueError("Kernel changed unexpectedly")
    return bytes(image), len(rc), len(new_rc), len(orig_r), len(new_r)

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--build", action="store_true", help="write one private, UNFLASHED experimental image")
    ap.add_argument("--output", type=Path, default=None, help="explicit output path, only with --build")
    args = ap.parse_args()
    root = Path(__file__).resolve().parents[1]
    src = root / "backups/device-2026-10-09/boot-active.bin"
    img, before, after, oldr, newr = build(src.read_bytes())
    print("OFFLINE_ONLY; NEVER FLASH AT LOW BATTERY")
    print(f"init.rc bytes: {before} -> {after}; ramdisk gzip: {oldr} -> {newr}")
    print(f"boot candidate SHA256: {hashlib.sha256(img).hexdigest()}")
    if args.build:
        dest = args.output or (root / "files/candidates/boot-s55-kpoc-UNFLASHED-EXPERIMENTAL.img")
        if dest.exists():
            raise SystemExit(f"Output already exists; refusing to overwrite: {dest}")
        dest.parent.mkdir(parents=True, exist_ok=True)
        fd, temporary = tempfile.mkstemp(prefix=".s55-kpoc-", dir=dest.parent)
        try:
            os.fchmod(fd, 0o600)
            with os.fdopen(fd, "wb") as out:
                out.write(img)
                out.flush()
                os.fsync(out.fileno())
            os.replace(temporary, dest)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
        print(f"EXPERIMENTAL_CANDIDATE_CREATED {dest}")
    else:
        print("PASS dry-run; no output file written; no phone access")

if __name__ == "__main__":
    main()
