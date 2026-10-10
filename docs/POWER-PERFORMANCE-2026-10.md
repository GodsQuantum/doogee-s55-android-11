# DOOGEE S55 — battery, performance and safety defaults (October 2026)

[English](../README.md) · [Français](../README.fr.md) · [简体中文](../README.zh-CN.md) · [Installer safety audit](INSTALLER-SAFETY-AUDIT-2026-10.md)

## Verified on the reference LineageOS 18.1 handset

- Battery Saver threshold **25%**: `low_power_trigger_level=25`; Android-controlled automatic mode `automatic_power_save_mode=0`.
- Avoid keeping cellular data permanently active under Wi-Fi: `mobile_data_always_on=0`. Cellular service remains available, but handover after losing Wi-Fi may take longer. **Do not disable the modem or telephony for this purpose.**
- Reduce background BLE location scanning: `ble_scan_always_enabled=0` (ordinary Bluetooth remains available). Wi-Fi scanning was already set to `wifi_scan_always_enabled=0`; the installer deliberately does not impose a new value here.
- Light/deep Doze were reported enabled. No custom wakelock killer, root daemon, CPU overclock, undervolt, forced 5% shutdown or startup service has been added.
- Voltage readout: device kernel uses legacy `batt_vol`; temperature readout uses `batt_temp` in tenths of °C. The exact Android 11 healthd binary, thermal HAL `proc_mtktz` read-only SELinux rules and OEM sensor/fingerprint fixes are hash-checked. **Thermal protection must never be bypassed.**

The kit applies and independently reads back its four Android global settings **only after the new ROM has booted**. Existing working S55 owners should use `./INSTALL.sh --verify` to *read* Android/GApps/thermal and native power settings, **never `--install` to adjust settings**.

## What is deliberately NOT a generic optimization

- Never disable thermal services, MediaTek fuel gauge, modem, MicroArray HAL or security rules based only on a historical wakelock.
- Do not replace vendor libraries/boot from another variant or S55 Lite. OEM June 2020 boot and the patched vendor are specific to the reference handset.
- No assured recovery after a physically deeply discharged lithium-ion battery: low-voltage protections belong to the LK/PMIC/charger hardware.
- A battery percentage displayed through Android, a `dumpsys battery` “max charging current” and USB-hub rated power are not physical measurements of actual charge current.
- Do not promise improved standby from an A/B measurement with USB connected. Previous reference tests showed continuous USB/battery wakelocks, so they did not represent untethered idle.
- Aggressive application disabling, lowering SELinux to Permissive, installing third-party CPU governors, editing `build.prop` memory knobs or moving to Android 13+ SAR GSI do **not** become safe merely because they are popular in forums.

## Measurable evaluation on a different S55

After all first-run services and the user's own account setup settle, measure **unplugged** overnight battery loss under comparable screen-off, Wi-Fi/SIM/Bluetooth and ambient-temperature conditions, including realistic standby. Record starting and ending state, uptime, radio conditions, deep sleep and unexpected restarts. Compare one variable at a time, preserving emergency-calling availability. Keep the device above a safe charge reserve; do not deliberately drive it to 0%.

For suspected radio drains, investigate historical `ttyC0` modem and WLAN interrupt counters using deltas under the same test conditions. Previous USB-attached short tests showed that airplane mode reduced `ttyC0` wakelocks, but airplane mode also disables cellular/emergency calling and must **not** be silently made permanent.

## Dependency and firmware selection as of 10 October 2026

| Component | Recommended selection | Rationale |
|---|---|---|
| ADB/Fastboot | Official Android Platform-Tools **37.0.1** (July 2026) | Latest release listed in Google's October 2026 release notes; use a Linux host and a stable USB data cable |
| Android | Exact SHA-verified **LineageOS 18.1 ARM64 non-SAR** reference GSI (January 2024 Android security patch) | Physical S55 boot evidence; Android 11 security patch is old, not a supported modern Android release |
| Google Play | **NikGapps Core Android 11, 4 February 2026 stable** | Newest *stable release* in the Android 11 Release branch, tested on the reference S55; not the much larger third-party Oct 2026 Config-Releases |
| Recovery | Exact pinned S55 TWRP **3.1.1-0** | Old recovery has old e2fsprogs and potentially limited mount/ZIP behavior; must pass real environment checks and may still reject unknown factory revisions |
| Android 12–17 GSI | **Do not install as drop-in system images** | System-as-root migration, legacy MTK VNDK 26, boot/init compatibility, sepolicy and HAL work not validated |

Official upstream references: [Platform Tools](https://developer.android.com/tools/releases/platform-tools), [NikGapps Android 11 stable releases](https://sourceforge.net/projects/nikgapps/files/Releases/Android-11/), [community custom releases (not equivalent to stable Core)](https://sourceforge.net/projects/nikgapps/files/Config-Releases/Android-11/), [NikGapps A-only flashing order](https://nikgapps.com/misc/2023/03/04/Flash-NikGapps.html), [GSI prerequisites](https://developer.android.com/topic/generic-system-image), [AOSP system-as-root](https://source.android.com/docs/core/architecture/partitions/system-as-root), [AOSP battery health](https://source.android.com/docs/core/perf/health), [Linux power-supply semantics](https://docs.kernel.org/power/power_supply_class.html).

**Scope of this page:** documented, reproducible settings and conservative evidence-based tuning, not proof of longer battery lifetime or a full second-phone install.
