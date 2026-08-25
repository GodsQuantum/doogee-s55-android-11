# Doogee S55 — Android 11 crDroid avec GApps

[← README](../README.md) · [Vanilla FR](INSTALL-VANILLA-FR.md) · [Fingerprint](FINGERPRINT-FIX.md) · [Dépannage](TROUBLESHOOTING.md)

## Résultat

Cette procédure part d'un **Doogee S55 stock Android 8** et installe **crDroid 7.16 / Android 11 avec Google Apps** (`arm64-agZ`). Elle inclut les correctifs spécifiques au S55 qui ont été validés :

- agrandissement de `/system` de 256 MiB pour faire rentrer l'image GApps ;
- conservation du début de `userdata` ;
- correction FDE/fstab ;
- préservation SELinux/NVRAM ;
- formatage complet de `/data` ;
- correctif du HAL MicroArray fingerprint avant le premier reboot Android.

> **S55 uniquement. Pas S55 Lite.** Cette procédure modifie la table GPT.

## 0. Fichiers requis

Dans le dépôt :

- `files/twrp-3.1.1-doogee-s55.img`
- `files/Disable_Dm-Verity_ForceEncrypt.zip`

À télécharger :

- `crdrom-v316-220330-arm64-agZ.img.xz`
- https://sourceforge.net/projects/treblerom/files/crDRom11/2022.03.30/crdrom-v316-220330-arm64-agZ.img.xz/download

Outils PC recommandés : **Google Platform Tools** (`adb`, `fastboot`), `xz`/`unxz`, `sha256sum`.

```bash
export ADB="${ADB:-adb}"
export FB="${FB:-fastboot}"
```

## 1. Déverrouiller le bootloader

Android stock : Options développeur → **OEM unlocking** + **USB debugging**.

```bash
$ADB reboot bootloader
$FB flashing unlock
```

Confirmer sur le téléphone. Cette opération efface les données.

## 2. Installer TWRP

```bash
$FB flash recovery files/twrp-3.1.1-doogee-s55.img
$FB reboot recovery
```

Attendre TWRP.

## 3. Désactiver dm-verity / forceencrypt

Dans TWRP → Advanced → ADB Sideload, puis :

```bash
$ADB sideload files/Disable_Dm-Verity_ForceEncrypt.zip
```

Choisir : dm-verity **disable**, forceencrypt **disable**, quota **no** si le script le demande.

## 4. Agrandir `/system` pour l'image GApps

L'image `agZ` décompressée est trop grande pour le `/system` stock. Le layout validé déplace uniquement la frontière **system/cache** : `userdata` commence toujours au secteur `8273920`.

Depuis le PC, téléphone dans TWRP :

```bash
./scripts/repartition-gapps.sh
```

Le script :

1. vérifie la géométrie exacte du S55 ;
2. sauvegarde la GPT dans `backups/` ;
3. agrandit `system` de 256 MiB ;
4. réduit `cache` de 432 à 176 MiB ;
5. conserve `userdata` inchangé ;
6. vérifie la GPT ;
7. redémarre TWRP pour forcer la relecture des partitions.

Ne continue pas si le script refuse la géométrie.

## 5. Décompresser et flasher l'image GApps

```bash
unxz crdrom-v316-220330-arm64-agZ.img.xz
IMG="$PWD/crdrom-v316-220330-arm64-agZ.img"
$ADB push "$IMG" /dev/block/mmcblk0p28
```

Le `push` direct vers le block device est volontaire : c'est la méthode validée après le repartitionnement.

Agrandir ensuite le filesystem ext4 de l'image jusqu'à la nouvelle taille de la partition et recréer cache :

```bash
$ADB shell 'e2fsck -fy /dev/block/mmcblk0p28 || true
resize2fs /dev/block/mmcblk0p28
mke2fs -t ext4 -L cache /dev/block/mmcblk0p29
sync'
```

## 6. Corriger le fstab Oreo sans casser SELinux

Toujours dans TWRP :

```bash
./scripts/decrypt-fstab.sh
```

Le script écrit via un fichier temporaire puis `cat > original` afin de conserver l'inode, et applique `restorecon`. Ne remplace pas cette étape par un simple `sed -i` sans gérer le contexte SELinux.

## 7. Appliquer le correctif fingerprint MicroArray

Fais-le **avant le premier boot Android** :

```bash
./scripts/fix-microarray-fingerprint.sh
```

Le script ne patche que la bibliothèque connue et validée :

- original SHA256 `e76c3884ab9935ac60c38370210747465b76fadda5acd3470e199f7c7070af06`
- patched SHA256 `3d89603ed3025bdc14e65d6269024c52920808c747aeb2d79417741d7cc7f9f6`

Il sauvegarde l'original et refuse tout hash inconnu.

## 8. Format Data dans TWRP

TWRP → **Wipe → Format Data → yes**.

C'est la procédure canonique de ce dépôt : elle évite le vieux piège où `fastboot -w` créait un filesystem userdata minuscule.

Si `/data` reste anormalement petit, utilise ensuite [le correctif userdata](TROUBLESHOOTING.md#stockage-interne-trop-petit).

## 9. Premier démarrage

TWRP → Reboot → System, ou :

```bash
$ADB reboot system
```

Le premier boot peut prendre plusieurs minutes.

Vérification :

```bash
$ADB wait-for-device
$ADB shell getprop sys.boot_completed
```

La valeur finale doit être `1`.

## 10. Vérifications post-install

- Assistant Android / Google terminé.
- Stockage interne cohérent avec la partition userdata (~53 GiB de partition, moins l'usage système).
- Paramètres → Sécurité → empreinte : enrollment fonctionnel.
- **Rebooter une fois**, puis vérifier que l'empreinte déverrouille toujours le téléphone.

Le reboot est important : c'est précisément après le premier reboot que le vieux HAL MicroArray échoue sans le correctif de ce repo.
