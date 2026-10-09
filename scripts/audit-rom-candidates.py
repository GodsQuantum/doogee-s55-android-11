#!/usr/bin/env python3
"""Read-only static audit of locally downloaded DOOGEE S55 GSI images.

No adb, fastboot, mounts, flash operations, automatic downloads, or edits.
The absolute working directory is derived from this repository location.
"""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import re
import subprocess
import sys

PROJECT = Path(__file__).resolve().parent.parent
ROOT = PROJECT.parent
IMAGES = {
    "crDroid11-GApps": "crdrom-v316-220330-arm64-agZ.img",
    "LineageOS18-Vanilla": "los18.img",
    "LineageOS20-Vanilla": "gsi_los20.img",
}
# Read-only geometry observed via MTKClient on 2026-10-09. Actual layout must be rechecked
# before reflashing anything, especially after switching to another firmware image.
SYSTEM_PARTITION_BYTES = int("c2800000", 16)


def debugfs(image: Path, request: str) -> str:
    p = subprocess.run(
        ["debugfs", "-R", request, str(image)],
        capture_output=True, text=True, timeout=18, check=False,
    )
    return p.stdout


def parse_props(text: str) -> dict[str, str]:
    return dict(
        pair for line in text.splitlines()
        if "=" in line and not line.startswith("#")
        for pair in [tuple(line.split("=", 1))]
    )


def get_prop(props: dict[str, str], suffix: str) -> str:
    return (
        props.get("ro.system." + suffix)
        or props.get("ro." + suffix)
        or "<unknown>"
    )


def sha256sum(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def identify(image: Path, hashing: bool) -> dict[str, object]:
    if not image.is_file():
        raise FileNotFoundError(image)
    if image.is_symlink():
        raise ValueError(f"Refusing symlink: {image}")
    size = image.stat().st_size
    sar_root = debugfs(image, "stat /init")
    sar_init = debugfs(image, "stat /system/bin/init")
    is_sar = "Inode:" in sar_root and "Inode:" in sar_init
    system_path = "/system/build.prop" if is_sar else "/build.prop"
    prop_text = debugfs(image, "cat " + system_path)
    if "ro.build.version.release" not in prop_text:
        # Distinguish missing file from unknown layout without guessing.
        raise ValueError(f"Cannot parse build.prop in {image.name} at {system_path}")
    props = parse_props(prop_text)
    return {
        "file": image.name,
        "size_bytes": size,
        "system_partition_bytes": SYSTEM_PARTITION_BYTES,
        "fits_current_system_partition": size <= SYSTEM_PARTITION_BYTES,
        "free_space_mib": round((SYSTEM_PARTITION_BYTES - size) / 1048576, 1),
        "architecture": get_prop(props, "product.cpu.abi"),
        "android": get_prop(props, "build.version.release"),
        "sdk": get_prop(props, "build.version.sdk"),
        "security_patch": get_prop(props, "build.version.security_patch"),
        "layout": "SAR / system-as-root" if is_sar else "non-SAR",
        "build": get_prop(props, "build.description"),
        **({"sha256": sha256sum(image)} if hashing else {}),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hash", action="store_true",
                        help="Compute SHA-256 for huge images (slow over NFS)")
    options = parser.parse_args()
    print("S55 static ROM compatibility inventory — NO PHONE ACTION")
    print(f"Project: {PROJECT}")
    print(f"Working images: {ROOT}")
    print(f"Current system partition: {SYSTEM_PARTITION_BYTES} bytes")
    errors = 0
    for name, relative_name in IMAGES.items():
        print(f"\n[{name}]")
        try:
            metadata = identify(ROOT / relative_name, options.hash)
            for key, value in metadata.items():
                print(f"{key}: {value}")
            if metadata["layout"] != "non-SAR":
                print("WARNING: Not a drop-in image on the stock S55 boot layout.")
            if not metadata["fits_current_system_partition"]:
                print("WARNING: Too big; new GPT is required, never flash as-is.")
        except (ValueError, FileNotFoundError, subprocess.TimeoutExpired) as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            errors += 1
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
