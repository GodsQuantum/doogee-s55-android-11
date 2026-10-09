#!/usr/bin/env bash
# DOOGEE S55 vendor ARM32 sensor ELF fix: add missing liblog.so DT_NEEDED.
# Exact hashes, exact recovery, reversible. Never changes bootloader/kernel.
set -Eeuo pipefail
export LC_ALL=C
MODE="${1:-}"
[[ "$MODE" == --check || "$MODE" == --apply || "$MODE" == --restore ]] || {
  echo "Usage: $0 --check|--apply|--restore" >&2; exit 2;
}
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRIVATE="$ROOT/files/candidates/s55-2018-compat"
NAMES=(msensord memsicp)
ORIG=(720ba2530b84bd7657bfd835430d3511ef4343c611116cd2502c816143845f39 960a1253262b641a47edda2c6bada399f2e20c8bc24a92c8e1bfbe489b4701d3)
FIX=(4a8a72f9ab04c0ea6375742fb2df46df1f40ef66c624b7846c039c3fdd254092 aa0c71b333ea0811e67add92feccee8998089836badb6e2d8a3d8cea62a25176)
for i in 0 1; do
  for suffix in original liblog-fixed; do
    expected="${ORIG[$i]}"
    [[ "$suffix" == liblog-fixed ]] && expected="${FIX[$i]}"
    actual="$(sha256sum "$PRIVATE/${NAMES[$i]}-$suffix" | awk '{print $1}')"
    [[ "$actual" == "$expected" ]] || { echo "Local image hash mismatch: ${NAMES[$i]}-$suffix" >&2; exit 1; }
  done
done
mapfile -t SERS < <(adb devices | awk '$2 == "recovery" {print $1}')
[[ "${#SERS[@]}" -eq 1 ]] || { echo "Expected exactly one authorized TWRP" >&2; exit 1; }
ADB=(adb -s "${SERS[0]}")
[[ "$("${ADB[@]}" shell getprop ro.product.device | tr -d '\r')" == S55 ]] || exit 1
[[ "$("${ADB[@]}" shell getprop ro.twrp.version | tr -d '\r')" == 3.1.1-0 ]] || exit 1
[[ "$("${ADB[@]}" shell id | tr -d '\r')" == uid=0* ]] || exit 1
CAP="$("${ADB[@]}" shell cat /sys/class/power_supply/battery/capacity | tr -d '\r')"
VOLT="$("${ADB[@]}" shell cat /sys/class/power_supply/battery/batt_vol | tr -d '\r')"
[[ "$CAP" =~ ^[0-9]+$ && "$CAP" -ge 30 ]] || { echo "Low reported charge" >&2; exit 1; }
[[ "$VOLT" =~ ^[0-9]+$ && "$VOLT" -ge 3300000 ]] || { echo "Low or invalid voltage" >&2; exit 1; }
ensure_vendor() {
  local cur
  cur="$("${ADB[@]}" shell 'mount | grep " on /vendor "' | tr -d '\r' || true)"
  if [[ -z "$cur" ]]; then
    "${ADB[@]}" shell 'mount -t ext4 -o ro,noload /dev/block/mmcblk0p27 /vendor'
    cur="$("${ADB[@]}" shell 'mount | grep " on /vendor "' | tr -d '\r' || true)"
  fi
  [[ "$cur" == *"mmcblk0p27 on /vendor type ext4"* ]] || {
    echo "Unexpected vendor mount" >&2; exit 1;
  }
}
ensure_vendor
for i in 0 1; do
  cur="$("${ADB[@]}" shell "sha256sum '/vendor/bin/${NAMES[$i]}'" | tr -d '\r' | awk '{print $1}')"
  [[ "$cur" == "${ORIG[$i]}" || "$cur" == "${FIX[$i]}" ]] || {
    echo "Unrecognized active binary ${NAMES[$i]}, no writes" >&2; exit 1;
  }
  echo "PRECHECK ${NAMES[$i]}=$cur"
done
if [[ "$MODE" == --check ]]; then echo "CHECK_OK (no writes)"; exit 0; fi
for i in 0 1; do
  "${ADB[@]}" push "$PRIVATE/${NAMES[$i]}-original" "/tmp/s55-${NAMES[$i]}-orig" >/dev/null
  "${ADB[@]}" push "$PRIVATE/${NAMES[$i]}-liblog-fixed" "/tmp/s55-${NAMES[$i]}-fixed" >/dev/null
  for kind in orig fixed; do
    ref="${ORIG[$i]}"; [[ "$kind" == fixed ]] && ref="${FIX[$i]}"
    rc="$("${ADB[@]}" shell "sha256sum /tmp/s55-${NAMES[$i]}-$kind" | tr -d '\r' | awk '{print $1}')"
    [[ "$rc" == "$ref" ]] || { echo "Transfer corrupt" >&2; exit 1; }
  done
done
ensure_vendor
"${ADB[@]}" shell 'mount -o remount,rw /vendor'
mnt="$("${ADB[@]}" shell 'mount | grep " on /vendor "' | tr -d '\r' || true)"
[[ "$mnt" == *' on /vendor type ext4 (rw,'* ]] || { echo "Vendor RW not confirmed" >&2; exit 1; }
cleanup() {
  "${ADB[@]}" shell 'mount -o remount,ro /vendor' >/dev/null 2>&1 || true
  "${ADB[@]}" shell 'rm -f /tmp/s55-msensord-orig /tmp/s55-msensord-fixed /tmp/s55-memsicp-orig /tmp/s55-memsicp-fixed' >/dev/null 2>&1 || true
}
trap cleanup EXIT
for i in 0 1; do
  kind=fixed; want="${FIX[$i]}"
  if [[ "$MODE" == --restore ]]; then kind=orig; want="${ORIG[$i]}"; fi
  path="/vendor/bin/${NAMES[$i]}"
  # Overwrite same inode, preserving SELinux extended attributes and ownership.
  "${ADB[@]}" shell "cat /tmp/s55-${NAMES[$i]}-$kind > '$path' && sync"
  got="$("${ADB[@]}" shell "sha256sum '$path'" | tr -d '\r' | awk '{print $1}')"
  label="$("${ADB[@]}" shell "ls -lZ '$path'" | tr -d '\r')"
  required_label='u:object_r:msensord_exec:s0'
  if [[ "${NAMES[$i]}" == 'memsicp' ]]; then required_label='u:object_r:memsicp_exec:s0'; fi
  if [[ "$got" != "$want" || "$label" != *"$required_label"* ]]; then
    echo "Sensor image/label unexpected: ${NAMES[$i]}; restoring original" >&2
    "${ADB[@]}" shell "cat /tmp/s55-${NAMES[$i]}-orig > '$path' && sync" || true
    exit 1
  fi
  echo "SUCCESS ${NAMES[$i]} $got $label"
done
echo "DONE — vendor remounted read-only on exit"
