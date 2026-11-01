#!/usr/bin/env python3
"""Offline S55 artwork-to-MTK-logo compiler. No device access or third-party libs.

Only LOW_BATTERY_INDEX=2 is replaced; overvoltage and every other frame
must remain exactly identical. Reuses the existing format-aware MTK packer.
"""
import argparse
import hashlib
import importlib.util
import os
import struct
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
MOD = HERE / "patch-s55-logo-neutral-charging.py"
spec = importlib.util.spec_from_file_location("s55_mtk_logo", MOD)
mtk = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mtk)
SIZE = (720, 1440)
PREFIX = b"\x89PNG\r\n\x1a\n"


def png_read_rgb(path):
    data = path.read_bytes()
    if not data.startswith(PREFIX) or len(data) > 32 * 1024 * 1024:
        raise ValueError("Expected ordinary PNG under 32 MiB")
    pos = 8
    w = h = None
    chunks = []
    while pos + 12 <= len(data):
        n = struct.unpack_from(">I", data, pos)[0]
        kind = data[pos + 4:pos + 8]
        end = pos + 12 + n
        if end > len(data):
            raise ValueError("Truncated PNG chunk")
        value = data[pos + 8:pos + 8 + n]
        expected_crc = struct.unpack_from(">I", data, pos + 8 + n)[0]
        if zlib.crc32(kind + value) & 0xFFFFFFFF != expected_crc:
            raise ValueError("PNG chunk CRC invalid")
        if kind == b"IHDR":
            w, h, depth, ctype, compression, filt, interlace = struct.unpack(">IIBBBBB", value)
            if (depth, ctype, compression, filt, interlace) != (8, 2, 0, 0, 0):
                raise ValueError("Only 8-bit noninterlaced RGB PNG supported")
            if not (200 <= w <= 4096 and 200 <= h <= 4096):
                raise ValueError("Unexpected artwork dimensions")
        elif kind == b"IDAT":
            chunks.append(value)
        elif kind == b"IEND":
            break
        pos = end
    if not w or not chunks:
        raise ValueError("Missing RGB dimensions / pixel data")
    stride = w * 3
    decompressor = zlib.decompressobj()
    packed = decompressor.decompress(b"".join(chunks), (stride + 1) * h + 1)
    packed += decompressor.flush()
    if len(packed) != (stride + 1) * h:
        raise ValueError("Unexpected PNG uncompressed byte count")
    raw = bytearray(stride * h)
    prev = bytearray(stride)
    offset = 0
    for y in range(h):
        ftype = packed[offset]
        offset += 1
        row = bytearray(packed[offset:offset + stride])
        offset += stride
        if ftype == 1:
            for i in range(3, stride):
                row[i] = (row[i] + row[i - 3]) & 255
        elif ftype == 2:
            for i in range(stride):
                row[i] = (row[i] + prev[i]) & 255
        elif ftype == 3:
            for i in range(stride):
                row[i] = (row[i] + ((row[i - 3] if i >= 3 else 0) + prev[i]) // 2) & 255
        elif ftype == 4:
            for i in range(stride):
                a = row[i - 3] if i >= 3 else 0
                b, c = prev[i], (prev[i - 3] if i >= 3 else 0)
                pred = a + b - c
                pa, pb, pc = abs(pred - a), abs(pred - b), abs(pred - c)
                v = a if pa <= pb and pa <= pc else b if pb <= pc else c
                row[i] = (row[i] + v) & 255
        elif ftype != 0:
            raise ValueError("Invalid PNG filter")
        raw[y * stride:(y + 1) * stride] = row
        prev = row
    return w, h, raw


def artwork_bgra(w, h, rgb):
    """Center-crop native portrait aspect, then fill all 720x1440 pixels.

    Use a full-height portrait source crop (not a square with padded
    borders).  For the 3000x3000 source, a 1050x2100 centered crop
    enlarges the blue sigil while preserving the vertical composition.
    Apply bilinear resampling rather than nearest-neighbor stretching.
    """
    cw = min(w, round(min(h, w * 2) * 0.35))
    ch = cw * 2
    if ch > h:
        ch = h
        cw = ch // 2
    left, top = (w - cw) // 2, (h - ch) // 2
    out = bytearray(SIZE[0] * SIZE[1] * 4)
    for y in range(SIZE[1]):
        fy = (y + .5) * ch / SIZE[1] - .5
        y0 = max(0, min(ch - 1, int(fy)))
        y1 = min(ch - 1, y0 + 1)
        wy = max(0.0, min(1.0, fy - y0))
        row0, row1 = (top + y0) * w * 3, (top + y1) * w * 3
        for x in range(SIZE[0]):
            fx = (x + .5) * cw / SIZE[0] - .5
            x0 = max(0, min(cw - 1, int(fx)))
            x1 = min(cw - 1, x0 + 1)
            wx = max(0.0, min(1.0, fx - x0))
            i00 = row0 + (left + x0) * 3
            i10 = row0 + (left + x1) * 3
            i01 = row1 + (left + x0) * 3
            i11 = row1 + (left + x1) * 3
            dst = (y * SIZE[0] + x) * 4
            for chan in range(3):
                up = rgb[i00 + chan] * (1 - wx) + rgb[i10 + chan] * wx
                down = rgb[i01 + chan] * (1 - wx) + rgb[i11 + chan] * wx
                v = int(up * (1 - wy) + down * wy + .5)
                out[dst + (2 - chan)] = v
            out[dst + 3] = 255
    return bytes(out)


def preview_png(bitmap):
    w, h = SIZE
    scan = bytearray()
    for y in range(h):
        scan.append(0)
        base = y * w * 4
        for x in range(w):
            i = base + x * 4
            scan.extend((bitmap[i + 2], bitmap[i + 1], bitmap[i]))
    def chunk(tag, value):
        return (struct.pack(">I", len(value)) + tag + value
                + struct.pack(">I", zlib.crc32(tag + value) & 0xFFFFFFFF))
    return (PREFIX + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(scan, 9))
            + chunk(b"IEND", b""))


def write_new_private(path, payload):
    with path.open("xb") as f:
        f.write(payload)
    path.chmod(0o600)
    print(path, len(payload), hashlib.sha256(payload).hexdigest())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("original", type=Path, help="EXACT OEM logo partition image")
    ap.add_argument("artwork", type=Path, help="Source RGB PNG")
    ap.add_argument("output", type=Path, help="8 MiB custom logo candidate")
    ap.add_argument("preview", type=Path, help="720x1440 PNG optical preview")
    ap.add_argument("--source-sha256", required=True)
    a = ap.parse_args()
    if hashlib.sha256(a.artwork.read_bytes()).hexdigest() != a.source_sha256:
        raise ValueError("The user's artwork changed from approved source")
    w, h, pixels = png_read_rgb(a.artwork)
    bitmap = artwork_bgra(w, h, pixels)
    assert len(bitmap) == mtk.PIXELS
    candidate = mtk.repack(a.original.read_bytes(), bitmap)
    assert len(candidate) == mtk.PART_SIZE
    write_new_private(a.preview, preview_png(bitmap))
    write_new_private(a.output, candidate)
    print("OFFLINE ONLY / NEVER FLASHED — original OEM warning frames intact")


if __name__ == "__main__":
    main()
