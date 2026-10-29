# DOOGEE S55 — audit croisé firmware d'origine, LineageOS 18.1, correctifs KPOC

**29 octobre 2026 — analyse vérifiée hors ligne, sans nouveau flash.** Le S55 affiche Android 11 normalement mais redémarre en cycle ~32 s lors de la charge téléphone éteint après le flash expérimental du 29/10. Le BOOT d'origine et le VENDOR exact sont conservés en sauvegardes privées. Ce rapport prime sur les hypothèses plus anciennes qui qualifiaient le KPOC de « stable » parce qu'aucun Fastboot n'était visible.

## 1. Configuration physique et état mesuré

- S55 standard, MediaTek MT6750/MT6755, partitions eMMC non-A/B, noyau préservé Linux 3.18.60+ du 29 juin 2020, LK/Preloader OEM préservés ; LineageOS 18.1 Android 11 **non-SAR** en /system, vendor ancien hérité Oreo avec patchs HAL/fingerprint/RIL.
- Boot d'origine 2020 (sauvegardé intact avant changement) : SHA-256 `a2e6c0db60b2ecc22fe4fb42e2ca2db03b55188d44f195361e36c5dd6873f5ab`, 16 MiB.
- Boot expérimental **flashé le 29/10 à 15:27** : SHA-256 `213236fcdd93efe3e825aa9c7d21b9e2204c020d95e5d1543db332c1164d7bcd`, 16 MiB. Android normal a démarré et la batterie était à 27% à 15:28. Aucune écriture sur LK/Preloader.
- Vendor en place : correctif `on charger` supprimant **uniquement** `start servicemanager`, évite une panique explicite du service critique provoquée par l'absence d'APEX en KPOC. SHA-256 du fichier corrigé `c5b3584a4d232ac7386704883d6f5c5f8e7c4867bccc99a46f36d2e0c58d3d84`. Les autres patchs vendor (notamment RIL/fingerprint) restent préservés.
- Ancien comportement : entrée KPOC -> `cannot execve('/system/bin/servicemanager')` -> 4 sorties critiques -> `init: panic: rebooting to bootloader` à ~26,68 s -> Fastboot. Après correction vendor et **avant** flash du nouveau BOOT : 0e8d:2008 continu au-delà de 12 minutes sans retour Fastboot, mais affichage vide/Orange State et recharge électrique non certifiée.
- Après flash BOOT : affichage `Charging ! ??/100` et cycles répétés de ~32 s `0e8d:2008 -> 0e8d:2000 Preloader -> 0e8d:2008` sur Pegasus ; ADB et Fastboot absents durant ce cycle. Test du script du 29/10 « PASS PARTIEL » = **FAUX POSITIF**, puisqu'il n'observait que Fastboot et pas les réénumérations USB.
- Le téléphone s'éteint visuellement sans câble ; le branchement secteur ou Pegasus provoque une entrée en mode charge. C'est un réveil matériel attendu du PMIC sur VBUS, pas la preuve que l'arrêt Android ne fonctionne pas.

## 2. Comparaison des vrais binaires et déclarations

| Élément | Constructeur DOOGEE Android 8 (2018-07/10) | Android 2020 conservé | Après flash 29/10 |
|---|---|---|---|
| `init.rc` boot | 26 919 octets, SHA `dcf59d4cb4ec7f60a6882ca341ee1b87984bd845c66082ffdcfd86f0e42c2e4e` | **strictement identique** à 2018 | même script + 9 lignes en fin de fichier |
| Noyau | OEM 2018 différents des 2020 | SHA du kernel `0d7b1c554e34fbd364…` | **identique au 2020**, aucun patch kernel |
| `/sbin/charger` | générique AOSP/healthd statique dans le ramdisk | existe, dormant, SHA `5681edd4406994a1cb24e9a42d906fae82ae18e35f01a5c5e7637fb9921df818` | **même binaire**, désormais lancé par init |
| `fuelgauged_static` | ARM32 dans le ramdisk | présent, SHA `47d62c2e608cc7dcd709b44da98fe92d5e793f1f321a8fb0d47a055db10e9b07` | identique, **pas explicitement lancé** par le patch |
| Modification BOOT 29/10 | — | — | `service charger /sbin/charger; class charger; user root; group root system; seclabel u:r:charger:s0` |

**Preuve :** comparaison des deux images via `scripts/build-s55-kpoc-experimental.py` (analyse CP/IO en lecture seule). La liste des fichiers du ramdisk est identique ; **seul `init.rc` diffère**. Le binaire, le kernel, le DT, LK, le preloader et les seuils d'alimentation n'ont pas été modifiés par ce patch.

### Chaîne de charge OEM perdue lors de la migration

Dans l'image constructeur **Android 8 du 24/10/2018**, `/system/etc/init/kpoc_charger.rc` contient :

```ini
on charger
    start kpoc_charger

service kpoc_charger /system/bin/kpoc_charger
    class charger
```

Le programme OEM `/system/bin/kpoc_charger` (29 296 octets) est **ARM32 et lié dynamiquement** avec `/system/bin/linker` Android 8, `libshowlogo.so`, `libui.so`, `libhardware_legacy.so` et d'autres bibliothèques Android 26. Il lit explicitement la tension native `/sys/class/power_supply/battery/batt_vol`, le mode `/sys/class/BOOT/BOOT/boot/boot_mode` et contrôle l'animation MTK. **Copier ce binaire seul vers LineageOS Android 11 ne peut pas fonctionner sans compatibilité de chargeur ELF/bibliothèques/SELinux**. L'image système OEM a été examinée via décompression temporaire du sparse ; aucune partition mobile n'a été modifiée.

Dans la GSI **LineageOS 18.1**, `/system/etc/init/hw/init.rc` déclare :

```ini
service gsicharger /bin/charger
    class gsicharger
    user system
    group system shell input graphics wakelock

on charger
    class_start gsicharger
```

Le **ramdisk non-SAR OEM 2020 n'a pas de répertoire `/bin`** (il comporte seulement le symlink `/charger -> /sbin/charger`). Le binaire de LineageOS réside en revanche dans la partition GSI `/system/bin/charger` et est un ELF64 **dynamique** Android 30 qui demande `/system/bin/linker64` (symlink vers un module APEX installé au démarrage Android normal) et Health HAL 2.0/2.1. La configuration GSI ne peut pas être supposée exécutable telle quelle en KPOC sur ce boot non-SAR. La présence de deux *déclarations* de chargeur n'est donc **pas la preuve de deux processus concurrents** : le GSI peut échouer avant exécution.

### Signature certaine du texte `Charging ! ??/100`

La chaîne exacte **`??/100`** est présente dans le binaire statique `/sbin/charger` du ramdisk 2020 (offset ELF `0x97feb` environ), mais pas dans LK, `fuelgauged_static` ni dans `kpoc_charger` OEM. L'écran incomplet est donc produit par le chargeur générique que le flash du 29/10 a activé. Il signale une jauge/capacité non exploitable dans ce mode, **pas une batterie matériellement à 0 %**.

## 3. Pourquoi le chargeur pourrait provoquer le redémarrage toutes les 32 s

Le binaire `/sbin/charger` contient ces chaînes :

- `healthd: BatteryCapacityPath not found`, `healthd: BatteryStatusPath not found`
- `charger: animation missing or unknown battery status`
- `charger: device unplugged: shutting down in ...`
- `charger: shutting down`

Dans AOSP Android 8, **le chargeur logiciel demande un POWER_OFF après environ 10 secondes** si la couche `healthd` signale qu'aucune alimentation ne reste connectée. Si le S55 remonte mal les valeurs `ac/online` et `usb/online` en KPOC, le cycle peut être : boot sur VBUS, service chargeur détecte « débranché » par erreur, demande POWER_OFF, PMIC redémarre automatiquement parce que VBUS est encore présent. La durée observée est compatible.

**IMPORTANT : cette explication reste une hypothèse causale**, car le log d'extinction du nouveau KPOC n'a pas encore été récupéré. Une erreur SELinux, un watchdog, un problème USB ou un appel de shutdown par le noyau peuvent aussi produire des cycles. Il serait incorrect de modifier le délai de shutdown ou de forcer `charger_online=1` sans lecture fiable du matériel : cela empêcherait l'arrêt de sécurité quand le câble est réellement retiré.

Autre incohérence possible : sous Android normal, `fuelgauged` tourne et donne ~24–27 % ; en KPOC les anciens logs donnaient `SOC 0:-100:-1`. Le service `/vendor/bin/fuelgauged` lancé par l'ancienne action `on charger` ne fonctionnait pas faute de runtime/linker, alors que `/sbin/fuelgauged_static` est disponible mais non configuré pour KPOC. Lancer cette version statique sans contrôler son domaine SELinux et ses accès au pilote reste expérimental.

## 4. Réglages d'extinction : lesquels peuvent aider ?

| Commande ou option | Effet | Décision |
|---|---|---|
| Bouton **Éteindre** Android / `reboot -p` | demande une extinction normale ; VBUS peut ensuite réveiller le PMIC en mode charge | aucun défaut Android shutdown isolé, pas besoin d'une autre commande |
| Fastboot `off-mode-charge=1` | autorise la charge appareil éteint, vérifié actif sur S55 | **conserver** |
| Fastboot `off-mode-charge=0` | change le mode au branchement ; peut démarrer Android au lieu d'une charge autonome | **ne pas modifier** ; ne répare pas une batterie déchargée |
| `ro.enable_boot_charger_mode` et `sys.boot_from_charger_mode` | transition **depuis** le mode chargeur **vers** Android au maintien Power | ne corrige ni détection du chargeur ni pourcentage |
| `settings ... low_power_trigger_level` / Battery Saver | autonomie en Android normal | ne modifie pas LK/PMIC/KPOC |
| `stay_on_while_plugged_in` | maintien écran allumé en développement | aucun rapport avec la charge éteinte |
| `ro.boot.fake_battery`, faux pourcentage, forcer `charger_online`, désactiver les protections sous-tension/thermiques | masquent le défaut et exposent au risque de sous-tension/arrêt incorrect | **interdit** |

**Conclusion : il n'existe pas de « tweak Settings » prouvé qui transforme le réveil électrique normal à l'insertion du câble en extinction permanente avec recharge fiable.** Corriger le service KPOC, sa jauge, et son chemin de shutdown est le traitement pertinent.

## 5. Plan expérimental priorisé

1. **Retour A/B à la base connue** : restaurer **uniquement** BOOT original 2020 (16 MiB SHA `a2e6c0db...`) en conservant la vendor corrigée. Ne toucher ni NVRAM ni GPT/LK, RIL ou empreinte. Android normal doit atteindre boot_completed=1 et afficher SOC/tension. Puis réessayer KPOC sous même chargeur ; avant flash du nouveau boot, il était resté en 0e8d:2008 >12 minutes sans Fastboot (mais pas de UI). Cela isolera la régression introduite par la déclaration de /sbin/charger.
2. **Capturer une vraie cause au prochain test** : `/sys/fs/pstore`, `/proc/last_kmsg`, logs noyau et compteurs reconnexions USB après retour Android, sans considérer un USB stable comme preuve de charge. Le script `flash-s55-kpoc-pegasus-20261029.sh` est obsolète : son verdict « PASS PARTIEL » était faux parce qu'il ignorait le Preloader.
3. **Corriger l'exécutable KPOC, pas un réglage général** : étudier un service chargeur unique adapté au noyau 2020, avec `fuelgauged_static`, bon accès aux sources power_supply, droits framebuffer/input/wakelock/SELinux, et comportement de shutdown basé sur un signal chargeur fiable. Ne pas importer directement `kpoc_charger` Android 8 et ses bibliothèques sur Android 11 sans port validé.
4. **Valider réellement** : boot normal, extinction physique sans câble, insertion chargeur secteur, aucun reboot du Preloader sur >5 min, capacité non-??, démarrage Power, et progression mesurée SOC + tension sous Android après charge. Ne pas créer volontairement une décharge profonde.

**Blocage physique au moment de l'audit :** S55 actuellement dans la boucle KPOC USB `0e8d:2008 <-> Preloader 0e8d:2000`, ni ADB ni Fastboot continus. La restauration du boot ne doit être exécutée qu'après retour contrôlé en Android ou Fastboot et précontrôle batterie/identité. Pas de flash direct sur le Preloader instable.

## Sources

- AOSP init / triggers charger vs late-init : https://chromium.googlesource.com/aosp/platform/system/core/+/refs/heads/upstream/init/
- AOSP Android 8 Healthd/charger `UNPLUGGED_SHUTDOWN_TIME` : https://android.googlesource.com/platform/system/core/+/refs/tags/android-cts-8.0_r26/healthd/healthd_mode_charger.cpp
- MTK Android 3.18 : https://android.googlesource.com/kernel/mediatek/+/android-mtk-3.18/drivers/power/mediatek/battery_common_fg_20.c
- LineageOS incident analogue après update : https://github.com/LineageOS/issues/issues/288
- Rapports précédents : `docs/RESEARCH-KPOC-COMMUNITY-2026-10-29.md`, `docs/RESEARCH-DEEP-DISCHARGE-2026-10.md`, `docs/LINEAGE18-MIGRATION-ROOT-CAUSE-2026-10.md`.

**Règle de sûreté :** conserver les sauvegardes complètes privées BOOT+VENDOR, y compris l'image vendor active post-RIL ; ne jamais flasher l'ancienne image golden vendor 2018/2020 sur le téléphone réparé.
