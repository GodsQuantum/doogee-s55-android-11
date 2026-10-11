#!/usr/bin/env python3
"""Keep live RIL testing reversible, pinned, and non-production."""
from pathlib import Path
import subprocess
import tempfile
import os

ROOT = Path(__file__).resolve().parents[1]
script = ROOT / "scripts/trial-rilproxy-live.sh"
s = script.read_text()
for required in ("--recover", "--check", "--trial", "setprop ctl.stop ril-proxy",
                 "umount '$TARGET'", "setprop ctl.start ril-proxy",
                 "ORIGINAL_RIL_RESTORED", "getprop sys.boot_completed",
                 "getprop persist.sys.phh.restart_ril", "getenforce",
                 "adb unroot", "chcon u:object_r:vendor_file:s0"):
    assert required in s, required
assert s.index("setprop ctl.stop ril-proxy") < s.index("umount '$TARGET'")
for forbidden in ("adb remount", "fastboot flash", "fastboot erase",
                  "disable-verity", "setenforce 0", "persist.sys.phh.restart_ril true"):
    assert forbidden not in s, forbidden
assert subprocess.run(["bash", "-n", str(script)], check=False).returncode == 0
with tempfile.TemporaryDirectory() as tmp:
    fake = Path(tmp) / "adb"
    fake.write_text("""#!/bin/sh
case "$*" in
  devices) printf 'List of devices attached\\nS55TEST device\\n' ;;
  'shell getprop ro.vendor.build.fingerprint') echo DOOGEE/S55/S55:8.0.0/test ;;
  'shell getprop sys.boot_completed') echo 1 ;;
  'shell getenforce') echo Enforcing ;;
  'shell getprop persist.sys.phh.restart_ril') echo false ;;
  *sha256sum*) echo '425312124514d3b87e0d8f249bb92596a2b90e6212c9484b524e761227f15f07  /vendor/lib64/librilproxy.so' ;;
  'shell getprop init.svc.ril-proxy') echo running ;;
  *) echo "unexpected ADB: $*" >&2; exit 22 ;;
esac
""")
    fake.chmod(0o755)
    env = dict(os.environ, PATH=f"{tmp}:{os.environ['PATH']}")
    result = subprocess.run(["bash", str(script), "--check"], env=env, capture_output=True, text=True)
    assert result.returncode == 0, (result.stdout, result.stderr)
    assert "RIL_HASH=" in result.stdout
    unsafe = subprocess.run(["bash", str(script), "--trial", "/no/such/vendor-candidate"], env=env, capture_output=True, text=True)
    assert unsafe.returncode != 0
print("RIL_LIVE_TRIAL_HARNESS_SAFETY_PASS")
