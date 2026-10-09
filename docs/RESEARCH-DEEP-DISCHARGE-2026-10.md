# DOOGEE S55 — Recherche ciblée « deep discharge » (09/10/2026)

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
