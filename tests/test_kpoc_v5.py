#!/usr/bin/env python3
"""V5 is offline-only: verify OEM order LED off -> FB blank, without phone."""
import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT=pathlib.Path(__file__).resolve().parents[1]
CLANG=shutil.which("clang")

class V5OemOrderTests(unittest.TestCase):
    def test_oem_order_and_privileged_domains(self):
        bridge=(ROOT/"scripts/s55-kpoc-bridge.rc").read_text()
        led=(ROOT/"scripts/s55-kpoc-lcd-off.rc").read_text()
        fb=(ROOT/"scripts/s55-kpoc-fb-off.rc").read_text()
        source=(ROOT/"scripts/kpoc-s55-bridge.c").read_text()
        fbsrc=(ROOT/"scripts/kpoc-s55-fb-off.c").read_text()
        self.assertIn("on property:init.svc.s55_kpoc_bridge=stopped\n    start s55_kpoc_lcd_off",bridge)
        self.assertIn("on property:init.svc.s55_kpoc_lcd_off=stopped\n    start s55_kpoc_fb_off",led)
        self.assertIn("service s55_kpoc_fb_off /vendor/bin/s55_kpoc_fb_off",fb)
        self.assertIn("    disabled\n    oneshot",fb)
        self.assertIn("seclabel u:r:charger:s0",fb)
        self.assertIn("seclabel u:r:mtk_hal_light:s0",led)
        self.assertIn("if(n==6){\n   logmsg(",source)
        self.assertNotIn("if(fb)sc_ioctl(f,FBIOBLANK,(void *)4);",source)
        self.assertIn("FBIOBLANK,4",fbsrc)
        self.assertIn("lcd-backlight/brightness",(ROOT/"scripts/kpoc-s55-lcd-off.c").read_text())
        self.assertNotIn("/sys/power/",source+fbsrc)
        self.assertNotIn("/sys/class/power_supply/",fbsrc)

    @unittest.skipUnless(CLANG,"clang unavailable")
    def test_fb_helper_safe_failure_status(self):
        with tempfile.TemporaryDirectory(prefix="kpoc-v5-fbioctl-") as directory:
            d=pathlib.Path(directory)
            exe=d/"helper"
            for path,expected in (("/dev/null",11),(str(d/"absent"),10)):
                args=[
                    CLANG,"--target=x86_64-linux-gnu","-Os","-static",
                    "-fno-stack-protector","-fno-builtin","-ffreestanding","-nostdlib",
                    "-fuse-ld=lld","-Wl,-e,_start","-Wl,--build-id=none",
                    "-Wall","-Wextra","-Werror",f'-DFB_PATH="{path}"',
                    str(ROOT/"scripts/kpoc-s55-fb-off.c"),"-o",str(exe),
                ]
                subprocess.run(args,check=True,capture_output=True)
                p=subprocess.run([str(exe)],capture_output=True,timeout=2)
                self.assertEqual(p.returncode,expected)

if __name__=="__main__":
    unittest.main()
