# DOOGEE S55 — Battery drain / offline charging (FR + EN)

Status: 2026-10-09. Diagnosis ongoing; no firmware or hardware fix validated. This is NOT a flash guide.

**Update on wall charging:** After severe 0–1% reporting on the Pegasus USB hub, the owner reports successful charging to **20% with a wall adapter** on October 9, 2026. This rules out the blanket claim that the phone cannot charge at all; it does **not** prove that the battery is healthy or that the Android fuel gauge is accurate. Investigate the distinction between PC/hub USB current and wall-adapter charging, then profile battery drain and suspend when the device can remain powered up. Do not buy a battery or flash firmware based solely on the earlier 0 mV/0 °C Android placeholders.

**Battery protection approach:** Prefer native automatic Battery Saver at about 20%, warn before 10–15% and avoid a forced shutdown based on an unreliable 5% reading. The 20% auto setting was prepared but not yet applied on the smartphone; verify ADB and the new values after the owner reconnects it. Full current OS candidates: [FR](ROM-OPTIONS-FR.md) / [EN](ROM-OPTIONS-EN.md).

**Recherche octobre 2026 et ordre de réparation : [RESEARCH-DEEP-DISCHARGE-2026-10.md](RESEARCH-DEEP-DISCHARGE-2026-10.md)**. Vérifier cette analyse avant toute opération sur les partitions ; elle inclut les preuves KPOC des firmwares, le firmware constructeur 2019, les possibilités de sauvegarde en lecture seule et le diagnostic matériel.

### Mesures complémentaires confirmées — 9 octobre 2026, 14 h 05–14 h 21

- Fastboot série `S550000000017268`, produit `K50V1_64`, bootloader déverrouillé ; `getvar off-mode-charge` et `getvar all` annoncent **`off-mode-charge: 1`**. La fonction de charge éteinte est déjà activée. Ne pas la désactiver avec `oem off-mode-charge 0`.
- Les deux fichiers `boot.img` constructeur ont une configuration kernel extraite et vérifiée : **`CONFIG_MTK_KERNEL_POWER_OFF_CHARGING=y`** pour juillet ET octobre 2018 ; les deux LK possèdent les routines KPOC. Le kernel actuellement flashé n'a pas été relu : sa configuration reste inconnue.
- À 14 h 05, `fastboot reboot` accepté ; Android ADB accessible à 14 h 06, `sys.boot_completed=1`. `dumpsys battery` affichait **1 %**, USB powered=true, courant maximal rapporté variant de 398100 à 183500 µA, tension et température **0** (remontées anormales/invalides), santé déclarée GOOD. Accès direct `power_supply/battery` refusé à l'utilisateur ADB shell (SELinux/permissions).
- À 14 h 14, `fastboot oem reboot-recovery` accepté mais n'a pas produit de session TWRP/ADB stable ; boucle d'énumération MTK preloader puis fastboot. À 14 h 18, un nouveau `fastboot reboot` a été tenté avec capture ADB préarmée ; le téléphone est retourné en fastboot après des passages préloader/MTP, sans capture ADB supplémentaire.
- **Aucune opération de flash, erase, format, bootloader lock, changement du réglage de charge ni patch fingerprint.** `fastboot getvar battery-voltage`, `battery-soc`, `battery-current` et `battery-status` ne renvoient aucune mesure sur ce bootloader.
- Diagnostic restant : déterminer si la **tension/capacité réelle** et le courant de charge évoluent, distinguer batterie usée/circuit de charge/câble de mode KPOC kernel et erreur de remontée du service Android. Une simple répétition de `off-mode-charge 1` ne peut pas être présentée comme un correctif.


## Français

### Constat vérifié

- Appareil : DOOGEE S55 / MediaTek MT6750, crDroid 7.16 (Android 11, GSI A-only), vendor Android 8. Conserver les correctifs /data, SELinux/NVRAM et MicroArray fingerprint.
- Symptômes rapportés : forte décharge puis boucle de démarrage, sans pouvoir atteindre Android, recharge difficile.
- Pegasus, 9 octobre 2026 : périphériques USB MediaTek 0bb4:0c01 (« Android »), 0e8d:2000 (MT65xx preloader) et 0e8d:0003 (BROM), suivis de déconnexions. Aucun périphérique ADB ou fastboot n'était présent lors du diagnostic. Ces modes ne sont pas interchangeables et preloader/BROM ne fournissent pas ADB.
- Deux firmwares stock 2018-07-07 et 2018-10-24 sont conservés localement. Leurs images LK contiennent des routines explicites de Kernel Power Off Charging (KPOC). Le bon fonctionnement des images actuellement installées reste **inconnu**.
- Sans appareil ADB fonctionnel : **tension, courant, état de la batterie et wakelocks inconnus**. Il serait prématuré de modifier une partition ou d'accuser uniquement crDroid.
- Spécifications : 5 500 mAh nominal en 2018, recharge Micro-USB 5 V / 2 A (10 W). Le vieillissement, la résistance interne et les pertes dans le câble/port peuvent empêcher le maintien de la tension lors du boot.

### Intervention immédiate non destructive

1. Déconnecter le téléphone de Pegasus. Vérifier le câble et le port Micro-USB (la trappe étanche ne doit pas gêner l'insertion). Ne pas charger en cas de gonflement, dommage, odeur ou chaleur anormale.
2. Brancher à un chargeur **mural** fiable **5 V / 2 A**. Ne pas enchaîner les démarrages ; laisser au moins 30 à 60 minutes et constater le comportement (écran noir, icône stable, animation de charge, boucle de redémarrage, échauffement).
3. Si Android redémarre, commencer par terminer la charge et sauvegarder les données. Sur Pegasus, exécuter ensuite depuis cette copie du dépôt : **bash scripts/diagnose-battery.sh**.
4. Si la charge ne tient pas sur secteur, examiner batterie, port et circuit de charge avant tout flash. Batterie gonflée ou température excessive : arrêter les essais.

### Diagnostic différentiel

| Observation | Hypothèse prioritaire, à vérifier |
|---|---|
| Chargeur mural + Android éteint : charge stable ; Android redémarre en boucle | Pic de consommation au boot, batterie fatiguée, services et kernel |
| Branche secteur : démarrage automatique répété au lieu de rester en charge | Séquence LK/KPOC, boot/ramdisk, bouton Power, matériel |
| % batterie élevé puis extinction instantanée | Chute de tension, batterie vieillissante, jauge |
| Fonctionne normalement mais se décharge en veille | Réseaux, modem, wakelocks, Doze, GApps éventuelles |
| USB 0e8d:2000 sans ADB | Préloader MediaTek, ne pas tenter des commandes Android dans ce mode |

### Script read-only

Le script scripts/diagnose-battery.sh lit sur **Pegasus** la présence USB, ADB, fastboot, les journaux USB récents ; et uniquement quand un appareil ADB autorisé est présent, les propriétés, le dossier sysfs power_supply, dumpsys battery, dumpsys power/deviceidle et batterystats. Aucun effacement, flash, adb root, adb reboot ou changement de propriété. Sortie sensible (identifiants) : ne pas publier telle quelle sur GitHub.

**Avant toute correction firmware :** récupérer une charge stable, vérifier les versions et hash des partitions actives, préserver les données et comparer kernel/ramdisk/LK aux images stock. Ne pas désactiver les seuils de sécurité basse tension. La présence du code KPOC dans le LK stock ne prouve pas qu'il fonctionne actuellement.

Sources : DOOGEE FAQ https://www.doogee.com/pages/faq ; Notebookcheck S55 https://www.notebookcheck.net/Doogee-S55-Smartphone-Review.323406.0.html ; MediaTek KPOC https://android.googlesource.com/kernel/mediatek/+/android-mtk-3.18/drivers/power/mediatek/Kconfig ; AOSP charger mode https://android.googlesource.com/platform/system/core/+/refs/heads/main/healthd/healthd_mode_charger.cpp

## English

The S55 shows a deep-discharge / bootloop issue that is **not yet resolved**. The stock LK images contain offline-charging (KPOC) functionality, but the active kernel/bootloader, battery voltage and charge current have not yet been verified.

Use a known-good **5 V / 2 A Micro-USB wall charger** and cable for at least 30–60 minutes, without repeatedly forcing a reboot. Inspect the battery/port and stop if overheated, swollen or damaged. Record if the charging icon is stable or the phone restarts spontaneously. A computer USB port may not provide the same charging current.

When Android or TWRP is stable enough for an authorized ADB connection, run **bash scripts/diagnose-battery.sh** on Pegasus. The script is strictly read-only and does not flash or reboot. Treat its output as private. Diagnose battery hardware versus KPOC firmware versus Android idle/boot consumption before any reversible change; preserve the validated fingerprint and vendor fixes.
