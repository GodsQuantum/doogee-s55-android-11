> **Historical crDroid installation procedure, not the current LineageOS path.** The recommended October 2026 method is the [single-command LineageOS 18.1 + GApps kit](../installer/README.md).

# Doogee S55 — Android 11 crDroid Vanilla

[← README](../README.md) · [GApps FR](INSTALL-GAPPS-FR.md) · [Fingerprint](FINGERPRINT-FIX.md) · [Dépannage](TROUBLESHOOTING.md)

## Résultat

Cette procédure installe **crDroid 7.16 / Android 11 sans Google Apps** sur le Doogee S55 avec l'image `arm64-avZ`.

**Différence majeure avec le guide GApps :** l'image Vanilla rentre dans la partition `/system` d'origine. **Aucun repartitionnement GPT n'est nécessaire.**

## 0. Fichiers requis

Les fichiers TWRP et dm-verity/force-encryption ci-dessous sont des artefacts tiers locaux et ne sont volontairement pas suivis par Git. Voir [`files/README.md`](../files/README.md).

- `files/twrp-3.1.1-doogee-s55.img`
- `files/Disable_Dm-Verity_ForceEncrypt.zip`
- `crdrom-v316-220330-arm64-avZ.img.xz`
- https://sourceforge.net/projects/treblerom/files/crDRom11/2022.03.30/crdrom-v316-220330-arm64-avZ.img.xz/download

```bash
export ADB="${ADB:-adb}"
export FB="${FB:-fastboot}"
```

## 1. Déverrouiller et installer TWRP

Dans Android stock, activer OEM unlocking + USB debugging, puis :

```bash
$ADB reboot bootloader
$FB flashing unlock
$FB flash recovery files/twrp-3.1.1-doogee-s55.img
$FB reboot recovery
```

## 2. Désactiver dm-verity / forceencrypt

TWRP → Advanced → ADB Sideload :

```bash
$ADB sideload files/Disable_Dm-Verity_ForceEncrypt.zip
```

## 3. Décompresser et flasher la GSI Vanilla

```bash
unxz crdrom-v316-220330-arm64-avZ.img.xz
$ADB reboot bootloader
$FB flash system crdrom-v316-220330-arm64-avZ.img
$FB reboot recovery
```

> N'utilise pas le fichier `agZ` dans cette commande sur une géométrie stock : le GApps build est trop gros et possède son propre guide.

## 4. Corriger FDE/fstab

Dans TWRP :

```bash
./scripts/decrypt-fstab.sh
```

Le script conserve/restaure le contexte SELinux du fstab. Cette partie est importante : un fstab `unlabeled` peut tuer `nvram_daemon` puis bloquer le boot sur `media.audio_policy`.

## 5. Corriger le fingerprint MicroArray

Avant le premier boot Android :

```bash
./scripts/fix-microarray-fingerprint.sh
```

Cette étape évite le cas classique sur ce S55 : enrollment fonctionnel au premier setup, puis fingerprint mort après le premier reboot.

## 6. Format Data

TWRP → **Wipe → Format Data → yes**.

Ne fais pas de `fastboot -w` dans le flux canonique : TWRP formate ici `/data` directement sur la partition userdata.

## 7. Boot et vérification

```bash
$ADB reboot system
$ADB wait-for-device
$ADB shell getprop sys.boot_completed
```

Après l'installation :

1. vérifier le stockage ;
2. enregistrer une empreinte ;
3. rebooter ;
4. vérifier que le déverrouillage par empreinte fonctionne toujours.

Pour F-Droid/Aurora/microG, installe ensuite la solution de ton choix ; ce guide Vanilla ne force aucun framework Google.
