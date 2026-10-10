#!/usr/bin/env bash
# Guarded S55 LineageOS 18.1 fix for real MTK batt_temp (deci-Celsius).
# Operates ONLY from the exact native TWRP, ONLY system/bin/healthd.
set -Eeuo pipefail
export LC_ALL=C
MODE="${1:-}"
[[ "$MODE" == --check || "$MODE" == --apply || "$MODE" == --restore ]] || {
  echo "Usage: $0 --check|--apply|--restore" >&2; exit 2;
}
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACK="$ROOT/backups/device-2026-10-10"
SRC="$BACK/healthd-lineage18-voltage-patched"
FIX="$BACK/healthd-lineage18-voltage-temperature-patched"
SRC_SHA="5f66b4c372d09eb84f2b23dadedaad0a53242bc44f31fdd7787a5467bee9e3ee"
FIX_SHA="4421bd4794a9470e74b28c63e3ba9a2528e83a7635314ae27e5375c136555381"
TARGET="/system/bin/healthd"
for k in adb sha256sum; do command -v "$k" >/dev/null || exit 1; done
[[ "$(sha256sum "$SRC" | awk '{print $1}')" == "$SRC_SHA" ]] || exit 1
[[ "$(sha256sum "$FIX" | awk '{print $1}')" == "$FIX_SHA" ]] || exit 1
mapfile -t DEVICES < <(adb devices | awk '$2=="recovery" {print $1}')
[[ "${#DEVICES[@]}" -eq 1 ]] || { echo "Exactly one TWRP required" >&2; exit 1; }
ADB=(adb -s "${DEVICES[0]}")
readprop() { "${ADB[@]}" shell "$1" | tr -d '\r'; }
[[ "$(readprop 'getprop ro.product.device')" == S55 ]] || exit 1
[[ "$(readprop 'getprop ro.twrp.version')" == 3.1.1-0 ]] || exit 1
[[ "$(readprop id)" == uid=0* ]] || exit 1
CAP="$(readprop 'cat /sys/class/power_supply/battery/capacity')"
VOLT="$(readprop 'cat /sys/class/power_supply/battery/batt_vol')"
[[ "$CAP" =~ ^[0-9]+$ && "$CAP" -ge 30 ]] || exit 1
[[ "$VOLT" =~ ^[0-9]+$ && "$VOLT" -ge 3500000 ]] || exit 1
mnt="$(readprop 'mount | grep " on /system "' || true)"
if [[ -z "$mnt" ]]; then
  "${ADB[@]}" shell 'mount -t ext4 -o ro,noload /dev/block/mmcblk0p28 /system'
  mnt="$(readprop 'mount | grep " on /system "' || true)"
fi
[[ "$mnt" == *'mmcblk0p28 on /system type ext4'* ]] || exit 1
ver="$(readprop 'grep "^ro.build.version.release=" /system/build.prop | head -1')"
[[ "$ver" == ro.build.version.release=11 ]] || exit 1
CURRENT="$(readprop "sha256sum '$TARGET'" | awk '{print $1}')"
[[ "$CURRENT" == "$SRC_SHA" || "$CURRENT" == "$FIX_SHA" ]] || {
  echo "Unknown healthd binary: $CURRENT" >&2; exit 1;
}
echo "S55 Lineage18 battery $CAP% ($VOLT uV), healthd $CURRENT"
if [[ "$MODE" == --check ]]; then echo 'CHECK_PASS (no writes)'; exit 0; fi
EXPECTED="$FIX_SHA"; PAYLOAD="$FIX"
if [[ "$MODE" == --restore ]]; then EXPECTED="$SRC_SHA"; PAYLOAD="$SRC"; fi
if [[ "$CURRENT" == "$EXPECTED" ]]; then echo ALREADY_APPLIED; exit 0; fi
"${ADB[@]}" push "$SRC" /tmp/s55-healthd-voltage >/dev/null
"${ADB[@]}" push "$FIX" /tmp/s55-healthd-temperature >/dev/null
[[ "$(readprop 'sha256sum /tmp/s55-healthd-voltage' | awk '{print $1}')" == "$SRC_SHA" ]] || exit 1
[[ "$(readprop 'sha256sum /tmp/s55-healthd-temperature' | awk '{print $1}')" == "$FIX_SHA" ]] || exit 1
cleanup() {
  "${ADB[@]}" shell 'mount -o remount,ro /system' >/dev/null 2>&1 || true
  "${ADB[@]}" shell 'rm -f /tmp/s55-healthd-voltage /tmp/s55-healthd-temperature' >/dev/null 2>&1 || true
}
trap cleanup EXIT
"${ADB[@]}" shell 'mount -o remount,rw /system'
rw="$(readprop 'mount | grep " on /system "' || true)"
[[ "$rw" == *'mmcblk0p28 on /system type ext4 (rw,'* ]] || {
  echo 'Refuse: RW mount not verified' >&2; exit 1;
}
FILE=/tmp/s55-healthd-temperature
if [[ "$MODE" == --restore ]]; then FILE=/tmp/s55-healthd-voltage; fi
"${ADB[@]}" shell "cat '$FILE' > '$TARGET' && sync"
GOT="$(readprop "sha256sum '$TARGET'" | awk '{print $1}')"
LABEL="$(readprop "ls -lZ '$TARGET'")"
if [[ "$GOT" != "$EXPECTED" || "$LABEL" != *'u:object_r:healthd_exec:s0'* ]]; then
  echo "Verification failure: hash=$GOT / $LABEL; rolling back voltage-only healthd" >&2
  "${ADB[@]}" shell "cat /tmp/s55-healthd-voltage > '$TARGET' && sync" || true
  exit 1
fi
echo "SUCCESS healthd: $GOT; SELinux: $LABEL; /system will be RO"
