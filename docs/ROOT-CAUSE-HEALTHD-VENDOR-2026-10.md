# DOOGEE S55 — Root cause audit: Android 11 / Oreo vendor (10 Oct 2026)

> **Status update (10 October 2026):** All four legacy linker/voltage repairs were validated on real Android 11, the five MTK sensors were enumerated, and LineageOS 18.1 has now been installed. The subsequent **battery temperature and thermal HAL fixes are also installed and verified under SELinux Enforcing**; see [definitive LineageOS battery/thermal report](BATTERY-THERMAL-LINEAGE18-2026-10.md). Remaining performance/deep-discharge limitations are distinct from these repaired telemetry issues. No bootloader, GPT, preloader, battery safety threshold or factory radio partition was changed.

[FR — choix des ROM](ROM-OPTIONS-FR.md) · [Battery history](BATTERY-POWER-AUDIT-2026-10.md) · [Fingerprint](FINGERPRINT-FIX.md)

## What was actually wrong

**This was not a general root/privileged-app setting error.** The crDroid Android 11 GSI runs with enforcing SELinux and connects to the old DOOGEE Oreo vendor (VNDK 26). Its changes to the Android framework and ELF/linker namespaces exposed interface incompatibilities that the stock Oreo image masked. The earlier validated MicroArray fingerprint modification remained intact and labeled `vendor_file`. The historical fstab change retained its `system_file` label. There is **no evidence** that all security contexts or superuser privileges were corrupted.

### Issue 1 — 0 mV battery reading: repaired

- The kernel correctly provides `/sys/class/power_supply/battery/batt_vol` (TWRP root observed **3,741,000 µV** around 50%). It **does not** provide `.../voltage_now`.
- Android 11's `/system/bin/healthd` sought two `voltage_now` paths and returned **0 mV**. The older Android healthd implementation [officially included a `batt_vol` fallback](https://android.googlesource.com/platform/system/core/+/b4354b3/healthd/BatteryMonitor.cpp).
- Built a guarded equal-length ARM64 ELF patch switching `voltage_now` to `batt_vol\x00\x00\x00`. The executable length stayed 79,960 bytes; only 20 bytes differ across two positions. The original and corrected files are stored **privately** under `backups/device-2026-10-10/`.
- Exact original SHA256: `14f0dbbb8ae722df2da8f1b040a6412cc6541e0ac20fd37cc4b782e98a845ef3`. Corrected SHA256: `d364def27affe780131c22c3d5a89c60e73f7e3bba12b6093c235f3a69cc9b05`.
- Installed via `scripts/fix-healthd-voltage.sh --apply` from TWRP root, original `healthd_exec` SELinux label and executable permissions retained; `/system` returned RO.
- **Live verified:** Android 11 boot completed, SELinux enforcing, `healthd` running; `dumpsys battery` measured **3,769–3,896 mV**, versus 0 before. Recovery `batt_vol` also produced plausible readings.

**Important caveat:** The reported `Max charging voltage` in `dumpsys battery` started following battery voltage (~3.8–3.9 V), whereas previously it was 5 V. This is a framework/healthd reported field, **not a physical voltage measurement** of the USB charger. Determine whether the second patched generic path is also used for charger voltage; consider a more surgical patch or AOSP/PHH healthd board config. Do not touch the kernel's charger safety controls to change a display field.

**Rollback in TWRP:** `scripts/fix-healthd-voltage.sh --restore`. The guard checks exact original and patched SHA256 and battery voltage. Never run the installer on an unknown `healthd`.

### Issue 2 — Vendor restart loops caused by missing GSI linker libraries: repaired

At first Android 11 reboot, crash logs showed `ipsec_mon` and `gesturewake_hal` failing to link **roughly every 5 seconds**:

- `/vendor/bin/ipsec_mon` needed ARM64 `liblogwrap.so`.
- `/vendor/bin/hw/vendor.hct.hardware.gesturewake@1.0-service` needed ARM64 `vendor.hct.hardware.gesturewake@1.0.so`.
- On stock DOOGEE Oreo (October 2018), both existed in `/system/lib64/` and were not in the Oreo vendor partition. They were no longer available in the isolated vendor namespace after installing the Android 11 GSI.
- The donor binaries have been extracted **from the locally preserved genuine DOOGEE S55 October 2018 system.img**, not from a different phone, and saved privately under `files/candidates/s55-2018-compat/` (not in Git).
- SHA256 stock ARM64 liblogwrap = `305b1e419589b19836ed2986d5f43af34de6783e46d54230b23ef3e08081577a`.
- SHA256 stock ARM64 gesturewake = `c0f5631eb2c3373e2a197282669f67ed31166fe508660718b6f14cb2103df318`; ELF analysis confirms **all 11** required HCT symbols of the actual 2020 vendor service are exported.
- `scripts/fix-vendor-compat-s55.sh --apply` copied the two matching stock libraries to `/vendor/lib64/`, SHA256 checked, root:root / 0644 / SELinux `vendor_file`; `/vendor` remounted RO.
- **Live verified after reboot:** `init.svc.ipsec_mon=running`, `init.svc.gesturewake_hal=running`, **no further ipsec or gesturewake linker crashes**, Android boot completed, enforcing mode retained. Declared gesturewake HIDL interface appears in `lshal`. Actual wake gesture functionality should still be tested manually before calling that feature fully verified.

**Rollback in TWRP:** `scripts/fix-vendor-compat-s55.sh --restore` removes precisely these added files, after validating hashes and device identity. This restores the pre-fix broken-linker baseline.

### Issue 3 — Old 32-bit sensor executable has undeclared logging dependency: installed, validation pending

At boot the original `msensord` and `memsicp` failed:

```text
CANNOT LINK EXECUTABLE "/vendor/bin/msensord": cannot locate symbol "__android_log_print"
CANNOT LINK EXECUTABLE "/vendor/bin/memsicp": cannot locate symbol "__android_log_print"
```

Their ARM32 dynamic symbol tables reference `__android_log_print` but have **no ELF `DT_NEEDED liblog.so`** entry. Original vendor binaries were extracted to private storage. Using temporary desktop `patchelf 0.18.0`, added `DT_NEEDED liblog.so` and confirmed ARM32 architecture and original other dependency names.

| Executable | Original SHA256 | Patched SHA256 |
|---|---|---|
| msensord | `720ba2530b84bd7657bfd835430d3511ef4343c611116cd2502c816143845f39` | `4a8a72f9ab04c0ea6375742fb2df46df1f40ef66c624b7846c039c3fdd254092` |
| memsicp | `960a1253262b641a47edda2c6bada399f2e20c8bc24a92c8e1bfbe489b4701d3` | `aa0c71b333ea0811e67add92feccee8998089836badb6e2d8a3d8cea62a25176` |

Installed from TWRP via `scripts/fix-vendor-sensor-log-s55.sh --apply`. Both target inode SELinux labels (`msensord_exec` and `memsicp_exec`), owner and executable flags preserved, bytes verified and /vendor returned RO. **Post-reboot validation completed:** Android finished booting, SELinux remains **Enforcing**, both vendor executables no longer produce `CANNOT LINK` errors. Both services report `stopped`, but the verified vendor init configuration declares **`oneshot`** for both: `msensord` and `memsicp` are allowed to exit after initialization. This establishes that the original linker errors are resolved, **not** that every individual accelerometer/compass calibration mode has been functionally exercised. **Live sensor-service evidence after reboot:** `init.svc.sensors-hal-1-0=running`; `dumpsys sensorservice` lists **5 actual MTK hardware sensors** (accelerometer, magnetometer, gyroscope, ambient light and proximity), plus standard Android fusion sensors. It contains timestamped recent readings from accelerometer, magnetometer and gyro, with nonzero values. Thus physical sensors are being enumerated and delivering data under crDroid 11. Manual orientation/compass calibration and wake-gesture user-interface tests remain to be performed. If regressions appear, restore the original executables with `--restore` from TWRP.

### Issue 4 — Battery thermal reporting: NOT YET REPAIRED

- Android 11 `dumpsys battery` still gives `temperature: 0`, and TWRP root reads `/sys/class/power_supply/battery/batt_temp=0`.
- Independently, kernel thermal subsystem reports valid `/proc/mtktz/mtktsbattery=25000` (25 °C), `/proc/mtktz/mtktscpu=37200` (37.2 °C), `/sys/class/thermal/thermal_zone0/temp=29000` (29 °C), at different moments. This shows the thermal zone machinery is present, not that all readings are calibrated.
- Stock vendor thermal HAL `/vendor/bin/hw/android.hardware.thermal@1.0-service` runs as **system:system**, but logs `EACCES(-13)` on `/proc/mtktz` entries. Exact denial type (SELinux vs procfs open flags/permissions) is not proven. Global `setenforce 0` is **not** an acceptable persistent workaround; capture exact denials and apply minimally scoped correction only after proving path and units.
- **Root cause of the thermal HAL permission error now isolated to vendor SELinux policy:** the phone's exact preserved Oreo `nonplat_sepolicy.cil` declares `proc_mtktz` and allows other system and MediaTek services to read it, but lacks an `allow hal_thermal_default proc_mtktz` entry. Android 11 shell also sees SELinux `Permission denied` reading `/proc/mtktz` despite the kernel nodes being readable in permissive TWRP. The HAL itself is assigned `hal_thermal_default`; its init service is `system:system` and cannot browse these files under Enforcing.
- Prepared a **minimal read-only rule** in temporary offline policy input (no policy changes on phone): `(allow hal_thermal_default proc_mtktz (dir (search read open getattr)))` and `(allow hal_thermal_default proc_mtktz (file (open read getattr)))`. Extracted the exact running crDroid 11 system `plat_sepolicy.cil`, `mapping/26.0.cil`, compatibility mapping and the archived vendor's `nonplat_sepolicy.cil`. Both original and augmented policies compiled successfully with Debian `secilc` when using `-N -m -M true -G -c 30`. Their binary policies have different hashes, demonstrating that the scoped rules are present in the output. The **original policy itself raises neverallow conflicts** on this newer offline compiler without `-N`; no inference about the device bootloader should be made from a successful `-N` compilation.
- **Do not install** this binary policy merely because it compiled. The handset has an existing precompiled policy/Android split-policy hash path that must be verified and a tested rollback from TWRP before any persistent modification. Global Permissive is not acceptable.
- Android's `batt_temp=0` persists even with TWRP root, so fixing this HAL's procfs access may restore thermal monitoring but **would not automatically correct Android's battery temperature field**. Different thermal sysfs APIs use millidegrees Celsius, whereas the Android battery service expects tenths of a degree. Do not substitute one without safe conversion and independent validation.
- Do not fake cell temperatures or force battery-protection overrides. A real battery may be degraded despite correctly reported voltage.

## Modern Android upgrade constraints

The S55 is MT6750/MT6755 ARM64, Android Oreo VNDK 26 vendor, kernel 3.18.60+, non-SAR/A-only system layout. This is why direct Android 13–17 GSI images are unsafe as simple replacements. The *local* LineageOS 20/Android 13 is SAR and requires a **boot/init/fstab/vendor migration and full rollback plan**. Other modern GSI ecosystems similarly expect newer Treble interfaces. Image size fitting on the system partition does not prove compatibility.

A tested modern alternative to evaluate first is local **LineageOS 18.1 Android 11 non-SAR** (January 2024 security patch) plus private NikGapps Core Android 11 (Feb 2026). It gives a newer security base but **not a newer major Android version**. Continue investigating a dedicated SAR bridge for Android 13 with measured tests; do not claim it already runs.

**Modernization priorities after all repairs**: (1) phone boots, charges and sleeps correctly; (2) full per-service SELinux and vendor linker compatibility; (3) test battery thermal readouts, camera, GPS, fingerprint, calls, mobile data, WiFi, BT, gestures, sensors; (4) compare performance and standby under Lineage 18.1; (5) prototype Android 13 and later without sacrificing rollback. User authorizes wiping userdata, **not** erasing modem identity partitions.

## Release and privacy

- Never publish raw `vendor`, `nvram`, `nvdata`, radio identifiers, crash dumps containing user accounts, nor the stock DOOGEE/MediaTek proprietary ELF donor files. Keep only scripts, checksums, documentation and source attribution in Git.
- Backups (read-only MTKClient) are private under `backups/device-2026-10-09/` and newer per-binary recovery copies under `backups/device-2026-10-10/`; prior radio/vendor SHA256 verified.
- GitHub connector write operations have returned HTTP 403, therefore only local commits can be claimed until access is restored.
