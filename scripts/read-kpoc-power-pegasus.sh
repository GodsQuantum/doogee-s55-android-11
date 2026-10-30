#!/usr/bin/env bash
# DOOGEE S55: READ-ONLY Android audit of off-mode display/power prerequisites.
# No adb root request, no sysfs writes, no remounts, no flashing.
set -euo pipefail
S=S550000000017268
adb -s "$S" get-state </dev/null | grep -Fqx device || { echo 'S55 not in Android ADB'; exit 1; }
echo "=== DATE: $(date -Is)"
echo "=== PHONE BOOT / BATTERY"
adb -s "$S" shell 'getprop sys.boot_completed; getprop ro.bootmode; getenforce; id; dumpsys battery' </dev/null
echo "=== OFF-MODE MODULE SHA"
adb -s "$S" shell sha256sum /vendor/bin/s55_kpoc_bridge /vendor/etc/init/s55-kpoc-bridge.rc /vendor/etc/init/s55-kpoc-fuelgauged.rc </dev/null
echo "=== KERNEL SUSPEND / FRAMEBUFFER / LED SYSFS READ-ONLY"
adb -s "$S" shell '
for f in /sys/power/state /sys/power/autosleep /sys/class/leds/lcd-backlight/brightness /sys/class/leds/lcd-backlight/max_brightness /sys/class/graphics/fb0/blank /sys/class/graphics/fb0/state; do
 echo "$f"
 cat "$f" 2>&1 || true
done
echo "=== CHARGER SERVICES:"
getprop init.svc.s55_kpoc_bridge
getprop init.svc.fuelgauged
getprop init.svc.s55_kpoc_fuelgauged
echo "=== KERNEL VERSION"
cat /proc/version
echo "=== LAST KMSG"
wc -c /proc/last_kmsg 2>&1 || true
echo "=== PSTORE NAMES"
ls -la /sys/fs/pstore/ 2>&1 | head -25
' </dev/null
