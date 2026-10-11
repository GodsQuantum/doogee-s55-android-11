#!/usr/bin/env bash
# Guided single-command stock S55 -> LineageOS 18.1 + GApps.
# Uses ONLY local, hash-pinned assets; never touches preloader or radio firmware.
set -Eeuo pipefail
export LC_ALL=C
# The INSTALL.sh is copied to the ROOT of each offline kit, not left inside
# the source repository's installer/ directory.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1:---install}"
ASSET="$ROOT/assets"
VENDOR_SHA=efef359fef8f6cd6dde651e4b6e4034cbf7ec2fdc8cc83087d079e5d2dbde759
BACK="$ROOT/private-install-state"
SCRIPTS="$ROOT/scripts"
LOG="$BACK/install.log"
progress_stream(){
  local total="$1"
  if command -v pv >/dev/null; then pv -f -s "$total"
  else python3 -u "$SCRIPTS/progress-stream.py" "$total"
  fi
}
die(){ printf 'STOP: %s\n' "$*" >&2; exit 1; }
step(){ printf '\n==> %s\n' "$*"; }
for c in sha256sum xz zstd awk python3 stat df; do
  command -v "$c" >/dev/null || die "Missing Linux command: $c"
done
[[ "$MODE" == --check || "$MODE" == --plan || "$MODE" == --install || "$MODE" == --verify || "$MODE" == --recovery-check ]] ||
  die "Usage: ./INSTALL.sh [--plan|--check|--verify|--recovery-check|--install]"
if [[ "$MODE" == --check || "$MODE" == --install || "$MODE" == --verify ]]; then
  command -v adb >/dev/null || die "Missing Linux adb"
fi
if [[ "$MODE" == --check || "$MODE" == --install ]]; then
  command -v fastboot >/dev/null || die "Missing Linux fastboot"
fi
if [[ "$MODE" == --install ]]; then
  command -v flock >/dev/null || die "Missing Linux flock"
fi
[[ -f "$ROOT/manifest.sha256" ]] || die "Kit incomplete: manifest.sha256 absent"
step "Verify every vendor, ROM and Google asset BEFORE changing the phone"
(cd "$ROOT" && sha256sum -c manifest.sha256) || die "Kit verification failed"
[[ -s "$ASSET/lineage18.img.xz" && -s "$ASSET/twrp-s55.img" &&
   -s "$ASSET/boot-tested-s55.img" && -s "$ASSET/nikgapps-core-11.zip" &&
   -s "$ASSET/vendor-s55-known-good.img.zst" ]] ||
  die "Missing files in assets/"
[[ -f "$SCRIPTS/fix-lineage18-thermal-sepolicy.sh" &&
   -f "$SCRIPTS/progress-stream.py" &&
   -f "$SCRIPTS/enable-microarray-persistence.sh" ]] ||
  die "Kit incomplete: required safety/fingerprint helper scripts missing"
if [[ "$MODE" == --plan ]]; then
  cat <<'NOTE'
STOCK DOOGEE S55, never S55 Lite. One command, guided:
  verify files -> unlock OEM if needed -> enter TWRP -> backup GPT,
  original system, boot, recovery, vendor, unique radio calibration
  -> enlarge /system and shrink /cache (known stock GPT only)
  -> flash/check LineageOS 18.1 -> clone exact working vendor with
     fingerprint/HIDL/sensors/thermal SELinux fixes already applied
  -> install NikGapps from recovery RAM without needing encrypted /data
  -> full /data format and prepare Android 11 vendor CE/DE
  -> patch healthd voltage and battery temperature
  -> copy exact known-good S55 boot -> reboot Android
  -> set guarded PHH MicroArray template retention (on Android 11)
  -> enroll a finger, reboot, unlock with SAME finger to accept biometrics.
This is a local community installer, not an official manufacturer update.
--plan does not communicate with the phone or write any partition.
NOTE
  exit 0
fi
# Verify saved per-phone original partitions without accessing any connected phone.
# This is NOT an automatic restore, nor does it bring back deleted userdata.
if [[ "$MODE" == --recovery-check ]]; then
  original="$BACK/backup"
  [[ -s "$original/gpt-original.bin" && -s "$original/gpt-original.sha256" ]] ||
    die "No complete original GPT backup under private-install-state"
  [[ "$(sha256sum "$original/gpt-original.bin" | awk '{print $1}')" == "$(cat "$original/gpt-original.sha256")" ]] ||
    die "Original GPT backup checksum differs"
  for part in system cache boot recovery vendor nvram nvdata protect1 protect2; do
    file="$original/$part.img.zst"
    [[ -s "$file" && -s "$file.raw.sha256" ]] ||
      die "Missing checked original backup for $part"
    zstd -q -t "$file" || die "Compressed backup failed validation: $part"
    [[ "$(zstd -dc "$file" | sha256sum | awk '{print $1}')" == "$(cat "$file.raw.sha256")" ]] ||
      die "Original raw checksum mismatch: $part"
    echo "ORIGINAL_BACKUP_SHA256_OK $part"
  done
  echo "NINE_ORIGINAL_PARTITIONS_PLUS_GPT_VERIFIED; NO_PHONE_OPERATIONS; NO_AUTOMATIC_RESTORE"
  exit 0
fi
if [[ "$MODE" == --check ]]; then
  echo "HOST_ASSETS_OK"
  adb devices -l
  fastboot devices -l
  if [[ "$(adb devices | awk '$2=="device" || $2=="recovery"{n++} END{print n+0}')" -eq 1 ]]; then
    echo "CONNECTED_MODEL=$(adb shell getprop ro.product.model | tr -d '\r')"
    echo "CONNECTED_VERSION=$(adb shell getprop ro.build.version.release | tr -d '\r')"
    echo "CONNECTED_TWRP=$(adb shell getprop ro.twrp.version | tr -d '\r')"
  else
    echo "PHONE_NOT_CHECKED — no unique authorized ADB device; only asset checks completed"
  fi
  exit 0
fi
# Post-boot audit needs no recovery, no root, and never writes Android settings.
if [[ "$MODE" == --verify ]]; then
  [[ "$(adb devices | awk '$2=="device"{n++} END{print n+0}')" -eq 1 ]] ||
    die "Exactly one authorized Android phone required"
  check_android(){ adb shell "$1" | tr -d '\r'; }
  [[ "$(check_android 'getprop ro.vendor.build.fingerprint')" == DOOGEE/S55/S55:* ]] || die "Not DOOGEE S55 vendor"
  [[ "$(check_android 'getprop ro.build.version.release')" == 11 ]] || die "Not Android 11"
  [[ "$(check_android 'getprop sys.boot_completed')" == 1 ]] || die "Android not fully booted"
  [[ "$(check_android getenforce)" == Enforcing ]] || die "SELinux not enforcing"
  apps="$(check_android 'pm list packages')"
  for pkg in com.google.android.gms com.android.vending com.google.android.gsf; do
    grep -Fqx "package:$pkg" <<<"$apps" || die "Missing $pkg"
  done
  battemp="$(check_android 'dumpsys battery | sed -n "s/.*temperature: *//p" | head -1')"
  [[ "$battemp" =~ ^[0-9]+$ && "$battemp" -gt 0 ]] || die "Battery temperature telemetry absent"
  batvolt="$(check_android 'dumpsys battery | sed -n "s/^[[:space:]]*voltage:[[:space:]]*//p" | head -1')"
  [[ "$batvolt" =~ ^[0-9]+$ && "$batvolt" -ge 3000 && "$batvolt" -le 4500 ]] ||
    die "Invalid battery voltage telemetry (expected millivolts)"
  thermal="$(check_android 'dumpsys thermalservice')"
  for sensor in CPU_T GPU_T BAT_T SKIN_T; do
    grep -Fq "mName=$sensor" <<<"$thermal" || die "Missing thermal sensor $sensor"
  done
  # The fix is a PAIR: exactly patched MicroArray enumerator AND PHH
  # template-cleanup retention. Neither alone is an acceptance test.
  [[ "$(check_android 'getprop ro.hardware.fingerprint')" == microarray ]] ||
    die "Unexpected fingerprint hardware (expected MicroArray)"
  fp_hash="$(check_android 'sha256sum /vendor/lib64/libfprint-x64.so' | awk '{print $1}')"
  [[ "$fp_hash" == 3d89603ed3025bdc14e65d6269024c52920808c747aeb2d79417741d7cc7f9f6 ]] ||
    die "MicroArray enumerator hash mismatch; verified vendor patch missing"
  [[ "$(check_android 'getprop persist.sys.phh.fingerprint.nocleanup')" == true ]] ||
    die "MicroArray retention not set; apply scripts/enable-microarray-persistence.sh --apply"
  # On S55 PHH restart_ril=true caused repeated boot/preloader transitions.
  [[ "$(check_android 'getprop persist.sys.phh.restart_ril')" != true ]] ||
    die "Unsafe PHH restart_ril=true caused reboot loops on S55"
  echo "RIL_AUTORESTART_LOOP_PROTECTION_OK"
  ril_hash="$(check_android 'sha256sum /vendor/lib64/librilproxy.so' | awk '{print $1}')"
  case "$ril_hash" in
    f47a4248174b4f375d82ccf1a83fc5bb4bcdea0d8594a7904195a37f4b9ac4f0)
      echo "S55_RIL_NULL_CALLBACK_GUARD_PERSISTENT_VERIFIED" ;;
    425312124514d3b87e0d8f249bb92596a2b90e6212c9484b524e761227f15f07)
      echo "S55_RIL_NULL_CALLBACK_GUARD_NOT_INSTALLED_OEM_VENDOR" ;;
    *)
      die "Unknown /vendor/lib64/librilproxy.so SHA256; do not overwrite" ;;
  esac
  echo "FINGERPRINT_PATCH_AND_PHH_RETENTION_VERIFIED_READ_ONLY"
  echo "FINGERPRINT_PHYSICAL_ACCEPTANCE: enroll, reboot, unlock with SAME finger (user action)"
  for setting in low_power_trigger_level automatic_power_save_mode mobile_data_always_on ble_scan_always_enabled; do
    echo "NATIVE_POWER_SETTING $setting=$(check_android "settings get global $setting")"
  done
  echo "ANDROID11_GAPPS_THERMAL_SELINUX_VERIFIED_READ_ONLY"
  echo "NOTE: --verify checks the FIX CONFIGURATION, not a finger's physical acceptance"
  exit 0
fi
cat <<'WARNING'
FULL DATA ERASURE: all apps AND shared internal media are lost.
Bootloader unlocking also erases device data.
A computer-level backup of user files must be performed beforehand.
At least 40% battery, stable USB and a Linux host are required.
Never run this kit on S55 Lite or a different revision.
The supplied known-good 2020 boot is not tested against every stock S55.
Do not disconnect the cable during flash operations.
WARNING
read -r -p "Type INSTALL-S55-ERASE-ALL to proceed: " answer
[[ "$answer" == INSTALL-S55-ERASE-ALL ]] || die "Cancelled"
mkdir -p "$BACK"/backup
chmod 700 "$BACK" "$BACK/backup"
exec 9>"$BACK/.installer.lock"
flock -n 9 || die "Another instance of this kit installer is already running"
free_bytes="$(df -B1 --output=avail "$BACK" | tail -1 | tr -d ' ')"
[[ "$free_bytes" =~ ^[0-9]+$ && "$free_bytes" -ge 6442450944 ]] ||
  die "At least 6 GiB host disk space required for private system and radio backups"
touch "$LOG"; chmod 600 "$LOG"
exec > >(tee -a "$LOG") 2>&1
echo "INSTALL_SESSION $(date -Is)"
on_exit(){ local status=$?; echo "INSTALL_FINISHED_OR_STOPPED rc=$status $(date -Is); private backup=$BACK/backup"; }
trap on_exit EXIT
# Interrupted destructive operations never rerun automatically.
stage_begin(){
  local stage="$1"
  [[ ! -e "$BACK/$stage.inflight" && ! -e "$BACK/$stage.ok" ]] ||
    die "Ambiguous checkpoint for $stage: manual recovery audit required"
  printf 'INFLIGHT %s %s\n' "$stage" "$(date -Is)" > "$BACK/$stage.inflight"
  chmod 600 "$BACK/$stage.inflight"
}
stage_done(){
  local stage="$1"
  [[ -s "$BACK/$stage.inflight" ]] || die "Missing in-flight guard for $stage"
  printf 'DONE %s %s\n' "$stage" "$(date -Is)" > "$BACK/$stage.ok.tmp"
  chmod 600 "$BACK/$stage.ok.tmp"
  mv -- "$BACK/$stage.ok.tmp" "$BACK/$stage.ok"
  rm -f -- "$BACK/$stage.inflight"
}
for stage in repartition cache system vendor gapps data thermal boot; do
  [[ ! -e "$BACK/$stage.inflight" ]] ||
    die "Interrupted $stage: STOP. Inspect actual partition state; do not blindly retry"
done
remote(){ adb shell "$1" | tr -d '\r'; }
adb_one(){
  [[ "$(adb devices | awk '$2=="device" || $2=="recovery"{c++} END {print c+0}')" == 1 ]] ||
    die "Connect exactly ONE authorized Android device"
}
wait_recovery(){
  local n
  for n in $(seq 1 180); do
    if [[ "$(adb devices | awk '$2=="recovery"{print $2}')" == recovery ]]; then
      adb_one
      [[ "$(remote 'getprop ro.product.device')" == S55 ]] || die "Not S55"
      [[ "$(remote 'getprop ro.twrp.version')" == 3.1.1-0 ]] || die "Wrong TWRP"
      [[ "$(remote id)" == uid=0* ]] || die "TWRP ADB not root"
      return
    fi
    sleep 2
  done
  die "TWRP not available. Reconnect it and rerun this kit."
}
wait_fastboot(){
  local n
  for ((n=1;n<=90;n++)); do
    [[ "$(fastboot devices | awk 'END{print NR+0}')" -eq 1 ]] && return
    sleep 2
  done
  die "Fastboot not found"
}
recovery_checks(){
  wait_recovery
  soc="$(remote 'cat /sys/class/power_supply/battery/capacity')"
  uv="$(remote 'cat /sys/class/power_supply/battery/batt_vol')"
  [[ "$soc" =~ ^[0-9]+$ && "$soc" -ge 40 ]] || die "Battery charge $soc% below 40%"
  [[ "$uv" =~ ^[0-9]+$ && "$uv" -ge 3600000 ]] || die "Battery voltage $uv microvolts too low"
}
ensure_recovery(){
  local seen_stock=0 product
  if [[ "$(adb devices | awk '$2=="recovery"{c++} END{print c+0}')" -eq 1 ]]; then
    recovery_checks; return
  fi
  if [[ "$(adb devices | awk '$2=="device"{c++} END{print c+0}')" -eq 1 ]]; then
    adb_one
    [[ "$(remote 'getprop ro.product.device')" == S55 ]] || die "Not DOOGEE S55"
    os="$(remote 'getprop ro.build.version.release')"
    [[ "$os" == 8* ]] || die "Not STOCK Android 8 (current is $os); preserving working Android"
    adb reboot bootloader
    seen_stock=1
  fi
  wait_fastboot
  product="$(fastboot getvar product 2>&1 || true)"
  grep -Eiq 'product:[[:space:]]*K50V1_64' <<<"$product" ||
    die "Wrong/unknown fastboot product; expected K50V1_64, no flash"
  [[ "$seen_stock" == 1 || -f "$BACK/target-recovery-id.sha256" ]] ||
    die "Cannot verify stock Android from fastboot alone; start from stock Android 8 ADB"

  is_unlocked(){
    local state
    state="$(fastboot getvar unlocked 2>&1 || true)"
    if grep -Eiq 'unlocked:[[:space:]]*(yes|true)' <<<"$state"; then return 0; fi
    state="$(fastboot oem device-info 2>&1 || true)"
    grep -Eiq 'device unlocked:[[:space:]]*(yes|true)' <<<"$state"
  }
  if ! is_unlocked; then
    echo "Bootloader appears locked or did not report its state."
    echo "If stock OEM unlocking is not enabled, activate Developer Options first."
    read -r -p 'Type UNLOCK-S55 to request official fastboot flashing unlock (wipes userdata): ' confirm
    [[ "$confirm" == UNLOCK-S55 ]] || die "Cancelled before unlock"
    if ! fastboot flashing unlock; then
      echo "Standard unlock was rejected. Some old S55 guides mention OEM unlock-go."
      echo "WARNING: OEM unlock-go can immediately ERASE data and reboot without confirmation."
      read -r -p "Type UNLOCK-GO-S55 for this explicit fallback, or anything else to STOP: " fallback
      [[ "$fallback" == UNLOCK-GO-S55 ]] || die "OEM unlock-go fallback cancelled"
      fastboot oem unlock-go || die "OEM unlock-go also failed; stop and inspect fastboot support"
    fi
    echo "Verify the PHONE. After unlock, if fastboot is available again, press Enter."
    read -r
    if [[ "$(fastboot devices | wc -l)" -ne 1 ]]; then
      echo "If the stock ROM restarted, unlock USB debugging again and press Enter."
      read -r
      adb_one
      adb reboot bootloader
    fi
    wait_fastboot
    is_unlocked || die "Bootloader unlock not independently confirmed by fastboot; stop"
  fi
  step "Install known S55 TWRP into RECOVERY only"
  fastboot flash recovery "$ASSET/twrp-s55.img"
  echo "Boot DIRECTLY into TWRP now; hold Power+Volume Up if required."
  fastboot oem reboot-recovery || true
  recovery_checks
}
ensure_recovery
# Verify recovery utilities and bind checkpoint state to this one target.
adb shell 'command -v sgdisk && command -v sha256sum && command -v blockdev && command -v dd && command -v mke2fs && command -v e2fsck && command -v resize2fs && command -v tune2fs && command -v awk && command -v df' >/dev/null ||
  die "Required recovery utilities missing"
adb shell 'sgdisk -v /dev/block/mmcblk0' || die "GPT integrity failed"
# Verify the recovery can stage the 80 MiB NikGapps ZIP before ANY partition write.
early_ram="$(adb shell 'df -k /tmp | awk "NR==2 {print \$4}"' | tr -d '\r')"
[[ "$early_ram" =~ ^[0-9]+$ && "$early_ram" -ge 180000 ]] ||
  die "Recovery /tmp has less than 180 MiB free; no device writes attempted"
recovery_serial="$(adb devices | awk '$2=="recovery"{print $1}')"
[[ -n "$recovery_serial" ]] || die "No TWRP serial"
target_sha="$(printf 'S55-TWRP-v1:%s' "$recovery_serial" | sha256sum | awk '{print $1}')"
if [[ -f "$BACK/target-recovery-id.sha256" ]]; then
  [[ "$(cat "$BACK/target-recovery-id.sha256")" == "$target_sha" ]] ||
    die "Existing private checkpoint belongs to another phone"
else
  [[ -z "$(find "$BACK" -maxdepth 1 -name '*.ok' -print -quit)" ]] ||
    die "Unbound checkpoint markers exist; stopping"
  printf '%s\n' "$target_sha" > "$BACK/target-recovery-id.sha256"
  chmod 600 "$BACK/target-recovery-id.sha256"
fi
gpt_info(){ remote "sgdisk -i $1 /dev/block/mmcblk0"; }
bounds(){
  gpt_info "$1" | awk -F: '
    /First sector/{gsub(/^ +/,"",$2);split($2,a," ");a1=a[1]}
    /Last sector/{gsub(/^ +/,"",$2);split($2,a," ");a2=a[1]}
    END{print a1 ":" a2}'
}
gpt_gate(){
  [[ "$(bounds 27)" == 491520:1540095 ]] || die "Vendor partition layout unknown"
  [[ "$(bounds 30)" == 8273920:120750046 ]] || die "Unknown /data end sector"
  case "$(bounds 28):$(bounds 29)" in
    1540096:7389183:7389184:8273919) echo STOCK_GPT ;;
    1540096:7913471:7913472:8273919) echo EXPANDED_GPT ;;
    *) die "Unknown system/cache GPT, absolutely no repartition" ;;
  esac
}
gpt_type="$(gpt_gate)"
[[ "$gpt_type" == STOCK_GPT || "$gpt_type" == EXPANDED_GPT ]] || die "GPT unknown"
[[ "$(remote 'cat /sys/class/block/mmcblk0p30/size')" == 112476127 ]] ||
  die "Userdata geometry differs from validated S55"
# Original S55 July/October 2018 vendor builds really differ from the 2020
# vendor already patched on our phone. Preserve THEIR complete original vendor,
# then install the SHA-verified golden 2020 vendor partition atomically by block.
[[ "$(remote 'blockdev --getsize64 /dev/block/mmcblk0p27')" == 536870912 ]] ||
  die "S55 vendor partition geometry unknown; refusing"
echo "Vendor and fingerprint source version will be backed up unchanged."
step "Save original per-phone GPT + system, boot, recovery, vendor and radio calibration"
if [[ ! -e "$BACK/backup/gpt-original.bin" ]]; then
  [[ "$gpt_type" == STOCK_GPT ]] ||
    die "No original GPT backup for this already-repartitioned handset"
  adb shell 'sgdisk --backup=/tmp/s55-restore-gpt.bin /dev/block/mmcblk0'
  remote_gpt_sha="$(remote 'sha256sum /tmp/s55-restore-gpt.bin' | awk '{print $1}')"
  [[ "$remote_gpt_sha" =~ ^[a-f0-9]{64}$ ]] || die "Cannot hash GPT on phone"
  adb pull /tmp/s55-restore-gpt.bin "$BACK/backup/gpt-original.bin.part" >/dev/null
  [[ "$(sha256sum "$BACK/backup/gpt-original.bin.part" | awk '{print $1}')" == "$remote_gpt_sha" ]] ||
    die "GPT transfer/checksum mismatch"
  mv "$BACK/backup/gpt-original.bin.part" "$BACK/backup/gpt-original.bin"
  printf '%s\n' "$remote_gpt_sha" > "$BACK/backup/gpt-original.sha256"
  chmod 600 "$BACK/backup/gpt-original.bin" "$BACK/backup/gpt-original.sha256"
fi
[[ -s "$BACK/backup/gpt-original.sha256" ]] ||
  die "GPT backup checksum absent; refusing potentially destructive operation"
[[ "$(sha256sum "$BACK/backup/gpt-original.bin" | awk '{print $1}')" == "$(cat "$BACK/backup/gpt-original.sha256")" ]] ||
  die "GPT backup damaged"
for part in system cache boot recovery vendor nvram nvdata protect1 protect2; do
  file="$BACK/backup/$part.img.zst"
  sz="$(remote "blockdev --getsize64 /dev/block/platform/mtk-msdc.0/11230000.msdc0/by-name/$part")"
  [[ "$sz" =~ ^[0-9]+$ && "$sz" -gt 4096 ]] || die "Unknown partition $part"
  if [[ -s "$file" ]]; then
    [[ -s "$file.raw.sha256" ]] ||
      die "Backup checksum missing for $part; refuse to skip"
    zstd -q -t "$file" || die "Corrupt old backup $part"
    orig_size="$sz"
    if [[ "$gpt_type" == EXPANDED_GPT ]]; then
      case "$part" in
        system) orig_size=2994733056 ;;
        cache) orig_size=452984832 ;;
      esac
    fi
    [[ "$(zstd -dc "$file" | wc -c)" == "$orig_size" ]] ||
      die "Unexpected original backup size $part (not the current expanded partition)"
    [[ "$(zstd -dc "$file" | sha256sum | awk '{print $1}')" == "$(cat "$file.raw.sha256")" ]] ||
      die "Corrupt original backup hash for $part"
    continue
  fi
  echo "BACKUP $part $sz bytes to PRIVATE folder"
  rm -f "$file.part"  # delete ONLY this installer's stale partial backup
  adb exec-out "dd if=/dev/block/platform/mtk-msdc.0/11230000.msdc0/by-name/$part bs=1048576 2>/dev/null" |
    zstd -q -T2 -3 -o "$file.part"
  [[ "$(zstd -dc "$file.part" | wc -c)" == "$sz" ]] ||
    die "Backup failed for $part; stopping"
  remote_sha="$(remote "sha256sum /dev/block/platform/mtk-msdc.0/11230000.msdc0/by-name/$part" | awk '{print $1}')"
  [[ "$remote_sha" =~ ^[a-f0-9]{64}$ ]] || die "Source checksum unavailable: $part"
  [[ "$(zstd -dc "$file.part" | sha256sum | awk '{print $1}')" == "$remote_sha" ]] ||
    die "Readback/source differ for $part; STOP before any writes"
  mv "$file.part" "$file"
  printf '%s\n' "$remote_sha" > "$file.raw.sha256"
  chmod 600 "$file" "$file.raw.sha256"
done
echo "DON'T PUBLISH OR SHARE THE RADIO/NVRAM BACKUPS."
if [[ ! -e "$BACK/repartition.ok" ]]; then
  step "Expand only exact factory /system boundary and shrink /cache"
  stage_begin repartition
  S55_GPT_BACKUP_DIR="$BACK/backup/gpt" bash "$SCRIPTS/repartition-gapps.sh"
  recovery_checks
  [[ "$(remote 'cat /sys/class/block/mmcblk0p28/size')" == 6373376 ]] ||
    die "Repartition kernel readback failed"
  [[ "$(gpt_gate)" == EXPANDED_GPT ]] || die "Repartition GPT was not persisted"
  adb shell 'sgdisk -v /dev/block/mmcblk0' || die "New GPT invalid"
  stage_done repartition
else
  [[ "$(gpt_gate)" == EXPANDED_GPT ]] ||
    die "repartition.ok exists but real geometry disagrees"
fi
# Original cache filesystem is invalid after shifting the start of p29.
if [[ ! -e "$BACK/cache.ok" ]]; then
  recovery_checks
  [[ "$(remote 'blockdev --getsize64 /dev/block/mmcblk0p29')" == 184549376 ]] ||
    die "Unexpected new /cache partition geometry"
  [[ -z "$(remote 'mount | grep mmcblk0p29 || true')" ]] || die "/cache mounted"
  stage_begin cache
  adb shell 'mke2fs -t ext4 -L cache /dev/block/mmcblk0p29'
  adb shell 'e2fsck -fn /dev/block/mmcblk0p29 >/tmp/s55-cache-fsck.log 2>&1; test $? -eq 0'
  stage_done cache
else
  [[ "$(remote 'blockdev --getsize64 /dev/block/mmcblk0p29')" == 184549376 ]] ||
    die "Old cache completion marker inconsistent"
  adb shell 'e2fsck -fn /dev/block/mmcblk0p29 >/tmp/s55-cache-existing-fsck.log 2>&1; test $? -eq 0' ||
    die "cache.ok marker disagrees with ext4 filesystem"
fi
if [[ -e "$BACK/system.ok" ]]; then
  adb shell 'mount -t ext4 -o ro,noload /dev/block/mmcblk0p28 /system 2>/dev/null || true'
  [[ "$(remote 'grep "^ro.build.version.release=" /system/build.prop | head -1')" == ro.build.version.release=11 ]] ||
    die "system.ok marker but system is NOT Android 11"
  current_healthd="$(remote 'sha256sum /system/bin/healthd' | awk '{print $1}')"
  case "$current_healthd" in
    fc17574161e743e11c38e3d9d44b1c0b1bfdf04e946e78610dd69c80954c4215|5f66b4c372d09eb84f2b23dadedaad0a53242bc44f31fdd7787a5467bee9e3ee|4421bd4794a9470e74b28c63e3ba9a2528e83a7635314ae27e5375c136555381) ;;
    *) die "system.ok marker but unexpected healthd; STOP without overwriting" ;;
  esac
  echo "SYSTEM_CHECKPOINT_REVERIFIED"
fi
if [[ ! -e "$BACK/system.ok" ]]; then
  [[ ! -e "$BACK/gapps.ok" && ! -e "$BACK/thermal.ok" ]] ||
    die "Inconsistent checkpoint: cannot reflash system over already-installed GApps"
  step "Write non-SAR LineageOS 18.1 and verify block-level hash"
  stage_begin system
  adb shell 'umount /system 2>/dev/null || true'
  xz -dc "$ASSET/lineage18.img.xz" | progress_stream 2055483392 |
    adb exec-in 'dd of=/dev/block/mmcblk0p28 bs=4194304 2>/dev/null || exit 2; sync'
  digest="$(remote 'dd if=/dev/block/mmcblk0p28 bs=4096 count=501827 2>/dev/null | sha256sum' | awk '{print $1}')"
  [[ "$digest" == 6ff112b937a5043aee862b48330a3895bb040461cdbe4304b342468600c7aaf5 ]] ||
    die "System readback differs; DO NOT BOOT!"
  adb shell 'e2fsck -fy /dev/block/mmcblk0p28 >/tmp/s55-fsck1 2>&1; test $? -le 1'
  adb shell 'resize2fs /dev/block/mmcblk0p28'
  adb shell 'e2fsck -fn /dev/block/mmcblk0p28 >/tmp/s55-fsck2 2>&1; test $? -eq 0'
  stage_done system
fi
if [[ -e "$BACK/vendor.ok" ]]; then
  [[ "$(remote 'sha256sum /dev/block/mmcblk0p27' | awk '{print $1}')" == "$VENDOR_SHA" ]] ||
    die "vendor.ok marker but raw vendor SHA disagrees; refuse reinstall"
  echo "VENDOR_CHECKPOINT_REVERIFIED"
fi
if [[ ! -e "$BACK/vendor.ok" ]]; then
  recovery_checks
  step "Restore complete known-working S55 Oreo vendor, preserving original backup"
  [[ -s "$BACK/backup/vendor.img.zst" ]] || die "Original vendor backup missing; refusing overwrite"
  adb shell 'umount /vendor 2>/dev/null || true'
  [[ -z "$(remote 'mount | grep mmcblk0p27 || true')" ]] || die "Vendor still mounted"
  stage_begin vendor
  zstd -dc "$ASSET/vendor-s55-known-good.img.zst" | progress_stream 536870912 |
    adb exec-in 'dd of=/dev/block/mmcblk0p27 bs=4194304 2>/dev/null || exit 2; sync'
  got="$(remote 'dd if=/dev/block/mmcblk0p27 bs=1048576 count=512 2>/dev/null | sha256sum' | awk '{print $1}')"
  [[ "$got" == "$VENDOR_SHA" ]] || die "Vendor readback mismatch, DO NOT BOOT"
  adb shell 'mount -t ext4 -o ro,noload /dev/block/mmcblk0p27 /vendor'
  [[ "$(remote 'sha256sum /vendor/lib64/libfprint-x64.so' | awk '{print $1}')" == 3d89603ed3025bdc14e65d6269024c52920808c747aeb2d79417741d7cc7f9f6 ]] || die "Vendor fingerprint missing"
  [[ "$(remote 'sha256sum /vendor/etc/selinux/nonplat_sepolicy.cil' | awk '{print $1}')" == e0602bae3099274aec52e4fdf8ba6b121859e8ff35dea08dbc89cce967bd6daf ]] || die "Vendor thermal rules missing"
  stage_done vendor
fi
if [[ -e "$BACK/gapps.inflight" && ! -e "$BACK/gapps.ok" ]]; then
  die "Interrupted/incomplete NikGapps install: inspect TWRP logs; never blindly rerun"
fi
if [[ -e "$BACK/gapps.ok" ]]; then
  adb shell 'mount -t ext4 -o ro,noload /dev/block/mmcblk0p28 /system 2>/dev/null || true'
  [[ "$(remote 'find /system -iname "*Phonesky*.apk" | head -1')" == *Phonesky* ]] ||
    die "gapps.ok but Google Play binary missing"
  [[ "$(remote 'find /system -iname "*GmsCore*.apk" | head -1')" == *GmsCore* ]] ||
    die "gapps.ok but Google Play Services missing"
  echo "GAPPS_CHECKPOINT_REVERIFIED"
fi
if [[ ! -e "$BACK/gapps.ok" ]]; then
  step "Install checked NikGapps Core from recovery RAM BEFORE /data format"
  adb shell 'mount -o remount,ro /system 2>/dev/null || true'
  ram_avail="$(remote 'df -k /tmp | awk "NR==2 {print \$4}"')"
  [[ "$ram_avail" =~ ^[0-9]+$ && "$ram_avail" -ge 180000 ]] ||
    die "TWRP /tmp RAM insufficient or unavailable: need 180 MiB"
  [[ ! -f "$BACK/gapps.inflight" ]] || die "NikGapps interrupted: check recovery log and repair before resuming"
  stage_begin gapps
  S55_GAPPS_REMOTE=/tmp/s55-NikGapps-core-arm64-11.zip S55_GAPPS_ZIP="$ASSET/nikgapps-core-11.zip" bash "$SCRIPTS/install-nikgapps-core11-s55.sh" --install
  adb shell 'mount -t ext4 -o ro,noload /dev/block/mmcblk0p28 /system 2>/dev/null || true'
  [[ "$(remote 'find /system -iname "*Phonesky*.apk" | head -1')" == *Phonesky* ]] ||
    die "Google Play Store not found after install"
  [[ "$(remote 'find /system -iname "*GmsCore*.apk" | head -1')" == *GmsCore* ]] ||
    die "Google Play services not found after install"
  stage_done gapps
fi
if [[ -e "$BACK/data.ok" ]]; then
  adb shell 'mount -t ext4 -o rw /dev/block/mmcblk0p30 /data 2>/dev/null || true'
  [[ "$(remote 'mount | grep " on /data "')" == *'mmcblk0p30 on /data type ext4 (rw,'* ]] ||
    die "data.ok checkpoint but /data cannot mount RW"
  for dirname in vendor_de vendor_ce; do
    [[ "$(remote "ls -ldZ /data/$dirname")" == *'u:object_r:vendor_data_file:s0'* ]] ||
      die "data.ok checkpoint but Android 11 /data/$dirname metadata missing"
  done
  echo "DATA_CHECKPOINT_REVERIFIED"
fi
if [[ ! -e "$BACK/data.ok" ]]; then
  step "Format full p30 userdata AFTER NikGapps, then prepare vendor CE/DE"
  recovery_checks
  adb shell 'umount /sdcard 2>/dev/null || true; umount /data 2>/dev/null || true'
  [[ -z "$(remote 'mount | grep mmcblk0p30 || true')" ]] || die "Data still mounted"
  stage_begin data
  adb shell 'mke2fs -t ext4 /dev/block/mmcblk0p30'
  adb shell 'tune2fs -m 0 -r 4096 -u 10010 /dev/block/mmcblk0p30'
  adb shell 'e2fsck -fn /dev/block/mmcblk0p30 >/tmp/s55-fsck-data 2>&1; test $? -eq 0'
  adb shell 'mount -t ext4 -o rw /dev/block/mmcblk0p30 /data'
  # Reuse the exact idempotent helper validated on the physical S55.
  bash "$SCRIPTS/prepare-lineage18-userdata-s55.sh" --apply
  stage_done data
fi
if [[ -e "$BACK/thermal.ok" ]]; then
  adb shell 'mount -t ext4 -o ro,noload /dev/block/mmcblk0p28 /system 2>/dev/null || true'
  [[ "$(remote 'sha256sum /system/bin/healthd' | awk '{print $1}')" == 4421bd4794a9470e74b28c63e3ba9a2528e83a7635314ae27e5375c136555381 ]] ||
    die "thermal.ok but corrected healthd not installed"
  echo "THERMAL_CHECKPOINT_REVERIFIED"
fi
if [[ ! -e "$BACK/thermal.ok" ]]; then
  step "Repair true battery voltage/temperature and SELinux thermal HAL"
  stage_begin thermal
  current_healthd="$(remote 'sha256sum /system/bin/healthd' | awk '{print $1}')"
  if [[ "$current_healthd" != 4421bd4794a9470e74b28c63e3ba9a2528e83a7635314ae27e5375c136555381 ]]; then
    if [[ "$current_healthd" == fc17574161e743e11c38e3d9d44b1c0b1bfdf04e946e78610dd69c80954c4215 ]]; then
      bash "$SCRIPTS/fix-healthd-voltage.sh" --apply
    fi
    bash "$SCRIPTS/fix-lineage18-healthd-temperature.sh" --apply
  fi
  [[ "$(remote 'sha256sum /system/bin/healthd' | awk '{print $1}')" == 4421bd4794a9470e74b28c63e3ba9a2528e83a7635314ae27e5375c136555381 ]] ||
    die "Final healthd not verified"
  # Already present and verified in the golden vendor image; no extra vendor patch.
  stage_done thermal
fi

if [[ -e "$BACK/boot.ok" ]]; then
  expected_boot="$(sha256sum "$ASSET/boot-tested-s55.img" | awk '{print $1}')"
  [[ "$(remote 'sha256sum /dev/block/platform/mtk-msdc.0/11230000.msdc0/by-name/boot' | awk '{print $1}')" == "$expected_boot" ]] ||
    die "boot.ok marker but boot partition changed; STOP"
  echo "BOOT_CHECKPOINT_REVERIFIED"
fi
if [[ ! -e "$BACK/boot.ok" ]]; then
  recovery_checks
  step "Install EXACT previously validated S55 2020 boot; stock boot is backed up"
  [[ "$(remote 'blockdev --getsize64 /dev/block/platform/mtk-msdc.0/11230000.msdc0/by-name/boot')" == 16777216 ]] ||
    die "Unknown boot partition geometry"
  adb push "$ASSET/boot-tested-s55.img" /tmp/s55-validated-boot.img >/dev/null
  sha="$(sha256sum "$ASSET/boot-tested-s55.img" | awk '{print $1}')"
  [[ "$(remote 'sha256sum /tmp/s55-validated-boot.img' | awk '{print $1}')" == "$sha" ]] ||
    die "Staged boot corrupted"
  stage_begin boot
  adb shell 'dd if=/tmp/s55-validated-boot.img of=/dev/block/platform/mtk-msdc.0/11230000.msdc0/by-name/boot bs=1048576 2>/dev/null || exit 2; sync'
  [[ "$(remote 'sha256sum /dev/block/platform/mtk-msdc.0/11230000.msdc0/by-name/boot' | awk '{print $1}')" == "$sha" ]] ||
    die "Boot partition hash mismatch, DO NOT REBOOT"
  stage_done boot
fi
step "Validate exact final fingerprint and healthd binaries"
adb shell 'mount -t ext4 -o ro,noload /dev/block/mmcblk0p28 /system 2>/dev/null || true'
adb shell 'mount -t ext4 -o ro,noload /dev/block/mmcblk0p27 /vendor 2>/dev/null || true'
[[ "$(remote 'sha256sum /system/bin/healthd' | awk '{print $1}')" == 4421bd4794a9470e74b28c63e3ba9a2528e83a7635314ae27e5375c136555381 ]] ||
  die "Healthd is not the final validated version"
[[ "$(remote 'sha256sum /vendor/lib64/libfprint-x64.so' | awk '{print $1}')" == 3d89603ed3025bdc14e65d6269024c52920808c747aeb2d79417741d7cc7f9f6 ]] ||
  die "Fingerprint HAL not patched"
step "Boot LineageOS 18.1 — complete the first-run setup on the phone"
adb reboot system
echo "A clean Android installation usually resets USB DEBUGGING."
echo "Complete Android setup, enable Developer Options / USB debugging and authorize this computer."
echo "This process continues after USB authorization. If it exits, use --verify."
echo "NEVER reflash a working Android 11 phone just to verify it."
phone_ready(){
  [[ "$(adb devices | awk '$2=="device"{n++} END{print n+0}')" -eq 1 ]] &&
    [[ "$(remote 'getprop sys.boot_completed' || true)" == 1 ]]
}
for ((i=1;i<=90;i++)); do
  phone_ready && break
  sleep 2
done
if ! phone_ready; then
  echo "ADB NOT AUTHORIZED YET. Android can be fully working without USB debugging."
  read -r -p "Enable USB debugging on Android and press Enter to retry verification: " _
  for ((i=1;i<=90;i++)); do
    phone_ready && break
    sleep 2
  done
fi
if ! phone_ready; then
  echo "AUTOMATIC VALIDATION NOT POSSIBLE: USB debugging/authorization missing or phone did not boot."
  read -r -p "Type ANDROID-BOOTED only if you can SEE and USE the LineageOS home screen: " answer
  if [[ "$answer" == ANDROID-BOOTED ]]; then
    touch "$BACK/visual-boot-only.ok"
    echo "VISUAL BOOT CONFIRMED BY USER. Google/sensors/battery verification PENDING."
    echo "Keep private backups at $BACK/backup; reconnect with USB debugging to audit further."
    exit 0
  fi
  die "Boot could not be confirmed; inspect phone/recovery before any more flashing"
fi
echo "ADB_FRAMEWORK_READY; wait for stable Android services"
sleep 25
phone_ready || die "Android framework dropped ADB after first boot"
[[ "$(remote 'getprop ro.build.version.release')" == 11 ]] || die "Unexpected Android version"
[[ "$(remote 'getenforce')" == Enforcing ]] || die "SELinux unexpectedly not Enforcing"
apps="$(remote 'pm list packages')"
for pkg in com.google.android.gms com.android.vending com.google.android.gsf; do
  grep -Fqx "package:$pkg" <<<"$apps" || die "Required Google package absent: $pkg"
done
temp="$(remote 'dumpsys battery | sed -n "s/.*temperature: *//p" | head -1')"
[[ "$temp" =~ ^[0-9]+$ && "$temp" -gt 0 ]] || die "Battery temperature telemetry missing"
thermal="$(remote 'dumpsys thermalservice')"
for name in CPU_T GPU_T BAT_T SKIN_T; do
  grep -Fq "mName=$name" <<<"$thermal" || die "Thermal HAL missing $name"
done
adb shell 'settings put global low_power_trigger_level 25; settings put global automatic_power_save_mode 0; settings put global mobile_data_always_on 0; settings put global ble_scan_always_enabled 0'
[[ "$(remote 'settings get global low_power_trigger_level')" == 25 ]] || die "Battery saver not persisted"
[[ "$(remote 'settings get global automatic_power_save_mode')" == 0 ]] || die "Automatic Battery Saver not selected"
[[ "$(remote 'settings get global mobile_data_always_on')" == 0 ]] || die "Mobile data background optimization not persisted"
[[ "$(remote 'settings get global ble_scan_always_enabled')" == 0 ]] || die "BLE background scanning setting not persisted"
bash "$SCRIPTS/enable-microarray-persistence.sh" --apply ||
  die "MicroArray PHH retention could not be enabled (manual remediation required)"
echo "ANDROID11_GOOGLE_THERMAL_BATTERY_VERIFIED"
adb shell 'dumpsys battery | grep -E "level:|voltage:|temperature:"'
adb shell 'dumpsys thermalservice | grep "Current temperatures from HAL:" -A5'
touch "$BACK/installed.ok"
echo "INSTALLATION VERIFIED. Private original backups: $BACK/backup"
echo "FINGERPRINT ACCEPTANCE: Settings > Security > Fingerprint: enroll a finger."
echo "REBOOT the phone, enter the PIN once if prompted, then lock and UNLOCK with that SAME finger."
echo "On the reference S55 this exact combined fix has passed a physical post-reboot unlock."
echo "For this NEW device, the biometric test is PENDING until the owner performs it."
echo "To audit the complete verified fix configuration without flashing: ./INSTALL.sh --verify"