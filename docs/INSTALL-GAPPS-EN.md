> **Historical crDroid installation procedure, not the current LineageOS path.** The recommended October 2026 method is the [single-command LineageOS 18.1 + GApps kit](../installer/README.md).

# Doogee S55 — crDroid Android 11 with GApps

[← README](../README.md) · [Vanilla EN](INSTALL-VANILLA-EN.md) · [Fingerprint](FINGERPRINT-FIX.md) · [Troubleshooting](TROUBLESHOOTING.md)

## Result

This procedure upgrades a **stock Android 8 Doogee S55** to **crDroid 7.16 / Android 11 with Google Apps** (`arm64-agZ`). It includes the validated S55-specific fixes:

- add 256 MiB to `/system` so the GApps image fits;
- keep the start of `userdata` unchanged;
- fix Oreo FDE/fstab compatibility;
- preserve SELinux/NVRAM behavior;
- format `/data` across the real userdata partition;
- patch the MicroArray fingerprint HAL before the first Android boot.

> **S55 only. Not S55 Lite.** This path modifies the GPT.

## 0. Required files

Place these third-party files locally under `files/` (they are intentionally not tracked by this repository; see [`files/README.md`](../files/README.md)):

- `files/twrp-3.1.1-doogee-s55.img`
- `files/Disable_Dm-Verity_ForceEncrypt.zip`

Download the GSI:

- `crdrom-v316-220330-arm64-agZ.img.xz`
- https://sourceforge.net/projects/treblerom/files/crDRom11/2022.03.30/crdrom-v316-220330-arm64-agZ.img.xz/download

Recommended PC tools: **Google Platform Tools** (`adb`, `fastboot`), `xz`/`unxz`, `sha256sum`.

```bash
export ADB="${ADB:-adb}"
export FB="${FB:-fastboot}"
```

## 1. Unlock the bootloader

On stock Android: Developer options → enable **OEM unlocking** and **USB debugging**.

```bash
$ADB reboot bootloader
$FB flashing unlock
```

Confirm on the phone. Unlocking wipes data.

## 2. Install TWRP

```bash
$FB flash recovery files/twrp-3.1.1-doogee-s55.img
$FB reboot recovery
```

Wait for TWRP.

## 3. Disable dm-verity / forceencrypt

TWRP → Advanced → ADB Sideload, then:

```bash
$ADB sideload files/Disable_Dm-Verity_ForceEncrypt.zip
```

Choose: disable dm-verity, disable forceencrypt, quota **no** if prompted.

## 4. Enlarge `/system` for the GApps image

The decompressed `agZ` image is larger than stock `/system`. The validated layout changes only the **system/cache boundary**; `userdata` still begins at sector `8273920`.

From the PC while the phone is in TWRP:

```bash
./scripts/repartition-gapps.sh
```

The script:

1. checks the exact S55 geometry;
2. backs up the GPT to `backups/`;
3. adds 256 MiB to `system`;
4. reduces `cache` from 432 to 176 MiB;
5. leaves `userdata` unchanged;
6. verifies the GPT;
7. reboots TWRP so the kernel rereads the partition table.

Do not continue if the script rejects the geometry.

### Rollback before flashing the GApps image

If you decide to stop **after repartitioning but before writing p28 or recreating p29**, you can restore the GPT backup created by `repartition-gapps.sh`:

```bash
BACKUP="backups/gpt/S55-gpt-before-gapps-YYYYMMDD-HHMMSS.bin"
$ADB push "$BACKUP" /tmp/s55-gpt-backup.bin
$ADB shell 'sgdisk --load-backup=/tmp/s55-gpt-backup.bin /dev/block/mmcblk0
sgdisk -v /dev/block/mmcblk0
sync'
$ADB reboot recovery
```

Replace the example filename with the backup actually printed by the script.

> The GPT backup restores the **partition table only**. If you already wrote the GApps image to p28 or recreated p29, restoring the GPT alone is not a stock restore; reflash the matching stock `system`/`cache` images or the full stock firmware as well.


## 5. Decompress and flash the GApps image

```bash
unxz crdrom-v316-220330-arm64-agZ.img.xz
IMG="$PWD/crdrom-v316-220330-arm64-agZ.img"
$ADB push "$IMG" /dev/block/mmcblk0p28
```

The direct push to the block device is intentional and is the validated method after repartitioning.

Expand the image filesystem to the new partition size and recreate cache:

```bash
$ADB shell 'e2fsck -fy /dev/block/mmcblk0p28
rc=$?
case "$rc" in
  0|1|2) ;;
  *) echo "e2fsck failed with code $rc" >&2; exit "$rc" ;;
esac
resize2fs /dev/block/mmcblk0p28
mke2fs -t ext4 -L cache /dev/block/mmcblk0p29
sync'
```

## 6. Fix the Oreo fstab without breaking SELinux

Still in TWRP:

```bash
./scripts/decrypt-fstab.sh
```

The script writes through a temporary file and `cat > original` to preserve the inode, then runs `restorecon`. Do not replace this with an unmanaged `sed -i` edit.

## 7. Apply the MicroArray fingerprint fix

Do this **before the first Android boot**:

```bash
./scripts/fix-microarray-fingerprint.sh
```

The script only patches the exact validated library:

- original SHA256 `e76c3884ab9935ac60c38370210747465b76fadda5acd3470e199f7c7070af06`
- patched SHA256 `3d89603ed3025bdc14e65d6269024c52920808c747aeb2d79417741d7cc7f9f6`

It backs up the original and refuses unknown hashes.

## 8. Format Data in TWRP

TWRP → **Wipe → Format Data → yes**.

This is the canonical path in this repository. It avoids the historical `fastboot -w` trap that could create a tiny userdata filesystem.

If `/data` is still undersized, use the [userdata recovery procedure](TROUBLESHOOTING.md#internal-storage-is-too-small).

## 9. First boot

TWRP → Reboot → System, or:

```bash
$ADB reboot system
```

The first boot can take several minutes.

```bash
$ADB wait-for-device
$ADB shell getprop sys.boot_completed
```

The final value should be `1`.

## 10. Post-install verification

- Complete Android / Google setup.
- Internal storage is consistent with the ~53 GiB userdata partition.
- Fingerprint enrollment works.
- **Reboot once**, then verify fingerprint unlock still works.

That reboot matters: without the vendor fix, this is where the legacy MicroArray HAL failure appears.
