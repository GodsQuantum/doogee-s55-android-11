# DOOGEE S55 — Battery and standby investigation, 9 October 2026

**Status: partial power optimization and private backup completed; charging/thermal bug not repaired; no ROM flashed.** This document deliberately excludes phone-specific serial numbers, radio identifiers, user account names and raw private logs.

## Live tests (FR)

- The S55 completed boot under **crDroid 7.16 / Android 11** on Pegasus, USB debugging available and battery level **46 %** after wall charging. USB charge was recognized, but Android's `dumpsys battery` still displayed **0 mV / 0 °C**, which are **invalid readings**; they do not establish real cell voltage or temperature.
- MediaTek **`fuelgauged`** was running and logging the correct displayed level. Stock `healthd` reported zero voltage/temperature. The Oreo-vendor **thermal HAL** logged `EACCES (-13)` opening `/proc/mtktz/mtktscpu` and `/proc/mtktz/mtktsbattery`. Its exact failure mechanism (SELinux policy, procfs permission, device nodes or HAL mismatch) is **not yet proven**.
- `dumpsys thermalservice` reported `ThermalHAL 1.0 connected: yes` but did **not expose usable temperatures**. Never disable charging, low-voltage or overtemperature safeguards to hide this symptom.
- `dumpsys batterystats --charged` contained **historical**, multi-day data: approximately 3 d 22 h 37 min on-battery real time, versus 3 d 17 h 57 min awake uptime. This suggests unusually low deep sleep over the sampled period, but cannot be extrapolated directly to today's instantaneous drain. Do not use the estimated battery capacity field as a hardware health measurement.
- Main **historical** kernel wakelocks: `ttyC0` ~33 h 6 min, `WLAN AHB ISR` ~16 h 54 min, `pmicAuxadc irq wakelock` ~1 h 3 min, `microarray_process_wakelock` ~46 min. The modem/UART and Wi-Fi stack deserve priority; **do not disable calls, Wi-Fi, fingerprint or all sensors** merely because a wakelock appears in a historic report. Actual attribution requires comparing increments between two screen-off captures under controlled network conditions.
- The phone reported **`mobile_data_always_on=1`** despite active Wi-Fi. This can keep cellular data established even on Wi-Fi, increasing radio overhead and improving instant handover. It is a configurable tradeoff, not proof of the primary drain.

### Reversible native changes completed in Android

```text
settings put global low_power_trigger_level 20
settings put global automatic_power_save_mode 0
settings put global mobile_data_always_on 0
```

All three values were **read back and confirmed** while Android was connected on 9 October 2026. Result: automatic Battery Saver at **20 %**, and cellular data is not intentionally held active while connected to Wi-Fi. Calls, SIM support, mobile data when needed, Wi-Fi and fingerprint remain available. A brief handover delay when leaving Wi-Fi is possible.

Rollback for the radio behavior if the user requires instant dual connectivity: `settings put global mobile_data_always_on 1`. Battery Saver threshold had previously been 15%; restoring it is `settings put global low_power_trigger_level 15`. Settings may be lost after a full ROM reinstall.

An **automatic shutdown at 5 % has deliberately not been added**: the fuel gauge previously reported 0–1 % and invalid voltage/temperature. A forced shutdown tied to an unreliable reading could create another deep-discharge recovery failure. Test an alert at 15 % and normal charging well before 10 %, after independent fuel-gauge validation.

### Recovery/backups completed without flashing

- A **temporary RAM boot** of the exact local TWRP 3.1.1 image returned `fastboot boot ... OKAY` while battery was ~46 %, but **recovery ADB never became accessible**; the phone subsequently booted the existing Android 11 system normally. Do **not** describe this as working TWRP.
- MTKClient 2.1.4 (revision `cd25cf9`, September 2026) recovered **10 additional device partitions, all read-only**: `nvram`, `nvdata`, `protect1`, `protect2`, `proinfo`, `secro`, `seccfg`, `recovery`, `md1img`, `vendor`. The final vendor partition was 512 MiB. A temporary MediaTek Download Agent was loaded into memory; **no eMMC partition was written**.
- Files are **private and ignored by Git** under `backups/device-2026-10-09/radio-vendor-readonly/`, with `SHA256SUMS`, a local-only MediaTek log and owner-restricted permissions. They were copied byte-for-byte from Pegasus to Cloud9 and passed SHA-256 verification on both systems. **Do not publish or attach any of these backups**, especially NV* partitions.
- The previously saved `boot`, `lk`, `lk2` are also SHA-256 validated. Together these protect much of the boot/vendor/radio state, but **not** the 53 GiB userdata or a full 64 GiB eMMC image. A boot/GPT/restoration recovery plan is still required before modifying layout.
- A subsequent `mtk.py reset` attempt failed to restore normal USB enumeration. Pegasus kernel repeatedly reported USB descriptor read timeouts `-110` and device address errors `-62` on the existing cable/hub connection between 23:31 and 23:33. This does **not prove a battery defect**, but confirms that the host can no longer send commands to the phone. **Normal Android boot after this reset has not yet been verified.** A manual long-press of Power is needed to reboot the phone; keep USB connected and check ADB afterward. Avoid resetting the entire Genesys hub because it also carries other Pegasus peripherals, including Ethernet.

### Next safe experiments after Android is accessible again

1. Confirm boot completed, battery above 40%, stable USB, three settings persisted. Obtain elevated diagnostic read permissions through the **documented developer toggle** for rooted debugging only if present and explicitly accessible. Do not circumvent access controls or modify boot just for telemetry.
2. Compare driver sysfs battery voltage, battery temperature, current and capacity (physical values) with Android `dumpsys battery`. Verify Android health service / HAL path, particularly `/proc/mtktz` access. Identify the actual permission failure before attempting a device-specific SELinux or sysfs fix.
3. Do controlled screen-off standby measurements with airplane mode OFF, first Wi-Fi ON, then Wi-Fi OFF, restoring settings at the end. Use two sequential `batterystats` snapshots and, with root, `wakeup_sources` counters. This differentiates WLAN interrupts from modem (`ttyC0`) and the fingerprint driver without disabling any capability permanently.
4. After stable power, validate [LineageOS 18.1 non-SAR](ROM-OPTIONS-FR.md) and **NikGapps Core Android 11** only in a staged, recoverable test. This would improve the ROM base but **would not increase the Android major version beyond 11**.
5. Android 13+ is a separate **SAR boot/vender compatibility porting project**. A local Android 13 GSI is saved but does not boot as a drop-in replacement of the current non-SAR system partition. Do not flash it until a compatible boot chain and rollback are independently tested.

### Technical references

- Android [battery status and service concepts](https://source.android.com/docs/core/perf/health) and [Linux power-supply sysfs semantics](https://docs.kernel.org/power/power_supply_class.html).
- [LineageOS developer rooted debugging prerequisite](https://wiki.lineageos.org/devices/kingdom/update/).
- Upstream [MediaTek AUXADC wakelock implementation](https://android.googlesource.com/kernel/mediatek/+/android-mediatek-sprout-3.4-kitkat-mr2/drivers/misc/mediatek/power/mt6582/pmic_mt6323.c).
- Community [MicroArray fingerprint driver wakelock case](https://4pda.to/forum/index.php?showtopic=320910&st=15460), unrelated hardware but similar subsystem.
- Google [system-as-root architecture](https://source.android.com/docs/core/architecture/partitions/system-as-root) and [GSI constraints](https://developer.android.com/topic/generic-system-image).

## Summary / Résumé

**EN:** Battery Saver at 20% and disabling simultaneous always-on cellular data while using Wi-Fi were successfully applied via ADB. The MediaTek fuel gauge works, but Android's voltage/thermal reporting is invalid and thermal HAL access errors remain. Private radio/vendor backups are complete and verified. Booting current Android again and any new ROM install remain outstanding.

**FR :** Économiseur à 20 % activé et données cellulaires permanentes sous Wi-Fi désactivées. La jauge MediaTek fonctionne, mais les valeurs tension/température Android sont invalides et des erreurs HAL thermiques persistent. Sauvegardes privées radio/vendor complètes et validées. Le redémarrage final sous Android et toute nouvelle ROM restent à valider.
