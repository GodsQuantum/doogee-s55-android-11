#!/usr/bin/env python3
"""Reproduce the S55 orange-warning text-only LK patch OFFLINE.

Never talks to a phone, flashes, changes lock bits, or edits input in place.
LK2 remains factory original. Do not use with other models.
"""
import argparse
import hashlib
from pathlib import Path

ORIGINAL_SHA256 = "5fe80cc3990fbe26f2f301792243c683ae9e976736f2b7bb9b7194e32bbb7dbc"
PATCHED_SHA256 = "22861f7b36f1ebb528f8f4a4c79fd1134bf21a7d0aa2410178f5846e552a9ac1"
WORDS = (
    b"Orange State",
    b"Your device has been unlocked and can't be trusted",
    b"Your device will boot in 5 seconds",
)

def sha(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()

def patch(source: bytes) -> bytes:
    if len(source) != 1048576 or sha(source) != ORIGINAL_SHA256:
        raise ValueError("Refuse unknown LK size/content")
    out=bytearray(source)
    for word in WORDS:
        if source.count(word)!=1:
            raise ValueError("Text not unique")
        offset=source.index(word)
        out[offset:offset+len(word)]=bytes(len(word))
    result=bytes(out)
    if sha(result)!=PATCHED_SHA256:
        raise ValueError("Refuse unexpected patch fingerprint")
    changes={i for i,(a,b) in enumerate(zip(source,result)) if a!=b}
    if len(changes)!=96 or changes & set(range(2048)):
        raise ValueError("Refuse non-cosmetic changes")
    return result

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("source",type=Path,help="1 MiB original LK partition backup")
    ap.add_argument("destination",type=Path,help="new patched candidate path only")
    args=ap.parse_args()
    out=patch(args.source.read_bytes())
    with args.destination.open("xb") as fd:
        fd.write(out)
    args.destination.chmod(0o600)
    print("OFFLINE LK PATCH ONLY:",len(out),"SHA256",sha(out))

if __name__=="__main__":
    main()
