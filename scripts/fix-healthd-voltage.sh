#!/usr/bin/env bash
# DOOGEE S55 crDroid 7.16: guarded, reversible healthd battery-voltage path fix.
# NO flash, format, repartition, global SELinux changes or kernel modifications.
set -Eeuo pipefail
export LC_ALL=C

usage() {
  echo "Usage: $0 --check | --apply | --restore" >&2
  exit 2
}
[[ "${1:-}" =~ ^(--check|--apply|--restore)$ ]] || usage
MODE="$1"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP="$ROOT/backups/device-2026-10-10"
SOURCE="$BACKUP/healthd-android11-original"
PATCHED="$BACKUP/healthd-android11-voltage-patched"
SOURCE_SHA="14f0dbbb8ae722df2da8f1b040a6412cc6541e0ac20fd37cc4b782e98a845ef3"
PATCH_SHA="d364def27affe780131c22c3d5a89c60e73f7e3bba12b6093c235f3a69cc9b05"
TARGET="/system/bin/healthd"
command -v adb >/dev/null || { echo "adb required" >&2; exit 1; }
command -v sha256sum >/dev/null || { echo "sha256sum required" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 required" >&2; exit 1; }
mapfile -t SERIALS < <(adb devices | awk '$2=="recovery"{print $1}')
[[ "${#SERIALS[@]}" -eq 1 ]] || { echo "Exactly one recovery device is required" >&2; exit 1; }
ADB=(adb -s "${SERIALS[0]}")
[[ "$("${ADB[@]}" shell getprop ro.twrp.version | tr -d '\r')" == "3.1.1-0" ]] || {
  echo "Expected S55 TWRP 3.1.1, refusing action" >&2; exit 1;
}
[[ "$("${ADB[@]}" shell getprop ro.product.device | tr -d '\r')" == "S55" ]] || {
  echo "Expected device S55, refusing action" >&2; exit 1;
}
[[ "$("${ADB[@]}" shell id | tr -d '\r')" == uid=0* ]] || {
  echo "No TWRP root, refusing action" >&2; exit 1;
}
ROOT_PATH="$("${ADB[@]}" shell "cat /sys/class/power_supply/battery/batt_vol 2>/dev/null" | tr -d '\r')"
[[ "$ROOT_PATH" =~ ^[0-9]+$ && "$ROOT_PATH" -gt 3000000 ]] || {
  echo "Battery voltage unavailable or too low; refusing" >&2; exit 1;
}
CAPACITY="$("${ADB[@]}" shell "cat /sys/class/power_supply/battery/capacity" | tr -d '\r')"
[[ "$CAPACITY" =~ ^[0-9]+$ && "$CAPACITY" -ge 30 ]] || {
  echo "Battery reported below 30%; refusing" >&2; exit 1;
}
[[ -f "$SOURCE" ]] || { echo "Private original backup not present: $SOURCE" >&2; exit 1; }
[[ "$(sha256sum "$SOURCE" | cut -d' ' -f1)" == "$SOURCE_SHA" ]] || {
  echo "Backup SHA256 mismatch" >&2; exit 1;
}
python3 "$ROOT/scripts/patch-healthd-voltage.py" "$SOURCE" "$PATCHED" >/dev/null
[[ "$(sha256sum "$PATCHED" | cut -d' ' -f1)" == "$PATCH_SHA" ]] || {
  echo "Patched SHA256 mismatch" >&2; exit 1;
}
CURRENT="$("${ADB[@]}" shell "sha256sum '$TARGET'" | tr -d '\r' | awk '{print $1}')"
printf 'Phone battery %s%%, %s microvolts; healthd=%s; mode=%s\n' "$CAPACITY" "$ROOT_PATH" "$CURRENT" "$MODE"
[[ "$CURRENT" == "$SOURCE_SHA" || "$CURRENT" == "$PATCH_SHA" ]] || {
  echo "Unrecognized healthd. No changes made." >&2; exit 1;
}
if [[ "$MODE" == "--check" ]]; then
  echo "SAFE: preflight passed, no partition modifications."
  exit 0
fi
EXPECTED="$PATCH_SHA"; PAYLOAD="$PATCHED"
if [[ "$MODE" == "--restore" ]]; then EXPECTED="$SOURCE_SHA"; PAYLOAD="$SOURCE"; fi
if [[ "$CURRENT" == "$EXPECTED" ]]; then
  echo "Already in requested state, no modifications."
  exit 0
fi

# Stage both good images in TWRP RAM so rollback does not rely on the host USB
# remaining up after /system remount.
"${ADB[@]}" push "$SOURCE" /tmp/s55-healthd-original >/dev/null
"${ADB[@]}" push "$PATCHED" /tmp/s55-healthd-patched >/dev/null
[[ "$("${ADB[@]}" shell sha256sum /tmp/s55-healthd-original | tr -d '\r' | awk '{print $1}')" == "$SOURCE_SHA" ]] || exit 1
[[ "$("${ADB[@]}" shell sha256sum /tmp/s55-healthd-patched | tr -d '\r' | awk '{print $1}')" == "$PATCH_SHA" ]] || exit 1
REMOTE=/tmp/s55-healthd-patched
if [[ "$MODE" == "--restore" ]]; then REMOTE=/tmp/s55-healthd-original; fi

echo "Requesting temporary RW remount of /system only."
"${ADB[@]}" shell 'mount -o remount,rw /system' || {
  echo "Cannot remount /system RW; no executable altered." >&2; exit 1;
}
# Always restore the read-only mount, even if the phone rejects the binary.
cleanup() {
  "${ADB[@]}" shell 'mount -o remount,ro /system' >/dev/null 2>&1 || true
  "${ADB[@]}" shell 'rm -f /tmp/s55-healthd-original /tmp/s55-healthd-patched' >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Writing into an existing inode preserves ownership, permission bits and xattrs.
"${ADB[@]}" shell "cat '$REMOTE' > '$TARGET' && sync" || true
FINAL="$("${ADB[@]}" shell "sha256sum '$TARGET'" | tr -d '\r' | awk '{print $1}')"
if [[ "$FINAL" != "$EXPECTED" ]]; then
  echo "Verification failed ($FINAL); restoring original." >&2
  "${ADB[@]}" shell "cat /tmp/s55-healthd-original > '$TARGET' && sync" || true
  exit 1
fi
LABEL="$("${ADB[@]}" shell "ls -lZ '$TARGET'" | tr -d '\r')"
if ! grep -q 'u:object_r:healthd_exec:s0' <<<"$LABEL"; then
  echo "SELinux label changed unexpectedly: $LABEL; restoring original." >&2
  "${ADB[@]}" shell "cat /tmp/s55-healthd-original > '$TARGET' && sync" || true
  exit 1
fi
printf 'SUCCESS: SHA256 %s; label %s\n' "$FINAL" "$LABEL"
