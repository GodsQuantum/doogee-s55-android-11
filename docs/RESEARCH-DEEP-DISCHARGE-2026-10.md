# DOOGEE S55 — Recherche ciblée « deep discharge » (09/10/2026)

## 9 octobre 2026, 19:53–20:03 — essai de récupération 100 % USB sur Pegasus

- USB absent à 19:53 ; les événements précédents montraient de longs cycles MediaTek Preloader (`0e8d:2000`), autre mode (`0e8d:2008`), puis fastboot (`0bb4:0c01`).
- Script de surveillance USB temporaire sous Pegasus, ciblé sur le numéro de série connu, **un seul redémarrage fastboot par séquence**, aucun flash/erase.
- Fastboot `reboot` accepté à 19:57:55, puis Android 11 GSI accessible ADB à 19:58:48. Le service Battery n'était pas prêt lors de l'énumération initiale.
- À 19:59:10 `dumpsys battery` : USB powered=true, charge 1 %, tension=0, température=0, « max charging current »=415200 µA (limite déclarée, PAS courant réel). `adb root` explicitement refusé : « ADB Root access is disabled by system setting » ; fichiers `/sys/class/power_supply/battery/*` refusent l'accès au shell sans root. **Ne pas déduire une tension réelle nulle de la sortie Android.**
- À 20:00:11 après boot complet `sys.boot_completed=1`, `settings put global low_power 1` a **réussi**, confirmé par `settings get global low_power = 1`. Écran mis en veille via `input keyevent 223`. La commande plus directe `cmd power set-mode 1` a échoué avec `SecurityException DEVICE_POWER` : ne pas la présenter comme ayant réussi.
- À 20:00:58 `dumpsys battery` : niveau 0 % malgré `status=2` (charge en cours déclarée), USB powered=true, limite max USB annoncée 98900 µA. Android s'est déconnecté vers 20:01:13.
- Second fastboot `reboot` à 20:02:15 accepté, Android/ADB récupéré 20:03:15.
- À **20:03:19** commande `adb reboot charger` acceptée (exit=0, aucune partition écrite). USB MediaTek Preloader a brièvement été présent à 20:03:22–25, puis plus d'appareil USB visible à 20:03:29. **ATTENTION : acceptation de la commande =/= preuve que le mode charge éteint fonctionne ni que la batterie prend réellement du courant** ; vérifier l'absence de boucle USB et l'état de l'écran/charge.
- Les fichiers de journal de ces tests sont dans `backups/device-2026-10-09/USB_CAPTURE_20261009.txt` et `USB_CHARGER_TRANSITION.log` (privés, ignorés par Git).
- Contrôle supplémentaire à **20:04:21–20:04:41** : la commande `adb reboot charger` n'a PAS stabilisé le mode chargeur. Le même cycle MediaTek est revenu : preloader `0e8d:2000` (20:03:22–25), périphérique `0e8d:2008` (20:03:48–20:04:07), nouveau preloader (20:04:10–13) puis **fastboot `0bb4:0c01`** à 20:04:21. Ne pas assimiler code de retour ADB 0 à une charge rétablie. Aucune écriture sur la partition boot n'est justifiée.
- Le téléphone est branché via le hub USB GenesysLogic `05e3:0610` sur Pegasus, appareil `1-5.1`. Le descripteur du hub indique **Self Powered** (autoalimenté). `bMaxPower` 100 mA du hub est sa propre consommation déclarée, **pas** une limite de courant de charge du smartphone. Les 98,9 à 583,5 mA de `dumpsys battery` sont des **limites négociées déclarées**, non la consommation réelle. Ne pas conclure que le hub est défectueux sur cette seule base.
- Aucun contournement des protections batterie, aucun patch flash. `off-mode-charge=1` reste inchangé. Seules modifications persistantes côté Android : réglage natif `settings put global low_power 1`. La réparation de la charge **n'est pas obtenue**. Sans lecture valide de VBAT/charge effective, aucune raison sûre de flasher des partitions; si la panne vient de batterie/PMIC/USB, une intervention logicielle par câble ne peut pas la résoudre.

## 9 octobre 2026, 15 h 49 — DÉCISION APRÈS TEST BOOTLOADER EN DIRECT

**Nouvelle preuve matérielle/firmware déterminante** : le S55 est toujours reconnu en fastboot sur Pegasus (serial vérifié). Une tentative UNIQUE de `fastboot boot` avec le TWRP 3.1.1 déjà testé et vérifié SHA256 `bbf6c46cb001f9b14c7476beb73f9d2ae4398619c3b855498cca1a8276436038` a été refusée **AVANT chargement** :

```text
Sending 'boot.img' (14110 KB) FAILED (remote: 'low power, need battery charging.')
```

Cette commande demande le lancement temporaire en RAM : **aucune partition flashée, pas de wipe et pas d'effacement**. Le refus vient **du bootloader natif** et non de crDroid, TWRP ou ADB. Il établit un niveau de charge jugé trop bas pour booter, **mais ne prouve pas quel composant empêche la recharge**.

Le bootloader actif indique `off-mode-charge: 1` ; le kernel actif 2020 contient `CONFIG_MTK_KERNEL_POWER_OFF_CHARGING=y`, `CONFIG_MTK_SMART_BATTERY=y`, `CONFIG_MTK_HAFG_20=y`. Le ramdisk actif comprend charger/fuelgauged et les déclencheurs `on charger`. **Ne PAS désactiver les seuils de sous-tension pour permettre un boot artificiel.**

**Fait externe corroborant :** discussion Doogee S55 datée de septembre 2018 (avant crDroid) signalant déjà un affichage « 0 % après deux heures de charge » — https://4pda.to/forum/index.php?showtopic=915045&st=100 . Ce n'est pas la preuve d'une défaillance identique, mais les difficultés de recharge existaient sur stock.

### Réparation concrète à réaliser dans cet ordre (sans modification du téléphone par logiciel)

1. **Contrôle électrique indispensable** : vérifier alimentation USB 5 V, chute de tension au port et **courant réel** entrant avec un instrument adapté, puis mesurer la tension de la batterie à vide et pendant un essai de charge, en respectant les consignes de sécurité Li-ion. Ne pas utiliser les 0 mV / 0 °C de `dumpsys battery` comme une mesure de cellule.
2. Si le 5 V arrive correctement, que la cellule ne se charge pas, chute à la tentative de démarrage ou présente une résistance interne excessive : **remplacer la batterie**. Référence commerciale V715874P, nominal 3,8 V, 5 500 mAh, **à confirmer sur l'étiquette du téléphone**. Une batterie neuve d'origine récente est préférable à un stock ancien de 2018. Sources : https://www.pour-batterie.com/doogee-Batterie-v715874p-p6266.htm et https://www.movileo.com/s55 (catalogue batterie et module S55).
3. Si le courant n'arrive pas jusqu'à la carte : inspecter/mesurer le **connecteur Micro-USB et la carte fille de charge**, réf. DOGS55-01 (https://www.fixshop.eu/spare-parts-cell-phone-spare-parts-connectors-charging-connector-pcb-board/doogee-s55-charging-connector-pcb-board/) ou équivalent S55 ; ne pas confondre avec S55 Lite sans vérification.
4. Si batterie et port sont bons mais pas de courant de charge, diagnostic PMIC/NTC/flex par réparateur. **Ne pas alimenter de force une batterie lithium profondément déchargée** ni court-circuiter les protections.
5. Après intervention physique, vérifier **charge sur secteur téléphone éteint**, démarrage autonome après faible charge, montée du pourcentage, capacité utile, Android et fingerprint. Ensuite seulement diagnostiquer les wakelocks/modem/Doze de crDroid pour l'autonomie.

**Aucun remplacement logiciel au hasard n'est justifié** : les codes source MediaTek 3.18 confirment que KPOC est conditionné par l'état réel du chargeur, de la batterie et de sa température (https://android.googlesource.com/kernel/mediatek/+/android-mtk-3.18/drivers/power/mediatek/battery_common.c). Ne pas flasher les références 2018 ou 2019 : kernel actif compilé juin 2020 et correctifs vendor/fingerprint présents.

**Pièces identifiées, à confirmer physiquement avant achat (tarifs affichés octobre 2026)** : Movileo Espagne référence une batterie d'origine S55 à **13,50 €** et une carte de charge + microphone S55 à **16,80 €** sur https://www.movileo.com/s55 ; il est essentiel d'obtenir une batterie réellement récente et non un stock vieilli. Autre batterie V715874P 3,8 V / 5500 mAh annoncée à **28,01 €** sur https://www.pour-batterie.com/doogee-Batterie-v715874p-p6266.htm ; carte de charge OEM DOGS55-01 sur https://www.fixshop.eu/spare-parts-cell-phone-spare-parts-connectors-charging-connector-pcb-board/doogee-s55-charging-connector-pcb-board/ (stock à confirmer). Éviter l'achat des deux pièces sans vérifier d'abord la tension au port et à la cellule. Une ouverture fragilise l'étanchéité IP68 ; joint à refaire et à tester.

**Dernier état :** fastboot détecté à 15 h 49, puis absence de périphérique USB sur Pegasus à 15 h 51, sans commande de flash ni redémarrage supplémentaire. Aucune modification matérielle ni réparation définitive n'a encore été effectuée. Les seules sauvegardes du projet concernent `boot`, `lk` et `lk2` (pas un backup complet de userdata ou vendor). Ne jamais les appeler « sauvegarde complète du téléphone ».

## Mise à jour : accès matériel et comparaison de la ROM ACTIVE (9 octobre 2026, 14:48–15:00)

**Résultat du travail réel : lecture des partitions réussie, batterie non réparée.** MTKClient 2.1.4 (git `cd25cf9` du 12 septembre 2026) a pu se connecter au MT6750/MT6755, HW code 0x326, et lire la GPT. Son diagnostic indique SBC/SLA/DAA non activés. Il a ensuite lu SANS ÉCRIRE les partitions `boot` (16 Mio), `lk` (1 Mio) et `lk2` (1 Mio). La connexion au preloader était instable et le fastboot avait disparu avant toute demande de reboot ; aucune commande de reboot n'a été nécessaire pour cette lecture.

Les fichiers sont stockés **uniquement en sauvegarde privée ignorée par Git** dans `backups/device-2026-10-09/`. Le fichier `SHA256SUMS` est relatif au dossier, les vérifications Cloud9 sont OK, permissions 0600, propriétaire arezki. Ne PAS les publier.

- boot : SHA256 `a2e6c0db60b2ecc22fe4fb42e2ca2db03b55188d44f195361e36c5dd6873f5ab`
- lk = lk2 : SHA256 `5fe80cc3990fbe26f2f301792243c683ae9e976736f2b7bb9b7194e32bbb7dbc`
- Analyse reproductible : `python3 scripts/analyze-s55-active-boot.py`, aucune extraction ou écriture sur le smartphone.

**Kernel actif : Linux 3.18.60+ compilé le 29 juin 2020 (20:02:29 CST).** Il est PLUS RÉCENT que les références stock juillet/octobre 2018 et que le firmware 2019 mentionné ci-dessous. Une source indépendante documente un DOOGEE S55 utilisant un firmware/modem de juin 2020 : https://www.phonecopy.com/en/phones/view/doogee_s55 . Ne pas supposer pour autant une correspondance bit-à-bit entre les versions sans firmware complet validé.

Configuration **vérifiée dans le vrai kernel actif** par décompression puis IKCONFIG (identique sur ces points aux stock 2018) :
- `CONFIG_POWER_SUPPLY=y`
- `CONFIG_MTK_SMART_BATTERY=y`
- `CONFIG_MTK_KERNEL_POWER_OFF_CHARGING=y`
- `CONFIG_MTK_HAFG_20=y`

Ramdisk actif contient `sbin/charger` (833 928 octets), `sbin/fuelgauged_static` (492 344 octets), `init.rc` avec `on charger` → `class_start charger` et le déclencheur `sys.boot_from_charger_mode=1`. Les binaires charger et fuel gauge actifs sont différents des références 2018, **sans preuve de dysfonctionnement**. Le kernel et le ramdisk sont eux aussi différents. `lk` et `lk2` actifs sont identiques et contiennent les routines et protections basse tension KPOC.

**Conclusion mise à jour :** la panne n'est PAS due à l'absence de KPOC, de fuel gauge, de ramdisk charger ou à `off-mode-charge=0`. Elle peut venir d'une exécution défaillante de ces services, d'une batterie âgée/de haute résistance interne, du port/circuit de charge ou d'une télémétrie Health HAL inadaptée à Android 11. La tension=0 et la température=0 de `dumpsys battery` sont **invalides** et ne constituent PAS une mesure physique de la cellule. Ni l'usure de la batterie ni le défaut PMIC ne sont prouvés.

**Décision : AUCUN FLASH de boot, lk, preloader, vendor ou GSI** tant que la capacité de charge réelle n'est pas mesurée. Écarter la ROM 2019 comme « mise à niveau » : elle est antérieure au kernel actuellement installé. Préserver en priorité fingerprint, partitionnement et données. Suite sûre : mesure du courant USB et tension de la cellule à la prise de charge (par un professionnel si appareil de mesure absent), puis diagnostic Android du fuel gauge et des wakelocks uniquement quand le téléphone peut démarrer de façon stable.

## Historique de l'enquête et hypothèses

État : **non résolu**. S55 en fastboot sur Pegasus à 14:27 le 09/10. Aucune écriture sur le téléphone autorisée avant vérification des tensions et du boot réellement installé. Ne pas confondre les firmwares de référence et les partitions *actives*.

## 1. Faits mesurés sur le S55

- Modèle : S55 (pas S55 Lite), MediaTek MT6750/nom kernel mt6755, ARM64 A-only non-SAR. crDroid 7.16 GSI Android 11, vendor Oreo et fix fingerprint MicroArray en fonctionnement avant incident.
- Identifiant fastboot vérifié : K50V1_64 ; bootloader déverrouillé ; **off-mode-charge: 1**. Le basculer à 1 à nouveau n'apporte rien. Ne jamais le mettre à 0.
- Sur Pegasus, à 14:06-14:07 : Android a fini son démarrage (sys.boot_completed=1), mais l'écran Android rapporte 1 % et le service batterie annonce 1 %, USB powered=true, maximum USB current 183500-398100 µA, tension 0 mV, température 0 °C ; charge counter 4708000 µAh. Ces **valeurs ne donnent pas la vraie tension de cellule, la vraie température ni le courant instantané** ; le charge counter n'est pas synonyme de charge réelle disponible.
- Lecture /sys/class/power_supply/battery bloquée pour ADB shell par permissions. À 14:07, perte de connexion. Deux essais supplémentaires ont ramené en preloader/BROM/fastboot sans ADB durable. **Ne pas répéter les boots à 1 %**.
- Fastboot getvar battery-voltage, battery-current, battery-soc : aucune donnée sur ce LK.

## 2. Investigation read-only des 2 firmwares stock locaux

Sous /srv/storage/cloud/arezki/Projets/Phones/Doogee S55/Doogee S55 :
- Firmware juillet 2018 et octobre 2018 (deux jeux boot.img + lk.img + vendor.img ; NE PAS FLASHER À L'AVEUGLE).
- Config Linux kernel extraite directement des deux boot.img avec extract-ikconfig :
  - CONFIG_MTK_SMART_BATTERY=y
  - CONFIG_MTK_KERNEL_POWER_OFF_CHARGING=y
  - CONFIG_MTK_HAFG_20=y
- Dans les deux lk.img, des traces Kernel Power Off Charging (KPOC), protection batterie basse tension, contrôle tension chargeur et commande OEM off-mode-charge.
- Dans les ramdisks des deux boot.img (extraits en mémoire, sans modification) : /sbin/charger (833928 octets) et /sbin/fuelgauged_static (492396 octets), init.rc contenant « on charger / class_start charger » et « on property:sys.boot_from_charger_mode=1 ».
- **Conclusion limitée** : la chaîne de recharge hors Android est présente dans les images STOCK. La partition boot réellement installée n'a pas encore été dumpée ; la présence des programmes ne garantit pas une recharge efficace si batterie/port/PMIC sont défaillants.

## 3. Vérifications web effectuées (octobre 2026)

- Code MediaTek 3.18 : KPOC nécessite le support kernel et le service de charge ; le code prévoit aussi batterie intelligente/fuel gauge, protections tension et température. Il est dangereux de retirer les protections basse tension juste pour forcer un boot.
- AOSP : « charger mode » est distinct du démarrage Android normal, avec seuil minimal pour démarrer ; un GSI système à lui seul ne recrée pas un service absent du ramdisk.
- Un **firmware constructeur daté 2019-11-08** existe dans les archives 4PDA et journaux de réparateurs (DOOGEE-S55-Android8.0-20191108) ; le projet ne contient pour l'instant que ceux de 2018. **Pas de preuve qu'il corrige la charge**, pas de checksum/paquet validé. Ne pas installer le firmware complet ni mélanger LK/vendor/boot sans analyser les révisions et conserver le fix fingerprint.
- La liste actuelle TrebleDroid présente en 2026 de nouvelles GSI Android 16/17 généralement system-as-root ; le profil historique non-SAR du S55 ne permet pas de remplacer directement la GSI testée. **La version Android plus récente n'est pas la correction batterie**.
- En octobre 2026, deux références de pièces compatibles identifiées (à vérifier sur le matériel avant commande) : batterie **V715874P 3,8 V / 5 500 mAh**, carte fille du connecteur USB **DOGS55-01**. Demander de préférence les pièces officielles à DOOGEE. L'ouverture d'un téléphone IP68 nécessite une remise en état du joint ; ne pas présumer qu'il reste étanche après réparation.
- Chargeur fourni annoncé 5 V / 2 A (10 W), Micro-USB ; un chargeur USB PD/QC « rapide » n'ajoute pas automatiquement de puissance sur cet appareil.

## 4. Classement hypothèses, pas des diagnostics définitifs

1. **Cellule fatiguée / résistance interne élevée / protection batterie / circuit de charge / port** : forte présomption, car téléphone de 2018, recharge une nuit sans remonter au-delà de 1 %, démarrage de courte durée. Ne peut être prouvé sans mesure réelle.
2. **Défaut logiciel de la chaîne KPOC active** : plausible, malgré flag bootloader 1, si boot.img modifié (noverity/ramdisk) ne contient plus les services ou si kernel actif diffère. À prouver par comparaison binaire.
3. **Lecture / estimation fuel gauge incohérente** : vraisemblable au vu des valeurs 0, à distinguer d'un défaut physique du capteur/NTC et des permissions sysfs.
4. **Wakelocks / modem / Google Services / crDroid idle** : à diagnostiquer seulement après recharge normale et boot durable ; ne suffit pas à expliquer à lui seul l'absence de charge hors Android.

## 5. Protocole de résolution minimal et ordonné

### Phase A — récupération stable sans flash

- Ne pas refaire des essais successifs de démarrage à 1 %. L'ordinateur offre un courant USB potentiellement inférieur à une alimentation 5 V / 2 A adaptée.
- La charge après toute une nuit n'ayant déjà pas récupéré le téléphone, **NE PAS redemander une nuit de charge**. Si nécessaire, faire mesurer par un professionnel **le courant entrant USB (ampèremètre USB 5 V)** et la **tension de la batterie hors charge et sous sollicitation** ; l'absence d'absorption, une forte chute de tension ou la batterie qui chauffe orientera vers le hardware. Ne pas court-circuiter, forcer ou « réveiller » directement une cellule lithium sur une alimentation de labo sans procédure métier sécurisée.
- Si le chargeur secteur alimente mais le téléphone boucle quand même : tester hors Android/étudier l'intégrité du chemin KPOC, pas d'optimisation GSI en premier.
- Si batterie endommagée/gonflée/chaude : arrêter, réparation spécialisée.

### Phase B — preuve logicielle avant correction

- Lorsque l'alimentation permet une session durable : sauvegarder **les partitions boot, recovery, lk, lk2, vendor et l'état GPT** en lecture seule, dans un dossier privé de sauvegarde, pas dans Git. Garder des SHA256 et préserver données existantes / NVRAM / IMEI.
- Méthode de lecture : ADB root autorisé si disponible, sinon **bkerler/mtkclient** en preloader/BROM pour lecture seule, avec DA compatible, sans payload destructeur ; documenter le mode et faire une première lecture limitée (boot/lk) avant toute grande extraction.
- Comparer le **boot.img actif** aux originaux : config KPOC/smart battery/HAFG, ramdisk /sbin/charger et fuelgauged, init « on charger », properties, éventuelles modifications noverity, chiffrage fstab, SELinux.
- Si éléments KPOC absents du boot actif, développer/tester une image boot préservant ses correctifs avec une image de référence exacte ; **pas de flash d'une image STOCK brute**, pas de remplacement du vendor qui écraserait le patch MicroArray. Valider hors appareil et disposer d'un rollback réel avant toute écriture.
- Si chaîne KPOC intacte, priorité au diagnostic batterie/USB/PMIC ; ne pas créer de daemon custom comme substitut.

### Phase C — autonomie/crDroid lorsque charge stable

- Mesurer d'abord tension et température réelles, pourcentage sur plusieurs cycles partiels, courant de charge, interruptions USB.
- Capturer dumpsys battery, batterystats --charged, dumpsys power/deviceidle, traces suspend/wakeup, consommation écran éteint, radio réseau/cellular, GApps ou MicroG, localisation, WLAN/BT ; comparer sur un intervalle représentatif, sans vider volontairement la batterie à 0.
- Optimiser seulement les coupables mesurés. Priorité réglages NATIFS Android : battery saver, mode veille, restriction apps à wakelocks confirmés. Ne pas désactiver services de sécurité ni protections thermiques, ne pas supprimer PHH/vendor services au hasard, ne pas ajouter de programmes de fond qui aggraveraient la consommation.
- Validation : recharge autonome hors Android à faible pourcentage, maintien de la charge, démarrage sans PC, repos prolongé mesuré, fingerprint après reboot, audio/NVRAM, Wi-Fi, données, aucune régression sur /data.

## 6. Sources

- AOSP MediaTek KPOC : https://android.googlesource.com/kernel/mediatek/+/android-mtk-3.18/drivers/power/mediatek/Kconfig
- AOSP charge mode Android 8 : https://android.googlesource.com/platform/system/core/+/refs/tags/android-cts-8.0_r26/healthd/healthd_mode_charger.cpp
- ABI Linux power_supply : https://docs.kernel.org/power/power_supply_class.html
- DOOGEE S55 2019 firmware listing : https://4pda.to/forum/index.php?showtopic=915045 et https://www.martview-forum.com/threads/post-here-successfully-unlocked-repaired-flashed-phones-with-pandoras-2021.42895/page-2
- TrebleDroid GSI list : https://github-wiki-see.page/m/TrebleDroid/treble_experimentations/wiki/Generic-System-Image-%28GSI%29-list
- MTKClient read-only partitions : https://github.com/bkerler/mtkclient/blob/main/README-USAGE.md
- DOOGEE service pièces : https://care.doogee.com/Spare-parts-price-List
- Batterie V715874P : https://www.pour-batterie.com/doogee-Batterie-v715874p-p6266.htm
- Carte de charge DOGS55-01 : https://www.fixshop.eu/spare-parts-cell-phone-spare-parts-connectors-charging-connector-pcb-board/doogee-s55-charging-connector-pcb-board/
