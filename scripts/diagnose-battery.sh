#!/usr/bin/env bash
# DOOGEE S55: host-side read-only battery diagnostics. NEVER flashes/reboots/wipes.
set -u
export LC_ALL=C
printf '\n== DATE AND HOST ==\n'
date -Is
uname -srm
printf '\n== USB ==\n'
command -v lsusb >/dev/null && lsusb
printf '\n== ADB ==\n'
if command -v adb >/dev/null 2>&1; then adb devices -l; else echo 'adb unavailable on this host'; fi
printf '\n== FASTBOOT ==\n'
if command -v fastboot >/dev/null 2>&1; then fastboot devices -l; else echo 'fastboot unavailable on this host'; fi
printf '\n== USB KERNEL LOG (45 MIN) ==\n'
journalctl -k -b --since '-45 minutes' --no-pager 2>/dev/null | grep -iE 'usb|mediatek|mt65|0e8d|0bb4|ttyACM' | tail -60 || true
if ! command -v adb >/dev/null 2>&1; then echo 'No adb client available; phone data cannot be read.'; exit 0; fi
serial="$(adb devices | awk '$2=="device"{print $1}' | head -1)"
count="$(adb devices | awk '$2=="device"{n++}END{print n+0}')"
if [ "$count" -ne 1 ] || [ -z "$serial" ]; then
  echo 'No single authorized ADB device. Preloader/BROM are NOT ADB. No battery metrics available.'
  exit 0
fi
phone() { timeout 20 adb -s "$serial" shell "$1" 2>&1 || true; }
printf '\n== PROPERTIES ==\n'
phone 'getprop ro.product.model; getprop ro.build.version.release; getprop ro.bootmode; getprop ro.boot.bootreason; getprop sys.boot_completed; getprop ro.twrp.version; getprop ro.enable_boot_charger_mode; getprop ro.charger_mode_autoboot'
printf '\n== BATTERY KERNEL INTERFACES ==\n'
phone 'for d in /sys/class/power_supply/*; do [ -d "$d" ] || continue; echo "### $d"; for f in type status capacity health present voltage_now current_now current_avg charge_full charge_full_design temp online input_current_limit; do [ -r "$d/$f" ] && { printf "%s=" "$f"; cat "$d/$f"; }; done; done'
printf '\n== BATTERY SERVICE ==\n'
phone 'dumpsys battery'
printf '\n== POWER AND IDLE ==\n'
phone 'dumpsys power | head -n 90'
phone 'dumpsys deviceidle | head -n 80'
printf '\n== BATTERYSTATS ==\n'
phone 'dumpsys batterystats --charged | head -n 130'
echo 'READ ONLY. Output may contain identifying info: do NOT commit logs.'
