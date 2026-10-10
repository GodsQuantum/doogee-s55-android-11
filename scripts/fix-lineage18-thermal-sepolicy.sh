#!/usr/bin/env bash
# Exact-version, reversible Android 11/Oreo-vendor thermal SELinux read rule.
# Only adds READ/SEARCH to hal_thermal_default for proc_mtktz; no permissive.
# Runs only on physical S55 via native TWRP, with original backup preserved.
set -Eeuo pipefail
export LC_ALL=C
MODE="${1:-}"
[[ "$MODE" == --check || "$MODE" == --apply || "$MODE" == --restore ]] || {
  echo "Usage: $0 --check|--apply|--restore" >&2; exit 2;
}
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACK="$ROOT/backups/device-2026-10-10"
ORIG="$BACK/nonplat-sepolicy-lineage18-thermal-original.cil"
PATCH="$BACK/nonplat-sepolicy-lineage18-thermal-readonly-patched.cil"
ORIG_SHA=e33ed85bb209b373030e6d4f0a48bbe05038e738e801255052a8da1229567491
PATCH_SHA=e0602bae3099274aec52e4fdf8ba6b121859e8ff35dea08dbc89cce967bd6daf
TARGET=/vendor/etc/selinux/nonplat_sepolicy.cil
[[ "$(sha256sum "$ORIG" | awk '{print $1}')" == "$ORIG_SHA" ]] || exit 1
[[ "$(sha256sum "$PATCH" | awk '{print $1}')" == "$PATCH_SHA" ]] || exit 1
mapfile -t DEV < <(adb devices | awk '$2=="recovery"{print $1}')
[[ "${#DEV[@]}" -eq 1 ]] || { echo 'Exactly one device in TWRP required' >&2; exit 1; }
ADB=(adb -s "${DEV[0]}")
get() { "${ADB[@]}" shell "$1" | tr -d '\r'; }
[[ "$(get 'getprop ro.twrp.version')" == 3.1.1-0 ]] || exit 1
[[ "$(get 'getprop ro.product.device')" == S55 ]] || exit 1
[[ "$(get id)" == uid=0* ]] || exit 1
CAP="$(get 'cat /sys/class/power_supply/battery/capacity')"
VOLT="$(get 'cat /sys/class/power_supply/battery/batt_vol')"
[[ "$CAP" =~ ^[0-9]+$ && "$CAP" -ge 30 ]] || exit 1
[[ "$VOLT" =~ ^[0-9]+$ && "$VOLT" -ge 3500000 ]] || exit 1
mnt="$(get 'mount | grep " on /vendor "' || true)"
if [[ -z "$mnt" ]]; then
  "${ADB[@]}" shell 'mount -t ext4 -o ro,noload /dev/block/mmcblk0p27 /vendor'
  mnt="$(get 'mount | grep " on /vendor "' || true)"
fi
[[ "$mnt" == *'mmcblk0p27 on /vendor type ext4'* ]] || exit 1
sm="$(get 'mount | grep " on /system "' || true)"
if [[ -z "$sm" ]]; then
  "${ADB[@]}" shell 'mount -t ext4 -o ro,noload /dev/block/mmcblk0p28 /system'
  sm="$(get 'mount | grep " on /system "' || true)"
fi
[[ "$sm" == *'mmcblk0p28 on /system type ext4'* ]] || exit 1
[[ "$(get 'grep "^ro.build.version.release=" /system/build.prop | head -1')" == ro.build.version.release=11 ]] || exit 1
CURRENT="$(get "sha256sum '$TARGET'" | awk '{print $1}')"
[[ "$CURRENT" == "$ORIG_SHA" || "$CURRENT" == "$PATCH_SHA" ]] || {
  echo "Unknown vendor SELinux policy: $CURRENT. Refusing." >&2; exit 1;
}
echo "POLICY_PREFLIGHT S55 Android11; charge=$CAP%; policy=$CURRENT"
if [[ "$MODE" == --check ]]; then echo CHECK_PASS; exit 0; fi
WANT="$PATCH_SHA"; SRC="$PATCH"
if [[ "$MODE" == --restore ]]; then WANT="$ORIG_SHA"; SRC="$ORIG"; fi
if [[ "$CURRENT" == "$WANT" ]]; then echo ALREADY_AT_DESIRED_POLICY; exit 0; fi
"${ADB[@]}" push "$ORIG" /tmp/s55-original-cil >/dev/null
"${ADB[@]}" push "$PATCH" /tmp/s55-thermal-cil >/dev/null
[[ "$(get 'sha256sum /tmp/s55-original-cil' | awk '{print $1}')" == "$ORIG_SHA" ]] || exit 1
[[ "$(get 'sha256sum /tmp/s55-thermal-cil' | awk '{print $1}')" == "$PATCH_SHA" ]] || exit 1
cleanup() {
 "${ADB[@]}" shell 'mount -o remount,ro /vendor' >/dev/null 2>&1 || true
 "${ADB[@]}" shell 'rm -f /tmp/s55-original-cil /tmp/s55-thermal-cil' >/dev/null 2>&1 || true
}
trap cleanup EXIT
"${ADB[@]}" shell 'mount -o remount,rw /vendor'
rw="$(get 'mount | grep " on /vendor "' || true)"
[[ "$rw" == *'mmcblk0p27 on /vendor type ext4 (rw,'* ]] || exit 1
TEMP=/tmp/s55-thermal-cil
if [[ "$MODE" == --restore ]]; then TEMP=/tmp/s55-original-cil; fi
"${ADB[@]}" shell "cat '$TEMP' > '$TARGET' && sync"
NOW="$(get "sha256sum '$TARGET'" | awk '{print $1}')"
LABEL="$(get "ls -lZ '$TARGET'")"
if [[ "$NOW" != "$WANT" || "$LABEL" != *'u:object_r:vendor_configs_file:s0'* ]]; then
 echo "POLICY_INSTALL_FAILED ($NOW $LABEL); restoring original" >&2
 "${ADB[@]}" shell "cat /tmp/s55-original-cil > '$TARGET' && sync" || true
 exit 1
fi
echo "SUCCESS policy=$NOW; $LABEL (vendor will be RO)"
