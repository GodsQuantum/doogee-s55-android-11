#!/usr/bin/env bash
# Locally assemble an offline, single-command DOOGEE S55 LineageOS 18.1 kit.
# No copyrighted OEM/Google binary is committed or published with this repo.
set -Eeuo pipefail
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${1:-$ROOT/local-kit}"
[[ "$DEST" = /* ]] || { echo "Destination must be absolute" >&2; exit 2; }
# Respect the canonical project folder and avoid overwriting existing user data.
case "$DEST/" in "$ROOT/"*) ;; *) echo "Destination must stay INSIDE $ROOT" >&2; exit 2;; esac
[[ ! -e "$DEST" ]] || { echo "Kit folder already exists: $DEST; choose a new destination" >&2; exit 1; }
for k in sha256sum xz python3 cp; do command -v "$k" >/dev/null || exit 1; done
mkdir -p "$DEST/assets" "$DEST/scripts" "$DEST/backups/device-2026-10-10" \
  "$DEST/files/candidates/s55-2018-compat"
chmod 700 "$DEST"
fail(){ printf "FAILED: %s\n" "$*" >&2; exit 1; }
copy_exact(){
  local src="$1" dst="$2" hash="$3"
  [[ -f "$src" ]] || fail "Source missing: $src"
  [[ "$(sha256sum "$src" | awk '{print $1}')" == "$hash" ]] ||
    fail "Source checksum mismatch: $src"
  cp -- "$src" "$dst"
  [[ "$(sha256sum "$dst" | awk '{print $1}')" == "$hash" ]] ||
    fail "Copy checksum mismatch: $dst"
}
echo "Building LOCAL kit (never commit binaries to GitHub)"
copy_exact "$ROOT/files/installer-assets/lineage18.img.xz" "$DEST/assets/lineage18.img.xz" f793f611a9a8a4eca05f744582b58121eb7b392edb1b03330d7b625da7109fca
copy_exact "$ROOT/files/installer-assets/twrp-s55.img" "$DEST/assets/twrp-s55.img" bbf6c46cb001f9b14c7476beb73f9d2ae4398619c3b855498cca1a8276436038
copy_exact "$ROOT/files/candidates/NikGapps-core-arm64-11-20260204-signed.zip" "$DEST/assets/nikgapps-core-11.zip" a56ad7da66e51a6cd1af0b0fb39a1ac167739161624115276b7f8d00633fd0f8
# Exact 2020 boot whose KPOC and driver behavior was validated on physical S55.
# This file may be proprietary and is LOCAL ONLY, never placed in git.
copy_exact "$ROOT/backups/device-2026-10-09/boot-active.bin" "$DEST/assets/boot-tested-s55.img" a2e6c0db60b2ecc22fe4fb42e2ca2db03b55188d44f195361e36c5dd6873f5ab
# This exact 512 MiB vendor image was READ BACK from the repaired real S55
# and contains the working fingerprint, fstab, sensor, HAL and thermal rules.
copy_exact "$ROOT/files/installer-assets/vendor-s55-known-good.img.zst" "$DEST/assets/vendor-s55-known-good.img.zst" 0e55ecace836f198887474cc1d267633c6c5a48e01a492a06f717c487b6622bb
donor="$ROOT/files/candidates/s55-2018-compat"
for f in logwrap2018-64.so gesturewake2018-64.so msensord-original msensord-liblog-fixed memsicp-original memsicp-liblog-fixed; do
  [[ -f "$donor/$f" ]] || fail "Missing $donor/$f"
  cp "$donor/$f" "$DEST/files/candidates/s55-2018-compat/$f"
done
private="$ROOT/backups/device-2026-10-10"
for f in healthd-lineage18-original healthd-lineage18-voltage-patched \
  healthd-lineage18-voltage-temperature-patched \
  nonplat-sepolicy-lineage18-thermal-original.cil \
  nonplat-sepolicy-lineage18-thermal-readonly-patched.cil; do
  [[ -f "$private/$f" ]] || fail "Missing checked private source $private/$f"
  cp "$private/$f" "$DEST/backups/device-2026-10-10/$f"
done
for f in repartition-gapps.sh decrypt-fstab.sh \
  fix-microarray-fingerprint.sh fix-vendor-compat-s55.sh \
  fix-vendor-sensor-log-s55.sh fix-healthd-voltage.sh \
  fix-lineage18-healthd-temperature.sh fix-lineage18-thermal-sepolicy.sh \
  patch-healthd-voltage.py patch-lineage18-healthd-temperature.py progress-stream.py \
  install-nikgapps-core11-s55.sh prepare-lineage18-userdata-s55.sh enable-microarray-persistence.sh; do
  [[ -f "$ROOT/scripts/$f" ]] || fail "Missing Git source scripts/$f"
  cp "$ROOT/scripts/$f" "$DEST/scripts/$f"
done
cp "$ROOT/installer/INSTALL.sh" "$DEST/INSTALL.sh"
cp "$ROOT/installer/README.md" "$DEST/README.md"
# Separate local backup state created by INSTALL.sh; never include unique user partitions.
(
 cd "$DEST"
 { find assets files backups scripts -type f -print0; printf '%s\0' INSTALL.sh README.md; } |
   sort -z | xargs -0 sha256sum > manifest.sha256
 chmod 600 manifest.sha256
 chmod -R go-rwx assets files backups
 chmod 755 INSTALL.sh
 for script in scripts/*.sh; do chmod 755 "$script"; done
 sha256sum -c manifest.sha256 > /dev/null
)
echo "KIT_READY $DEST"
echo "ONE_COMMAND: cd '$DEST' && ./INSTALL.sh"
echo "NO DEVICE WRITES took place during this build."
echo "Keep this LOCAL kit private; never publish phone-specific boot/vendor or backups."