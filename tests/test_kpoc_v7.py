#!/usr/bin/env python3
"""KPOC v7 hardware-safe, finite light-off attempt regression tests."""
import pathlib
import subprocess
import shutil
import tempfile
import unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
CC=shutil.which("clang")
class ChargingLEDV7Tests(unittest.TestCase):
    def test_charger_class_unconditional(self):
        rc=(ROOT/"scripts/s55-kpoc-lcd-off.rc").read_text()
        self.assertIn("service s55_kpoc_lcd_off /vendor/bin/s55_kpoc_lcd_off",rc)
        self.assertIn("on init\n    chown system system /sys/class/leds/lcd-backlight/brightness\n    chmod 0664 /sys/class/leds/lcd-backlight/brightness",rc)
        self.assertLess(rc.index("on init"),rc.index("service s55_kpoc_lcd_off"))
        self.assertIn("    class charger",rc)
        self.assertNotIn("\n    disabled\n",rc)
        self.assertIn("    oneshot",rc)
        self.assertIn("    seclabel u:r:mtk_hal_light:s0",rc)
        self.assertIn("on property:init.svc.s55_kpoc_lcd_off=stopped\n    start s55_kpoc_fb_off",rc)
        src=(ROOT/"scripts/kpoc-s55-lcd-off.c").read_text()
        self.assertEqual(src.count("led_off()"),3) # Three finite writes
        self.assertIn("pause_ms(450)",src)
        self.assertIn("pause_ms(650)",src)
        self.assertNotIn("/sys/power/",src)
        self.assertNotIn("/dev/mem",src)
    def test_fg_charger_log_only(self):
        old=(ROOT/"files/candidates/kpoc-v4-stage/init.mt6755.v4.rc").read_text()
        new=(ROOT/"files/candidates/kpoc-v7-init-LOWLOG-UNINSTALLED.rc").read_text()
        k=old.index("on charger\n")
        self.assertEqual(new,old[:k]+old[k:].replace("FG_daemon_log_level 7","FG_daemon_log_level 2",1))
        self.assertIn("# KPOC: legacy dynamic fuelgauged is unavailable",new)
        self.assertIn("# KPOC: skip servmgr",new)
    @unittest.skipUnless(CC,"clang absent")
    def test_mock_three_write_attempts(self):
        with tempfile.TemporaryDirectory(prefix="kpoc-v7-light-") as d:
            path=pathlib.Path(d)
            led=path/"sys/class/leds/lcd-backlight/brightness"
            led.parent.mkdir(parents=True)
            led.write_text("58\n")
            binary=path/"helper"
            subprocess.run([CC,"--target=x86_64-linux-gnu","-Os",
              "-static","-fno-stack-protector","-fno-builtin","-ffreestanding",
              "-nostdlib","-fuse-ld=lld","-Wl,-e,_start",
              "-Wl,--build-id=none","-Wall","-Wextra","-Werror",
              "-DTEST_LOCAL_REGULAR_FILE",f'-DSYSFS_ROOT="{path}"',
              str(ROOT/"scripts/kpoc-s55-lcd-off.c"),"-o",str(binary)],
              check=True,capture_output=True)
            r=subprocess.run([str(binary)],capture_output=True,timeout=3)
            self.assertEqual(r.returncode,0,r.stderr)
            self.assertTrue(led.read_text().startswith("0\n"))
            led.unlink()
            r=subprocess.run([str(binary)],capture_output=True,timeout=3)
            self.assertEqual(r.returncode,10,r.stderr)

if __name__=="__main__":
    unittest.main()
