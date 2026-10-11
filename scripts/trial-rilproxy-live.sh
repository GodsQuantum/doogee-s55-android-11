#!/usr/bin/env bash
# Reversible S55 RIL test: temporary bind mount only, never flash vendor.
set -euo pipefail
export LC_ALL=C
ORIG=425312124514d3b87e0d8f249bb92596a2b90e6212c9484b524e761227f15f07
PATCH=f47a4248174b4f375d82ccf1a83fc5bb4bcdea0d8594a7904195a37f4b9ac4f0
TARGET=/vendor/lib64/librilproxy.so
DEVICE_TMP=/data/local/tmp/s55-ril-trial-20261011.so
RAM_TMP=/dev/s55-ril-trial-20261011.so
usage() { echo "Usage: $0 --check | --trial <private-candidate.so> [seconds] | --recover" >&2; exit 2; }
[[ $# -ge 1 ]] || usage
mode=$1
case "$mode" in
  --check) [[ $# -eq 1 ]] || usage ;;
  --recover) [[ $# -eq 1 ]] || usage ;;
  --trial) [[ $# -ge 2 && $# -le 3 ]] || usage ;;
  *) usage ;;
esac
command -v adb >/dev/null || { echo "adb not found" >&2; exit 3; }
device_count=$(adb devices | awk '$2=="device"{n++}END{print n+0}')
[[ "$device_count" == 1 ]] || { echo "One authorized ADB device required" >&2; exit 3; }
device_model=$(adb shell getprop ro.vendor.build.fingerprint | tr -d '\r')
[[ "$device_model" == DOOGEE/S55/S55:* ]] || { echo "Not S55" >&2; exit 3; }
read_phone() { adb shell "$1" | tr -d '\r'; }
[[ "$(read_phone 'getprop sys.boot_completed')" == 1 ]] || { echo "Android not booted" >&2; exit 3; }
[[ "$(read_phone getenforce)" == Enforcing ]] || { echo "Must be SELinux Enforcing" >&2; exit 3; }
[[ "$(read_phone 'getprop persist.sys.phh.restart_ril')" != true ]] || { echo "PHH restart RIL unsafe on S55" >&2; exit 3; }
hash_remote() { read_phone "sha256sum '$TARGET'" | awk '{print $1}'; }
if [[ "$mode" == --check ]]; then
  echo "RIL_HASH=$(hash_remote) service=$(read_phone 'getprop init.svc.ril-proxy')"
  exit 0
fi
did_root=0
restore_adb() {
  if [[ "$did_root" == 1 ]]; then
    adb unroot >/dev/null 2>&1 || :
    adb wait-for-device >/dev/null 2>&1 || :
  fi
}
root_adb() {
  adb root >/dev/null
  adb wait-for-device
  [[ "$(read_phone 'id -u')" == 0 ]] || { echo "Root disabled" >&2; exit 4; }
  did_root=1
}
rollback() {
  adb shell "set -eu
    current=\$(sha256sum '$TARGET' | awk '{print \$1}')
    if [ \"\$current\" = '$PATCH' ]; then
      setprop ctl.stop ril-proxy
      sleep 3
      umount '$TARGET'
    fi
    actual=\$(sha256sum '$TARGET' | awk '{print \$1}')
    if [ \"\$actual\" != '$ORIG' ]; then
      echo RIL_RESTORE_HASH_MISMATCH >&2
      exit 18
    fi
    if [ \"\$(getprop init.svc.ril-proxy)\" != running ]; then
      setprop ctl.start ril-proxy
    fi
    rm -f '$RAM_TMP' '$DEVICE_TMP'
    echo ORIGINAL_RIL_RESTORED
  "
}
if [[ "$mode" == --recover ]]; then
  trap restore_adb EXIT
  root_adb
  rollback
  [[ "$(hash_remote)" == "$ORIG" ]] || exit 18
  exit 0
fi
duration=60
if [[ $# -ge 3 ]]; then duration=$3; fi
[[ "$duration" =~ ^[0-9]+$ && "$duration" -ge 5 && "$duration" -le 180 ]] || {
  echo "Duration must be 5..180 seconds" >&2; exit 2;
}
candidate=$2
[[ -f "$candidate" ]] || { echo "Candidate missing" >&2; exit 2; }
[[ "$(sha256sum "$candidate" | awk '{print $1}')" == "$PATCH" ]] || { echo "Candidate SHA mismatch" >&2; exit 5; }
[[ "$(hash_remote)" == "$ORIG" ]] || { echo "Original not active, use --recover" >&2; exit 5; }
trap restore_adb EXIT
root_adb
cleanup() {
  local rc=$?
  trap - EXIT INT TERM
  if ! rollback; then
    echo "CRITICAL: rollback failed. Retry --recover or reboot to clear temporary mount." >&2
    rc=19
  fi
  restore_adb
  exit "$rc"
}
trap cleanup EXIT
adb shell "test ! -e '$DEVICE_TMP' && test ! -e '$RAM_TMP'"
adb push "$candidate" "$DEVICE_TMP" >/dev/null
adb shell "set -eu
  cp '$DEVICE_TMP' '$RAM_TMP'
  chmod 644 '$RAM_TMP'
  chown root:root '$RAM_TMP'
  chcon u:object_r:vendor_file:s0 '$RAM_TMP'
  test \"\$(sha256sum '$RAM_TMP' | awk '{print \$1}')\" = '$PATCH'
  test \"\$(getprop persist.sys.phh.restart_ril)\" != true
  mount -o bind '$RAM_TMP' '$TARGET'
  test \"\$(sha256sum '$TARGET' | awk '{print \$1}')\" = '$PATCH'
  setprop ctl.restart ril-proxy
"
sleep 4
pid=$(read_phone 'pidof rilproxy')
[[ -n "$pid" && "$(read_phone 'getprop init.svc.ril-proxy')" == running ]] || {
  echo "RIL not running" >&2; exit 6;
}
echo "PATCH_MOUNTED_RIL_PID=$pid"
read_phone "grep 'librilproxy.so' /proc/$pid/maps | head -1"
n=0
while (( n < duration )); do
  sleep 5
  status=$(read_phone 'getprop init.svc.ril-proxy')
  current=$(read_phone 'pidof rilproxy' || :)
  [[ "$status" == running && "$current" == "$pid" ]] || {
    echo "RIL died/restarted" >&2; exit 7;
  }
  n=$((n+5))
done
echo "S55_RIL_TRANSIENT_TRIAL_PASS duration=$duration seconds (SIM calls NOT certified)"
