# DOOGEE S55 — Analyse constructeur de l'extinction, du LCD et de KPOC (30/10/2026)

**État : recherche approfondie terminée pour les mécanismes de base ; diagnostic matériel final encore conditionné au journal KPOC v4. Aucune écriture supplémentaire sur le téléphone dans cette phase.**

## Méthode et fichiers locaux réellement analysés

- Deux ROM DOOGEE Android 8 (juillet et octobre 2018) : LK original (`lk.img`), `system.img` sparse d'octobre converti uniquement en RAM CT700 et extrait par `debugfs`, `kpoc_charger` (29 296 octets), `libshowlogo.so` (67 120 o), `libhardware_legacy.so` et `libsuspend.so` (ARM32 20 336 o, ARM64 15 088 o).
- BOOT 2020 réellement sauvegardé (SHA256 `a2e6c0db60b2ecc22fe4fb42e2ca2db03b55188d44f195361e36c5dd6873f5ab`) : extraction du noyau 3.18.60 et de sa configuration `IKCFG_ST`. Le noyau décompressé compte 19 609 904 o, SHA256 `7c604466ab315f6e3520593f94a4c453bf233ba7643164aa6ae818d2711ecbbf`.
- SELinux constructeur extrait du VENDOR d'avant les correctifs KPOC, fichier `nonplat_sepolicy.cil`, et empreintes actuelles v4 épinglées dans `files/candidates/kpoc-v4-stage`.
- Événements USB réels Pegasus 30/10 : 10:22:35 Preloader `0e8d:2000`, 10:22:54 KPOC `0e8d:2008` toujours connecté à 10:25, sans boucle Fastboot.

## Chaîne exacte, depuis l'arrêt Android

1. **Android normal** : l'action Éteindre se termine, CPU est hors du mode normal. Une nouvelle alimentation VBUS déclenche la logique d'alimentation du PMIC ; elle ne signifie pas que le shutdown Android a échoué.
2. **Preloader + LK** : détection batterie/USB, mode KPOC/LPOC, contrôle de seuil de tension, logo initial et éventuelle transition vers le noyau. Les binaires LK de juillet (SHA `8c0e24...`) et octobre (SHA `837506...`) contiennent `mt65xx_backlight_on`, `mt65xx_backlight_off`, `mt_power_off : check charger`, `kernel charging` et contrôle de PWM. L'Orange State résulte du bootloader déverrouillé. La batterie « vide » initiale appartient à cette couche, pas au programme Android.
3. **Init en bootmode charger** : déclenchement `on charger` / classe `charger`, **pas** le chemin complet `late-init` d'Android. Les liens dynamiques, APEX, HAL et services Android peuvent donc manquer. Les anciens `fuelgauged` dynamiques échouaient avec ENOENT ; le gauge statique dans le ramdisk échouait SELinux `{ entrypoint }`.
4. **Noyau MediaTek 3.18** : `CONFIG_MTK_KERNEL_POWER_OFF_CHARGING=y` et `CONFIG_MTK_HAFG_20=y`; un thread de batterie mesure VCHR, tension/température, réalise les protections et invoque la commande d'activation du chargeur. Le journal antérieur prouve `pchr_turn_on_charging(), enable=1` et VCHR ≈4,73 V, **pas** l'entrée de courant nette dans la cellule.
5. **Daemon graphique KPOC** : fabricant `kpoc_charger` gère en continu animation, batterie, touches `/dev/input`, événements d'alimentation, rétroéclairage, framebuffer et veille/réveil. Notre programme v3/v4 dessine `?? / 3,74 V`, fait FBIOBLANK à environ 6 s, puis quitte vers 8 s : il n'a jamais remplacé cette machine d'états complète.

## Ce que fait réellement le binaire DOOGEE d'octobre 2018

- `readelf -d /system/bin/kpoc_charger` révèle treize bibliothèques liées dynamiquement, notamment `libshowlogo.so`, `libui.so`, `libhardware_legacy.so` et surtout **`libsuspend.so`** : copier l'exécutable Android 8 sous LineageOS 11 ne suffirait pas.
- Les **symboles importés** du vrai binaire sont `autosuspend_enable`, `autosuspend_disable`, `poll`, `ioctl` et `reboot`. Ses chaînes comprennent `/dev/input`, `/dev/graphics/fb0`, `/sys/class/leds/lcd-backlight/brightness`, `/sys/class/power_supply/{usb,ac}/online` et des messages de long appui Power.
- **Dans `libsuspend.so` constructeur** ARM32 et ARM64 : les chemins persistants visibles sont `/sys/power/state` et `/sys/power/wakeup_count`; on retrouve les symboles `autosuspend_enable`, `autosuspend_disable`, `autosuspend_wakeup_count_init`. En conformité avec les sources Android 8/9, le thread lit `wakeup_count`, écrit la même valeur atomiquement puis écrit `mem` à `state` si aucun événement n'a changé. Il attend puis redevient actif sur une source de réveil. Ce n'est PAS une simple écriture de `mem` dans `/sys/power/autosleep`.
- La source constructeur MediaTek `vendor/mediatek/proprietary/external/charger/main.cpp`, corroborée par le vrai exécutable, suit : désactiver la veille → activer affichage → redessiner → `stop_backlight` → `ioctl(FBIOBLANK, FB_BLANK_POWERDOWN)` → **`request_suspend(true)`**. Pour allumer, la séquence inverse désactive d'abord suspend et fait `FB_BLANK_UNBLANK`, puis allume le rétroéclairage. Un thread lit aussi les appuis Power via `poll`.

## Pourquoi écran noir ET rétroéclairage encore allumé

Il faut distinguer **quatre états** : contenu framebuffer noir ; moteur DSI/LCM suspendu ; rétroéclairage LED/PWM éteint ; CPU en veille. Nos corrections n'observent directement que le premier, et ont seulement tenté les deux suivants.

- Source MediaTek 3.18 `drivers/misc/mediatek/video/common/mtkfb.c` : `FBIOBLANK(4)` passe par `mtkfb_blank_suspend`, qui fait **retour immédiat si `disp_helper_get_stage()!=DISP_HELPER_STAGE_NORMAL`**. Sinon, appelle `primary_display_suspend()`. Un ioctl peut donc ne produire aucune mise hors tension matérielle dans certains états KPOC.
- Le même pilote expose `mtkfb_set_backlight_level` vers `primary_display_setbacklight` et un callback `mtkfb_pm_suspend`. Le noir ne prouve pas que DSI/LCM et LED sont hors tension.
- Le S55 a `CONFIG_MTK_FB=y`, `CONFIG_MTK_LCM=y`, `CONFIG_MTK_LEDS=y`, `CONFIG_MTK_PWM=y`, `CONFIG_PM_AUTOSLEEP=y`, `CONFIG_PM_WAKELOCKS=y`. **`CONFIG_BACKLIGHT_SUPPORT_LP8557` est désactivé** : ne pas supposer que la dalle utilise ce contrôleur I2C externe ; analyser le mode LED/BLS/PWM effectivement fixé par la carte et le panneau.
- Source MTK `drivers/misc/mediatek/leds/leds_drv.c` : l'action réelle dépend du `cust_led_list[MT65XX_LED_TYPE_LCD].mode` (PWM, PMIC, CUST_LCM, CUST_BLS_PWM). Au *shutdown noyau*, les chemins PWM désactivent le PWM ; ce n'est pas la même opération qu'afficher un framebuffer noir ou attribuer zéro à un fichier sysfs.
- Les versions v2 et v3 tentaient respectivement une écriture de luminosité depuis le domaine `charger`, puis une action `init`. v4 tente un binaire dans le domaine `mtk_hal_light` OEM. **On ne sait PAS encore si l'action v4 a été exécutée, si la valeur a été modifiée puis rétablie, ni si le driver a réellement coupé le PWM**. Seul le journal du dernier KPOC pourra distinguer ces branches.

## Erreurs de conception à éviter

- Garder un service graphique `oneshot` sans thread d'entrée ni séquence de réveil et activer ensuite arbitrairement le suspend global : risque d'absence de réaction normale à Power ou au débranchement.
- Contourner les labels SELinux, forcer une capacité artificielle (0%, 50%), pousser courant/thermique/PMIC ou charger ROM/boot/LK d'une variante S55 Lite.
- Ajouter un deuxième moteur UI KPOC concurrent à celui d'origine sans inventorier la classe init, les dépendances et les chemins de framebuffer.
- Déduire « charge effective » de la seule tension USB ou de `pchr_turn_on_charging(), enable=1` : le niveau SOC doit progresser pendant une fenêtre de charge éteinte vérifiée.

## Plan de réparation fondé sur les preuves

**Priorité 1 — Observer la v4 actuelle** : après le dernier essai physique (10:22–), sortir du mode KPOC, démarrer Android, reconnecter ADB et lire immédiatement `/proc/last_kmsg` et `pstore` en lecture seule (logs circulaires, susceptibles d'être écrasés). Rechercher `s55_kpoc_fuelgauged`, `s55_kpoc_bridge`, `s55_kpoc_lcd_off`, refus `avc`, sortie `status 0/127`, erreur `FBIOBLANK`, LED/PWM/display suspend. Si aucun log, les futures sorties du helper devront être envoyées explicitement à `/dev/kmsg`, testées hors ligne.
**Priorité 2 — Démontrer les états matériels** : sous Android normal seulement, mesures lecture seule de `brightness`, modes `/sys/class/graphics/fb0/blank`, éventuel `bl_power`, `/sys/power/state`, `/sys/power/wakeup_count`, `wakeup_sources`, GPIO/LCM/PWM exposés par le noyau (sans écrire pendant que l'écran est en service). Vérifier si l'écriture zéro dans le helper retourne OK et si le noyau remet la LED à un niveau non nul.
**Priorité 3 — Reconstituer UNE machine d'états KPOC** à la manière du constructeur : `init` et gauge chargés, animation affichée brièvement, `autosuspend_disable` avant `FB_BLANK_UNBLANK`, réduction LED et `FB_BLANK_POWERDOWN`, **thread wakeup_count + state mem** synchronisé, et gestion explicite des touches Power, des VBUS/unplug et du seuil batterie. La logique PMIC/kernels de protection reste native.
**Priorité 4 — Certification physique** : un seul essai bref du noir intégral et du réveil Power, absence de reboot Preloader ; ensuite un test de progression SOC/VBAT hors Android sur chargeur 5 V standard pendant une durée raisonnable ; aucun test jusqu'à 0 %.

## Sources primaires et analogues

- Kernel exact KPOC/charging : https://android.googlesource.com/kernel/mediatek/+/android-mtk-3.18/drivers/power/mediatek/battery_common_fg_20.c
- Framebuffer MTK 3.18 : https://android.googlesource.com/kernel/mediatek/+/4f43e6b499c6d194030df8d2506485db9d5165bd/drivers/misc/mediatek/video/common/mtkfb.c
- LED/PWM MediaTek : https://android.googlesource.com/kernel/mediatek/+/android-mtk-3.18/drivers/misc/mediatek/leds/leds_drv.c
- Chargeur propriétaire MTK, avec séquence de dessin, suspend et Power : https://www.cnblogs.com/sayhellowen/p/6510633.html
- AOSP 2018 libsuspend / wakeup_count : https://android.googlesource.com/platform/system/core/+/cfb8800e188a306d828357bed87134f61d2d3c19/libsuspend/autosuspend_wakeup_count.c
- AOSP charger : https://chromium.googlesource.com/aosp/platform/system/core/+/master/healthd/healthd_mode_charger.cpp
- Notes constructeur MediaTek KPOC (BSP) et boot mode LK/kernel : https://www.ziver.com.cn/wiki/ZM65/_static/Driver_Configuration_BSP_MT6761_P.pdf

**Décision : ne pas installer de v5, modifier l'autosuspend ni flasher le noyau/bootloader tant que les traces v4 de KPOC n'ont pas été étudiées.**