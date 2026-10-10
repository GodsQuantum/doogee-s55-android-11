> **Two procedures coexist.** Entries referring to agZ/crDroid are historical. For the currently maintained LineageOS 18.1 + GApps one-command kit and guarded stopping rules, see [installation audit](INSTALLER-SAFETY-AUDIT-2026-10.md).

# Doogee S55 — Troubleshooting / Dépannage

[← README](../README.md) · [Fingerprint](FINGERPRINT-FIX.md) · [Technical notes](TECHNICAL-NOTES.md)

## Français

| Symptôme | Cause probable | Action |
|---|---|---|
| `agZ` ne rentre pas dans `/system` | `/system` stock trop petit | Utiliser [le guide GApps](INSTALL-GAPPS-FR.md) + `repartition-gapps.sh` |
| Boot vers recovery / factory reset | `/data` encore forcé en FDE | `decrypt-fstab.sh`, puis TWRP Format Data |
| Boot animation infinie + attente `media.audio_policy` | fstab vendor mauvais contexte → `nvram_daemon` mort | `restorecon` du fstab ; `decrypt-fstab.sh` gère ce cas |
| Fingerprint OK au setup, KO après reboot | HAL MicroArray ne termine pas l'enumeration Android | [`fix-microarray-fingerprint.sh`](../scripts/fix-microarray-fingerprint.sh) |
| `nocleanup=true` mais fingerprint toujours KO | Ce workaround n'évite pas l'énumération bloquée sur ce S55 | Utiliser le patch HAL validé |
| Stockage interne de quelques centaines de Mo / quelques Go | filesystem userdata sous-dimensionné | Voir [Stockage interne trop petit](#stockage-interne-trop-petit) |
| `e2fsck/resize2fs: unsupported feature(s): quota` sur userdata | vieux e2fsprogs de TWRP 3.1.1 | reformater userdata plutôt que tenter de l'agrandir |
| `already in use` sur userdata | `/data` et/ou `/sdcard` toujours montés | forcer les `umount` avant formatage |
| `std::bad_alloc` en fastboot | vieux/mauvais fastboot | utiliser Google Platform Tools |
| Boot instable après batterie totalement vide | tension trop basse sous charge système | charger sur secteur avant de booter Android |

### Stockage interne trop petit

Cette opération **efface `/data`**. À faire dans TWRP :

```bash
./scripts/format-userdata-full.sh
```

Le script vérifie que `/dev/block/mmcblk0p30` existe, démonte `/data` et `/sdcard`, demande une confirmation explicite et reformate la partition complète en ext4.

---

## English

| Symptom | Likely cause | Action |
|---|---|---|
| `agZ` does not fit `/system` | stock `/system` is too small | use the [GApps guide](INSTALL-GAPPS-EN.md) + `repartition-gapps.sh` |
| Boots to recovery / factory reset | `/data` still forced to Oreo FDE | run `decrypt-fstab.sh`, then TWRP Format Data |
| Endless boot animation + `media.audio_policy` wait | bad vendor fstab context → dead `nvram_daemon` | restorecon the fstab; `decrypt-fstab.sh` handles it |
| Fingerprint works at setup, dies after reboot | MicroArray HAL never terminates Android enumeration | [`fix-microarray-fingerprint.sh`](../scripts/fix-microarray-fingerprint.sh) |
| `nocleanup=true` but fingerprint is still dead | that workaround does not bypass the stuck enumeration on this S55 | use the validated HAL patch |
| Internal storage is only hundreds of MB / a few GB | undersized userdata filesystem | see [Internal storage is too small](#internal-storage-is-too-small) |
| `e2fsck/resize2fs: unsupported feature(s): quota` on userdata | TWRP 3.1.1 has old e2fsprogs | reformat userdata instead of trying to resize it |
| `already in use` on userdata | `/data` and/or `/sdcard` still mounted | force unmount before formatting |
| `std::bad_alloc` in fastboot | old/broken fastboot | use Google Platform Tools |
| Unstable boot after deep battery discharge | voltage too low under Android boot load | charge from a wall charger before booting Android |

### Internal storage is too small

This **erases `/data`**. Run in TWRP:

```bash
./scripts/format-userdata-full.sh
```
