# DOOGEE S55 — journal KPOC réel récupéré après 5 h 53 min de charge éteinte

**30 octobre 2026, 07:54 (Europe/Paris)** — diagnostic en lecture seule via Pegasus et SentinelX.

## Observations vérifiées

- 01:58:42, dernier passage dans le mode KPOC USB `0e8d:2008` après Preloader; 07:51:56 déconnexion physique. Aucun Fastboot/reboot Preloader entre-temps.
- 07:53:24, Android démarré et ADB relié, `sys.boot_completed=1`, SELinux Enforcing, ro.bootmode normal.
- Batterie Android après le test : `level=30`, `voltage=3645 mV`, température `360` dixièmes de degré, `status=2` (charging USB), `Max charging current=500000` µA (valeur annoncée, pas courant réellement mesuré), `charge counter=4708000` µAh (valeur HAL non encore validée). **Aucun gain SOC démontré** après presque 6 heures KPOC USB Pegasus. Une mesure unique et un SOC possiblement figé ne suffisent pas pour conclure qu'aucun courant ne passe.
- Nouveau fichier `/proc/last_kmsg` **262 206 octets**, début `ram console header, hw_status: 0, fiq step 0; Not Clear, old status is 0`. C'est un **tampon circulaire tronqué**, qui ne couvre ici que les timestamps noyau ~20979–21200 secondes de la fin du KPOC de presque six heures (et non le lancement à t=0). Le texte est manifestement altéré par de nombreux octets corrompus : il faut seulement retenir les motifs répétés et les messages qui restent intelligibles. Original brut non conservé en dehors de la lecture temporaire Pegasus (supprimé après analyse).

## Défauts dans les services KPOC : preuves directes du kernel

1. Plusieurs dizaines d'échecs du service `s55_kpoc_fuelgauged`, qui tente `/sbin/fuelgauged_static` dans le domaine `u:r:fuelgauged:s0`. Les logs montrent clairement `avc: denied { entrypoint }` du processus init et le label fichier `u:object_r:rootfs:s0`, puis `cannot execve('/sbin/fuelgauged_static'): Permission denied` et `exited with status 127`. Redémarrage automatique de ce service toutes les ~5 secondes.
2. Service OEM normal `fuelgauged` lancé par `on charger` dans `/vendor/etc/init/hw/init.mt6755.rc` : `cannot execve('/vendor/bin/fuelgauged'): No such file or directory`, puis statut 127, également relancé toutes les ~5 secondes. Sur Android normal ce service fonctionne; en KPOC, l'erreur ENOENT peut indiquer l'absence de linker/bibliothèque plutôt que le chemin exécutable lui-même (il faut vérifier).
3. Le noyau rapporte à plusieurs reprises `[BATTERY] pchr_turn_on_charging(), enable=1` et `[mt_kpoc_power_off_check] chr_vol=4730, boot_mode=8`. Ces logs **prouvent la demande d'activation du chargeur et une tension USB détectée**, mais PAS un courant net effectivement entrant dans la batterie. Aucun contournement PMIC n'a été fait.

## Comparaison avec la politique SELinux constructeur

Politique originale dans la sauvegarde `vendor-active-before-kpoc.img`, fichier `/etc/selinux/nonplat_sepolicy.cil` extrait en lecture seule (contenu temporaire CT700).

- `(allow fuelgauged fuelgauged_exec (file (read getattr execute entrypoint open)))`
- `(typetransition init_26_0 fuelgauged_exec process fuelgauged)`
- Le fichier `/(system\\/vendor|vendor)/bin/fuelgauged` est labellisé **`u:object_r:fuelgauged_exec:s0`**, alors que `/sbin/fuelgauged_static` est **rootfs:s0**, sans permission d'entrypoint pour le domaine fuelgauged.
- Binaire `/sbin/fuelgauged_static` extrait du BOOT 2020 sauvegardé : ARM32 EABI5 **statiquement lié**, 492 344 octets, SHA256 `47d62c2e608cc7dcd709b44da98fe92d5e793f1f321a8fb0d47a055db10e9b07`. Exécutable conçu pour MTK FG 2.0, utilise directement le protocole `FG_DAEMON_CMD_*`, `/dev/kmsg`, netlink noyau, réglages de jauge, potentiellement pertinent en KPOC.
- Configuration réelle du noyau 2020 : `CONFIG_MTK_HAFG_20=y`, `CONFIG_MTK_SMART_BATTERY=y`, `CONFIG_MTK_KERNEL_POWER_OFF_CHARGING=y`, `# CONFIG_SOC_BY_SW_FG is not set`. Ce montage utilise la jauge assistée MTK; le daemon semble important pour un SOC exploitable.
- Le noyau MediaTek 3.18 est documenté comme propriétaire du contrôle de charge et de la protection batterie; l'animation KPOC est une couche distincte : https://android.googlesource.com/kernel/mediatek/+/android-mtk-3.18/drivers/power/mediatek/Kconfig et https://android.googlesource.com/kernel/mediatek/+/android-mtk-3.18/drivers/power/mediatek/battery_common_fg_20.c

## Plan de correction technique (NON exécuté)

- Corriger **la cause SELinux d'entrypoint**, en conservant Enforcing et en n'ajoutant aucun domaine privilégié générique. Étudier un emplacement privé de l'exécutable OEM statique sur `vendor` avec type **fuelgauged_exec** exact et persistant sur ext4, plutôt qu'exécuter directement un binaire labellisé `rootfs`. Toute modification de file_contexts doit être vérifiée sur l'Android actuel; éviter les labels non persistants `chcon` en l'absence de règle correspondante et éviter de remplacer `/vendor/bin/fuelgauged` qui sert à Android normal.
- Arrêter la relance inutile du daemon dynamique en **KPOC seulement** : supprimer le `start fuelgauged` de l'action `on charger` OEM corrigée uniquement après l'installation et la validation d'une alternative fiable. Préserver le service normal `class main`, les correctifs RIL/fingerprint, la jauge sous Android et toutes les protections noyau.
- Évaluer séparément rétroéclairage et autosuspend : les écritures de luminosité et `FBIOBLANK` ne suffisent pas; le chargeur original MediaTek gérait aussi `request_suspend(true)`, réveil Power et événements USB. **Ne PAS forcer `/sys/power/autosleep=mem` depuis un service one-shot incapable de réveiller Android**.
- Une fois un correctif crédible assemblé, préflight et sauvegardes SHA des fichiers exacts, test KPOC bref, extraction immédiate du journal avant l'écrasement du buffer, vérification charge physique et rétablissement du rétroéclairage. Ne jamais décharger intentionnellement jusqu'à zéro.

## État

**Aucune modification du téléphone effectuée lors de cet audit**, pas de root/flash, aucun changement SELinux/PMIC. LCDv3 reste installé et affichait `?? 3,67 V` en KPOC tout en laissant l'écran rétroéclairé. Rooted debugging était désactivé au boot Android de 07:53; tentative `adb root` a confirmé le message officiel indiquant une activation nécessaire dans les options développeur. Ne demander cette action utilisateur que lorsqu'un correctif prêt et contrôlé exige réellement l'accès root.
