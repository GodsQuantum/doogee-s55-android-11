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
for f in /sys/power/state /sys/power/autosleep /sys/power/wakeup_count /sys/class/leds/lcd-backlight/brightness /sys/class/leds/lcd-backlight/max_brightness /sys/class/leds/lcd-backlight/trigger /sys/class/graphics/fb0/blank /sys/class/graphics/fb0/state /sys/class/graphics/fb0/name; do
 echo "$f"
 cat "$f" 2>&1 || true
done
echo "=== SYSFS LCD DRIVER PARENTS (READ-ONLY)"
for f in /sys/class/leds/lcd-backlight/device /sys/class/leds/lcd-backlight /sys/class/graphics/fb0/device; do
 printf "%s -> " "$f"
 readlink -f "$f" 2>&1 || true
done
echo "=== BACKLIGHT CLASSES (NAMES ONLY)"
ls /sys/class/backlight/ 2>&1 || :
echo "=== POWER AND DISPLAY SERVICES"
getprop init.svc.s55_kpoc_bridge
getprop init.svc.s55_kpoc_lcd_off
getprop init.svc.s55_kpoc_fuelgauged
getprop init.svc.fuelgauged
echo "=== POWER KEY DEVICES"
grep -A8 -B2 -E "mtk-kpd|ACCDET" /proc/bus/input/devices | head -35
' </dev/null
echo "=== KERNEL VERSION"
adb -s "$S" shell 'cat /proc/version' </dev/null
echo "=== LAST KMSG SIZE"
adb -s "$S" shell 'wc -c /proc/last_kmsg' </dev/null
echo "=== PSTORE NAMES"
adb -s "$S" shell 'ls -la /sys/fs/pstore 2>&1 | head -25' </dev/null
