#!/usr/bin/env bash
# DOOGEE S55: verify, flash or restore the non-SAR LineageOS 18.1 system.
# MUST run from Pegasus while the phone is in TWRP 3.1.1 via USB.
# Does not touch boot, recovery, lk, GPT, vendor, nvram or nvdata.
set -Eeuo pipefail
export LC_ALL=C
MODE="${1:-}"
[[ "$MODE" =~ ^(--check|--flash|--restore)$ ]] || {
  echo "Usage: $0 --check | --flash | --restore" >&2; exit 2;
}
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="$ROOT/../los18.img"
BACKUPS="$ROOT/backups/device-2026-10-10"
BACKUP="$BACKUPS/system-active-before-lineage18.img.zst"
BACKUP_HASH="$BACKUPS/system-active-before-lineage18.raw.sha256"
EXPECTED_IMAGE="6ff112b937a5043aee862b48330a3895bb040461cdbe4304b342468600c7aaf5"
SYSTEM_BYTES=3263168512
IMAGE_BYTES=2055483392
IMAGE_BLOCKS=501827
PART="/dev/block/mmcblk0p28"

die() { echo "REFUSED: $*" >&2; exit 1; }
command -v adb >/dev/null || die 'ADB absent'
command -v sha256sum >/dev/null || die 'sha256sum absent'
command -v zstd >/dev/null || die 'zstd absent'
command -v stat >/dev/null || die 'stat absent'
command -v pv >/dev/null || die 'pv absent'
mapfile -t SERIALS < <(adb devices | awk '$2=="recovery"{print $1}')
[[ "${#SERIALS[@]}" -eq 1 ]] || die 'Exactly one device in recovery required'
ADB=(adb -s "${SERIALS[0]}")
[[ "$("${ADB[@]}" shell getprop ro.product.device | tr -d '\r')" == S55 ]] || die 'Not a DOOGEE S55'
[[ "$("${ADB[@]}" shell getprop ro.twrp.version | tr -d '\r')" == 3.1.1-0 ]] || die 'Expected original S55 TWRP 3.1.1'
[[ "$("${ADB[@]}" shell id | tr -d '\r')" == uid=0* ]] || die 'TWRP ADB is not root'
charge="$("${ADB[@]}" shell 'cat /sys/class/power_supply/battery/capacity' | tr -d '\r')"
volt="$("${ADB[@]}" shell 'cat /sys/class/power_supply/battery/batt_vol' | tr -d '\r')"
[[ "$charge" =~ ^[0-9]+$ && "$charge" -ge 30 ]] || die 'Battery reported below 30%'
[[ "$volt" =~ ^[0-9]+$ && "$volt" -ge 3500000 ]] || die 'Battery voltage too low'
blocks="$("${ADB[@]}" shell 'cat /sys/class/block/mmcblk0p28/size' | tr -d '\r')"
[[ "$blocks" =~ ^[0-9]+$ && $((blocks*512)) -eq "$SYSTEM_BYTES" ]] || die 'Unexpected system partition size'
mounts="$("${ADB[@]}" shell 'mount' | tr -d '\r')"
! grep -Eq 'mmcblk0p28 on | on /system ' <<<"$mounts" || die '/system is mounted; unmount before using script'
[[ -f "$IMAGE" && "$(stat -c '%s' "$IMAGE")" == "$IMAGE_BYTES" ]] || die 'ROM file missing or wrong size'
hash="$(sha256sum "$IMAGE" | awk '{print $1}')"
[[ "$hash" == "$EXPECTED_IMAGE" ]] || die 'LineageOS image hash mismatch'
[[ -f "$BACKUP" && -f "$BACKUP_HASH" ]] || die 'Current system backup and its raw SHA256 not complete'
savedhash="$(tr -d ' \n\r' < "$BACKUP_HASH")"
[[ "$savedhash" =~ ^[a-f0-9]{64}$ ]] || die 'Invalid backup hash'
zstd -q -t "$BACKUP" || die 'Backup is not decompressible'
echo "SAFE_PREFLIGHT: S55 TWRP /system partition $SYSTEM_BYTES bytes; battery $charge% $volt uV."
echo "ROM_SHA256 $hash"
echo "ROLLBACK_SHA256 $savedhash"

if [[ "$MODE" == '--check' ]]; then
  echo 'READ_ONLY_PREFLIGHT_PASS'
  exit 0
fi
if [[ "$MODE" == '--flash' ]]; then
  echo 'FLASHING LINEAGEOS 18.1 SYSTEM ONLY'
  # Phone receives a raw filesystem. exec-in is tested for correct stdin delivery.
  pv -f -s "$IMAGE_BYTES" "$IMAGE" | "${ADB[@]}" exec-in "dd of=$PART bs=4194304 2>/dev/null || exit 2; sync"
  echo 'READBACK_SHA256: physical p28 image region'
  actual="$("${ADB[@]}" exec-out "dd if=$PART bs=4096 count=$IMAGE_BLOCKS 2>/dev/null" | sha256sum | awk '{print $1}')"
  [[ "$actual" == "$EXPECTED_IMAGE" ]] || die "Flash readback mismatch ($actual); DO NOT BOOT. Restore with --restore."
  echo 'FLASH_READBACK_MATCHED'
  echo 'GROWING EXT4 to full p28 partition for GApps'
  # The image is smaller than the partition; grow only inside p28, never GPT.
  "${ADB[@]}" shell "e2fsck -fy $PART >/tmp/s55-lineage-e2fsck.log 2>&1; rc=\$?; [ \$rc -eq 0 -o \$rc -eq 1 ]" || die 'e2fsck failed; stay in TWRP'
  "${ADB[@]}" shell "resize2fs $PART" || die 'resize2fs failed; stay in TWRP'
  "${ADB[@]}" shell "e2fsck -fn $PART >/tmp/s55-lineage-final-e2fsck.log 2>&1; rc=\$?; [ \$rc -eq 0 ]" || die 'Final filesystem check failed; stay in TWRP'
  echo 'LINEAGE18_SYSTEM_WRITTEN_AND_EXT4_VERIFIED'
  echo 'Remain in TWRP for the GApps stage and optional data wipe.'
else
  echo 'RESTORE PREVIOUS CRDROID SYSTEM FROM PRIVATE VERIFIED BACKUP'
  zstd -dc "$BACKUP" | "${ADB[@]}" exec-in "dd of=$PART bs=4194304 2>/dev/null || exit 2; sync"
  echo 'READBACK_SHA256: full p28'
  actual="$("${ADB[@]}" exec-out "dd if=$PART bs=4096 count=$((SYSTEM_BYTES/4096)) 2>/dev/null" | sha256sum | awk '{print $1}')"
  [[ "$actual" == "$savedhash" ]] || die "Rollback readback mismatch ($actual), leave TWRP running"
  echo 'PREVIOUS_CRDROID_SYSTEM_RESTORED'
fi
