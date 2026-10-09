#!/usr/bin/env bash
# DOOGEE S55/Oreo init + Android 11 GSI: prepare vendor CE/DE parents.
# Run in TWRP after format/wipe of /data, BEFORE first LineageOS boot.
# Idempotent. Does not alter boot/vendor/GPT/radio, erase or decrypt data.
set -Eeuo pipefail
export LC_ALL=C
MODE="${1:-}"
[[ "$MODE" == --check || "$MODE" == --apply ]] || {
  echo "Usage: $0 --check|--apply" >&2; exit 2;
}
mapfile -t DEVICES < <(adb devices | awk '$2 == "recovery" {print $1}')
[[ "${#DEVICES[@]}" == 1 ]] || { echo "Exactly one TWRP device required" >&2; exit 1; }
ADB=(adb -s "${DEVICES[0]}")
get() { "${ADB[@]}" shell "$1" | tr -d '\r'; }
[[ "$(get 'getprop ro.product.device')" == S55 ]] || exit 1
[[ "$(get 'getprop ro.twrp.version')" == 3.1.1-0 ]] || exit 1
[[ "$(get id)" == uid=0* ]] || exit 1
charge="$(get 'cat /sys/class/power_supply/battery/capacity')"
volt="$(get 'cat /sys/class/power_supply/battery/batt_vol')"
[[ "$charge" =~ ^[0-9]+$ && "$charge" -ge 30 ]] || exit 1
[[ "$volt" =~ ^[0-9]+$ && "$volt" -ge 3500000 ]] || exit 1
size="$(get 'cat /sys/class/block/mmcblk0p30/size')"
[[ "$size" == 112476127 ]] || { echo "Unexpected /data partition geometry" >&2; exit 1; }

mnt="$(get 'mount | grep " on /data "' || true)"
if [[ -z "$mnt" ]]; then
  "${ADB[@]}" shell 'mount -t ext4 -o rw /dev/block/mmcblk0p30 /data'
  mnt="$(get 'mount | grep " on /data "' || true)"
fi
[[ "$mnt" == *"mmcblk0p30 on /data type ext4 (rw,"* ]] || {
  echo "/data not mounted from p30 RW" >&2; exit 1;
}
for target in vendor_de vendor_ce; do
  type="$(get "if [ -L /data/$target ]; then echo symlink; elif [ -d /data/$target ]; then echo dir; elif [ -e /data/$target ]; then echo other; else echo absent; fi")"
  [[ "$type" == dir || "$type" == absent ]] || {
    echo "Unsafe pre-existing /data/$target: $type" >&2; exit 1;
  }
  echo "PREFLIGHT /data/$target=$type"
done
if [[ "$MODE" == --check ]]; then
  echo "CHECK_PASS (no files modified)"
  exit 0
fi
"${ADB[@]}" shell 'mkdir -p /data/vendor_de /data/vendor_ce &&
  chown 0:0 /data/vendor_de /data/vendor_ce &&
  chmod 0771 /data/vendor_de /data/vendor_ce &&
  chcon u:object_r:vendor_data_file:s0 /data/vendor_de /data/vendor_ce &&
  sync'
for target in vendor_de vendor_ce; do
  label="$(get "ls -ldZ /data/$target")"
  [[ "$label" == *"u:object_r:vendor_data_file:s0"* ]] || {
    echo "SELinux label wrong: $target" >&2; exit 1;
  }
  echo "PREPARED $target: $label"
done
echo "SUCCESS: native vold parent directories are ready before boot."
