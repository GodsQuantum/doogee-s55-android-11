> **Historical candidate assessment (before the 10 October LineageOS migration).** LineageOS 18.1 + NikGapps **has since booted and was inspected on the reference S55**. Any statements below claiming it has not been flashed are preserved as historical findings, not the current status. See the [current installation audit](INSTALLER-SAFETY-AUDIT-2026-10.md) and [migration report](LINEAGE18-MIGRATION-ROOT-CAUSE-2026-10.md).

# DOOGEE S55 — Android upgrade candidates and alternative OSes (October 2026)

**Status: research and static testing, NOT proof of a successful upgrade.** Only the existing crDroid 7.16 / Android 11 upgrade and its S55-specific fixes have been validated on the actual phone. The user is currently charging the handset from a wall charger; no firmware modifications are being attempted.

[README](../README.md) · [Guide en français](ROM-OPTIONS-FR.md) · [Battery and charging](BATTERY-CHARGING.md) · [Current GApps installation](INSTALL-GAPPS-EN.md)

## Verified hardware constraints

- **DOOGEE S55**, not S55 Lite; MediaTek MT6750/MT6755, ARM64, 4 GB RAM, 64 GB eMMC.
- Legacy Oreo **VNDK 26 vendor**, **A-only and non-system-as-root (non-SAR)** partition arrangement.
- Active kernel recovered over MTKClient: **Linux 3.18.60+ built on June 29, 2020**. This **does not establish** that a full factory firmware dated June 2020 can be downloaded.
- The modified **current** system partition is **3,263,168,512 bytes**. Do not assume this size on another S55.
- Verified recovery images **boot / lk / lk2 only**, privately saved with SHA-256 on October 9, 2026. Not a complete phone backup or an IMEI/modem backup.
- With low battery and a PC USB connection, the bootloader reported `low power, need battery charging.` Android reported 0–1% and unusable battery voltage/temperature metrics. **The owner later reported the device charging successfully to 20% on a wall charger**, so power delivery does work in at least one configuration. Do not assume the battery is dead.

## Ranked firmware candidates

| Candidate | Android | Locally available file | Actual S55 support |
|---|---|---|---|
| crDroid 7.16 with built-in Google apps | **11** | `crdrom-v316-220330-arm64-agZ.img` | **Previously verified** using the instructions in this repository |
| AndyYan LineageOS 18.1 (Jan 2024) | **11** | `los18.img`, `los18.img.xz` | ARM64 non-SAR, suitable for a controlled **first device test**; not yet boot-tested |
| AndyYan LineageOS 20 (Oct 2025) | **13** | `gsi_los20.img` | ARM64 **system-as-root/SAR**; **NOT a drop-in image** for the current S55 |
| LineageOS 21 and other Android 14 GSIs | **14** | Not qualified locally | Requires a device-specific SAR boot/vendor compatibility strategy |
| Modern Android 15, 16, 17 GSIs | **15–17** | Available upstream, not qualified locally | **Not validated; do not flash directly** on this Android 8-era platform |
| Factory DOOGEE Oreo | **8** | Stock 2018 image sets in local project | Recovery/fallback reference only; 2019 release also documented elsewhere |

Google's official [GSI device requirements](https://developer.android.com/topic/generic-system-image) target fully Treble-compliant devices originally launched with Android 9+. Its [Android 12 GSI documentation](https://source.android.com/docs/core/tests/vts/gsi) says that workarounds for older, incompletely Treblized Android 8.x devices were dropped. Android 12+ would require a researched device-specific migration rather than a generic flash.

Sources: [AndyYan Lineage 18.1 downloads](https://sourceforge.net/projects/andyyan-gsi/files/lineage-18.x/), [AndyYan Lineage 20 October 2025](https://sourceforge.net/projects/andyyan-gsi/files/lineage-20-td/), [Google Android 17 GSIs](https://developer.android.com/about/versions/17/gsi-release-notes), and [system-as-root migration](https://source.android.com/docs/core/architecture/partitions/system-as-root).

## Read-only tests completed on Cloud9

Reproduce (the command performs **no** ADB, fastboot, mounts or image writes):

```bash
python3 scripts/audit-rom-candidates.py
```

| Image | Framework security patch **declared in the file** | Layout | Size | Free space inside current /system |
|---|---|---|---:|---:|
| crDroid Android 11 GApps | March 5, 2022 | non-SAR | 3,088,048,128 B | 167 MiB |
| LineageOS 18.1 Android 11 | January 5, 2024 | **non-SAR** | 2,055,483,392 B | 1,151.7 MiB |
| LineageOS 20 Android 13 | September 5, 2025 | **SAR** | 2,242,465,792 B | 973.4 MiB |

The local LineageOS 18.1 image has a **non-SAR filesystem layout**, even though its compiled build description still contains `arm64_bvS`; inspect actual layout, not just the build description. Its 617.1 MB compressed file passed `xz -t`, and its decompressed bytes match `los18.img` exactly (image SHA256 `6ff112b937a5043aee862b48330a3895bb040461cdbe4304b342468600c7aaf5`); consistent with AndyYan's January 21, 2024 ARM64 `avS` build; cryptographic provenance is **not independently verified**.

LineageOS 20 has a SAR root `/init` pointing to `/system/bin/init`, and the ext4 image has `shared_blocks` set. It also requires analysis of old VNDK libraries and legacy MediaTek HAL startup. **Fits in a partition != boots on this phone.**

## Google Play integration — prefer minimal services

Official signed **NikGapps Core ARM64** archives downloaded to `files/candidates/` (ignored by Git), fully ZIP-tested:

| Target | File | Size | Locally measured SHA256 |
|---|---|---:|---|
| Android 11 | `NikGapps-core-arm64-11-20260204-signed.zip` | 80,480,608 B | `a56ad7da66e51a6cd1af0b0fb39a1ac167739161624115276b7f8d00633fd0f8` |
| Android 13 | `NikGapps-core-arm64-13-20260204-signed.zip` | 110,851,336 B | `d969df417bc3ea9c79e4219c8dd955d8d5f6d31597cbe5f88dc51518a3fc9613` |

These are locally computed checksums, **not independent signature verification**. They have not been flashed. Source: [NikGapps Releases](https://sourceforge.net/projects/nikgapps/files/Releases/). **Never** install the Android 13 package on Android 11. Avoid adding a second GApps stack on top of an image that already bundles Google services.

## Non-Android operating systems

- **postmarketOS / upstream Linux:** no working DOOGEE S55 port was confirmed. Its [MT6750/MT6755 mainline status](https://wiki.postmarketos.org/wiki/MediaTek_Helio_P10_%28MT6755%29) still shows core features such as USB, storage, GPU, calls, camera, Wi-Fi and suspend broken. It is a development project, **not** a functional replacement phone OS.
- **Ubuntu Touch, Droidian and SailfishOS:** no supported **device-specific S55 image** was confirmed. An image for another MT6750 device is not automatically compatible.

## Comparable battery/charging failures reported by GSI users

In the upstream [PHH Treble discussion for AOSP 12.1 v415](https://github.com/phhusson/treble_experimentations/discussions/2393), a Galaxy A50 user reported that connecting power after shutdown/empty battery triggered the **Android boot animation instead of the offline charging animation**, followed by a bootloop. **This is a comparable failure mode, not proof of the same root cause on the S55.** Offline charging must be tested separately from normal Android boot after every ROM experiment.

The [Treble community GSI index](https://github.com/TadiT7/treble_experimentations_wiki/blob/master/Generic-System-Image-%28GSI%29-list.md) explicitly describes SAR as the default for its listed builds, except where marked otherwise. The corresponding AOSP [non-A/B system-as-root conversion](https://source.android.com/docs/core/architecture/partitions/system-as-root) requires changing how the kernel/init/system partitions boot, not simply flashing a newer image to /system.

The reported 20% wall-charge recovery calls for **comparing PC/hub power negotiation to wall-adapter charging** before condemning the cell, and for validating the actual fuel-gauge signals once Android can run.

## Testing order after wall charging

1. Read-only complete rollback prerequisites: partition table and copies of **vendor, recovery, nvram, nvdata, modem identity** plus the existing boot/lk/lk2. Preserve serial, IMEI and unrelated data. The user allows a wipe of `userdata`, not destruction of radio identity or the recovery path.
2. Verify USB charging, actual battery driver voltage/temp when access is authorized, radio network, hardware identity and baseline performance. Do not mistake invalid Android 0 mV readings for cell voltage.
3. Evaluate LineageOS 18.1 + correctly matched NikGapps Core 11 (first boot, reboots, fingerprint after second boot, camera, LTE, sound, GPS, Bluetooth, charging, standby and Google Play).
4. For Android 13, **prepare a separate SAR-conversion experiment** using a backup of the exact active boot image, appropriate init/fstab/system and legacy vendor libraries. Validate a full rollback strategy **before writing**. No direct flash of `gsi_los20.img`.
5. Profile benchmark outcomes and keep the actual winner. Do not assume a higher version runs faster on 4 GB RAM and MT6750.
6. Consider Android 14+ only after SAR/vendor adaptation is proven.

## Carry-forward requirements for newer Android builds

The October 10 on-device audit uncovered and fixed several independently reproducible Android 11/Oreo-vendor incompatibilities: legacy MediaTek battery voltage property `batt_vol` instead of `voltage_now`, missing OEM HIDL/IMS linker libraries, undeclared ARM32 sensor `liblog.so` dependencies, and a still-unresolved `proc_mtktz` thermal HAL SELinux permission gap. The MicroArray fingerprint patch remains independently required. See [full per-file compatibility audit and rollback commands](ROOT-CAUSE-HEALTHD-VENDOR-2026-10.md).

Any Android 13–17 port must account for these interfaces **with version-appropriate binaries and policies**; do not transplant the old Android 11 healthd executable or Oreo vendor sepolicy into a newer framework. **10 October update:** the Android 11-targeted SELinux read-only thermal rules were later installed and verified on the real phone. They are **not portable** to Android 13+ without revalidation.

## Battery reservation policy

For now, use the stock Android **Battery Saver trigger near 20%**, charge before 10%, and test the fuel gauge first. The user's suggested forced shutdown at an indicated **5% is not a physical reserve** if the battery estimator is unreliable; it could make recovery worse. The 20% native setting was prepared but **not yet applied** because ADB disappeared when the owner moved the phone to a wall charger.

Detailed decision record and USB logs: [October 2026 deep discharge investigation](RESEARCH-DEEP-DISCHARGE-2026-10.md).
