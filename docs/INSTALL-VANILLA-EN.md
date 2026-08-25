# Doogee S55 — crDroid Android 11 Vanilla

[← README](../README.md) · [GApps EN](INSTALL-GAPPS-EN.md) · [Fingerprint](FINGERPRINT-FIX.md) · [Troubleshooting](TROUBLESHOOTING.md)

## Result

This procedure installs **crDroid 7.16 / Android 11 without Google Apps** on the Doogee S55 using the `arm64-avZ` image.

**Major difference from the GApps guide:** the Vanilla image fits the original `/system` partition. **No GPT repartitioning is required.**

## 0. Required files

- `files/twrp-3.1.1-doogee-s55.img`
- `files/Disable_Dm-Verity_ForceEncrypt.zip`
- `crdrom-v316-220330-arm64-avZ.img.xz`
- https://sourceforge.net/projects/treblerom/files/crDRom11/2022.03.30/crdrom-v316-220330-arm64-avZ.img.xz/download

```bash
export ADB="${ADB:-adb}"
export FB="${FB:-fastboot}"
```

## 1. Unlock and install TWRP

On stock Android enable OEM unlocking + USB debugging, then:

```bash
$ADB reboot bootloader
$FB flashing unlock
$FB flash recovery files/twrp-3.1.1-doogee-s55.img
$FB reboot recovery
```

## 2. Disable dm-verity / forceencrypt

TWRP → Advanced → ADB Sideload:

```bash
$ADB sideload files/Disable_Dm-Verity_ForceEncrypt.zip
```

## 3. Decompress and flash the Vanilla GSI

```bash
unxz crdrom-v316-220330-arm64-avZ.img.xz
$ADB reboot bootloader
$FB flash system crdrom-v316-220330-arm64-avZ.img
$FB reboot recovery
```

> Do not substitute `agZ` in this command on stock geometry: the GApps build is too large and has its own installation guide.

## 4. Fix FDE/fstab

In TWRP:

```bash
./scripts/decrypt-fstab.sh
```

The script preserves/restores the fstab SELinux context. An `unlabeled` fstab can kill `nvram_daemon` and later stall boot while waiting for `media.audio_policy`.

## 5. Fix the MicroArray fingerprint HAL

Before the first Android boot:

```bash
./scripts/fix-microarray-fingerprint.sh
```

This prevents the S55-specific failure where enrollment works during first setup and fingerprint stops working after the first reboot.

## 6. Format Data

TWRP → **Wipe → Format Data → yes**.

The canonical flow does not use `fastboot -w`; TWRP formats `/data` directly on the userdata partition.

## 7. Boot and verify

```bash
$ADB reboot system
$ADB wait-for-device
$ADB shell getprop sys.boot_completed
```

After setup:

1. verify storage;
2. enroll a fingerprint;
3. reboot;
4. verify fingerprint unlock still works.

For F-Droid/Aurora/microG, install your preferred solution afterwards; the Vanilla guide does not force a Google framework.
