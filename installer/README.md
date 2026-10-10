# DOOGEE S55 → LineageOS 18.1 + Google Play, one command

**Target:** standard DOOGEE **S55**, original Android 8.0 firmware, MediaTek MT6750 family, eMMC GPT matching the documented stock S55 layout. **Not S55 Lite.** Host: Linux, USB data cable, current official Android Platform Tools (ADB / fastboot), bash, Python 3, xz, zstd, pv, sha256sum and e2fsck/resize2fs/sgdisk **in the bundled S55 TWRP recovery**.

## 1. Build the kit on the maintainer's authorized Linux workstation

The public Git repository contains the **installer source, documentation and checksums**; it does **not** redistribute the large ROM, Google package, OEM boot, vendor, or another user's sensitive calibration data.

The maintainer who has obtained the *exact locally verified binaries* builds a ready-to-copy offline directory with:

```bash
bash scripts/build-s55-lineage18-kit.sh
```

It produces **`local-kit/`** inside this project's working folder, containing everything needed for the following step. All binaries are compared to hardcoded SHA256 checksums. The vendor is an exact block-level capture of the repaired, functioning S55. **Keep the kit local/private: it includes proprietary firmware**. Do not commit it, publish it as a GitHub release or send any backup of another phone's NVRAM or NVDATA.

## 2. Copy the whole kit folder to a Linux computer with the stock S55 attached

Enable **Developer options → OEM unlocking and USB debugging** on the stock phone and authorize the computer. Keep the phone above **40%**, connected to USB, and make your own backup of its pictures/files, which will be erased.

Then run only:

```bash
cd local-kit
./INSTALL.sh
```

The single command guides through unlocking the bootloader (physical confirmation if necessary), entering the exact TWRP, safe backups, exact partition resizing, verified installation of LineageOS 18.1 and NikGapps Core, vendor/fingerprint/thermal compatibility, fresh user storage, and Android 11 boot and Google services checks.

For a non-destructive look at the installation plan:

```bash
./INSTALL.sh --plan
./INSTALL.sh --check
```

**Human interaction cannot be removed from OEM unlocking, physical key combinations, USB authorization and the initial fingerprint enrollment.** If an image, device signature, checksum or geometry does not match, the installer must refuse to flash it. No universal promise is made for unknown board revisions or modified S55 firmware.

## What's inside the local kit

- `assets/lineage18.img.xz`: validated non-SAR ARM64 LineageOS 18.1 / Android 11 system image, SHA256 pinned.
- `assets/nikgapps-core-11.zip`: NikGapps Core for Android 11, 4 February 2026.
- `assets/twrp-s55.img`: the tested S55 TWRP 3.1.1.
- `assets/boot-tested-s55.img`: 16 MiB 2020 boot/kernel/charger partition image, previously booted on our real S55. Does not include radio calibration.
- `assets/vendor-s55-known-good.img.zst`: full 512 MiB vendor partition captured after the working fingerprint, fstab, sensor, thermal and SELinux fixes; the installer verifies the uncompressed raw image after writing it.
- `scripts/`: the detailed rollback and individual fix utilities.
- `backups/device-2026-10-10/`: **only generic source binaries and known-good patch candidates** for this build; original phone data is not embedded.
- `manifest.sha256`: hash manifest checked before opening a connection to the phone.

**Per-phone backup data is created only after the installer connects to the target S55**, under `private-install-state/backup/`, never packaged by the kit builder. It includes each phone's original `system`, `vendor`, `boot`, `recovery`, `nvram`, `nvdata`, `protect1`, `protect2` and GPT image. These backups must remain private and are necessary if restoring original stock behavior. They cannot automatically restore the user's original internal storage, which is erased by OEM unlock and userdata formatting.

## Important implementation boundaries

- Before any repartition, verify exact known GPT sector ranges. On factory S55, the installer increases `/system` from ~2.995 GiB to ~3.263 GiB by reducing `/cache` without moving the start of `/data`. It never uses a generic MediaTek scatter flash, never touches preloader/LK/modem or writes NVRAM/NVDATA.
- Original July 2018 firmware has **different** fingerprint and SELinux hashes from our tested modernized phone. This is why the install process backs up the original vendor and restores the **complete** known-working vendor rather than blindly applying patches to incompatible binaries.
- The Golden vendor is hardware-specific; the kit refuses unknown hardware/partition geometry. Its successful behavior on our S55 cannot prove every historical S55 board variant is identical.
- The Android 11 battery service reads real `batt_vol` and `batt_temp`. ThermalHAL exposes real BAT/CPU/GPU/SKIN temperatures under SELinux Enforcing. Native Battery Saver is set at 25%; there is no battery calibration spoofing or disabling of lithium cell protection.
- The fingerprint enumeration fix is built in, but the new owner must enroll a fingerprint, reboot, then prove that the same fingerprint unlocks again.
- **There is no guarantee of recovery after a genuine deep discharge or defective battery.** The phone's bootloader and hardware charge controller set the safety threshold independently of Android.
- We have thoroughly verified the *asset signatures, stock/GPT layout and current working S55*, but the combined single-command journey from a **different never-modified stock S55** is not yet end-to-end proven. The safeguards intentionally fail closed, and any exception should be documented rather than worked around by unconditional flashing.

Official upstream references: [ADB / Fastboot](https://developer.android.com/tools/releases/platform-tools), [Android bootloader unlock](https://source.android.com/docs/core/architecture/bootloader/locking_unlocking), [NikGapps A-only flash sequence](https://nikgapps.com/misc/2023/03/04/Flash-NikGapps.html).
