# DOOGEE S55 → LineageOS 18.1 + Google Play, one command

**Target:** standard DOOGEE **S55**, original Android 8.0 firmware, MediaTek MT6750 family, eMMC GPT matching the documented stock S55 layout. **Not S55 Lite.** Host: Linux, USB data cable, current official Android Platform Tools (ADB / fastboot), bash, Python 3, xz, zstd, sha256sum and e2fsck/resize2fs/sgdisk **in the bundled S55 TWRP recovery**.

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

An already running Android 11 S55 can be audited without flashing or wiping with ./INSTALL.sh --verify. This read-only mode checks Android boot completion, SELinux, Google services, and battery/thermal telemetry. On our reference handset, the enrolled fingerprint **successfully unlocked the phone after reboot (physically confirmed by the owner, 10 October 2026)**. Another target S55 still requires its own enrollment and reboot-unlock test. A checkpoint bound to a recovery identity is rechecked against actual partitions before it can be skipped; ambiguous interrupted GApps installations stop for manual diagnosis.

Install order: flash ROM; stage and install NikGapps Core 11 from TWRP /tmp RAM; format userdata; prepare vendor CE/DE directories; patch healthd and install verified boot. This matches the upstream A-only ROM/GApps/data-wipe sequence. Recovery RAM must have at least 180 MiB free. This RAM staging flow remains unvalidated on a second untouched stock S55.

Flash progress uses pv when present, or the bundled pure-Python progress indicator when pv is unavailable. No global software installation is required for progress.

After a partial run, verify all **original** partition backups and GPT checksum without touching a phone by using ./INSTALL.sh --recovery-check. It intentionally does not flash or restore stock; interrupted recovery still requires expert supervision.

For a non-destructive look at the installation plan:

```bash
./INSTALL.sh --plan
./INSTALL.sh --check
./INSTALL.sh --verify
./INSTALL.sh --recovery-check
```

**Human interaction cannot be removed from OEM unlocking, physical key combinations, USB authorization and the initial fingerprint enrollment.** After erasing userdata, Android normally disables USB debugging again: complete the first-run setup, re-enable Developer Options → USB debugging, and authorize the same computer when the installer requests it. The script then verifies Android 11, Google packages, real thermal sensors and the 25% battery-saver setting. If ADB is still unavailable, the script may record only a user-confirmed visible boot, explicitly marked **unverified**; it will never silently report completed automated tests. If an image, checksum or GPT geometry does not match, installation stops. No universal promise is made for unknown board revisions.

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
- **Reference S55 post-reboot fingerprint unlocking succeeded (owner-confirmed, 10 October 2026).** The kit includes the SHA256-pinned MicroArray enumerator fix in its vendor image and separately enables persistent PHH cleanup retention after Android boots. Every newly installed S55 still needs physical finger enrollment, reboot, PIN if requested, and unlock with that same finger.
- **There is no guarantee of recovery after a genuine deep discharge or defective battery.** The phone's bootloader and hardware charge controller set the safety threshold independently of Android.
- We have thoroughly verified the *asset signatures, stock/GPT layout and current working S55*, but the combined single-command journey from a **different never-modified stock S55** is not yet end-to-end proven. The safeguards intentionally fail closed, and any exception should be documented rather than worked around by unconditional flashing.

Official upstream references: [ADB / Fastboot](https://developer.android.com/tools/releases/platform-tools), [Android bootloader unlock](https://source.android.com/docs/core/architecture/bootloader/locking_unlocking), [NikGapps A-only flash sequence](https://nikgapps.com/misc/2023/03/04/Flash-NikGapps.html).


## Fingerprint retention and real-world acceptance test

On the final S55 LineageOS 18.1 GSI, the installer activates PHH fingerprint cleanup retention only after verifying the known-good MicroArray patched library. The helper scripts/enable-microarray-persistence.sh can be run separately (--check read-only, --apply guarded and reversible). Temporary root ADB, where available, is disabled immediately after the property update. Fingerprint templates are neither copied nor erased.

Our reference S55 passed a physical post-reboot unlock test, confirmed by its owner on 10 October 2026. On each newly converted S55, enroll a finger, reboot and complete any required first PIN unlock; then lock the phone again and unlock using that same finger. Repeat across later reboots as a recommended durability check. The --verify audit confirms the configuration is present; it cannot confirm biometric recognition. If the property cannot be set on an unknown stock build, stop instead of falsely claiming a verified fingerprint fix.


## Read-only battery and radio health audit

The local offline kit now includes scripts/diagnose-battery.sh. With an already booted and authorized Android S55 attached, run:

    bash scripts/diagnose-battery.sh

This reports Android battery telemetry, MediaTek batt_vol and batt_temp where permissions permit, actual thermal HAL readings, Android native Battery Saver settings, RIL service status and radio process crash/death counts, without requiring root or changing the phone. Logs and identifiers remain private. It is a diagnostic, not a battery calibration or a proof that recovery at 0% works.

The validated reference S55 on 11 October 2026 reported 100%, around 4.3 V, roughly 24 C, a working fingerprint, 25% Battery Saver and enabled Doze. However, on that boot ril-proxy had crashed and stopped, and repeated Android com.android.phone deaths were recorded even with no SIM installed. Do not force a radio restart loop, turn off mobile emergency calling permanently, disable undervoltage cutoffs or blindly replace an old MTK vendor binary. Test unplugged standby separately and use a known-good 5 V / 2 A wall charger for a moderate-charge powered-off charging test; never deliberately deep-discharge a suspected aged battery.


## S55 radio crash safety (11 October 2026)

The PHH property persist.sys.phh.restart_ril=true was **experimentally tested and rejected** on the reference S55: it recovered a stopped RIL process, but led to repeated reboot/preloader transitions when Android was restarted. The original false value was restored and the phone booted. The read-only --verify check now fails if the unsafe property is enabled.

A precisely guarded offline candidate for the null callback in librilproxy.so exists in scripts/patch-rilproxy-networkinfo.py. It is NOT automatically used by this installer or bundled in the proprietary golden vendor image. The RIL guard was permanently installed on the reference S55 vendor partition after two reversible trials, using a one-byte change to the exact SHA256-pinned OEM binary on 11 October 2026. Two Android boots retained the corrected SHA256, with the radio daemon, two HIDL slots, fingerprint and SELinux Enforcing healthy. No SIM is fitted: calls/SMS/data and long-run stability remain unverified. The bundled vendor image remains OEM stock and will revert this patch if reflashed. Read-only INSTALL.sh --verify now reports precisely whether the radio patch is present. The live-trial harness remains a temporary-test-only tool, not a production installer. Never blindly flash an unknown OEM revision. See docs/RADIO-RILPROXY-2026-10-11.md.
