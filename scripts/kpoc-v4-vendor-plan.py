#!/usr/bin/env python3
"""Pure offline manifest transformation for DOOGEE S55 KPOC v4.

Input files must come from the *current* S55 /vendor, not legacy OEM backups.
No ADB or filesystem writes to phone; pass --make staging_dir to write output.
"""
import argparse
import hashlib
import pathlib
import re

EXPECTED_CURRENT_INIT = "c5b3584a4d232ac7386704883d6f5c5f8e7c4867bccc99a46f36d2e0c58d3d84"
EXPECTED_CURRENT_CONTEXTS = "fece3829c645c556ef4315377773af4dd5e6eb34cde9dfe36bc10d42a2819b03"
KPOC_FG_LINE = r"/(system\/vendor|vendor)/bin/s55_kpoc_fuelgauged_static" + "\t\t" + "u:object_r:fuelgauged_exec:s0"
KPOC_LED_LINE = r"/(system\/vendor|vendor)/bin/s55_kpoc_lcd_off" + "\t\t" + "u:object_r:mtk_hal_light_exec:s0"

def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def safe_patch_vendor_init(data: bytes) -> bytes:
    if digest(data) != EXPECTED_CURRENT_INIT:
        raise ValueError("unexpected vendor init sha; refuse modification")
    text = data.decode("utf-8")
    match = re.search(r"(?ms)^on charger\n(.*?)(?=^on [^\n]+\n|\Z)", text)
    if not match:
        raise ValueError("charger action not found")
    block = match.group(1)
    if block.count("    start fuelgauged\n") != 1:
        raise ValueError("expected single charger start fuelgauged")
    if "start servicemanager" in block:
        raise ValueError("servicemanager reboot regression")
    replaced = block.replace("    start fuelgauged\n",
                             "    # KPOC: legacy dynamic fuelgauged is unavailable before Android late-init\n", 1)
    result = (text[:match.start(1)] + replaced + text[match.end(1):]).encode("utf-8")
    if result.count(b"start fuelgauged") != data.count(b"start fuelgauged") - 1:
        raise ValueError("unexpected fuelgauged occurrence count")
    return result

def safe_patch_file_contexts(data: bytes) -> bytes:
    if digest(data) != EXPECTED_CURRENT_CONTEXTS:
        raise ValueError("unexpected vendor file contexts sha; refuse modification")
    text = data.decode("utf-8")
    if "s55_kpoc_fuelgauged_static" in text or "s55_kpoc_lcd_off" in text:
        raise ValueError("context already defined")
    if "u:object_r:fuelgauged_exec:s0" not in text or "u:object_r:mtk_hal_light_exec:s0" not in text:
        raise ValueError("target SELinux domains not found")
    if not text.endswith("\n"):
        raise ValueError("file contexts lacks expected newline")
    return (text + KPOC_FG_LINE + "\n" + KPOC_LED_LINE + "\n").encode("utf-8")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--make", type=pathlib.Path, required=True,
                    help="directory with init.mt6755.rc and nonplat_file_contexts")
    args = ap.parse_args()
    src = args.make
    init = safe_patch_vendor_init((src/"init.mt6755.rc").read_bytes())
    labels = safe_patch_file_contexts((src/"nonplat_file_contexts").read_bytes())
    (src/"init.mt6755.v4.rc").write_bytes(init)
    (src/"nonplat_file_contexts.v4").write_bytes(labels)
    for name, contents in (("init.mt6755.v4.rc",init),("nonplat_file_contexts.v4",labels)):
        print(name,len(contents),digest(contents))

if __name__=="__main__":
    main()
