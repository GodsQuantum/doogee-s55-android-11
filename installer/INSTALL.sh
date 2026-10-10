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
die(){ printf 'STOP: %s\n' "$*" >&2; exit 1; }
step(){ printf '\n==> %s\n' "$*"; }
for c in sha256sum xz zstd awk python3 stat df; do
  command -v "$c" >/dev/null || die "Missing Linux command: $c"
done
[[ "$MODE" == --check || "$MODE" == --plan || "$MODE" == --install ]] ||
  die "Usage: ./INSTALL.sh [--plan|--check|--install]"
if [[ "$MODE" != --plan ]]; then
  for c in adb fastboot pv; do
    command -v "$c" >/dev/null || die "Missing Linux command: $c"
  done
fi
# Confirm a supported action before touching any device or private state.
[[ "$MODE" == --check || "$MODE" == --plan || "$MODE" == --install ]] ||
  die "Usage: ./INSTALL.sh [--plan|--check|--install]"
[[ -f "$ROOT/manifest.sha256" ]] || die "Kit incomplete: manifest.sha256 absent"
step "Verify every vendor, ROM and Google asset BEFORE changing the phone"
(cd "$ROOT" && sha256sum -c manifest.sha256) || die "Kit verification failed"
[[ -s "$ASSET/lineage18.img.xz" && -s "$ASSET/twrp-s55.img" &&
   -s "$ASSET/boot-tested-s55.img" && -s "$ASSET/nikgapps-core-11.zip" &&
   -s "$ASSET/vendor-s55-known-good.img.zst" ]] ||
  die "Missing files in assets/"
[[ -f "$SCRIPTS/fix-lineage18-thermal-sepolicy.sh" ]] || die "Missing scripts"
if [[ "$MODE" == --plan ]]; then
  cat <<'NOTE'
STOCK DOOGEE S55, never S55 Lite. One command, guided:
  verify files -> unlock OEM if needed -> enter TWRP -> backup GPT,
  original system, boot, recovery, vendor, unique radio calibration
  -> enlarge /system and shrink /cache (known stock GPT only)
  -> flash/check LineageOS 18.1 -> clone exact working vendor with
     fingerprint/HIDL/sensors/thermal SELinux fixes already applied
  -> install NikGapps -> patch healthd voltage and battery temperature
  -> full /data format -> prepare Android 11 userdata vendor paths
  -> copy the exact known-good S55 boot -> reboot + test.
This is a local community installer, not an official manufacturer update.
--plan does not communicate with the phone or write any partition.
NOTE
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
free_bytes="$(df -B1 --output=avail "$BACK" | tail -1 | tr -d ' ')"
[[ "$free_bytes" =~ ^[0-9]+$ && "$free_bytes" -ge 6442450944 ]] ||
  die "At least 6 GiB host disk space required for private system and radio backups"
touch "$LOG"; chmod 600 "$LOG"
exec > >(tee -a "$LOG") 2>&1
echo "INSTALL_SESSION $(date -Is)"
on_exit(){ local status=$?; echo "INSTALL_FINISHED_OR_STOPPED rc=$status $(date -Is); private backup=$BACK/backup"; }
trap on_exit EXIT
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
  if [[ "$(adb devices | awk '$2=="recovery"{c++} END{print c+0}')" -eq 1 ]]; then
    recovery_checks; return
  fi
  if [[ "$(adb devices | awk '$2=="device"{c++} END{print c+0}')" -eq 1 ]]; then
    adb_one
    [[ "$(remote 'getprop ro.product.device')" == S55 ]] || die "Not DOOGEE S55"
    os="$(remote 'getprop ro.build.version.release')"
    [[ "$os" == 8* ]] || die "Not STOCK Android 8 (current is $os); preserving working Android"
    adb reboot bootloader
  fi
  wait_fastboot
  unlocked="$(fastboot getvar unlocked 2>&1 || true)"
  if ! grep -Eiq 'unlocked:\s*(yes|true)' <<<"$unlocked"; then
    echo "Bootloader appears locked or did not report its state."
    echo "If stock OEM unlocking is not enabled, activate Developer Options first."
    read -r -p 'Type UNLOCK-S55 to request official fastboot flashing unlock (wipes userdata): ' confirm
    [[ "$confirm" == UNLOCK-S55 ]] || die "Cancelled before unlock"
    fastboot flashing unlock || die "OEM unlock failed"
    echo "Confirm on the PHONE. When it has finished and fastboot is available, press Enter."
    read -r
    if [[ "$(fastboot devices | wc -l)" -ne 1 ]]; then
      echo "If the stock ROM restarted, unlock USB debugging again and press Enter."
      read -r
      adb_one
      adb reboot bootloader
    fi
    wait_fastboot
    unlocked="$(fastboot getvar unlocked 2>&1 || true)"
    grep -Eiq 'unlocked:\s*(yes|true)' <<<"$unlocked" ||
      die "Bootloader unlock still not confirmed"
  fi
  step "Install known S55 TWRP into RECOVERY only"
  fastboot flash recovery "$ASSET/twrp-s55.img"
  echo "Boot DIRECTLY into TWRP now; hold Power+Volume Up if required."
  fastboot oem reboot-recovery || true
  recovery_checks
}
ensure_recovery
gpt_info(){ remote "sgdisk -i $1 /dev/block/mmcblk0"; }
bounds(){
  gpt_info "$1" | awk -F: '
    /First sector/{gsub(/^ +/,"",$2);split($2,a," ");a1=a[1]}
    /Last sector/{gsub(/^ +/,"",$2);split($2,a," ");a2=a[1]}
    END{print a1 ":" a2}'
}
gpt_gate(){
  [[ "$(bounds 27)" == 491520:1540095 ]] || die "Vendor partition layout unknown"
  [[ "$(bounds 30)" == 8273920:* ]] || die "Userdata layout unknown"
  case "$(bounds 28):$(bounds 29)" in
    1540096:7389183:7389184:8273919) echo STOCK_GPT ;;
    1540096:7913471:7913472:8273919) echo EXPANDED_GPT ;;
    *) die "Unknown system/cache GPT, absolutely no repartition" ;;
  esac
}
gpt_gate
[[ "$(remote 'cat /sys/class/block/mmcblk0p30/size')" == 112476127 ]] ||
  die "Userdata geometry differs from validated S55"
# Original S55 July/October 2018 vendor builds really differ from the 2020
# vendor already patched on our phone. Preserve THEIR complete original vendor,
# then install the SHA-verified golden 2020 vendor partition atomically by block.
[[ "$(remote 'blockdev --getsize64 /dev/block/mmcblk0p27')" == 536870912 ]] ||
  die "S55 vendor partition geometry unknown; refusing"
echo "Vendor and fingerprint source version will be backed up unchanged."
step "Save original per-phone GPT + system, boot, recovery, vendor and radio calibration"
if [[ ! -s "$BACK/backup/gpt-original.bin" ]]; then
  adb shell 'sgdisk --backup=/tmp/s55-restore-gpt.bin /dev/block/mmcblk0'
  adb pull /tmp/s55-restore-gpt.bin "$BACK/backup/gpt-original.bin" >/dev/null
  [[ -s "$BACK/backup/gpt-original.bin" ]] || die "Could not back up GPT"
fi
for part in system boot recovery vendor nvram nvdata protect1 protect2; do
  file="$BACK/backup/$part.img.zst"
  sz="$(remote "blockdev --getsize64 /dev/block/platform/mtk-msdc.0/11230000.msdc0/by-name/$part")"
  [[ "$sz" =~ ^[0-9]+$ && "$sz" -gt 4096 ]] || die "Unknown partition $part"
  if [[ -s "$file" ]]; then
    zstd -q -t "$file" || die "Corrupt old backup $file"
    [[ "$(zstd -dc "$file" | wc -c)" == "$sz" ]] ||
      die "Unexpected backup size $part"
    continue
  fi
  echo "BACKUP $part $sz bytes to PRIVATE folder"
  rm -f "$file.part"  # delete ONLY this installer's stale partial backup
  adb exec-out "dd if=/dev/block/platform/mtk-msdc.0/11230000.msdc0/by-name/$part bs=1048576 2>/dev/null" |
    zstd -q -T2 -3 -o "$file.part"
  [[ "$(zstd -dc "$file.part" | wc -c)" == "$sz" ]] ||
    die "Backup failed for $part; stopping"
  mv "$file.part" "$file"; chmod 600 "$file"
done
echo "DON'T PUBLISH OR SHARE THE RADIO/NVRAM BACKUPS."
if [[ ! -e "$BACK/repartition.ok" ]]; then
  step "Resize exact STOCK /system +256 MiB, shrink /cache"
  bash "$SCRIPTS/repartition-gapps.sh"
  recovery_checks
  [[ "$(remote 'cat /sys/class/block/mmcblk0p28/size')" == 6373376 ]] ||
    die "Repartition verification failed"
  touch "$BACK/repartition.ok"
fi
if [[ ! -e "$BACK/system.ok" ]]; then
  step "Write non-SAR LineageOS 18.1 and verify block-level hash"
  adb shell 'umount /system 2>/dev/null || true'
  xz -dc "$ASSET/lineage18.img.xz" | pv -f -s 2055483392 |
    adb exec-in 'dd of=/dev/block/mmcblk0p28 bs=4194304 2>/dev/null; sync'
  digest="$(remote 'dd if=/dev/block/mmcblk0p28 bs=4096 count=501827 2>/dev/null | sha256sum' | awk '{print $1}')"
  [[ "$digest" == 6ff112b937a5043aee862b48330a3895bb040461cdbe4304b342468600c7aaf5 ]] ||
    die "System readback differs; DO NOT BOOT!"
  adb shell 'e2fsck -fy /dev/block/mmcblk0p28 >/tmp/s55-fsck1 2>&1; test $? -le 1'
  adb shell 'resize2fs /dev/block/mmcblk0p28'
  adb shell 'e2fsck -fn /dev/block/mmcblk0p28 >/tmp/s55-fsck2 2>&1; test $? -eq 0'
  touch "$BACK/system.ok"
fi
if [[ ! -e "$BACK/vendor.ok" ]]; then
  recovery_checks
  step "Restore complete known-working S55 Oreo vendor, preserving original backup"
  [[ -s "$BACK/backup/vendor.img.zst" ]] || die "Original vendor backup missing; refusing overwrite"
  adb shell 'umount /vendor 2>/dev/null || true'
  [[ -z "$(remote 'mount | grep mmcblk0p27 || true')" ]] || die "Vendor still mounted"
  zstd -dc "$ASSET/vendor-s55-known-good.img.zst" | pv -f -s 536870912 |
    adb exec-in 'dd of=/dev/block/mmcblk0p27 bs=4194304 2>/dev/null; sync'
  got="$(remote 'dd if=/dev/block/mmcblk0p27 bs=1048576 count=512 2>/dev/null | sha256sum' | awk '{print $1}')"
  [[ "$got" == "$VENDOR_SHA" ]] || die "Vendor readback mismatch, DO NOT BOOT"
  adb shell 'mount -t ext4 -o ro,noload /dev/block/mmcblk0p27 /vendor'
  [[ "$(remote 'sha256sum /vendor/lib64/libfprint-x64.so' | awk '{print $1}')" == 3d89603ed3025bdc14e65d6269024c52920808c747aeb2d79417741d7cc7f9f6 ]] || die "Vendor fingerprint missing"
  [[ "$(remote 'sha256sum /vendor/etc/selinux/nonplat_sepolicy.cil' | awk '{print $1}')" == e0602bae3099274aec52e4fdf8ba6b121859e8ff35dea08dbc89cce967bd6daf ]] || die "Vendor thermal rules missing"
  touch "$BACK/vendor.ok"
fi
if [[ ! -e "$BACK/data.ok" ]]; then
  step "Format original p30 userdata, then initialize vendor CE/DE"
  recovery_checks
  adb shell 'umount /sdcard 2>/dev/null || true; umount /data 2>/dev/null || true'
  [[ -z "$(remote 'mount | grep mmcblk0p30 || true')" ]] || die "Data still mounted"
  adb shell 'mke2fs -t ext4 /dev/block/mmcblk0p30'
  adb shell 'tune2fs -m 0 -r 4096 -u 10010 /dev/block/mmcblk0p30'
  adb shell 'e2fsck -fn /dev/block/mmcblk0p30 >/tmp/s55-fsck-data 2>&1; test $? -eq 0'
  adb shell 'mount -t ext4 -o rw /dev/block/mmcblk0p30 /data'
  # Reuse the exact idempotent helper validated on the physical S55.
  bash "$SCRIPTS/prepare-lineage18-userdata-s55.sh" --apply
  touch "$BACK/data.ok"
fi
if [[ ! -e "$BACK/gapps.ok" ]]; then
  step "Install checked NikGapps Core before formatting /data"
  adb shell 'mount -o remount,ro /system 2>/dev/null || true'
  [[ "$(remote 'mount | grep " on /data "')" == *'mmcblk0p30 on /data type ext4'* ]] ||
    die "GApps requires freshly mounted userdata from p30"
  adb shell 'mkdir -p /data/local/tmp; chmod 0755 /data/local/tmp'
  S55_GAPPS_ZIP="$ASSET/nikgapps-core-11.zip" bash "$SCRIPTS/install-nikgapps-core11-s55.sh" --install
  adb shell 'mount -t ext4 -o ro,noload /dev/block/mmcblk0p28 /system 2>/dev/null || true'
  [[ "$(remote 'find /system -iname "*Phonesky*.apk" | head -1')" == *Phonesky* ]] ||
    die "Google Play Store not found after install"
  [[ "$(remote 'find /system -iname "*GmsCore*.apk" | head -1')" == *GmsCore* ]] ||
    die "Google Play services not found after install"
  touch "$BACK/gapps.ok"
fi
if [[ ! -e "$BACK/thermal.ok" ]]; then
  step "Repair true battery voltage/temperature and SELinux thermal HAL"
  S55_BACKUPS="$ROOT/backups/device-2026-10-10" bash "$SCRIPTS/fix-healthd-voltage.sh" --apply
  bash "$SCRIPTS/fix-lineage18-healthd-temperature.sh" --apply
  # Already present and verified in the golden vendor image; no extra vendor patch.
  touch "$BACK/thermal.ok"
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
  adb shell 'dd if=/tmp/s55-validated-boot.img of=/dev/block/platform/mtk-msdc.0/11230000.msdc0/by-name/boot bs=1048576 2>/dev/null; sync'
  [[ "$(remote 'sha256sum /dev/block/platform/mtk-msdc.0/11230000.msdc0/by-name/boot' | awk '{print $1}')" == "$sha" ]] ||
    die "Boot partition hash mismatch, DO NOT REBOOT"
  touch "$BACK/boot.ok"
fi
step "Validate exact final fingerprint and healthd binaries"
adb shell 'mount -t ext4 -o ro,noload /dev/block/mmcblk0p28 /system 2>/dev/null || true'
[[ "$(remote 'sha256sum /system/bin/healthd' | awk '{print $1}')" == 4421bd4794a9470e74b28c63e3ba9a2528e83a7635314ae27e5375c136555381 ]] ||
  die "Healthd is not the final validated version"
[[ "$(remote 'sha256sum /vendor/lib64/libfprint-x64.so' | awk '{print $1}')" == 3d89603ed3025bdc14e65d6269024c52920808c747aeb2d79417741d7cc7f9f6 ]] ||
  die "Fingerprint HAL not patched"
step "Boot LineageOS 18.1 — complete the first-run setup on the phone"
adb reboot system
echo "A clean Android installation usually resets USB DEBUGGING."
echo "Complete Android setup, enable Developer Options / USB debugging and authorize this computer."
echo "The SAME installer resumes automatically once authorized; do not flash again."
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
echo "ANDROID11_GOOGLE_THERMAL_BATTERY_VERIFIED"
adb shell 'dumpsys battery | grep -E "level:|voltage:|temperature:"'
adb shell 'dumpsys thermalservice | grep "Current temperatures from HAL:" -A5'
touch "$BACK/installed.ok"
echo "INSTALLATION VERIFIED. Private original backups: $BACK/backup"
echo "Enroll fingerprint and validate unlocking across another reboot on the phone."