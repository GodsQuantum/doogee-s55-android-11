> Historical crDroid reference; **not the current recommended installation**. For LineageOS 18.1 use the [single-command kit](../installer/README.md).

# Doogee S55 — Android 11 Upgrade Guide (crDroid GSI)

**A tested upgrade path for the Doogee S55: stock Android 8 Oreo → crDroid 7.16 / Android 11, with either Vanilla or Google Apps, plus the device-specific fixes needed to make the old MediaTek vendor behave correctly.**

> 🇫🇷 Ce dépôt transforme un **Doogee S55** d'origine sous Android 8 en un appareil réellement utilisable sous **Android 11 / crDroid 7.16**, avec un chemin **Vanilla** ou **GApps**, et documente les correctifs nécessaires pour le stockage, le chiffrement, SELinux/NVRAM et le capteur d'empreintes MicroArray.

> **Scope:** Doogee **S55 only**. Not S55 Lite. The tested device is ARM64, Treble **A-only**, non-SAR, with an Oreo vendor / VNDK 26.

---

## Before → After

| | Stock Doogee S55 | With this project |
|---|---|---|
| OS | Android 8.0 Oreo / DoogeeOS 2.0 | **crDroid 7.16 / Android 11** |
| SoC | MediaTek MT6750 family / MT6750T, ARM64 | Same hardware, newer userspace |
| RAM / storage | 4 GB / 64 GB eMMC | Same hardware, **full userdata restored** |
| Display | 5.5" IPS, 1440×720 | Same panel |
| Battery | 5500 mAh | Same battery |
| Treble layout | A-only, non-SAR | Android 11 GSI A-only |
| Google services | Stock Google stack | **Choose Vanilla or GApps** |
| Recovery | Stock recovery | **TWRP 3.1.1** |
| Root | Stock | `Z` build: PHH/crDroid dynamic root available |
| SELinux | Stock | **Enforcing**, with vendor labels preserved |
| Fingerprint | Legacy MicroArray HAL | **Works after reboot with the HAL fix in this repo** |
| Maximum target here | Android 8 stock | **Android 11 — maximum validated by this project** |

Hardware baseline references: [Notebookcheck](https://www.notebookcheck.net/Doogee-S55-Smartphone-Review.323406.0.html) and [GSMchoice](https://www.gsmchoice.com/en/catalogue/doogee/s55/).

---

## What this repository actually fixes

Flashing a generic Android 11 image is not enough on this phone. The S55 combines an old MediaTek Oreo vendor with a newer Android framework, and several incompatibilities appear in real use.

This project documents and fixes the ones validated on the S55:

- **Android 8 → Android 11** on the A-only S55.
- **Vanilla and GApps paths** using the correct ARM64 A-only crDRom images.
- **GApps system image too large for the stock `/system` partition**: safe GPT backup + a tested +256 MiB `/system` layout.
- **Oreo FDE vs Android 11 `/data`**: vendor fstab fix without losing SELinux labels.
- **SELinux/NVRAM boot hang** after careless fstab edits: preserve/restore the correct file context.
- **Undersized userdata filesystem**: format `/data` across the actual userdata partition instead of living with a few hundred MB / a few GB.
- **Fingerprint works during first setup, then dies after reboot**: a verified MicroArray HAL bug is patched at the vendor binary level.

The goal is not to hide these problems behind one-off commands. The guides explain what is changed, why, and how to verify it.

---

## Choose your path

**October 2026 update:** LineageOS 18.1 Android 11 is now installed and running on the actual S55. Battery voltage, real temperature and thermal HAL readings were repaired and verified with SELinux Enforcing. **Do not directly flash an Android 13+ SAR GSI onto this non-SAR S55.** Older firmware/KPOC behavior and physical deep-discharge reliability cannot be guaranteed by these Android-level repairs.

- **[LineageOS 18.1 with NikGapps Core installed on the real S55](LINEAGE18-MIGRATION-ROOT-CAUSE-2026-10.md):** validated image write/readback, userdata compatibility fix, and two Android boot-complete tests. Run the guarded [vendor CE/DE directory preparation](../scripts/prepare-lineage18-userdata-s55.sh) after future full userdata wipes.
- **[Android 13: hardware compatibility gate and LineageOS 18.1 fallback](ANDROID13-FEASIBILITY-DECISION-2026-10.md):** exact local LineageOS 20 image fails the stock non-SAR/Oreo vendor gate; a boot/vendor port is needed before any meaningful on-device test.
- **[Guarded LineageOS 18.1 flashing/rollback](../scripts/flash-lineage18-s55.sh)** and **[Android 11 NikGapps Core installation](../scripts/install-nikgapps-core11-s55.sh)**: exact private backups, partition/hash preflight, optional verified restoration; no radio/bootloader changes.
- 🇫🇷 **[ROMs Android 11 à 17, GApps, Linux et tests réels — version française](ROM-OPTIONS-FR.md)**
- 🇬🇧 **[Android 11–17 ROM compatibility, Google apps, Linux alternatives and test matrix](ROM-OPTIONS-EN.md)**
- **[Read-only local image auditor](../scripts/audit-rom-candidates.py):** inspect Android version, SAR/non-SAR layout, security patch and /system partition fit without flashing or mounting images.
- **[Battery and power-off charging investigation](RESEARCH-DEEP-DISCHARGE-2026-10.md):** charging from a wall charger recovered to 20% according to the owner; the earlier PC USB/deep-discharge failures are not proof of an irreparably dead battery.
- **[Battery, wakelocks, thermal HAL and read-only recovery audit — October 2026](BATTERY-POWER-AUDIT-2026-10.md):** verified native power settings and historical standby data; private modem/vendor backups.
- **[Verified Android 11 ↔ Oreo vendor compatibility fixes](ROOT-CAUSE-HEALTHD-VENDOR-2026-10.md):** repaired actual battery voltage readings, restored two missing stock vendor libraries and corrected legacy sensor ELF logging dependencies, with guarded rollback scripts.
- **[Battery temperature, thermal HAL and power optimizations — validated on S55](BATTERY-THERMAL-LINEAGE18-2026-10.md):** actual battery temperature and CPU/GPU/skin HAL values restored under SELinux Enforcing; native battery saver at 25%, fully reversible patches. Historical investigation: [SELinux thermal root cause](THERMAL-SELINUX-INVESTIGATION-2026-10.md).

### 🇫🇷 Français

| I want… | Guide |
|---|---|
| Android 11 **avec Play Store / Google Apps** | **[Installation GApps FR](INSTALL-GAPPS-FR.md)** |
| Android 11 **sans Google** | **[Installation Vanilla FR](INSTALL-VANILLA-FR.md)** |
| Corriger uniquement l'empreinte | **[Correctif MicroArray fingerprint](FINGERPRINT-FIX.md#français)** |
| Résoudre un problème | **[Dépannage](TROUBLESHOOTING.md#français)** |
| Batterie vide, bootloop ou recharge hors Android | **[Diagnostic batterie et charge](BATTERY-CHARGING.md#français)** |
| Comprendre les modifications bas niveau | **[Notes techniques](TECHNICAL-NOTES.md)** |

### 🇬🇧 English

| I want… | Guide |
|---|---|
| Android 11 **with Play Store / Google Apps** | **[GApps installation EN](INSTALL-GAPPS-EN.md)** |
| Android 11 **without Google** | **[Vanilla installation EN](INSTALL-VANILLA-EN.md)** |
| Fix only the fingerprint issue | **[MicroArray fingerprint fix](FINGERPRINT-FIX.md#english)** |
| Diagnose a problem | **[Troubleshooting](TROUBLESHOOTING.md#english)** |
| Battery drain, deep discharge, offline charge | **[Battery & charging diagnostics](BATTERY-CHARGING.md#english)** |
| Understand the low-level changes | **[Technical notes](TECHNICAL-NOTES.md)** |

---

## Important: the fingerprint problem is real, reproducible, and fixed here

A common GSI problem on old devices is that the fingerprint framework and a legacy vendor HAL disagree about enumeration/cleanup. PHH/Treble documentation even exposes `persist.sys.phh.fingerprint.nocleanup` as a generic workaround for some devices.

On this S55, that generic workaround **does not solve the failure**. The exact S55 failure was traced further:

1. enrollment works during the first Android 11 setup;
2. after a reboot, the sensor still reacts as a navigation device, but authentication and new enrollment are blocked;
3. Android remains stuck in `InternalEnumerateClient` cleanup;
4. the S55 MicroArray library `/vendor/lib64/libfprint-x64.so` sends an invalid terminal enumeration state;
5. Android expects `remaining_templates` to reach **0**; this legacy library can leave it non-zero;
6. changing one ARM64 instruction in the **known tested binary** restores normal fingerprint unlock/enrollment after reboot.

The repository includes a guarded, idempotent script that patches **only the exact known vendor binary hash**, makes a backup first, preserves the file inode/SELinux context, verifies the patched hash, and refuses unknown builds.

→ **[Read the fingerprint fix and root-cause analysis](FINGERPRINT-FIX.md)**
→ **[`scripts/fix-microarray-fingerprint.sh`](../scripts/fix-microarray-fingerprint.sh)**

Upstream behavior references:

- [Android fingerprint HAL contract: `remaining_templates`](https://android.googlesource.com/platform/hardware/libhardware/+/f1ccec1/include/hardware/fingerprint.h)
- [Android 8-era HIDL fingerprint 2.1 legacy wrapper](https://android.googlesource.com/platform/hardware/interfaces/+/0dc66a2c6/biometrics/fingerprint/2.1/default/)
- [PHH/Treble common fingerprint workaround](https://github.com/TadiT7/treble_experimentations_wiki/blob/master/Common-Issues-and-fixes.md)

---

## Validated ROM images

The tested release is **crDRom 7.16 / Android 11, 2022-03-30** by eremitein:

- Vanilla: `crdrom-v316-220330-arm64-avZ.img.xz`
- GApps: `crdrom-v316-220330-arm64-agZ.img.xz`

SourceForge folder:
https://sourceforge.net/projects/treblerom/files/crDRom11/2022.03.30/

Naming:

- `arm64` = 64-bit ARM userspace
- `a` = A-only layout (**required for this S55**)
- `v` = vanilla
- `g` = Google Apps
- `Z` = dynamic root variant

> **Critical:** the `agZ` GApps image does **not** fit the S55 stock `/system` partition. Do not treat it as a drop-in replacement for `avZ`. Use the dedicated GApps guide and its repartition step.

---

## Third-party artifacts

TWRP and `Disable_Dm-Verity_ForceEncrypt.zip` are intentionally **not redistributed or stored in Git**. Obtain them from sources you trust and place them locally under `files/` before following an installation guide. See [`files/README.md`](../files/README.md) and [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md).

---

## Repository map

```text
.
├── README.md
├── docs/
│   ├── INSTALL-GAPPS-FR.md
│   ├── INSTALL-GAPPS-EN.md
│   ├── INSTALL-VANILLA-FR.md
│   ├── INSTALL-VANILLA-EN.md
│   ├── FINGERPRINT-FIX.md
│   ├── TROUBLESHOOTING.md
│   └── TECHNICAL-NOTES.md
├── scripts/
│   ├── decrypt-fstab.sh
│   ├── repartition-gapps.sh
│   ├── fix-microarray-fingerprint.sh
│   ├── format-userdata-full.sh
│   ├── bootanim-replace.sh
│   └── make-bootanimation.sh
└── files/
    └── README.md   # third-party binaries are local-only / not tracked
```

---

## Safety and support boundary

- Unlocking and flashing erase data and can brick a phone if the wrong partition is modified.
- **Back up the GPT before the GApps repartition.** The provided script does this automatically and refuses unexpected geometry.
- The fingerprint patch is intentionally limited to one known `libfprint-x64.so` SHA256. An unknown hash means **stop, do not force the patch**.
- This Android 11 image is historical (2022-era). It is dramatically newer than the S55 stock Android 8 build, but it is **not a currently security-supported Android release in 2026**.
- This repository documents the **Doogee S55**, not the S55 Lite and not other MT6750 phones.

---

## Credits

- [phhusson](https://github.com/phhusson) / Project Treble GSI foundations
- [AndyYan](https://github.com/AndyCGYan)
- [eremitein / TrebleGSI](https://sourceforge.net/projects/treblerom/) — crDRom Android 11 images
- [Zackptg5](https://github.com/Zackptg5) — Disable_Dm-Verity_ForceEncrypt
- TWRP and the wider Treble community
