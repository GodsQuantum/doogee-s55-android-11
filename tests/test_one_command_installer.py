"""Offline, non-destructive regression checks for the stock-S55 installer."""
from __future__ import annotations

import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    installer = (ROOT / "installer/INSTALL.sh").read_text()
    builder = (ROOT / "scripts/build-s55-lineage18-kit.sh").read_text()
    docs = (ROOT / "installer/README.md").read_text()
    assert 'ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"' in installer
    assert 'VENDOR_SHA=efef359fef8f6cd6dde651e4b6e4034cbf7ec2fdc8cc83087d079e5d2dbde759' in installer
    assert "e0602bae3099274aec52e4fdf8ba6b121859e8ff35dea08dbc89cce967bd6daf" in installer
    assert "3d89603ed3025bdc14e65d6269024c52920808c747aeb2d79417741d7cc7f9f6" in installer
    assert "1540096:7389183:7389184:8273919" in installer
    assert "1540096:7913471:7913472:8273919" in installer
    assert "INSTALL-S55-ERASE-ALL" in installer
    assert "UNLOCK-S55" in installer
    assert "private-install-state" in installer
    assert "prepare-lineage18-userdata-s55.sh" in installer
    assert installer.index('if [[ ! -e "$BACK/data.ok" ]]') < installer.index('if [[ ! -e "$BACK/gapps.ok" ]]')
    assert "nvram nvdata protect1 protect2" in installer
    assert "flash preloader" not in installer.lower()
    assert "boot-tested-s55.img" in builder and "vendor-s55-known-good.img.zst" in builder
    assert "private-install-state/backup" in docs
    assert "one command" in docs.lower()
    for prohibited in ("fastboot flash preloader", "fastboot flash nvram", "fastboot flash lk", "adb reboot sideload"):
        assert prohibited not in installer
    for script in [ROOT / "installer/INSTALL.sh", ROOT / "scripts/build-s55-lineage18-kit.sh",
                   ROOT / "scripts/install-nikgapps-core11-s55.sh"]:
        subprocess.run(["bash", "-n", str(script)], check=True)
    tracked = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True,
                             check=True).stdout.splitlines()
    assert not any(p.startswith("local-kit/") for p in tracked)
    assert not any(p.startswith("files/candidates/") or p.startswith("files/installer-assets/")
                   for p in tracked)
    print("ONE_COMMAND_KIT_STATIC=PASS")


if __name__ == "__main__":
    main()
