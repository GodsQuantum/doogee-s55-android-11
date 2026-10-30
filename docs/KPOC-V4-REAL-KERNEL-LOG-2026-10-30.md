# DOOGEE S55 — Diagnostic v4 après essai réel KPOC, 30 octobre 2026

## Journal réellement récupéré à 10 h 51

Téléphone redémarré sous Android normal, USB Pegasus `0e8d:201c`, ADB connecté, SELinux Enforcing, pas de root, batterie 45 %, 3 896 mV, 30 °C. Test précédent KPOC branché 10 h 22 min 54 s, recharge en mode KPOC `0e8d:2008`. Un changement de numéro de périphérique KPOC à 10 h 26 min 24 s a été noté, **sans retour Preloader observé** : ne pas qualifier ce trajet de parfaitement stable.

Copie brute exacte de `/proc/last_kmsg` préservée dans `backups/device-2026-10-29-kpoc/kpoc-v4-test-20261030-1051-last_kmsg.bin`, 262 206 octets, SHA256 `a8787b87f6b10a57e9e6e939e50745a4cb57395cd6ad9230f6ff28a92793a500`. Permissions 0600. Le fichier est une capture de RAM console **circulaire et fortement corrompue** (caractères manquants/remplacés) ; il ne couvre que les secondes de noyau ~617–779 et **a perdu l'initialisation KPOC des huit premières secondes**. Attention à ne pas interpréter absence de ligne comme absence de service.

### Confirmation d'une réparation réelle : fuel gauge

Sur des centaines de lignes conservées, le processus `[271:s55_kpoc_fuelga]` est continuellement actif. Les sorties constructeur `MTK_FG` indiquent notamment :
- communication réelle avec le démon jauge et `FG_DAEMON_CMD_NOTIFY_DAEMON` ;
- `FG_DAEMON_CMD_GET_INIT_FLAG, flag 1` ;
- `FG_DAEMON_CMD_SET_SOC, soc 45` ;
- `FG_DAEMON_CMD_SET_UI_SOC2, soc 45`, puis `battery_update_final ... soc:45 uisoc:45 uisoc2:45` ;
- `fg_charger_exist 1`, `fg_coulomb_is_charging 1` et des relevés `I=231, Iavg=243` au format spécifique MTK, ainsi qu'un `UI_SOC=45`.

Ce n'est donc plus le démon historique qui échoue en boucle avec `avc: denied { entrypoint }` ou ENOENT, contrairement à l'essai v3. **Le correctif des permissions de jauge v4 fonctionne pendant l'essai KPOC.** Le programme graphique affiche toujours `??` car `KPOC_SOC_CERTIFIED=0` est compilé volontairement dans son ancien binaire : ce blocage artificiel devra être retiré une fois l'affichage revalidé. Les mesures MTK suggèrent la charge active mais ne prouvent pas un courant net positif précis ni le comportement à batterie complètement déchargée.

Les threads du noyau rapportent `pchr_turn_on_charging(), enable=1` et `mt_kpoc_power_off_check chr_vol≈4,69 V boot_mode=8`.

### Écran toujours fortement rétroéclairé — événement manquant dans le journal

Le journal circonscrit ne contient **aucune** trace interprétable des services `s55_kpoc_lcd_off` ou `s55_kpoc_bridge`, ni de leur sortie ou d'un refus SELinux. **Cela ne prouve pas qu'ils ne sont pas lancés** : leurs appels de démarrage/fin se produisent à t≈0–8 secondes, hors du tampon conservé (t≈617–779 s).

L'échec du LCD v4 reste un problème à isoler selon les hypothèses :
1. le programme LCD n'est jamais démarré par `init` ;
2. il démarre mais échoue à ouvrir/écrire/lire la luminosité sous le domaine `mtk_hal_light` ;
3. il écrit bien zéro, mais le driver MTK/AAL/LCM/PWM ne coupe pas physiquement la lumière ou la rallume ;
4. la suspension complète `primary_display_suspend` puis `libsuspend` manque, car notre bridge s'arrête après huit secondes sans machine d'états.

Les fichiers d'origine et sources comparables démontrent que le chargeur constructeur lié à `libsuspend.so` possède `autosuspend_enable()` et `autosuspend_disable()` ; voir `docs/KPOC-ORIGINAL-POWER-DISPLAY-RESEARCH-2026-10-30.md`.

### Prochain relevé sans risque

Sous Android normal et **uniquement en lecture** : consulter `/sys/class/leds/lcd-backlight/{brightness,max_brightness,trigger,device}`, `/sys/class/graphics/fb0/{blank,state}`, `/sys/power/{state,autosleep,wakeup_count}`, `/sys/class/backlight`, les sources de réveil, les chemins LCD MTK exposés, le mode de boot et le service fuelgauged. L'accès root ADB peut être nécessaire, mais aucun changement ne doit être fait à la luminosité ou à la mise en veille tant qu'Android tourne.

Ensuite concevoir un **diagnostic KPOC instrumenté avec journal durable**, sans plusieurs heures d'attente : enregistrer les codes retour de `FBIOBLANK`, des sysfs de lumière et du processus d'extinction. La boucle d'origine (Power, VBUS, `wakeup_count`, `state=mem`) sera reconstituée seulement après cette mesure. Éviter une v5 empirique et les tests à 0 %.

**Statut final : jauge KPOC réparée sur le test observé ; écran toujours allumé, cause de la non-extinction pas encore différenciée. Aucun nouveau fichier du téléphone modifié pendant cette analyse.**

## 30 octobre 2026 — Lecture des pilotes en root ADB à 11 h 33

**Accès root temporaire confirmé :** `uid=0`, contexte `u:r:su:s0`, SELinux reste `Enforcing` ; aucune écriture n'a été faite dans `/sys`, `/proc` ou `/sys/kernel/debug` pendant l'audit.

**Interfaces vérifiées sous Android normal :** `/sys/power/state` annonce `freeze mem`, `/sys/power/autosleep` vaut `off`, `/sys/class/leds/lcd-backlight/brightness` valait `58` lorsque l'écran était allumé puis `0` lorsqu'il était en veille ; `max_brightness=255`, LED trigger `[none]`, étiquette `u:object_r:sysfs:s0`, pilote `leds-mt65xx`. `/sys/class/backlight` est absent. Framebuffer `/sys/class/graphics/fb0/name=mtkfb`, `/modes=U:720x1440p-0`, `state=0`. `/sys/kernel/debug/mtkfb` donne : **`LCM Driver=[hct_ili9881d_dsi_vdo_fhd_ivo_60_dzx]`, `Interface:DSI`, `State=Sleep`** pendant le sommeil Android. `/sys/kernel/debug/disp/lowpowermode` : `unknown mode(n)` ; lecture uniquement.

**Preuve hardware du bon chemin de coupure :** le `dmesg` du système Android normal montre, au réveil, la tâche `light@2.0-service` appelant `disp_pwm_set_backlight_cmdq(id=0x1, level_1024=233), old=0` puis `backlight is on (233), ddp_pwm power:(1)` ; à l'endormissement, `disp_pwm_set_backlight_cmdq(id=0x1, level_1024=0), old=56` puis **`backlight is off, ddp_pwm power:(0)`**. Même séquence observée deux fois (t=877/887 et 3375/3443 secondes du noyau). La rétroéclairage physique passe donc par le **DDP display PWM**, pas juste le dessin du framebuffer. En revanche, l'action v4 par écriture LED sysfs pourrait passer par un chemin non initialisé en KPOC : encore NON PROUVÉ.

**Preuve sur le vrai matériel du S55 :** extraction **en lecture seule** du DTB FDT v17 intégré au noyau 2020 actuellement sauvegardé : offset kernel compressé 8 010 937, blob 69 551 octets, `mediatek,disp_pwm`, `reg=<0x1100e000 0x1000>` sur `/soc/disp_pwm@1100e000`. Pilote `CONFIG_MTK_PWM=y`, `CONFIG_MTK_FB=y`, `CONFIG_MTK_LEDS=y`. La source analogue du PWM fait `disp_pwm_set_enabled(..., 0)` quand la consigne est zéro, sinon `ddp_pwm` reste actif : https://android.googlesource.com/kernel/mediatek/+/android-mtk-3.18/drivers/misc/mediatek/video/mt8173/dispsys/ddp_pwm.c. Le sous-système LCM est `hct_ili9881d_dsi_vdo_fhd_ivo_60_dzx` extrait directement de `/sys/kernel/debug/mtkfb` (pas inféré de l'Internet).

**Journal du dernier KPOC v4 :** le fait que les erreurs du helper LCD soient absentes du dernier `/proc/last_kmsg` est NON CONCLUANT (tampon circulaire tronqué commençant à t=617 s, alors que la demande LCD est à t≈8 s). Le nouveau daemon fuelgauge **fonctionne** et fixe SOC ≈45. Il faut instrumenter spécifiquement l'extinction LCD avec journal de codes retour open/write/read et FBIOBLANK, ou un moyen de conserver les premières secondes du log, avant un nouveau test physique. Le `on charger` du constructeur force `FG_daemon_log_level=7` très bavard, contribuant probablement à l'écrasement des anciens logs ; ne pas supprimer de traces sans preuve du nouveau fonctionnement. Une autre idée serait un diagnostic ultra court avec récupération rapide d'Android pour ne pas perdre les logs. AUCUN test KPOC supplémentaire n'a été effectué.

**Prochaine décision technique :** déterminer si `s55_kpoc_lcd_off` est déclenché et si la luminosité LED 0 engendre réellement les traces `disp_pwm_set_backlight_cmdq(...0)` et `ddp_pwm power:(0)`. Ne pas confondre `State=Sleep` Android avec `autosleep=off` : la veille de la dalle et celle du CPU sont deux fonctions distinctes. Ne pas écrire directement en MMIO sur 0x1100e000, ni forcer le sommeil CPU, ni modifier BOOT/PMIC.

## 30 octobre 2026 — v5 : corriger l'ordre de la séquence OEM, sans toucher la veille CPU

La cause probable est désormais plus précise. Le noyau original du S55 expose `LCM Driver=hct_ili9881d_dsi_vdo_fhd_ivo_60_dzx` et `mediatek,disp_pwm` au registre virtuellement accessible par le pilote (FDT : 0x1100e000). Sous Android, `light@2.0-service` provoque `disp_pwm_set_backlight_cmdq(...level_1024=0)` et `ddp_pwm power:(0)` lors du sommeil. Le code source MediaTek `primary_display_setbacklight()` saute les demandes lorsque l'écran est déjà `DISP_SLEPT` : https://android.googlesource.com/kernel/mediatek/+/android-mtk-3.18/drivers/misc/mediatek/video/mt8173/videox/primary_display.c. Cela explique plausiblement pourquoi v4, qui faisait FBIOBLANK à 6s puis LED=0 vers 8s, pouvait laisser l'écran allumé.

**Version v5 préparée hors ligne, non encore testée physiquement :**

- Bridge dessine pendant environ 8 s, **ne fait plus FBIOBLANK avant de terminer**.
- À `init.svc.s55_kpoc_bridge=stopped`, init démarre le helper `s55_kpoc_lcd_off` existant (domaine OEM `mtk_hal_light`), qui écrit LED=0 et vérifie la valeur retournée.
- À `init.svc.s55_kpoc_lcd_off=stopped`, init démarre le nouveau helper statique ARM64 `s55_kpoc_fb_off` (domaine `charger`, identique au bridge), qui ouvre `/dev/graphics/fb0` et appelle `FBIOBLANK(4)` **après** la tentative d'extinction du rétroéclairage, avec codes de sortie 0/succès, 10/open et 11/ioctl.
- Aucun `autosuspend=mem`, écriture de registres PWM/MMIO, nouveau daemon, modification jauge, PMIC, noyau ou bootloader. La fonctionnalité réveil Power reste à implémenter selon le modèle complet OEM lors d'une phase ultérieure, seulement si nécessaire.
- Candidats privés `files/candidates/kpoc-v5-bridge-UNINSTALLED-arm64` SHA256 `50bdd6b3d5ad0005998f0c09deba0d10f3e7142c7f202d1b2dff5c554d69b9a3` et `kpoc-v5-fb-off-UNINSTALLED-arm64` SHA256 `b763022619f23f2777b5ebf58e1edb877651301da53722fbda8369c15d322d38`.
- RC v5 : bridge `f1910b759ebd166935f529c05d409d12933c2e5ee02e08bf51adbc285f83c727`, LED `8038dcfb6d46d5219b470c8a6914aad631508b2204dc5d2ebfea6370bf883756`, nouveau FB `da97cde889c7df452bad629903f76e1ef04fb7d39510cd435aa59740d2e63129`.
- La v4 reste sauvegardée byte-for-byte dans `backups/device-2026-10-29-kpoc/v4-before-v5-*` avec empreintes originales; deux scripts privés fail-closed `upgrade-kpoc-v5-on-pegasus.sh` et `rollback-kpoc-v5-on-pegasus.sh`, bash et dash validés. Mode **dry-run sur S55 réel le 30/10 à 11:45 : PASS**, batterie 51%, fichiers source et cinq candidats vérifiés sans écriture.
- Tests hors ligne C x86 et Python : **10/10 PASS** ; compilation binaire ARM64 statique sans interpréteur ; `make lint PASS`.

**Important :** ce correctif inverse une séquence démontrée incorrecte, mais seul un prochain test KPOC pourra vérifier le PWM physique. Le helper FB sort après le helper LED, ce qui évite de solliciter le backlight une fois `DISP_SLEPT`. L'autosuspend complet constructeur reste absent : ne pas prétendre que CPU/KPOC passe en veille profonde ni que la charge à 0% est certifiée.
