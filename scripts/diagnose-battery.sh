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
# MT6750 S55 exposes batt_vol (uV), batt_temp (0.1 C) instead of
# standard voltage_now and temp. Read only, no ADB root.
phone 'for d in /sys/class/power_supply/*; do
  [ -d "$d" ] || continue
  echo "### $d"
  for f in type status capacity health present voltage_now batt_vol temp batt_temp current_now BatteryAverageCurrent current_avg ChargerVoltage charge_counter charge_full charge_full_design online current_max input_current_limit; do
    [ -f "$d/$f" ] || continue
    printf "%s=" "$f"
    cat "$d/$f" 2>/dev/null || printf "UNAVAILABLE (permissions)\n"
  done
done'
printf '\n== BATTERY SERVICE ==\n'
phone 'dumpsys battery'
printf '\n== THERMAL HAL ==\n'
phone 'dumpsys thermalservice | grep -E "Thermal Status|mName=(BAT_T|SKIN_T|CPU_T|GPU_T)|ThermalHAL" | head -n 28'
printf '\n== NATIVE POWER SETTINGS ==\n'
phone 'for key in low_power_trigger_level automatic_power_save_mode mobile_data_always_on ble_scan_always_enabled wifi_scan_always_enabled airplane_mode_on; do printf "%s=" "$key"; settings get global "$key"; done'
printf '\nNOTE: charge_counter and USB Max charging current do not measure true cell capacity or actual USB current.\n'
printf 'NOTE: a working battery display does not demonstrate off-mode charging or recovery after 0%%.\n'
printf '\n== POWER AND IDLE ==\n'
phone 'dumpsys power | head -n 90'
phone 'dumpsys deviceidle | head -n 80'
printf '\n== RIL / RADIO HEALTH (IMPORTANT FOR IDLE DRAIN) ==\n'
phone 'printf "ril-proxy="; getprop init.svc.ril-proxy; printf "ril-daemon-mtk="; getprop init.svc.ril-daemon-mtk; printf "sim_state="; getprop gsm.sim.state; printf "PHH_RIL_AUTO_RESTART="; getprop persist.sys.phh.restart_ril'
printf '\n== RIL CRASH COUNT AND ANDROID PHONE PROCESS DEATHS ==\n'
phone 'logcat -d -b crash -v brief 2>/dev/null | grep -c -E "Fatal signal.*rilproxy|Fatal signal.*Ril Proxy Main" || true'
phone 'logcat -d -b events -v brief 2>/dev/null | grep -c -E "am_proc_died.*com.android.phone" || true'
printf '\n== BATTERYSTATS ==\n'
phone 'dumpsys batterystats --charged | head -n 130'
echo 'READ ONLY. Never enable RIL auto restart in a crash loop without testing.'
echo 'Output may contain identifying info: do NOT commit logs.'
