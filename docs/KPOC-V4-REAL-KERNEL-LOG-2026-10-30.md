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
