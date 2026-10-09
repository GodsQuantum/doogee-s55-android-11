# DOOGEE S55 — LineageOS 18.1 Android 11 migration (10 October 2026)

## Confirmed on the physical phone

LineageOS 18.1 ARM64 **non-SAR** from the local `los18.img`, build security patch **2024-01-05**, boots to `sys.boot_completed=1` with TWRP-preserved legacy MTK kernel, vendor, fingerprint patch and NikGapps Core Android 11. Android reports SELinux **Enforcing**.

A second normal reboot **also completed** with correct, non-deleted `/data/user/0` bind mount and the Android 11 DE/CE vendor data directories available. Prolonged stability should still be monitored independently; a boot-complete signal alone does not prove all system apps stable.

The previous crDroid 7.16 `/system` was copied bit-for-bit **before** this migration, zstd-compressed and integrity-verified. Raw SHA256 of the former 3,263,168,512-byte partition:
`1006ac7c3de774a61ad4f3bb69f4c8a8310ee5db59d4e9480365bfe79c067620`.
Its exact private copy, plus boot/vendor/radio backups, is under `backups/device-2026-10-10/` and `backups/device-2026-10-09/`; none is published.

## Verified installation

- LineageOS 18.1 source SHA256: `6ff112b937a5043aee862b48330a3895bb040461cdbe4304b342468600c7aaf5`.
- TWRP wrote **only** p28 `/system`. A full raw image readback SHA256 matched the source. Ext4 `resize2fs` grew the filesystem within the pre-existing p28 bounds; `e2fsck` completed cleanly. No GPT change.
- Installed `NikGapps-core-arm64-11-20260204-signed.zip` in TWRP, checksum `a56ad7da66e51a6cd1af0b0fb39a1ac167739161624115276b7f8d00633fd0f8`. Google Play Store (`com.android.vending`), GMS (`com.google.android.gms`) and Google Services Framework (`com.google.android.gsf`) are registered. About 1 GiB remained on /system after installation.
- On LineageOS's *own* ARM64 healthd ELF, fixed legacy MTK `batt_vol` fallback using a dedicated exact-SHA in-place patch: original `fc17574161e743e11c38e3d9d44b1c0b1bfdf04e946e78610dd69c80954c4215`; patched `5f66b4c372d09eb84f2b23dadedaad0a53242bc44f31fdd7787a5467bee9e3ee`. Verified label `healthd_exec`; SELinux Enforcing. `fix-healthd-voltage.sh` supports both exact crDroid and Lineage healthd binaries.
- Preserved the OEM MicroArray fingerprint vendor library, IMS gesture libraries and patched legacy sensor binaries. Their hashes were verified in TWRP after installation.

## First-boot failure and actual root cause

**An ordinary TWRP `wipe data` was not equivalent to a full format:** it preserved older TEE directories and left the Android 11 userdata provisioning unusable. A full ext4 reformat **only of userdata p30**, after independently confirming the exact block device, unlocked stale data and rebuilt a clean filesystem; the older TWRP command-line did **not** accept `twrp format data`. The real native TWRP `mke2fs` 1.42.9 was used, then `tune2fs` to restore reserved blocks, `e2fsck -fn` and verified mounting. The old tool cannot create the modern ext4 `quota` superblock feature directly; the recreated ext4 has kernel-supported conventional features instead, which passed the mount/fsck checks. All userdata, including internal-media contents, may be considered lost.

**More importantly, old Oreo `init.rc` lacked the Android 11 vendor CE/DE parent-directory preparation.** First boot logs preserved privately show:

- `vold: Failed to prepare /data/vendor_de/0: No such file or directory`
- `vold: Failed to prepare user 0 storage`
- `UserDataPreparer.prepareUserData` / `StorageManagerService.prepareUserStorageInternal` errors
- Missing app directories under `/data/user_de/0/`, SQLite crashes for phone, clock, Bluetooth; Android `RescueParty` requesting recovery.

AOSP [Android 11 init.rc](https://android.googlesource.com/platform/system/core/+/refs/tags/android-11.0.0_r33/rootdir/init.rc) requires `/data/vendor_ce` and `/data/vendor_de` as `root:root`, mode `0771`, **before** preparing user storage. TWRP was used to create and label exactly these two parent directories, `u:object_r:vendor_data_file:s0`. The following Android boot and the next normal reboot reached `sys.boot_completed=1`; the latter showed proper non-deleted `/data/user/0` mount. No new `Failed to prepare user 0 storage` appeared in the successful boot logs.

**This change persists across ordinary reboots but must be repeated after another complete userdata format.** The guarded and idempotent script `scripts/prepare-lineage18-userdata-s55.sh --check|--apply` records the native setup; use it after wiping userdata and before the next first boot. It changes no bootloader/vendor/kernel partition, starts no service and makes no broad SELinux exceptions.

Recovery error logs, pstore, dropbox and live logcat are kept **privately** at `backups/device-2026-10-10/lineage18-firstboot-failure-private/`. They must not be committed to GitHub.

## Hardware receipt checklist

| Area | Confirmed | Limitation |
|---|---|---|
| Boot/Android | LineageOS 18.1 Android 11 and SELinux Enforcing | 2024-01 security patch is not current |
| Google | Play Store, GMS, GSF registered | Google account sign-in / Play Store download requires user interaction |
| Battery voltage | healthd shows real ~3.8–3.9 V and 5 V charger maximum field | `battery temperature: 0` persists; no proof of physical charging current |
| Vendor | `ipsec_mon`, `gesturewake_hal`, `sensors-hal-1-0`, `fuelgauged` running | Actual hardware gesture not tested by screen |
| Sensors | Accelerometer, gyroscope, magnetometer, light, proximity enumerated | Calibration and physical tests still needed |
| Fingerprint | Fingerprint manager and MicroArray patch preserved, no HAL death in initial run | After userdata format zero enrolled fingers; must enroll and verify twice |
| Wi-Fi/Bluetooth | Wi-Fi enabled, Bluetooth in ON state | One Bluetooth database crash occurred early in the first successful boot, then service recovered |
| Mobile radio | Radio service running | No SIM inserted in either slot; calls/data not testable |
| Thermal | Kernel thermal nodes exist | Thermal HAL SELinux access candidate only tested offline; not installed |
| Security | SELinux Enforcing | On this legacy setup `ro.crypto.state=unsupported`; do not imply modern at-rest device encryption |

## Restoration

From verified S55 TWRP and Pegasus, the guarded `scripts/flash-lineage18-s55.sh --restore` restores the previous, exact crDroid **system partition** from the private backup and checks the full physical readback hash. Never erase NVRAM, NVDATA, PROTECT partitions or load a GPT merely to recover the ROM. Do not copy the Lineage healthd patch to crDroid or vice versa; hashes guard this.

Android 13 remains a **separate non-SAR → SAR porting project**; the available local LineageOS 20 Android 13 GSI was checked offline and not flashed because its init/root layout and VNDK runtime are not drop-in compatible with the preserved S55 boot and Oreo vendor.
