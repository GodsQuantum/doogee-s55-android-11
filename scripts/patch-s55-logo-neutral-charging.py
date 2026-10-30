#!/usr/bin/env python3
"""Repack exactly the OEM DOOGEE S55 MTK logo partition offline.

Change ONLY static LOW_BATTERY_INDEX=2 (shown unconditionally on charger).
Replace misleading zero-charge picture with neutral charging *bolt*, no SOC.
Overvoltage warning CHARGER_OV_INDEX=3 and all 37 other assets untouched.
NEVER touches a device; output is a verified new file.
"""
import argparse
import hashlib
import struct
import zlib
from pathlib import Path

ORIGINAL_SHA="7d887a58f3ef55675194cf3a54ae2b6e67e1f926465aa1808e48e4f48f796499"
PART_SIZE=8388608
OUTER=512
SPRITES=39
LOW_BATTERY_INDEX=2
CHARGER_OV_INDEX=3
PIXELS=720*1440*4

def digest(b):return hashlib.sha256(b).hexdigest()

def unpack(part):
    if len(part)!=PART_SIZE or digest(part)!=ORIGINAL_SHA:
        raise ValueError("Refuse unknown S55 logo partition")
    if struct.unpack_from('<I',part)[0]!=0x58881688 or part[8:12]!=b'logo':
        raise ValueError("Unrecognized MTK logo wrapper")
    outer_size=struct.unpack_from('<I',part,4)[0]
    n,total=struct.unpack_from('<II',part,OUTER)
    if n!=SPRITES or total!=outer_size or total>len(part)-OUTER:
        raise ValueError("MTK logo header invalid")
    offsets=struct.unpack_from('<39I',part,OUTER+8)
    if offsets[0]!=8+SPRITES*4 or tuple(sorted(offsets))!=offsets:
        raise ValueError("Unsorted sprite offsets")
    compressed=[]
    for i in range(n):
        start=OUTER+offsets[i]
        end=OUTER+(offsets[i+1] if i+1<n else total)
        if end<=start:raise ValueError("Invalid sprite bounds")
        z=part[start:end]
        data=zlib.decompress(z)
        if i in (2,3) and len(data)!=PIXELS:
            raise ValueError("Unexpected low battery or overvoltage bitmap size")
        compressed.append(z)
    return compressed

def polygon(x,y,pts):
    flag=False
    j=len(pts)-1
    for i in range(len(pts)):
        xi,yi=pts[i];xj,yj=pts[j]
        if (yi>y)!=(yj>y) and x<(xj-xi)*(y-yi)/(yj-yi)+xi:
            flag=not flag
        j=i
    return flag

def neutral_bitmap():
    # BGRA8888; neutral power symbol without any charge-level implication.
    raw=bytearray(b'\x00\x00\x00\xff'*(720*1440))
    cx,cy=360,720
    pts=[(375,610),(311,723),(357,723),(345,830),(414,698),(372,698),(395,610)]
    for y in range(580,856):
        for x in range(236,485):
            dx=x-cx;dy=y-cy;d2=dx*dx+dy*dy
            ring=(114*114>=d2>=110*110)
            bolt=polygon(x+.5,y+.5,pts)
            if not ring and not bolt:continue
            a=(y*720+x)*4
            if bolt:raw[a:a+4]=bytes((245,245,245,255))
            else:raw[a:a+4]=bytes((151,151,151,255))
    return bytes(raw)

def repack(part):
    original=unpack(part)
    compressed=list(original)
    compressed[LOW_BATTERY_INDEX]=zlib.compress(neutral_bitmap(),9)
    offsets=[];position=8+SPRITES*4
    for blob in compressed:
        offsets.append(position)
        position+=len(blob)
    content=struct.pack('<II',SPRITES,position)
    content+=struct.pack('<39I',*offsets)+b''.join(compressed)
    if len(content)!=position or OUTER+len(content)>PART_SIZE:
        raise ValueError("Repack invalid size")
    prefix=bytearray(part[:OUTER])
    struct.pack_into('<I',prefix,4,position)
    out=bytes(prefix)+content+bytes(PART_SIZE-OUTER-len(content))
    # Complete readback validation using original decompressed sprites.
    n,total=struct.unpack_from('<II',out,OUTER)
    assert n==SPRITES and total==position
    spans=struct.unpack_from('<39I',out,OUTER+8)
    for i in range(n):
        lo=OUTER+spans[i]
        hi=OUTER+(spans[i+1] if i+1<n else total)
        v=zlib.decompress(out[lo:hi])
        if i==LOW_BATTERY_INDEX:
            assert v==neutral_bitmap()
        else:
            assert v==zlib.decompress(original[i])
    assert out[:4]==part[:4] and out[8:OUTER]==part[8:OUTER]
    return out

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('original',type=Path)
    ap.add_argument('output',type=Path)
    a=ap.parse_args()
    candidate=repack(a.original.read_bytes())
    with a.output.open('xb') as o:o.write(candidate)
    a.output.chmod(0o600)
    print('MTK 39-sprite neutral charging candidate ONLY, NOT FLASHED',
          digest(candidate),len(candidate))

if __name__=='__main__':main()
