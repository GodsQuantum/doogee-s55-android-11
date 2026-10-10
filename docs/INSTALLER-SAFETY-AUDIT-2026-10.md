# DOOGEE S55 — LineageOS 18.1 offline installer audit (10 October 2026)

[English README](../README.md) · [Français](../README.fr.md) · [简体中文](../README.zh-CN.md) · [Installation](../installer/README.md)

## Scope and evidence standard

Target: **original DOOGEE S55**, MTK6750 family, A-only/non-system-as-root Android 8 factory firmware, exact *known factory* GPT sector layout. **S55 Lite is excluded.**

**Hardware evidence:** one working S55 runs LineageOS 18.1 / Android 11, NikGapps Core, patched MicroArray fingerprint library, corrected voltage/temperature and thermal HAL under SELinux Enforcing; see the device migration and thermal reports. Its own conversion used controlled recovery operations, **not** the newly consolidated factory-to-ROM installer. The patched vendor and June 2020 boot are from that reference handset. No independent second factory S55 has passed the complete unattended installation. USB authorization, bootloader unlocking, physical TWRP key actions and fingerprint enrollment remain interactive.

**What offline tests prove:** verified copy/archive checksums, lint/static tests, and fake ADB/Fastboot tests for plan, check, read-only Android audit, wrong model, already upgraded handset and edited manifest. The fakes cannot demonstrate actual TWRP memory capacity, bootloader compatibility, successful full stock conversion, Play Store sign-in, real sensor or radio functionality on a second handset, or recovery after a lithium-ion deep discharge.

## Sequence for the private, assembled kit

1. Verify SHA256 manifest (including INSTALL.sh and instructions), boot/vendor image identities, source files and available tools. The manifest is an *integrity checksum*, not a signed independent upstream attestation.
2. Confirm explicit destructive consent and adequate battery; identify **one** S55 on Android 8, and in fastboot require the observed device product identifier. Unlocking erases all user photos/app data **before** the new program can back up system partitions. Users must copy personal files out first.
3. Enter exact S55 TWRP 3.1.1, verify root/recovery utilities, available recovery RAM, exact GPT geometry and GPT integrity. All progress checkpoints are bound to a hash of the TWRP serial within a private state directory.
4. Before changing partition boundaries, save original GPT plus complete system, cache, boot, recovery, vendor, NVRAM, NVDATA, protect1, protect2. Compare decoded compressed backups' size and raw SHA256 against a second direct read of the original partition; store private checksums. **Never publish** original radio calibration, serials or user data.
5. Grow p28 /system by 256 MiB by moving only the p28/p29 boundary; p30 /userdata stays at sector 8273920. Verify new GPT and recovery reread; reformat p29 cache, which otherwise retains a filesystem from its obsolete start sector.
6. Write exact non-SAR Android 11 /system, verify on-device hash of source-size bytes, fsck and grow ext4. Transfer the reference patched S55 vendor (preserving the separate *original* vendor backup) and verify the whole raw 512 MiB readback and critical per-file hashes. **Not a generic vendor for every MTK phone or board revision.**
7. Flash exact Android 11 NikGapps Core from TWRP **/tmp RAM**, then fully format p30 /userdata and create correctly owned/labeled Android 11 vendor_ce and vendor_de directories. This matches NikGapps' documented A-only **ROM → GApps → /data wipe → boot** order; using TWRP RAM rather than the freshly formatted /data staging from the reference phone remains **an unproved integration path on stock hardware**.
8. Apply hash-pinned LineageOS healthd voltage/temperature repairs, verify already-patched vendor thermal policy and fingerprint library, flash only the exact known-good boot with raw readback, boot, and verify Google packages, SELinux and physical thermal telemetry. Final fingerprint persistence needs a human enrollment/reboot/unlock test.

## Interrupted installation and safe resumption

- Every completed checkpoint is retested against observed GPT, ext4 filesystem state, target boot/vendor SHA, healthd hash or actual Google files before skipping. A filename alone is not trusted.
- Backups remain in private-install-state/backup; earlier factory system/cache sizes are compared against the *original* geometry, not the new layout.
- An interrupted NikGapps stage leaves gapps.inflight and **stops** on retry: its effects might be partial. Diagnose recovery logs and repair the system/Google files using an expert-controlled procedure; no blind second flash.
- Failed or incomplete backup, unknown board, non-root TWRP, low voltage, insufficient /tmp RAM, corrupt image, mismatching partitions or altered marker stop the run. The installer does not silently try a different firmware, global Permissive SELinux, scatter "Format All", automatic IMEI restore or battery protection bypass.
- If the installer shell process exits **after Android 11 boots**, use the explicit **read-only --verify** mode, not --install again.
- Bootloader/TWRP and vendor compatibility differ between production batches; the kit must stop on unknown geometry even if a user wants it to "just work."

## Restoration boundary

The host-only --recovery-check mode revalidates all nine original partition archives and the saved GPT without any phone connection. The original GPT and partition backups are necessary for manual recovery, **not** a one-click stock-firmware guarantee. Once the system/cache boundary has moved, the old p29 cache image cannot be written onto the smaller new p29; an expert must first validate and restore factory GPT geometry, reboot recovery to reread the table, then restore the correspondingly sized system/cache/vendor/boot images and verify raw hashes. Keep TWRP functional until any remaining restoration operations finish. Original NVRAM/NVDATA/protect copies are for safekeeping; **never overwrite them indiscriminately**. Unlocking and the final /data format irreversibly erase the prior phone user files; no backup of userdata is produced by this installer.

The project includes a specific guarded prior-ROM rollback from the reference phone, not a universally validated stock S55 recovery environment. Any stock restoration, data-format differences and Android 8 encryption initialization require case-by-case validation.

## Public/private separation

**Public:** MIT-licensed helper scripts, installer logic, CI/tests, README EN/FR/zh-CN, SVG project identity and docs.

**Private:** local-kit, third-party system/Google ZIP, S55 boot, complete vendor image, donor proprietary ELF files, patch source binaries, device partitions, radio calibration, logcat/account/IMEI content. Do not upload kit to GitHub or attach it to a public release. No factory radio content is intentionally bundled.

## October 2026 references and limitations

- [Google: Generic System Image requirements](https://developer.android.com/topic/generic-system-image): official GSI prerequisites target newer, compliant devices; this legacy Oreo-vendor setup is a device-specific exception, not a universal official installation.
- [AOSP: GSI / older Oreo VNDK](https://source.android.com/docs/core/tests/vts/gsi) and [system-as-root architecture](https://source.android.com/docs/core/architecture/partitions/system-as-root): modern Android 12+ GSI cannot be assumed compatible with the non-SAR boot chain.
- [AOSP: bootloader unlocking](https://source.android.com/docs/core/architecture/bootloader/locking_unlocking): unlock includes physical confirmation and erases personal data.
- [Android Platform Tools release notes](https://developer.android.com/tools/releases/platform-tools): latest checked July 2026 v37.0.1; compatible host ADB/Fastboot required.
- [NikGapps: A-only flash order](https://nikgapps.com/misc/2023/03/04/Flash-NikGapps.html) and [NikGapps FAQ](https://nikgapps.com/faqs): ROM before GApps, then wipe userdata, and do not overlay an existing GApps stack.
- [NikGapps Core Android 11, February 2026](https://sourceforge.net/projects/nikgapps/files/Releases/Android-11/04-Feb-2026/): locally downloaded and SHA256-pinned, source signature not independently established.
- [Unofficial DOOGEE S55 bootloader guide (September 2018)](https://www.androidweblog.com/root-doogee-s55-install-twrp-recovery/): documents the **oem unlock-go** command. Another unofficial S55 TWRP guide documents **flashing unlock / oem unlock**. Both are low-confidence community recipes, not proof of behavior on every firmware. The guided installer tries the standard command first and offers unlock-go **only after another explicit wipe consent**; it verifies the unlock state independently or stops.
- [Team Win recovery support](https://twrp.me/Devices/): no official S55-specific upstream support is presumed; the actual working S55 TWRP binary and checksum are retained privately.
- [4PDA S55 community firmware discussion](https://4pda.to/forum/index.php?showtopic=915045&st=100): older 2018/2019 factory builds and device-specific recovery complications; forum posts are not verified universal installation tests.
- No reliable independently reproducible, current October 2026 XDA/Reddit report demonstrating complete installation of this exact patched kit on a second untouched S55 was established. Lack of such a report is not proof of incompatibility.

**Release decision:** code/kit may pass isolated integrity and negative-path tests, but **do not describe an untested virgin-S55 ROM migration or deep-discharge recovery as fully validated**.
