# Doogee S55 Second Life — Technical notes

[← README](../README.md) · [Fingerprint fix](FINGERPRINT-FIX.md)

These notes hold the low-level facts used by the user-facing guides so the installation docs can stay readable.

## 1. Validated device profile

- Model: **Doogee S55** (not S55 Lite)
- SoC family: MediaTek MT6750/MT6750T
- ISA/userspace: ARM64
- Stock OS: Android 8.0 Oreo
- Treble: enabled
- Vendor VNDK: 26
- Layout: **A-only, non-SAR**
- Physical `/system` and `/vendor`
- Recovery used: TWRP 3.1.1-0
- Android 11 target: crDRom/crDroid 7.16, 2022-03-30

Android 11 is described in this project as the **maximum validated target**, not as a universal theorem that no custom Android 12+ experiment could ever exist.

## 2. Stock and GApps GPT geometry

Relevant stock GPT sectors:

| Partition | Start | End | Approx. size |
|---|---:|---:|---:|
| p27 vendor | 491520 | 1540095 | 512 MiB |
| p28 system | **1540096** | **7389183** | 2856 MiB |
| p29 cache | **7389184** | **8273919** | 432 MiB |
| p30 userdata | **8273920** | unchanged | ~53.6 GiB partition |

Validated GApps geometry:

| Partition | Start | End | Approx. size |
|---|---:|---:|---:|
| p27 vendor | 491520 | 1540095 | 512 MiB |
| p28 system | **1540096** | **7913471** | stock + 256 MiB |
| p29 cache | **7913472** | **8273919** | 176 MiB |
| p30 userdata | **8273920** | unchanged | unchanged |

Only the system/cache boundary moves. The start of userdata is preserved.

The validated decompressed GApps image was larger than the stock p28 capacity. After repartition, `/system` was large enough for the image and `resize2fs` could expand its ext filesystem to the new block device size.

`repartition-gapps.sh` deliberately refuses geometry that is neither the exact known stock layout nor the exact already-patched layout.

## 3. Why `/data` needed an Oreo vendor fix

The vendor comes from Android 8 and expects legacy Full-Disk Encryption behavior. Android 11 no longer matches those assumptions. Leaving the old `forceencrypt` / `forcefdeorfbe` / `fileencryption` entries can cause `/data` setup to fail and bounce the device back into recovery/factory reset behavior.

The canonical script is [`scripts/decrypt-fstab.sh`](../scripts/decrypt-fstab.sh).

### SELinux/NVRAM gotcha

An early version of the procedure used `sed -i` directly on `/vendor/etc/fstab.mt6755`. On this old recovery/filesystem combination that can replace the inode and lose the SELinux xattr.

A wrongly labelled/unlabelled vendor fstab can prevent `nvram_daemon` from reading its configuration. MediaTek audio then waits for NVRAM readiness; `media.audio_policy` never arrives and Android appears to hang indefinitely during boot.

The current script writes the transformed content back into the existing file and runs `restorecon` (with a `chcon` fallback).

## 4. Fingerprint root cause

### Framework observation

Android 11 logs showed authentication/enrollment blocked behind an internal cleanup client. The sensor remained alive and the fingerprint HAL process did not die.

The framework's `InternalEnumerateClient.onEnumerationResult(identifier, remaining)` only completes when `remaining == 0`. Until that terminal result arrives, new authentication/enrollment clients can stay pending.

### Generic PHH workaround test

`persist.sys.phh.fingerprint.nocleanup=true` was set persistently before `system_server` start and verified active. The failure remained unchanged.

Disassembly of the device's Android 11 `services.jar` showed `mNocleanup` is checked inside `doTemplateCleanup()`; it changes whether unknown templates are removed from software state, not whether HAL enumeration must complete.

### Vendor call chain

Active service:

```text
android.hardware.biometrics.fingerprint@2.1-service
```

Relevant vendor files:

```text
/vendor/lib64/hw/microarray.fingerprint.default.so
/vendor/lib64/libfprint-x64.so
```

`microarray.fingerprint.default.so` imports `bio_enumerate`. The implementation lives in `libfprint-x64.so`.

The tested `bio_enumerate()` eventually executes an `enumerate_notify` call. At ELF virtual/file offset `0x4ecc`, the original code copies a non-zero value into the argument used as the enumeration `remaining` value:

```text
Original instruction: mov w2,w1
Bytes:                e2 03 01 2a
```

The validated fix is:

```text
Patched instruction:  mov w2,#0
Bytes:                02 00 80 52
```

Known hashes:

```text
Original SHA256: e76c3884ab9935ac60c38370210747465b76fadda5acd3470e199f7c7070af06
Patched  SHA256: 3d89603ed3025bdc14e65d6269024c52920808c747aeb2d79417741d7cc7f9f6
```

Only four bytes differ, at file offsets `0x4ecc` through `0x4ecf`.

### Why this is consistent with Android's API

AOSP defines `remaining_templates` as the number of **additional enumeration messages to expect**. A terminal enumeration callback therefore has to reach 0.

References:

- https://android.googlesource.com/platform/hardware/libhardware/+/f1ccec1/include/hardware/fingerprint.h
- https://android.googlesource.com/platform/hardware/interfaces/+/refs/heads/android16-release/biometrics/fingerprint/2.1/IBiometricsFingerprint.hal
- https://android.googlesource.com/platform/hardware/interfaces/+/oreo-dr1-release/biometrics/fingerprint/2.1/default/BiometricsFingerprint.cpp

## 5. Fingerprint patch safety model

[`fix-microarray-fingerprint.sh`](../scripts/fix-microarray-fingerprint.sh) does not perform a blind byte patch:

1. check current device SHA256;
2. if already patched: exit successfully;
3. if not the exact known original: abort;
4. pull and hash a local backup;
5. verify original bytes at `0x4ecc`;
6. patch exactly four bytes locally;
7. verify the expected full patched SHA256;
8. push to TWRP `/tmp`;
9. write into the existing vendor file using `cat > target`;
10. verify device SHA256 and SELinux metadata.

This prevents the S55 fix from being accidentally applied to a different vendor build.

## 6. Userdata filesystem

The physical device has 64 GB eMMC, but the userdata partition itself is approximately 53.6 GiB after the other fixed partitions.

An old flow using `fastboot -w` could create a filesystem much smaller than the actual p30 partition. TWRP 3.1.1 also has an old e2fsprogs that can fail to resize newer ext4 features such as `quota`.

The current install guides therefore use **TWRP Format Data** as the normal path. For recovery, [`format-userdata-full.sh`](../scripts/format-userdata-full.sh) reformats the whole p30 device after explicit confirmation.

## 7. Display resolution correction

The S55 display is **1440×720**, not 960×480. Optional boot animation tooling should therefore default to `720 1440` for portrait assets.
