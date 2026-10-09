#!/usr/bin/env python3
"""Analyze Android boot v0 ramdisk/kernel without modifying images.

Usage: python3 scripts/analyze-s55-active-boot.py
Only reads local known backup and original firmware references.
"""
from pathlib import Path
from hashlib import sha256
import gzip
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT.parent
active = ROOT / "backups/device-2026-10-09/boot-active.bin"
stock = sorted((PROJECT / "Doogee S55").rglob("boot.img"))
lk_active = ROOT / "backups/device-2026-10-09/lk-active.bin"
lk2_active = ROOT / "backups/device-2026-10-09/lk2-active.bin"
lk_stock = sorted((PROJECT / "Doogee S55").rglob("lk.img"))

def h(data):
    return sha256(data).hexdigest()

def parse_cpio(data):
    result = {}
    pos = 0
    while pos + 110 < len(data):
        if data[pos:pos + 6] not in (b"070701", b"070702"):
            pos += 4
            continue
        try:
            fields = [int(data[pos + 6 + i * 8:pos + 14 + i * 8], 16) for i in range(13)]
        except ValueError:
            break
        filesize, namesize = fields[6], fields[11]
        if not namesize or namesize > 2000 or filesize > len(data):
            break
        name = data[pos+110:pos+110+namesize].rstrip(b"\0").decode(errors="replace")
        start = (pos + 110 + namesize + 3) & ~3
        result[name] = data[start:start+filesize]
        pos = (start + filesize + 3) & ~3
        if name == "TRAILER!!!":
            break
    return result

def ikconfig(kernel):
    image = kernel
    idx = image.find(b"IKCFG_ST")
    if idx == -1 and kernel.startswith(b"\x1f\x8b"):
        try:
            image = zlib.decompressobj(16 + zlib.MAX_WBITS).decompress(kernel)
            idx = image.find(b"IKCFG_ST")
        except zlib.error:
            return "<kernel decompression failed>"
    if idx == -1:
        return "<not found>"
    try:
        return zlib.decompressobj(16 + zlib.MAX_WBITS).decompress(image[idx+8:]).decode(errors="replace")
    except zlib.error:
        return "<configuration decompression failed>"

def parse_boot(path):
    b = path.read_bytes()
    if b[:8] != b"ANDROID!":
        raise ValueError(f"Not Android boot image: {path}")
    ks, rs, pg = (struct.unpack_from("<I", b, offset)[0] for offset in (8,16,36))
    if pg not in (2048,4096,8192,16384) or rs >= len(b) or ks >= len(b):
        raise ValueError(f"Invalid Android boot header: {path}")
    koff = ((1648 + pg - 1)//pg)*pg
    roff = koff + ((ks + pg -1)//pg)*pg
    kernel, raw_rd = b[koff:koff+ks], b[roff:roff+rs]
    try:
        rd = gzip.decompress(raw_rd)
    except Exception as exc:
        raise ValueError(f"Unrecognized ramdisk compression in {path}: {exc}") from exc
    return dict(path=path, image=b, kernel=kernel, ramdisk=raw_rd, entries=parse_cpio(rd), config=ikconfig(kernel),
                ks=ks, rs=rs, pg=pg)

if __name__ == "__main__":
    if not all(p.is_file() for p in (active, lk_active, lk2_active)):
        raise SystemExit("Private device backup missing: backups/device-2026-10-09/boot-active.bin, lk-active.bin or lk2-active.bin")
    boots = [parse_boot(active)] + [parse_boot(p) for p in stock]
    interesting = ("CONFIG_MTK_KERNEL_POWER_OFF_CHARGING", "CONFIG_MTK_SMART_BATTERY", "CONFIG_MTK_HAFG_20",
                   "CONFIG_POWER_SUPPLY")
    for b in boots:
        print("\n=== BOOT", b["path"], "===")
        print("IMAGE_BYTES",len(b["image"]), "SHA256",h(b["image"]))
        print("KERNEL_BYTES",b["ks"], "SHA256",h(b["kernel"]))
        print("RAMDISK_BYTES",b["rs"], "SHA256",h(b["ramdisk"]), "ENTRIES",len(b["entries"]))
        for k in interesting:
            match = next((line for line in b["config"].splitlines() if line.startswith(k+"=")), "<missing>")
            print("CONFIG",k,match)
        for name in ("sbin/charger","sbin/fuelgauged_static","init.rc","factory_init.rc","default.prop"):
            data=b["entries"].get(name)
            print("RAMDISK_FILE",name, "MISSING" if data is None else "BYTES=%d SHA256=%s"%(len(data),h(data)))
        for name in ("init.rc","factory_init.rc"):
            data = b["entries"].get(name,b"").decode(errors="replace").splitlines()
            for idx, line in enumerate(data):
                if "on charger" in line or "class_start charger" in line or "sys.boot_from_charger_mode" in line:
                    print("CHARGING_INIT",name,idx+1,line.strip())
    print("\n=== ACTIVE VS STOCK COMPARISON ===")
    for b in boots[1:]:
        print(b["path"].parent.name)
        print("same_kernel",boots[0]["kernel"]==b["kernel"])
        print("same_ramdisk",boots[0]["ramdisk"]==b["ramdisk"])
        for name in ("sbin/charger","sbin/fuelgauged_static","init.rc","factory_init.rc"):
            x,y=boots[0]["entries"].get(name),b["entries"].get(name)
            print("same",name,x is not None and x==y)
    print("\n=== ACTIVE LK COMPARISON ===")
    if lk_active.read_bytes() != lk2_active.read_bytes():
        print("WARNING: lk and lk2 differ")
    else:
        print("lk_eq_lk2",True)
    for p in lk_stock:
        stock_data=p.read_bytes()
        active_data=lk_active.read_bytes()
        print("reference",p.parent.name,"stock_bytes",len(stock_data),"active_bytes",len(active_data),
              "exact_prefix",active_data.startswith(stock_data),
              "trailing_zero_padding", all(x==0 for x in active_data[len(stock_data):]),
              "effective_bytes_equal",active_data.rstrip(b"\0")==stock_data.rstrip(b"\0"))
