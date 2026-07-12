#!/usr/bin/env bash
# Doogee S55 — decrypt /data at the vendor fstab level AND restore the SELinux label.
# Run this while the phone is in TWRP with ADB connected (adb devices -> "recovery").
# Requires Google's official platform-tools adb in $PT (or in PATH).
set -euo pipefail
ADB="${ADB:-adb}"

echo ">> Waiting for device (TWRP/recovery)..."
$ADB wait-for-device
$ADB root >/dev/null 2>&1 || true

echo ">> Remounting /vendor RW and stripping encryption from fstab..."
$ADB shell 'mount -o rw,remount /vendor 2>/dev/null
for f in /vendor/etc/fstab*; do
  sed -i "s/forceencrypt/encryptable/g; s/forcefdeorfbe/encryptable/g; s/fileencryption/encryptable/g" "$f"
  sed -i "s#,encryptable=/dev/block/platform/mtk-msdc.0/11230000.msdc0/by-name/metadata##g" "$f"
  sed -i "s#,=/dev/block/platform/mtk-msdc.0/11230000.msdc0/by-name/metadata##g" "$f"
done'

echo ">> Restoring SELinux label (CRITICAL — prevents the audio/boot hang)..."
$ADB shell 'restorecon -Rv /vendor/etc/fstab*'

echo ">> Result — /data line and label:"
$ADB shell 'grep -n "userdata /data" /vendor/etc/fstab*; echo "---"; ls -Z /vendor/etc/fstab.mt6755'

cat <<'EOF'

>> Check above:
   - the /data line should end at "...quota,resize" (no encrypt keyword)
   - the label must be u:object_r:vendor_configs_file:s0  (NOT "unlabeled")
Next: TWRP -> Wipe -> Format Data -> type "yes", then reboot system.
EOF
