#!/usr/bin/env python3
"""Portable stdin->stdout binary stream with bounded, visible progress.

Used only when pv is absent. No dependency, daemon, or extra disk copy.
"""
from __future__ import annotations

import os
import sys
import time


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: progress-stream.py EXPECTED_BYTES", file=sys.stderr)
        return 2
    expected = int(sys.argv[1])
    if expected <= 0:
        return 2
    done = 0
    started = time.monotonic()
    last = started
    reader = sys.stdin.buffer
    writer = sys.stdout.buffer
    try:
        while True:
            block = reader.read(1024 * 1024)
            if not block:
                break
            writer.write(block)
            done += len(block)
            now = time.monotonic()
            if now - last >= 0.7:
                pct = min(100.0, done * 100.0 / expected)
                rate = done / max(0.001, now - started) / 1048576
                sys.stderr.write(f"\rFlashing stream: {pct:5.1f}%  {done}/{expected} bytes  {rate:.1f} MiB/s")
                sys.stderr.flush()
                last = now
        writer.flush()
    except BrokenPipeError:
        print("\nTransfer stopped: consumer closed the stream", file=sys.stderr)
        return 1
    print(f"\rFlashing stream complete: {done}/{expected} bytes", file=sys.stderr)
    return 0 if done == expected else 1


if __name__ == "__main__":
    raise SystemExit(main())
