#!/usr/bin/env python3
"""Offline-only tests: S55 KPOC v4 (never connects to an Android device)."""
import importlib.util
import pathlib
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT=pathlib.Path(__file__).resolve().parents[1]
STAGE=ROOT/"files/candidates/kpoc-v4-stage"
SPEC=importlib.util.spec_from_file_location("plan",ROOT/"scripts/kpoc-v4-vendor-plan.py")
PLAN=importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PLAN)
CLANG=shutil.which("clang")

class V4Tests(unittest.TestCase):
    def test_live_config_patch_minimal_diffs(self):
        # The input files were captured read-only from the device, hash-pinned.
        old=STAGE/"init.mt6755.rc"
        fcs=STAGE/"nonplat_file_contexts"
        if not old.exists() or not fcs.exists():
            self.skipTest("private phone snapshots not present")
        patched=PLAN.safe_patch_vendor_init(old.read_bytes())
        newfcs=PLAN.safe_patch_file_contexts(fcs.read_bytes())
        self.assertEqual(PLAN.digest(patched),"7fd3d9fd6bbf8f11ea9d1f65c1ceb19b0ffefd81381412f8cf0453f086e9c103")
        self.assertEqual(PLAN.digest(newfcs),"51f943a60b4571f14f5d08f914aea4af857c4e04d4316d5272563ec75c6d473c")
        self.assertIn(b"# KPOC: skip servmgr",patched)
        # The normal Android fuelgauged service is defined in another RC file.
        # This patch modifies ONLY the charger action, not that definition.
        self.assertIn(b"start spm_script",patched)
        self.assertNotIn(b"start servicemanager",patched)
        self.assertEqual(newfcs[:len(fcs.read_bytes())], fcs.read_bytes())
        # Ensure SELinux file_contexts uses literal tabs, not slash-t sequences.
        tail=newfcs[len(fcs.read_bytes()):]
        self.assertEqual(tail.count(b"\t"),4)
        self.assertIn(b"u:object_r:fuelgauged_exec:s0",tail)
        self.assertIn(b"u:object_r:mtk_hal_light_exec:s0",tail)
        for data in [old.read_bytes()+b"tamper",fcs.read_bytes()+b"tamper"]:
            with self.assertRaises(ValueError):
                (PLAN.safe_patch_vendor_init if b"on charger" in data else PLAN.safe_patch_file_contexts)(data)

    def test_init_actions_and_no_charging_control(self):
        bridge=(ROOT/"scripts/s55-kpoc-bridge.rc").read_text()
        fg=(ROOT/"scripts/s55-kpoc-fuelgauged.rc").read_text()
        led=(ROOT/"scripts/s55-kpoc-lcd-off.rc").read_text()
        c=(ROOT/"scripts/kpoc-s55-lcd-off.c").read_text()
        self.assertIn("on property:init.svc.s55_kpoc_bridge=stopped\n    start s55_kpoc_lcd_off",bridge)
        self.assertNotIn("write /sys/class/leds/lcd-backlight/brightness",bridge)
        self.assertIn("service s55_kpoc_fuelgauged /vendor/bin/s55_kpoc_fuelgauged_static",fg)
        self.assertIn("seclabel u:r:fuelgauged:s0",fg)
        self.assertIn("oneshot",fg)
        self.assertIn("service s55_kpoc_lcd_off /vendor/bin/s55_kpoc_lcd_off",led)
        self.assertIn("seclabel u:r:mtk_hal_light:s0",led)
        # Charger-class startup must not depend solely on init.svc properties.
        self.assertIn("class charger",led)
        self.assertNotIn("\n    disabled\n",led)
        self.assertIn("oneshot",led)
        self.assertNotIn("/sys/power/autosleep",c)
        self.assertNotIn("/sys/class/power_supply",c)
        self.assertNotIn("reboot",c)
        self.assertNotIn("poweroff",c)

    def test_binary_hashes(self):
        for file,expected in [
            ("s55_kpoc_fuelgauged_static","47d62c2e608cc7dcd709b44da98fe92d5e793f1f321a8fb0d47a055db10e9b07"),
            ("s55_kpoc_lcd_off","4f8218c1ce96cdc9f692f1442a6f709a516af3fc438363e3abdac9f25de8940a"),
        ]:
            f=STAGE/file
            if f.exists():
                self.assertEqual(PLAN.digest(f.read_bytes()),expected)

    @unittest.skipUnless(CLANG, "clang not available")
    def test_lcd_helper_simulated_no_phone(self):
        with tempfile.TemporaryDirectory(prefix="s55-v4-lcd-") as tmp:
            root=pathlib.Path(tmp)
            led=root/"sys/class/leds/lcd-backlight/brightness"
            led.parent.mkdir(parents=True)
            out=root/"helper"
            args=[
                CLANG, "--target=x86_64-linux-gnu", "-Os", "-static",
                "-fno-stack-protector", "-fno-builtin", "-ffreestanding",
                "-nostdlib", "-fuse-ld=lld", "-Wl,-e,_start",
                "-Wl,--build-id=none", "-Wall", "-Wextra", "-Werror",
                "-DTEST_LOCAL_REGULAR_FILE",
                f'-DSYSFS_ROOT="{root}"',
                str(ROOT/"scripts/kpoc-s55-lcd-off.c"),"-o",str(out),
            ]
            subprocess.run(args,check=True,capture_output=True)
            for before in ("58\n","0\n","255\n"):
                led.write_text(before)
                proc=subprocess.run([str(out)],capture_output=True,timeout=3)
                self.assertEqual(proc.returncode,0,repr(proc.stderr))
                self.assertTrue(led.read_text().startswith("0\n"))
            led.unlink()
            proc=subprocess.run([str(out)],capture_output=True,timeout=3)
            self.assertEqual(proc.returncode,10)

    def test_real_oem_policy_rules_if_available(self):
        cil=pathlib.Path("/tmp/s55-vendor-cil-20261030.txt")
        if not cil.exists():self.skipTest("OEM CIL unavailable")
        s=cil.read_text()
        for fragment in [
            "(typetransition init_26_0 fuelgauged_exec process fuelgauged)",
            "(allow fuelgauged fuelgauged_exec (file (read getattr execute entrypoint open)))",
            "(typetransition init_26_0 mtk_hal_light_exec process mtk_hal_light)",
            "(allow mtk_hal_light mtk_hal_light_exec (file (read getattr execute entrypoint open)))",
            "(allow mtk_hal_light sysfs_26_0 (file (ioctl read write getattr lock append open)))",
        ]:self.assertIn(fragment,s)

if __name__=="__main__":
    unittest.main()
