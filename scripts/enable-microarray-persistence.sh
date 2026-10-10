#!/usr/bin/env bash
# S55 only: combine exact MicroArray enumeration patch with PHH cleanup retention.
# No fingerprint templates are read, exported, deleted or modified.
set -Eeuo pipefail
MODE=--check
if [[ $# -gt 0 ]]; then MODE="$1"; fi
[[ $# -le 1 && ( "$MODE" == --check || "$MODE" == --apply ) ]] ||
  { echo "Usage: $0 [--check|--apply]" >&2; exit 2; }
die(){ printf 'S55_FINGERPRINT: %s\n' "$*" >&2; exit 1; }
adb_one(){
  [[ "$(adb devices | awk '$2=="device"{n++} END{print n+0}')" == 1 ]] ||
    die "Exactly one authorized running Android device is required"
}
read_phone(){ adb shell "$1" | tr -d '\r'; }
adb_one
[[ "$(read_phone 'getprop ro.vendor.build.fingerprint')" == DOOGEE/S55/S55:* ]] || die "Refusing non-S55 vendor"
[[ "$(read_phone 'getprop ro.build.version.release')" == 11 ]] || die "Android 11 required"
[[ "$(read_phone 'getprop sys.boot_completed')" == 1 ]] || die "Android not booted"
[[ "$(read_phone 'getprop ro.hardware.fingerprint')" == microarray ]] ||
  die "Unknown fingerprint HAL"
[[ "$(read_phone getenforce)" == Enforcing ]] || die "SELinux must remain Enforcing"
golden=3d89603ed3025bdc14e65d6269024c52920808c747aeb2d79417741d7cc7f9f6
current="$(read_phone 'sha256sum /vendor/lib64/libfprint-x64.so' | awk '{print $1}')"
[[ "$current" == "$golden" ]] || die "MicroArray enumerator hash differs; do not use override"
prop=persist.sys.phh.fingerprint.nocleanup
before="$(read_phone "getprop $prop")"
if [[ "$MODE" == --check ]]; then
  [[ "$before" == true ]] || die "PHH retention is not enabled; run --apply"
  echo 'S55_PHH_MICROARRAY_RETENTION_ENABLED; ENROLL_AND_AUTHENTICATE_AFTER_REBOOT_TO_VALIDATE'
  exit 0
fi
if [[ "$before" == true ]]; then
  echo 'S55_PHH_MICROARRAY_RETENTION_ALREADY_ENABLED'
  exit 0
fi
[[ "$(read_phone 'getprop ro.debuggable')" == 1 ]] ||
  die "ADB root unavailable on this Android build; no changes made"
command -v timeout >/dev/null || die "timeout required on Linux"
adb root >/dev/null || die "Cannot temporarily enable ADB root"
trap 'adb unroot >/dev/null 2>&1 || true' EXIT
timeout 45 adb wait-for-device >/dev/null || die "ADB root did not reconnect"
[[ "$(read_phone id)" == uid=0* ]] || die "Root ADB not available"
adb shell "setprop $prop true" || die "Cannot set PHH retention"
[[ "$(read_phone "getprop $prop")" == true ]] || die "PHH retention value did not persist"
adb unroot >/dev/null || die "Failed to return ADB to non-root"
timeout 45 adb wait-for-device >/dev/null || die "Unprivileged ADB did not reconnect"
trap - EXIT
[[ "$(read_phone "getprop $prop")" == true ]] || die "Retention disappeared after ADB unroot"
echo 'S55_PHH_MICROARRAY_RETENTION_ENABLED; ENROLL_AND_AUTHENTICATE_AFTER_REBOOT_TO_VALIDATE'
