# DOOGEE S55 — KPOC : jauge MediaTek statique (29 octobre 2026)

## Cause vérifiée

L'appareil tourne sous LineageOS 18.1 (Android 11) avec noyau/ramdisk constructeur 2020 et vendor héritée d'Android 8. L'ancienne action `on charger` lançait `/vendor/bin/fuelgauged` (ELF dynamique) avant que le runtime Android 11 soit prêt. Le `last_kmsg` de l'essai du chargeur générique démontre :

- `init: cannot execve('/vendor/bin/fuelgauged'): No such file or directory` ;
- Kernel `CHR_Type 1`, `VChr ~4.7V`, `SOC 0:-100:-1` en KPOC ;
- `healthd: battery l=50 v=3654 t=0.0 h=2 st=4 c=0`, valeurs par défaut / état incorrect ;
- `charger: device unplugged: shutting down in 10000` alors que le câble était connecté ;
- le processus chargeur appelle finalement l'extinction du noyau (`reboot: Power down`), entraînant une nouvelle entrée Preloader sur câble branché.

La communication chargeur ↔ pilote jauge est donc réellement en défaut en KPOC. L'hypothèse d'un simple souci d'animation est réfutée.

## Correction minimale installée, **sans flash boot**

Source maintenue : `scripts/s55-kpoc-fuelgauged.rc`, SHA-256 `5c18d35c4030d02fe3d1c73cc7df7e3949d45024162c2f54f3a9b511dbd3e3c9`.

Destination sur l'appareil : `/vendor/etc/init/s55-kpoc-fuelgauged.rc`, même SHA, 398 octets, root:root, 0644, contexte `u:object_r:vendor_configs_file:s0`. Contenu fonctionnel :

```ini
service s55_kpoc_fuelgauged /sbin/fuelgauged_static
    class charger
    user root
    group root
    seclabel u:r:fuelgauged:s0
```

- Le binaire est déjà présent dans le boot 2020 : ELF ARM32 **statiquement lié**, 492344 octets, SHA-256 `47d62c2e608cc7dcd709b44da98fe92d5e793f1f321a8fb0d47a055db10e9b07`. Pas de linker APEX requis.
- Le domaine `u:r:fuelgauged:s0` existe et est employé par le service `fuelgauged` normal.
- La classe `charger` est lancée par le `on charger` du ramdisk d'origine ; elle n'est pas démarrée sous Android normal.
- Le `fuelgauged` normal sous Android reste celui de `/vendor/bin/fuelgauged` (classe main), **inchangé**.
- Le patch précédent `start servicemanager` désactivé seulement en KPOC est préservé ; plus aucun flash du boot expérimental `/sbin/charger` provoquant le cycle de ~32 s.

Installation vérifiée en direct : SHA, propriétaire/mode/SELinux, `/vendor` revenu en lecture seule, Android boot_completed=1, `init.svc.fuelgauged=running`, SELinux enforcing. Le réglage `adb_root` temporaire a été restauré à `null`, `adbd` est revenu UID 2000.

## Critères de validation manquants

1. Test de démarrage KPOC avec boot 2020+vendor modifiée : absence de retour Fastboot et de cycle Preloader pendant plusieurs minutes.
2. Après retour manuel Android, lire `/proc/last_kmsg` : preuve de démarrage du service `s55_kpoc_fuelgauged`, absence d'erreur SELinux/fuelgauge, progression de SOC (qui doit cesser de donner `0:-100:-1`).
3. Vérifier les valeurs `usb/online`, `ac/online` et `battery/status` dans un environnement KPOC (via journal / instrumentation minimale) ; le service de jauge seul ne garantit pas que le **chargeur graphique AOSP** aurait les données.
4. Développer l'interface d'animation uniquement sur preuves. Garder les protections PMIC, températures et seuils batterie.
5. Épreuve de charge réelle sur secteur avec SOC initial/final et tension dans Android, sans provoquer volontairement une décharge profonde.

## Rollback ciblé

Une fois Android accessible et le root ADB temporaire autorisé, retirer seulement `/vendor/etc/init/s55-kpoc-fuelgauged.rc` après vérification de son SHA, `sync`, remonter `/vendor` en lecture seule et rétablir `adb_root` à `null` / `adb unroot`. Ne pas reflasher l'ancienne image vendor entière, qui effacerait les correctifs radio et empreinte. Les images 2020 BOOT et vendor live antérieure complètes sont sous `backups/device-2026-10-29-kpoc/` (privées).

Sources : [AOSP init Android 11](https://android.git.googlesource.com/platform/system/core/+show/refs/tags/android-11.0.0_r12/init/README.md), [AOSP healthd mode charger Android 8](https://android.googlesource.com/platform/system/core/+/refs/tags/android-8.1.0_r46/healthd/healthd_mode_charger.cpp), [MediaTek FG20](https://android.googlesource.com/kernel/mediatek/+/android-mtk-3.18/drivers/power/mediatek/battery_meter_fg_20.c).
