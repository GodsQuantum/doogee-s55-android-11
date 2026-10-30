#!/usr/bin/env python3
"""Offline-only tests for the DOOGEE S55 KPOC read-only UI bridge.

Does not access a phone or change USB/device state.
"""
import pathlib
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / "scripts/kpoc-s55-bridge.c"
CC = shutil.which("clang")

class KpocBridgeTests(unittest.TestCase):
    def test_no_power_control_in_bridge(self):
        src = SOURCE.read_text()
        self.assertNotIn("N_REBOOT,", src.replace("#define N_REBOOT 142", "").replace("#define N_REBOOT 169", ""))
        self.assertNotIn("sys_poweroff", src)
        self.assertNotIn("poweroff();", src)
        self.assertIn("ADC_Charger_Voltage", src)
        self.assertIn("s.voltage>=3000000", src)

    @unittest.skipUnless(CC, "clang not installed")
    def test_mock_sysfs(self):
        with tempfile.TemporaryDirectory(prefix="s55-kpoc-test-") as tmp:
            root = pathlib.Path(tmp)
            data = {
                "sys/class/power_supply/usb/online": "1\n",
                "sys/class/power_supply/ac/online": "0\n",
                "sys/class/power_supply/battery/batt_vol": "3802000\n",
                "sys/class/power_supply/battery/capacity": "26\n",
                "sys/class/power_supply/battery/present": "1\n",
                "sys/class/power_supply/battery/status": "Charging\n",
                "sys/devices/platform/battery/ADC_Charger_Voltage": "4749\n",
            }
            for relative, contents in data.items():
                target = root / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(contents)
            exe = root / "bridge-test"
            args = [
                CC, "--target=x86_64-linux-gnu", "-Os", "-static",
                "-fno-stack-protector", "-fno-builtin", "-ffreestanding",
                "-nostdlib", "-fuse-ld=lld", "-Wl,-e,_start",
                "-Wl,--build-id=none", "-Wall", "-Wextra", "-Werror", "-Wno-unused-function",
                "-DTEST_ONE_SHOT",
                f'-DSYSFS_ROOT="{root}"',
                '-DFB_PATH="/dev/null"',
                str(SOURCE), "-o", str(exe)
            ]
            subprocess.run(args, check=True, capture_output=True)
            def run():
                p = subprocess.run([str(exe)], check=True, capture_output=True, text=True)
                return p.stdout
            self.assertIn("usb=1 ac=0 vchr_mv=4749 bat_uv=3802000 soc=26 valid=1 charging=1 power=1", run())
            (root/"sys/class/power_supply/usb/online").write_text("0\n")
            (root/"sys/class/power_supply/battery/capacity").write_text("0\n")
            self.assertIn("soc=0 valid=0 charging=1 power=1", run())
            (root/"sys/devices/platform/battery/ADC_Charger_Voltage").write_text("0\n")
            self.assertIn("soc=0 valid=0 charging=1 power=0", run())
            (root/"sys/class/power_supply/battery/capacity").write_text("77\n")
            (root/"sys/class/power_supply/battery/batt_vol").write_text("nan\n")
            self.assertIn("valid=0", run())

    @unittest.skipUnless(CC, "clang not installed")
    def test_init_delegated_backlight_and_oneshot_timing(self):
        rc = (ROOT / "scripts/s55-kpoc-bridge.rc").read_text()
        source = SOURCE.read_text()
        service, property_action = rc.split("on property:init.svc.s55_kpoc_bridge=stopped\n", 1)
        self.assertIn("service s55_kpoc_bridge /vendor/bin/s55_kpoc_bridge", service)
        self.assertIn("class charger", service)
        self.assertIn("oneshot", service)
        self.assertIn("write /sys/class/leds/lcd-backlight/brightness 0", property_action)
        self.assertNotIn("on charger", rc)
        self.assertIn("KPOC_SOC_CERTIFIED 0", source)
        self.assertNotIn("disable_backlight", source)
        self.assertNotIn("O_WRONLY", source)
        self.assertNotIn("n%60==0", source)

        # Fast simulated eight-heartbeat run (does not access a phone).
        with tempfile.TemporaryDirectory(prefix="s55-kpoc-timer-") as tmp:
            exe = pathlib.Path(tmp) / "timer"
            args = [
                CC, "--target=x86_64-linux-gnu", "-Os", "-static",
                "-fno-stack-protector", "-fno-builtin", "-ffreestanding",
                "-nostdlib", "-fuse-ld=lld", "-Wl,-e,_start",
                "-Wl,--build-id=none", "-Wall", "-Wextra", "-Werror",
                "-Wno-unused-function", "-DTEST_TIMED_ONESHOT",
                '-DFB_PATH="/dev/null"',
                str(SOURCE), "-o", str(exe)
            ]
            subprocess.run(args, check=True, capture_output=True)
            result = subprocess.run([str(exe)], check=True, capture_output=True, text=True, timeout=2)
            self.assertIn("s55-kpoc: framebuffer blank requested;", result.stdout)
            self.assertEqual(result.stdout.count("framebuffer blank requested"), 1)
            self.assertEqual(result.stdout.count("s55-kpoc: usb="), 2)

if __name__ == "__main__":
    unittest.main()
