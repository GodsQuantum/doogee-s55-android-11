#!/usr/bin/env python3
"""Host-only installer simulation. All ADB/fastboot invocations are fake.

No real handset can be reached; all dummy assets and checkpoints are ephemeral.
"""
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def install_fake_tool(bin_dir: Path, name: str, body: str) -> None:
    path = bin_dir / name
    path.write_text("#!/usr/bin/env python3\n" + body)
    path.chmod(0o755)


# Regression: the max charger-voltage field must never masquerade as cell voltage.
battery_dump = "  Max charging voltage: 5000000\n  voltage: 3950\n  temperature: 290\n"
voltage_extract = subprocess.run(
    ["sed", "-n", "s/^[[:space:]]*voltage:[[:space:]]*//p"],
    input=battery_dump, capture_output=True, text=True, check=True)
assert voltage_extract.stdout.strip() == "3950", voltage_extract.stdout

# Stream accounting is tested without disk images or physical devices.
stream_script = ROOT / "scripts/progress-stream.py"
dummy = (bytes(range(256)) * 2048) + b"TAIL"
ok = subprocess.run(["python3", "-u", str(stream_script), str(len(dummy))],
                    input=dummy, capture_output=True, timeout=10)
assert ok.returncode == 0 and ok.stdout == dummy
short = subprocess.run(["python3", "-u", str(stream_script), str(len(dummy)+1)],
                       input=dummy, capture_output=True, timeout=10)
assert short.returncode != 0, "Byte-count mismatch was silently accepted"

with tempfile.TemporaryDirectory(prefix="local-s55-test-", dir=ROOT) as temp:
    sandbox = Path(temp)
    kit = sandbox / "kit"
    bin_dir = sandbox / "fake-tools"
    bin_dir.mkdir()
    (kit / "assets").mkdir(parents=True)
    (kit / "scripts").mkdir()
    for name in ("lineage18.img.xz", "twrp-s55.img", "boot-tested-s55.img",
                 "nikgapps-core-11.zip", "vendor-s55-known-good.img.zst"):
        (kit / "assets" / name).write_bytes(b"FAKE--NOT-A-VALID-IMAGE:" + name.encode())
    shutil.copy2(ROOT / "installer/INSTALL.sh", kit / "INSTALL.sh")
    shutil.copy2(ROOT / "installer/README.md", kit / "README.md")
    (kit / "scripts/fix-lineage18-thermal-sepolicy.sh").write_text("#!/bin/sh\nexit 99\n")
    (kit / "scripts/enable-microarray-persistence.sh").write_text("#!/bin/sh\nexit 99\n")
    (kit / "scripts/progress-stream.py").write_text("#!/usr/bin/env python3\nraise SystemExit(99)\n")
    paths = sorted(p for p in kit.rglob("*") if p.is_file())
    with (kit / "manifest.sha256").open("w") as out:
        for path in paths:
            out.write(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.relative_to(kit)}\n")

    log = sandbox / "mock-calls.txt"
    install_fake_tool(bin_dir, "adb", """import os, sys
from pathlib import Path
args = sys.argv[1:]
with Path(os.environ['S55_MOCK_LOG']).open('a') as f:
    f.write('adb ' + ' '.join(args) + '\\n')
if args and args[0] == 'devices':
    print('List of devices attached')
    print('MOCK_S55_0001\\t'+os.environ.get('S55_MOCK_STATE','device'))
elif args and args[0] == 'shell':
    cmd = ' '.join(args[1:])
    if 'getprop ro.vendor.build.fingerprint' in cmd: print(os.environ.get('S55_MOCK_VENDOR', 'DOOGEE/S55/S55:8.0.0/O00623/1573208580:user/release-keys'))
    if 'getprop ro.product.device' in cmd: print(os.environ.get('S55_MOCK_PRODUCT', 'S55'))
    elif 'getprop ro.product.model' in cmd: print('DOOGEE S55')
    elif 'getprop ro.hardware.fingerprint' in cmd: print(os.environ.get('S55_MOCK_FINGERPRINT_HAL', 'microarray'))
    elif 'sha256sum /vendor/lib64/libfprint-x64.so' in cmd: print(os.environ.get('S55_MOCK_FINGERPRINT_SHA', '3d89603ed3025bdc14e65d6269024c52920808c747aeb2d79417741d7cc7f9f6')+'  /vendor/lib64/libfprint-x64.so')
    elif 'getprop ro.build.version.release' in cmd: print(os.environ.get('S55_MOCK_VERSION', '11'))
    elif 'getprop ro.twrp.version' in cmd: print(os.environ.get('S55_MOCK_TWRP', '3.1.1-0' if os.environ.get('S55_MOCK_STATE')=='recovery' else ''))
    elif 'getprop sys.boot_completed' in cmd: print('1')
    elif cmd.startswith('settings get global '): print('25' if cmd.endswith('low_power_trigger_level') else '0')
    elif 'getenforce' in cmd: print('Enforcing')
    elif cmd == 'id': print('uid=0(root) gid=0(root)')
    elif 'cat /sys/class/power_supply/battery/capacity' in cmd: print('65')
    elif 'cat /sys/class/power_supply/battery/batt_vol' in cmd: print('3950000')
    elif cmd.startswith('command -v ') or cmd.startswith('sgdisk -v '): pass
    elif cmd.startswith('df -k /tmp'): print('580000')
    elif 'pm list packages' in cmd:
        print('package:com.google.android.gms\\npackage:com.android.vending\\npackage:com.google.android.gsf')
    elif 'getprop persist.sys.phh.restart_ril' in cmd: print(os.environ.get('S55_MOCK_RIL_RESTART','false'))
    elif 'getprop persist.sys.phh.fingerprint.nocleanup' in cmd: print(os.environ.get('S55_MOCK_PHH_RETENTION', 'true'))
    elif 'dumpsys battery' in cmd: print('3950' if 'voltage' in cmd else '310')
    elif 'dumpsys thermalservice' in cmd:
        print('mName=CPU_T\\nmName=GPU_T\\nmName=BAT_T\\nmName=SKIN_T')
    else:
        print('REFUSED unexpected fake shell command', cmd, file=sys.stderr)
        sys.exit(92)
else:
    print('REFUSED fake ADB mutation', args, file=sys.stderr)
    sys.exit(93)
""")
    install_fake_tool(bin_dir, "fastboot", """import os,sys
from pathlib import Path
args=sys.argv[1:]
with Path(os.environ['S55_MOCK_LOG']).open('a') as f: f.write('fastboot '+' '.join(args)+'\\n')
if args and args[0]=='devices': print('')
else: print('REFUSED fake FASTBOOT mutation',file=sys.stderr);sys.exit(94)
""")
    install_fake_tool(bin_dir, "df", """import sys
print('Avail\\n999999999999')
""")
    install_fake_tool(bin_dir, "pv", """import sys
print('NO PV DEVICE ACCESS IN MOCK',file=sys.stderr)
sys.exit(96)
""")
    env = {**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}",
           "S55_MOCK_LOG": str(log)}
    def run(*args: str, stdin: str = "", custom_env: dict | None = None) -> subprocess.CompletedProcess:
        return subprocess.run(["bash", str(kit / "INSTALL.sh"), *args],
                              cwd=kit, env={**env, **(custom_env or {})},
                              input=stdin, capture_output=True, text=True, timeout=12)

    result = run("--plan")
    assert result.returncode == 0, result.stderr
    assert "STOCK DOOGEE S55" in result.stdout
    assert not log.exists(), "Plan unexpectedly invoked adb/fastboot"

    result = run("--check")
    assert result.returncode == 0, result.stderr
    assert "HOST_ASSETS_OK" in result.stdout
    before = log.read_text()
    result = run("--recovery-check")
    assert result.returncode != 0 and "No complete original GPT backup" in result.stderr
    assert log.read_text() == before, "Recovery check contacted fake ADB"

    result = run("--verify")
    assert result.returncode == 0, result.stderr
    assert "ANDROID11_GAPPS_THERMAL_SELINUX_VERIFIED_READ_ONLY" in result.stdout
    assert "FINGERPRINT_PATCH_AND_PHH_RETENTION_VERIFIED_READ_ONLY" in result.stdout
    assert "PHYSICAL_ACCEPTANCE" in result.stdout
    for env_overrides, expected in [
        ({"S55_MOCK_FINGERPRINT_HAL": "other"}, "Unexpected fingerprint hardware"),
        ({"S55_MOCK_FINGERPRINT_SHA": "0" * 64}, "enumerator hash mismatch"),
        ({"S55_MOCK_PHH_RETENTION": "false"}, "retention not set"),
    ]:
        negative = run("--verify", custom_env=env_overrides)
        assert negative.returncode != 0 and expected in negative.stderr, (env_overrides, negative.stderr)


    result = run("--verify", custom_env={"S55_MOCK_RIL_RESTART": "true"})
    assert result.returncode != 0 and "Unsafe PHH restart_ril=true" in result.stderr, result.stderr

    result = run("--verify", custom_env={"S55_MOCK_VENDOR": "DOOGEE/S55_Lite/S55_Lite:8.0.0/test"})
    assert result.returncode != 0 and "Not DOOGEE S55" in result.stderr

    result = run("--verify", custom_env={"S55_MOCK_VERSION": "8.0.0"})
    assert result.returncode != 0 and "Not Android 11" in result.stderr

    result = run("--install", stdin="INSTALL-S55-ERASE-ALL\n")
    assert result.returncode != 0
    assert "Not STOCK Android 8" in result.stdout, (result.stdout, result.stderr)

    # Model a TWRP recovery restart with an old checkpoint from another phone
    # (without a bound serial). The installer must reject it before any backup
    # or partition modification.
    (kit / "private-install-state/repartition.ok").touch()
    result = run("--install", stdin="INSTALL-S55-ERASE-ALL\n",
                 custom_env={"S55_MOCK_STATE": "recovery"})
    assert result.returncode != 0, (result.stdout, result.stderr)
    assert "Unbound checkpoint markers" in result.stdout, (result.stdout, result.stderr)
    (kit / "private-install-state/repartition.ok").unlink()

    result = run("--install", stdin="INSTALL-S55-ERASE-ALL\n",
                 custom_env={"S55_MOCK_STATE": "recovery", "S55_MOCK_TWRP": "3.0.0"})
    assert result.returncode != 0 and "Wrong TWRP" in result.stdout

    # Simulate a complete original GPT and 9 compressed partition backups;
    # verify the host-only recovery check including detection of a corrupt SHA.
    backup = kit / "private-install-state" / "backup"
    backup.mkdir(exist_ok=True, parents=True)
    original_gpt = b"TEST_GPT_NOT_REAL_DATA" * 4
    (backup / "gpt-original.bin").write_bytes(original_gpt)
    (backup / "gpt-original.sha256").write_text(hashlib.sha256(original_gpt).hexdigest() + "\n")
    for partition in ("system", "cache", "boot", "recovery", "vendor",
                      "nvram", "nvdata", "protect1", "protect2"):
        raw = b"FAKE_DATA_NO_PHONE:" + partition.encode() * 20
        source = backup / f"{partition}.mockraw"
        source.write_bytes(raw)
        compressed = backup / f"{partition}.img.zst"
        subprocess.run(["zstd", "-q", "-f", "-o", str(compressed), str(source)],
                       check=True, capture_output=True)
        source.unlink()
        (backup / f"{partition}.img.zst.raw.sha256").write_text(
            hashlib.sha256(raw).hexdigest() + "\n")
    calls_before = log.read_text()
    result = run("--recovery-check")
    assert result.returncode == 0, (result.stdout, result.stderr)
    assert "NINE_ORIGINAL_PARTITIONS_PLUS_GPT_VERIFIED" in result.stdout
    assert log.read_text() == calls_before
    one_hash = backup / "nvdata.img.zst.raw.sha256"
    valid_hash = one_hash.read_text()
    one_hash.write_text("0" * 64 + "\n")
    result = run("--recovery-check")
    assert result.returncode != 0 and "Original raw checksum mismatch: nvdata" in result.stderr
    assert log.read_text() == calls_before
    one_hash.write_text(valid_hash)

    # A power loss while ANY destructive stage is in flight cannot
    # silently start another write on the next execution.
    for stage in ("repartition", "cache", "system", "vendor",
                  "gapps", "data", "thermal", "boot"):
        marker = kit / "private-install-state" / (stage + ".inflight")
        marker.write_text("TEST_INTERRUPTED_STAGE\n")
        previous_calls = log.read_text()
        result = run("--install", stdin="INSTALL-S55-ERASE-ALL\n")
        assert result.returncode != 0, (stage, result.stdout, result.stderr)
        assert f"Interrupted {stage}" in result.stdout, (stage, result.stdout)
        assert log.read_text() == previous_calls, "Interrupted stage unexpectedly contacted ADB"
        marker.unlink()

    # A manifest bit flip must fail before opening a connection to the phone.
    previous_calls = log.read_text()
    with (kit / "README.md").open("a") as handle:
        handle.write("\nCHANGED WITHOUT CHECKSUM UPDATE\n")
    result = run("--plan")
    assert result.returncode != 0 and "Kit verification failed" in result.stderr
    assert log.read_text() == previous_calls

    recorded = log.read_text().splitlines()
    assert not any(" flash " in f" {s} " or " reboot" in s or
                   " erase" in s or " format" in s for s in recorded), recorded
    assert not any("exec-in" in s or "exec-out" in s or " push " in s for s in recorded), recorded

print("INSTALLER_OFFLINE_MOCKS=PASS (plan, check, Android verification, wrong target, no reflashing, tampered manifest)")
