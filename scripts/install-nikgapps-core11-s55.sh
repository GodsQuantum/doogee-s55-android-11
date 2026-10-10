#!/usr/bin/env bash
# S55 / LineageOS 18.1 only: stage & install NikGapps Core 11 via TWRP.
# Does not format/wipe userdata or modify boot/vendor/radio partitions.
set -Eeuo pipefail
export LC_ALL=C
MODE="${1:-}"
[[ "$MODE" == "--check" || "$MODE" == "--install" ]] || {
  echo "Usage: $0 --check | --install" >&2; exit 2;
}
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZIP="${S55_GAPPS_ZIP:-$ROOT/files/candidates/NikGapps-core-arm64-11-20260204-signed.zip}"
HASH="a56ad7da66e51a6cd1af0b0fb39a1ac167739161624115276b7f8d00633fd0f8"
# Stage under freshly formatted, mounted /data as validated on the real S55.
# The kit formats userdata BEFORE installing NikGapps.
REMOTE="${S55_GAPPS_REMOTE:-/data/local/tmp/s55-NikGapps-core-arm64-11.zip}"
mapfile -t DEV < <(adb devices | awk '$2=="recovery"{print $1}')
[[ "${#DEV[@]}" -eq 1 ]] || { echo "Expected S55 TWRP" >&2; exit 1; }
ADB=(adb -s "${DEV[0]}")
[[ "$("${ADB[@]}" shell getprop ro.product.device | tr -d '\r')" == S55 ]] || exit 1
[[ "$("${ADB[@]}" shell getprop ro.twrp.version | tr -d '\r')" == 3.1.1-0 ]] || exit 1
[[ "$("${ADB[@]}" shell id | tr -d '\r')" == uid=0* ]] || exit 1
[[ "$(sha256sum "$ZIP" | awk '{print $1}')" == "$HASH" ]] || {
  echo "GApps ZIP SHA256 mismatch" >&2; exit 1;
}
# Recovery uses a stock Android 8 build.prop; inspect the actual /system partition instead.
if ! "${ADB[@]}" shell 'mount | grep -q " on /system "'; then
  "${ADB[@]}" shell 'mount -t ext4 -o ro /dev/block/mmcblk0p28 /system' || exit 1
fi
[[ "$("${ADB[@]}" shell 'grep "^ro.build.version.release=" /system/build.prop | head -1' | tr -d '\r')" == "ro.build.version.release=11" ]] || {
  echo "The mounted system image is not Android 11; refusing GApps flash" >&2; exit 1;
}
echo "GAPPS_PREFLIGHT_GOOD (Android 11, exact Core ZIP)"
if [[ "$MODE" == "--check" ]]; then exit 0; fi
"${ADB[@]}" push "$ZIP" "$REMOTE"
rc="$("${ADB[@]}" shell "sha256sum '$REMOTE'" | tr -d '\r' | awk '{print $1}')"
[[ "$rc" == "$HASH" ]] || { echo "Phone ZIP SHA mismatch" >&2; exit 1; }
echo "INSTALLING NIKGAPPS CORE FROM TWRP"
"${ADB[@]}" shell "twrp install '$REMOTE'"
echo "NIKGAPPS_INSTALLER_EXITED_SUCCESSFULLY — inspect recovery log and installed apps"
