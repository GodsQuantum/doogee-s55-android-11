#!/usr/bin/env bash
# S55 Oreo vendor / crDroid11 compatibility: install two *stock* HIDL deps.
# No firmware flash, wipes, root-mode changes or global SELinux edits.
set -Eeuo pipefail
export LC_ALL=C
MODE="${1:---check}"
[[ "$MODE" =~ ^(--check|--apply|--restore)$ ]] || { echo "Usage: $0 --check|--apply|--restore" >&2; exit 2; }
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
C="$ROOT/files/candidates/s55-2018-compat"
source_files=(logwrap2018-64.so gesturewake2018-64.so)
target_files=(liblogwrap.so vendor.hct.hardware.gesturewake@1.0.so)
hashes=(305b1e419589b19836ed2986d5f43af34de6783e46d54230b23ef3e08081577a c0f5631eb2c3373e2a197282669f67ed31166fe508660718b6f14cb2103df318)
for i in 0 1; do
  local_sha="$(sha256sum "$C/${source_files[$i]}" | awk '{print $1}')"
  [[ "$local_sha" == "${hashes[$i]}" ]] || { echo "Invalid private donor SHA: ${source_files[$i]}" >&2; exit 1; }
done
mapfile -t SERIALS < <(adb devices | awk '$2=="recovery"{print $1}')
[[ "${#SERIALS[@]}" -eq 1 ]] || { echo "Exactly one device in TWRP required" >&2; exit 1; }
ADB=(adb -s "${SERIALS[0]}")
[[ "$("${ADB[@]}" shell getprop ro.product.device | tr -d '\r')" == S55 ]] || exit 1
[[ "$("${ADB[@]}" shell getprop ro.twrp.version | tr -d '\r')" == 3.1.1-0 ]] || exit 1
[[ "$("${ADB[@]}" shell id | tr -d '\r')" == uid=0* ]] || exit 1
VOLT="$("${ADB[@]}" shell cat /sys/class/power_supply/battery/batt_vol | tr -d '\r')"
CAPACITY="$("${ADB[@]}" shell cat /sys/class/power_supply/battery/capacity | tr -d '\r')"
[[ "$VOLT" =~ ^[0-9]+$ && "$VOLT" -gt 3300000 ]] || { echo "Unsafe battery voltage" >&2; exit 1; }
[[ "$CAPACITY" =~ ^[0-9]+$ && "$CAPACITY" -ge 30 ]] || { echo "Unsafe battery level" >&2; exit 1; }

ensure_vendor_mounted() {
  local actual
  actual="$("${ADB[@]}" shell 'mount | grep " on /vendor "' | tr -d '\r' || true)"
  if [[ -z "$actual" ]]; then
    "${ADB[@]}" shell 'mount -t ext4 -o ro,noload /dev/block/mmcblk0p27 /vendor'
    actual="$("${ADB[@]}" shell 'mount | grep " on /vendor "' | tr -d '\r' || true)"
  fi
  [[ "$actual" == *"mmcblk0p27 on /vendor type ext4"* ]] || {
    echo "Cannot verify the exact /vendor block device; refusing." >&2; exit 1;
  }
}
ensure_vendor_mounted
for i in 0 1; do
  path="/vendor/lib64/${target_files[$i]}"
  exists="$("${ADB[@]}" shell "test -f '$path' && echo yes || echo no" | tr -d '\r')"
  if [[ "$exists" == yes ]]; then
    sha="$("${ADB[@]}" shell "sha256sum '$path'" | tr -d '\r' | awk '{print $1}')"
    [[ "$sha" == "${hashes[$i]}" ]] || { echo "Unknown existing library, refusing: $path" >&2; exit 1; }
  else
    sha=missing
  fi
  printf 'CHECK %s=%s\n' "${target_files[$i]}" "$sha"
done
if [[ "$MODE" == --check ]]; then echo 'CHECK PASSED, no writes'; exit 0; fi
# Stage both small validated binaries to recovery RAM before altering /vendor.
if [[ "$MODE" == --apply ]]; then
  for i in 0 1; do
    "${ADB[@]}" push "$C/${source_files[$i]}" "/tmp/s55-compat-$i.so" >/dev/null
    sha="$("${ADB[@]}" shell "sha256sum /tmp/s55-compat-$i.so" | tr -d '\r' | awk '{print $1}')"
    [[ "$sha" == "${hashes[$i]}" ]] || { echo "ADB transfer mismatch" >&2; exit 1; }
  done
fi
ensure_vendor_mounted
"${ADB[@]}" shell 'mount -o remount,rw /vendor'
ACTUAL_MOUNT="$("${ADB[@]}" shell 'mount | grep " on /vendor "' | tr -d '\r' || true)"
[[ "$ACTUAL_MOUNT" == *' on /vendor type ext4 (rw,'* ]] || {
  echo "Vendor remount was not confirmed RW; no files changed." >&2; exit 1;
}
cleanup() {
  "${ADB[@]}" shell 'mount -o remount,ro /vendor' >/dev/null 2>&1 || true
  "${ADB[@]}" shell 'rm -f /tmp/s55-compat-0.so /tmp/s55-compat-1.so' >/dev/null 2>&1 || true
}
trap cleanup EXIT
for i in 0 1; do
  path="/vendor/lib64/${target_files[$i]}"
  if [[ "$MODE" == --apply ]]; then
    "${ADB[@]}" shell "cat /tmp/s55-compat-$i.so > '$path' && chown 0:0 '$path' && chmod 0644 '$path' && chcon u:object_r:vendor_file:s0 '$path' && sync"
    sha="$("${ADB[@]}" shell "sha256sum '$path'" | tr -d '\r' | awk '{print $1}')"
    [[ "$sha" == "${hashes[$i]}" ]] || { echo "Installed file SHA mismatch, restore with --restore" >&2; exit 1; }
    label="$("${ADB[@]}" shell "ls -lZ '$path'" | tr -d '\r')"
    [[ "$label" == *"u:object_r:vendor_file:s0"* ]] || { echo "SELinux label mismatch, restore with --restore" >&2; exit 1; }
    echo "INSTALLED ${target_files[$i]}"
  else
    "${ADB[@]}" shell "rm -f '$path' && sync"
    echo "REMOVED ${target_files[$i]}"
  fi
done
echo "SUCCESS $MODE — /vendor will return to read-only."
