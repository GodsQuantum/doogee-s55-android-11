#!/usr/bin/env bash
# Replace the crDroid boot animation on the Doogee S55 (running system, root ADB).
# Usage: ./bootanim-replace.sh my-bootanimation.zip
set -euo pipefail
ADB="${ADB:-adb}"
ZIP="${1:?Usage: bootanim-replace.sh <bootanimation.zip>}"

$ADB root >/dev/null 2>&1 || true; sleep 1

echo ">> Locating current bootanimation.zip..."
DEST=$($ADB shell "find /system /product /system_ext -name bootanimation.zip 2>/dev/null | head -n1" | tr -d '\r')
[ -z "$DEST" ] && DEST="/system/media/bootanimation.zip"
echo "   target: $DEST"

echo ">> Remounting system RW and pushing..."
$ADB shell "mount -o rw,remount /" 2>/dev/null || $ADB shell "mount -o rw,remount /system" 2>/dev/null || true
$ADB push "$ZIP" "$DEST"
$ADB shell "chmod 644 '$DEST'; chcon u:object_r:system_file:s0 '$DEST' 2>/dev/null || true"

echo ">> Done. Reboot to see it:  $ADB reboot"
