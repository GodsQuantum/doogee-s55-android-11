> **Historical investigation (2026-10-30).** This report documents the backlight failure **before** v10. A later 2026-11-01 physical test observed successful full shutdown using a bounded PWM 1→0 transition. See [the current KPOC technical status](KPOC-BACKLIGHT-OFF-2026-11.md). Previous warnings about net charging and suspend remain valid.

# DOOGEE S55 — rétroéclairage permanent en KPOC : diagnostic approfondi (30/10/2026)

## Constat matériel reproductible

- Android 11 démarre normalement et s'éteint réellement avant l'insertion USB. Sur Pegasus, Preloader `0e8d:2000` apparaît seulement après le branchement, puis KPOC `0e8d:2008` est stable, sans boucle Fastboot.
- LCDv1, v2 et v3 exécutent bien la partie graphique KPOC ; LCDv3 affiche `??` et **3,67 V** (mesure matérielle) au lieu de fausses capacités `0 %` ou `50 %`. Le niveau Android récent était ~30 %.
- Après environ huit secondes, le framebuffer devient noir, mais **le rétroéclairage LCD reste fort**. Cela laisse le SoC et le LCD possiblement alimentés alors qu'on veut une charge éteinte économe.
- Plus récente observation USB : 30/10 01:58:22 Preloader puis 01:58:42 KPOC, identifiant 104 stable à 01:59:50 (pas d'ADB, normal pour ce mode). Aucun flash de BOOT ou de LK.

## Nouveaux éléments : firmware DOOGEE ET source OEM MediaTek

Image système constructeur d'octobre 2018 : `Doogee S55/18-10-27 .../system.img` (sparse, en lecture seule). Elle a été convertie *temporairement en /tmp tmpfs CT700*, avec purge automatique, et seuls quelques binaires ciblés ont été extraits avec `debugfs`, sans modifier le firmware ou le téléphone.

Dans le **vrai binaire constructeur `/system/bin/kpoc_charger` (29 296 octets ARM32)**, les chaînes sont :
- `/dev/graphics/fb0`, `Failed to blank fb0 device`, `Failed to unblank fb0 device`;
- `/sys/class/leds/lcd-backlight/brightness`;
- `/sys/devices/platform/battery/ADC_Charger_Voltage`, `/sys/class/power_supply/battery/batt_vol`;
- `stop_backlight 1` et plusieurs routines d'animation/gestion alimentation.

Le code MediaTek original (`vendor/mediatek/proprietary/external/charger/main.cpp`, `draw_thread_routine`) présente explicitement la séquence **animation → `stop_backlight()` → rafraîchissement du framebuffer → `ioctl(fb0, FBIOBLANK, FB_BLANK_POWERDOWN)` → `request_suspend(true)`**. Le `request_suspend(true)` appelle `autosuspend_enable()` si `CHARGER_ENABLE_SUSPEND` est compilé ; l'autosuspend Linux n'entre en veille que lorsque les wakeup sources le permettent. Les programmes LCDv1/v2/v3 **n'appellent jamais autosuspend_enable**, d'où une hypothèse solide d'absence de vraie mise en veille LCD. Les commandes luminosité seules peuvent être insuffisantes, notamment sur Mediatek framebuffer/DSI.

Sources étudiées :
- https://www.cnblogs.com/sayhellowen/p/6510633.html (source du chargeur propriétaire MTK, section `draw_thread_routine`)
- https://android.googlesource.com/platform/system/core/+/90dd14029414af26e64e3232f37c84feaa317ea8%5E2..90dd14029414af26e64e3232f37c84feaa317ea8/ (AOSP `request_suspend` et chargeur)
- https://android.googlesource.com/kernel/mediatek/+/android-mtk-3.18/drivers/misc/mediatek/leds/leds_drv.c (pilote MTK backlight)
- https://android.git.googlesource.com/kernel/common/+/702fdf3513b045f596f836d9a4b8672c76f11834/Documentation/ABI/testing/sysfs-power (autosleep wake locks).

La configuration **extraite effectivement du noyau 2020 actif sauvegardé**, sans boot ni flasher, contient :
```
CONFIG_PM=y
CONFIG_PM_SLEEP=y
CONFIG_PM_SLEEP_SMP=y
CONFIG_PM_AUTOSLEEP=y
CONFIG_PM_WAKELOCKS=y
CONFIG_PM_WAKELOCKS_LIMIT=100
CONFIG_PM_WAKELOCKS_GC=y
CONFIG_MTK_KERNEL_POWER_OFF_CHARGING=y
```

## Pourquoi ne pas ajouter aveuglément `write /sys/power/autosleep mem`

Ce serait une modification de **gestion d'alimentation du noyau**, pas un simple affichage. Les KPOC OEM continuent à surveiller le bouton Power, les transitions câble USB et l'animation pour pouvoir sortir de veille/redémarrer normalement. Notre bridge LCDv3 est `oneshot` et quitte après 8 s : il ne comporte aucun surveillant de touches ou d'événements USB. Activer l'autosuspend en même temps peut empêcher la sortie normale du KPOC (ou provoquer un cycle de réveils). L'absence de journaux KPOC récupérables rend dangereuse une nouvelle intervention supposée « simple ».

**Actions prudentes avant la suite** :
1. Au prochain boot Android normal, vérifier en lecture seule `/sys/power/autosleep`, `/sys/power/state`, `/sys/class/leds/lcd-backlight/brightness`, `/sys/class/graphics/fb0/blank`, `/proc/last_kmsg`, `/sys/fs/pstore`, et l'état des services chargeurs. NE PAS écrire `mem` sous Android ni en KPOC sans mécanisme validé de réveil et de rollback.
2. Examiner si `FBIOBLANK` de LCDv3 retourne une erreur, et si l'écriture `init` de la luminosité échoue réellement (journal KPOC absent pour l'instant). Ne pas assimiler l'écran noir à la mise en veille matérielle.
3. Concevoir un moteur adapté à l'original : animation contrôlée, gestion fiable `autosuspend_enable()/disable()`, gestion du bouton Power/charge USB et maintien des protections PMIC, **ou** porter l'exécutable constructeur avec son environnement ARM32 complet après vérification des dépendances/SELinux ; aucune installation expérimentale avant ces validations.
4. Ne pas provoquer de batterie à 0% à des fins de test ; mesurer ensuite charge réelle sur chargeur secteur 5V en comparant SOC et tension avant/après, en tenant compte des variations de charge.

## Statut

**LCDv3 reste installée et opérationnelle en KPOC (affichage `?? 3,67V`), mais PAS certifiée pour éteindre l'écran.** La charge électrique déchargée n'est pas certifiée. Ne pas toucher au bootloader (Orange State = déverrouillé), ne pas désactiver SELinux ni l'option off-mode-charge, ne pas réintroduire le BOOT expérimental qui provoquait des boucles.
