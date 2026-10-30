# DOOGEE S55 — KPOC v4 : jauge et écran (30 octobre 2026)

**Statut : préparée et testée hors ligne, NON INSTALLÉE sur le téléphone.**

## Faits observés

Le S55 entre en KPOC sans boucle Preloader/Fastboot. La v3 affiche ?? puis une tension réelle d'environ 3,67 V, mais laisse l'écran noir rétroéclairé. Après presque six heures en KPOC USB Pegasus, le pourcentage n'avait pas progressé. En revanche, la charge normale Android a augmenté la batterie de 30 à 41 % entre 07 h 54 et 09 h 52.

Le journal réel /proc/last_kmsg révèle deux services de jauge redémarrant à l'infini (toutes les cinq secondes environ) : exécution refusée pour /sbin/fuelgauged_static dans le domaine fuelgauged à cause du label rootfs, puis échec du démon dynamique en mode KPOC avant initialisation du linker Android. Le noyau rapporte une tension USB et une demande de charge active : ce n'est pas une preuve de courant net dans la batterie.

## Correctifs proposés

**Jauge :** réinstaller une copie exacte du binaire constructeur ARM32 statique sous /vendor/bin/s55_kpoc_fuelgauged_static, avec contexte SELinux fuelgauged_exec existant et domaine fuelgauged. Le service s55_kpoc_fuelgauged devient oneshot pour ne pas tourner en boucle si l'exécution échoue. La ligne start fuelgauged dans l'action on charger est neutralisée. L'ancien service fuelgauged class main reste inchangé et peut continuer à fonctionner sous Android.

**LCD :** conserver le programme LCDv3 actuel, qui dessine la batterie puis se termine après huit secondes. Au signal init.svc.s55_kpoc_bridge=stopped, init démarre un helper statique s55_kpoc_lcd_off sous le domaine fabricant mtk_hal_light, avec contexte d'exécutable mtk_hal_light_exec. Ce helper écrit seulement la luminosité LCD à zéro et relit la valeur. SELinux OEM autorise open/read/write de sysfs pour ce domaine. Cela contourne les limitations des précédents essais en domaines charger et vendor_init.

**Pas de mise en veille automatique forcée**, aucun changement PMIC, noyau, bootloader, courant de charge, protections batterie ou mode SELinux.

## Sécurité et preuves hors ligne

Les quatre fichiers vendor originaux destinés à être modifiés ont été lus sur le téléphone en lecture seule et copiés dans files/candidates/kpoc-v4-stage, qui conserve également les candidats. Le générateur scripts/kpoc-v4-vendor-plan.py refuse tout contenu source dont les SHA-256 divergent des empreintes mesurées. Les deux nouveaux types SELinux ont été résolus avec la bibliothèque libselinux de CT700 et vérifiés dans la politique MediaTek.

L'installateur privé backups/device-2026-10-29-kpoc/install-kpoc-v4-pegasus-NOT-RUN.sh est limité au S55 branché à Pegasus, exige Android normal, batterie >= 20 %, SELinux Enforcing, empreintes attendues et ADB root, puis sauvegarde les fichiers avant toute écriture et remonte vendor en lecture seule. Un rollback privé backups/device-2026-10-29-kpoc/rollback-kpoc-v4-pegasus-NOT-RUN.sh restaure exactement la v3 sans remplacer la partition vendor complète. Aucune commande Fastboot ou Flash n'est exécutée.

Le test **à blanc sur le vrai téléphone le 30/10 à 09 h 52** a réussi : Android, batterie, empreintes et sept candidats vérifiés. Aucun accès root ni fichier vendor modifié. Huit tests ciblés antérieurs vérifient les règles init, les fichiers sources et la commande LCD simulée. La validation en mode KPOC reste à faire après installation.

## Prochain essai

Ne réactiver Rooted debugging dans les Options développeur que lorsque l'installation est entièrement certifiée. Faire ensuite **un seul test manuel KPOC bref** (20 à 40 secondes), observer animation ??/V puis extinction physique de la lumière, redémarrer Android et extraire rapidement le dernier journal pour vérifier le succès de la jauge et du helper. Ne jamais laisser l'écran allumé en KPOC pendant des heures ni volontairement vider la batterie à 0 %.

**Limites :** la capacité de charger à batterie épuisée et l'extinction effective du LCD restent non certifiées tant qu'un test matériel n'a pas réussi.

## Références

Android 11 init : https://android.googlesource.com/platform/system/core/+/refs/tags/android-11.0.0_r3/init/

Android vendor_init : https://source.android.com/docs/security/features/selinux/vendor-init

Politique SELinux MediaTek fuelgauged : https://android.googlesource.com/device/mediatek/wembley-sepolicy/+/6d555ef61f95565c998147812af4d57ad3491263/non_plat/fuelgauged.te
