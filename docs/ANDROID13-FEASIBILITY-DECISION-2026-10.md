# DOOGEE S55 — Portage Android 13 : verdict de prévalidation (10 octobre 2026)

## Ce qui a été réellement testé

**Analyse hors téléphone, aucun flash Android 13, aucun changement boot/GPT.**

Matériel réel lu via ADB/TWRP :
- DOOGEE S55, MediaTek MT6750, ARM64, vendor Android 8.0, VNDK **26**.
- Système de partition ancien **non-SAR**, une seule partition système (**3 263 168 512 octets**) et une partition recovery séparée.
- Boot actif = kernel MediaTek **3.18.60+** avec ramdisk d'origine, **/init et scripts MTK** dans le boot, gestion de charge hors Android intégrée.
- Bootloader non-A/B (pas de `slot_suffix` / `ab_update`). Boot, lk, lk2, vendor, recovery et partitions radio sauvegardés avant intervention.

Image Android 13 locale : `gsi_los20.img`, LineageOS 20 / Android 13, SDK 33, correctifs 2025-09-05, 2 242 465 792 octets.
- L'image passe le contrôle de taille : elle tient dans la partition système existante.
- **Mais** sa racine ext4 comprend `/init -> /system/bin/init`, `/system/bin`, `/system/etc`, des répertoires de première phase d'init, et non un système non-SAR dont `/bin` et `/etc` sont directement disponibles sous `/system`.
- Les GSI Android 13 de cette famille requièrent un démarrage **system-as-root**. Sur ce S55, le noyau et le boot ramdisk actuels démarrent au contraire un Android Oreo non-SAR. Un `fastboot flash system gsi_los20.img` seul **ne constitue pas un test valide**.
- L'image Android 13 inclut `com.android.vndk.current.apex` et des bibliothèques système de génération 13 ; l'image inspectée ne contient pas une distribution explicite de VNDK 26. Les anciennes bibliothèques MTK, HCT, microphone, caméra, radio et thermal dépendent précisément d'interfaces legacy.
- Les adaptations déjà prouvées sur crDroid Android 11 (fallback voltage, HCT, ipsec, sensors ARM32, sepolicy `proc_mtktz`) nécessiteraient une **réécriture version 13**, pas un simple copier-coller du binaire Android 11.

Références :
- AOSP [system-as-root pour les non-A/B](https://source.android.com/docs/core/architecture/partitions/system-as-root) : adapte boot + système + dm-verity + dépendances racine spécifiques.
- AOSP [ramdisk/first-stage init](https://source.android.com/docs/core/architecture/partitions/ramdisk-partitions) : changements incompatibles avec anciens ramdisks 8.x.
- [Treble GSI/community list](https://github.com/TadiT7/treble_experimentations_wiki/blob/master/Generic-System-Image-%28GSI%29-list.md) : les GSI récentes sont system-as-root par défaut, sauf indication contraire.
- [Documentation officielle GSI](https://source.android.com/docs/core/tests/vts/gsi).

## Décision : ne pas flasher Android 13 directement

Le test de faisabilité ne valide **pas** un démarrage Android 13. Un essai matériel nécessiterait :
1. Migration complète et réversible boot/SAR/first-stage init/fstab, tout en conservant le kernel 3.18 (ou un kernel compatible propre au S55).
2. Réintroduction contrôlée du VNDK 26 et des compatibilités des HAL radio/caméra/audio/empreinte/capteurs.
3. Compatibilité SELinux Android 13 / MTK Oreo.
4. Restauration TWRP fiable depuis les backups privées, une fois le niveau de charge stabilisé.

**Il ne faut pas conclure « Android 13 impossible en toute circonstance »** : il s'agit d'un portage non réalisé. En revanche, **cette image Android 13 précise est incompatible en l'état avec le boot présent**, et la flasher pour la voir bloquer au démarrage n'apporterait rien.

## Repli retenu par l'utilisateur : LineageOS 18.1 Android 11

Image locale `los18.img` non-SAR ARM64 (2 055 483 392 octets), patch sécurité **2024-01-05**, SHA256 `6ff112b937a5043aee862b48330a3895bb040461cdbe4304b342468600c7aaf5`.

Avant toute écriture : sauvegarde exacte de `/system` crDroid corrigé dans `backups/device-2026-10-10/` avec contrôle SHA256 et test de décompression. Préserver le boot actif et le vendor avec leurs correctifs, le fingerprint, et les sauvegardes des partitions radio. Le formatage de la partition utilisateur est autorisé par l'utilisateur.

GApps : `NikGapps-core-arm64-11-20260204-signed.zip`, SHA256 local `a56ad7da66e51a6cd1af0b0fb39a1ac167739161624115276b7f8d00633fd0f8`. Archives ZIP intègres ; `AndroidVersion=11` dans la configuration du paquet. Le succès de leur installation recovery ne peut être attesté **qu'après installation et premier boot complet**.

**Contrôles de réception :** Android 11 démarré, Play Store et compte Google si besoin, fingerprint après deux redémarrages, température batterie/charge, mode charge éteint, appels/data SIM, Wi-Fi/BT/GPS, caméra, accéléromètre/magnétomètre/gyroscope/lumière/proximité, veille/suspend, thermal, services vendor et absence de boucle crash.
