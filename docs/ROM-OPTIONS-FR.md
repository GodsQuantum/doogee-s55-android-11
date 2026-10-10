> **Rapport historique antérieur au passage à LineageOS le 10 octobre.** LineageOS 18.1 + NikGapps a ensuite démarré et a été contrôlé sur notre S55. Les mentions ci-dessous « non installé / non testé » sont conservées comme historique, **pas comme état actuel**. Voir [audit installateur](INSTALLER-SAFETY-AUDIT-2026-10.md) et [rapport migration](LINEAGE18-MIGRATION-ROOT-CAUSE-2026-10.md).

# DOOGEE S55 — Versions Android et autres OS (recherche octobre 2026)

> **Important — état réel :** ce document compare des candidats. **Seuls Android 11/crDroid 7.16 et les correctifs décrits dans les guides historiques ont été effectivement validés sur notre S55.** Aucune ROM alternative de cette page n'a encore été démarrée sur l'appareil. Le téléphone se recharge actuellement sur secteur, sans connexion USB à Pegasus ; ne rien flasher pendant la charge.

[README](../README.md) · [Installation Android 11 GApps](INSTALL-GAPPS-FR.md) · [Charge et autonomie](BATTERY-CHARGING.md) · [English](ROM-OPTIONS-EN.md)

## 1. Matériel et contraintes PROUVÉES

- DOOGEE **S55** (pas « S55 Lite »), MT6750/MT6755, CPU ARM64, 4 Go de RAM, eMMC 64 Go.
- Bootloader déverrouillé, fastboot MTK, **partition A-only, non-system-as-root (non-SAR)** ; vendor Oreo, **VNDK 26**.
- Kernel actif extrait de l'appareil : **3.18.60+**, compilé le **29 juin 2020**. Ne pas confondre date du kernel et disponibilité d'un paquet de ROM constructeur 2020 vérifié.
- Partition /system courante : **3 263 168 512 octets** après redimensionnement documenté dans ce dépôt. L'image système d'origine avait une géométrie différente.
- Déjà validé : crDroid 7.16 / Android 11, y compris patch SELinux/NVRAM, chiffrement fstab et MicroArray fingerprint.
- Backups privés existants : **boot, lk, lk2** au 09/10/2026, SHA256 vérifiés. **Ils ne constituent pas une sauvegarde complète** de vendor, userdata, nvram, nvdata, modem, partitions GPT ou de l'identité radio.
- Historique de charge : à 0–1 % sur USB de Pegasus, fastboot a répondu « low power, need battery charging ». Le propriétaire rapporte ensuite **20 % de charge sur secteur**, ce qui prouve qu'une recharge est possible sur une alimentation adaptée. Ne pas conclure que batterie/PMIC est mort. Chercher prioritairement charge secteur vs USB, état réel de la jauge et consommation Android.
- La batterie doit monter suffisamment et rester stable **avant** tout flash. Ne pas débrancher le chargeur pour tester sans nécessité.

## 2. Candidats : classement concret

| Rang | ROM/OS | Android | Fichier et disponibilité | Bascule sur S55 | État |
|---|---|---|---|---|---|
| A (référence) | crDroid 7.16 | 11 | `crdrom-v316-220330-arm64-agZ.img` sur Cloud9, GApps intégrées | non-SAR, GApps, patch fingerprint décrit | **VALIDÉ auparavant** ; charge actuellement à diagnostiquer |
| B (priorité quand chargé) | LineageOS 18.1 AndyYan | 11, correctif janvier 2024 | `los18.img` et `los18.img.xz` déjà présents | non-SAR, ARM64 ; **nécessite essais S55** | Statique OK, démarrage non testé |
| C (expérimental) | LineageOS 20 AndyYan/TrebleDroid | **13**, correctif septembre 2025 | `gsi_los20.img`, construit en octobre 2025 | **system-as-root (SAR), incompatible en remplacement direct de la /system actuelle** | Statique OK, migration boot/init/vendor à développer, démarrage non testé |
| D (recherche à long terme) | LineageOS 21, TrebleDroid Android 14 | 14 | Images SAR officielles/non officielles disponibles | adaptation SAR + ancien vendor Oreo / 3.18, risques majeurs | Aucune image locale qualifiée |
| E (veille) | Android 15 / 16 / 17 GSIs | 15–17 | GSI Google et communautés publiées en 2026 | destiné aux appareils récents, surtout SAR ; aucun port S55 opérationnel vérifié | **Non validé, pas à flasher** |
| F (retour) | Stock DOOGEE Oreo | 8 | Firmwares complets juillet et octobre 2018 présents | compatibilité native | Versions stock connues ; à garder en récupération seulement |

**Pourquoi Android 17 ne doit pas être choisi uniquement à son numéro :** les GSI officielles exigent un matériel Treble récent et Google a **abandonné dès Android 12 les contournements permettant aux anciens appareils Android 8.x partiellement Treble de fonctionner**. Ce S55 a en plus des interfaces MediaTek et un démarrage non-SAR. Il ne suffit pas qu'un fichier porte le nom « arm64 » ni qu'il tienne dans /system.

Documents de référence :
- Google [GSI prerequisites](https://developer.android.com/topic/generic-system-image)
- Google [legacy GSI supprimé avec Android 12](https://source.android.com/docs/core/tests/vts/gsi)
- Google [transition non-A/B vers system-as-root](https://source.android.com/docs/core/architecture/partitions/system-as-root)
- Google [GSI Android 17, juin 2026](https://developer.android.com/about/versions/17/gsi-release-notes)
- [TrebleDroid GSI list](https://github-wiki-see.page/m/TrebleDroid/treble_experimentations/wiki/Generic-System-Image-%28GSI%29-list)

## 3. Résultats de tests HORS téléphone (Cloud9)

Commande (lecture seule, aucun ADB/fastboot, aucun montage) :

```bash
python3 scripts/audit-rom-candidates.py
```

| Image | Android / API | Correctif sécurité contenu dans le build | Mise en page | Taille | Marge sur /system actuelle |
|---|---|---|---|---:|---:|
| crDroid GApps 2022 | 11 / 30 | 2022-03-05 | non-SAR | 3 088 048 128 o | 167,0 Mio |
| LineageOS 18.1 2024 | 11 / 30 | 2024-01-05 | **non-SAR** | 2 055 483 392 o | 1 151,7 Mio |
| LineageOS 20 2025 | 13 / 33 | 2025-09-05 | **SAR** | 2 242 465 792 o | 973,4 Mio |

Le build `gsi_los20.img` déclare `lineage_arm64_bvN` et possède une racine SAR `/init` pointant vers `/system/bin/init`. L'image ext4 est marquée `shared_blocks`, donc **ne pas la monter/écrire directement**. La taille en dessous de /system ne la rend pas bootable.

Le build `los18.img` est réellement non-SAR au niveau des fichiers de son image, malgré un libellé `ro.build.description` comportant « _bvS ». **L'anatomie du système prime sur un champ descriptif potentiellement générique.** Le fichier local compressé fait 617 124 608 octets, son intégrité XZ est vérifiée, et sa décompression correspond octet pour octet à `los18.img` (SHA256 de l’image : `6ff112b937a5043aee862b48330a3895bb040461cdbe4304b342468600c7aaf5`), cohérent avec [AndyYan arm64_avS du 21 janvier 2024](https://sourceforge.net/projects/andyyan-gsi/files/lineage-18.x/) ; vérifier sa provenance cryptographique avant flash.

Comparaison de builds AndyYan : [Lineage 18.1 janvier 2024](https://sourceforge.net/projects/andyyan-gsi/files/lineage-18.x/) et [LineageOS 20 octobre 2025](https://sourceforge.net/projects/andyyan-gsi/files/lineage-20-td/).

**Tests non encore possibles hors téléphone :** démarrage, modem, Wi-Fi, GPU/HW codec, caméra, fingerprint au 2e redémarrage, TWRP, gestion de charge hors Android. Ne pas écrire « testé et fonctionnel » pour ces points.

## 4. Google Play/GApps sans alourdir le S55

Le besoin est **Google Play + services indispensables**, pas toutes les applications Google préinstallées. Pour 4 Go de RAM et un MT6750, privilégier NikGapps **Core** (ou un équivalent minimal vérifié), puis installer Gmail/Maps/etc. via Play si nécessaire.

Fichiers réellement téléchargés depuis le projet [NikGapps SourceForge](https://sourceforge.net/projects/nikgapps/files/Releases/) et contrôlés par lecture ZIP intégrale :

| Android | Archive locale privée | Taille octets | SHA256 locale |
|---|---|---:|---|
| 11 | `files/candidates/NikGapps-core-arm64-11-20260204-signed.zip` | 80 480 608 | `a56ad7da66e51a6cd1af0b0fb39a1ac167739161624115276b7f8d00633fd0f8` |
| 13 | `files/candidates/NikGapps-core-arm64-13-20260204-signed.zip` | 110 851 336 | `d969df417bc3ea9c79e4219c8dd955d8d5f6d31597cbe5f88dc51518a3fc9613` |

Les SHA256 sont **mesurés localement** ; pas de validation de signature publique indépendante. ZIP testée sans erreur, pas encore installée. Ne JAMAIS installer le paquet Android 13 sur la ROM Android 11. Il est interdit d'ajouter ces fichiers binaires au dépôt Git public.

- Source exacte [NikGapps Core 11 du 4 février 2026](https://sourceforge.net/projects/nikgapps/files/Releases/Android-11/04-Feb-2026/)
- Source exacte [NikGapps Core 13 du 4 février 2026](https://sourceforge.net/projects/nikgapps/files/Releases/Android-13/04-Feb-2026/)
- Ne pas injecter dans une image ayant DÉJÀ des GApps sans savoir lesquelles pour éviter les signatures/frameworks dupliqués.

## 5. Autres OS — Linux mobile

- **postmarketOS / Linux mainline** : **pas de port DOOGEE S55 utilisable identifié**. Le [support MT6755/MT6750](https://wiki.postmarketos.org/wiki/MediaTek_Helio_P10_%28MT6755%29) est expérimental : stockage, USB, GPU, audio, téléphonie, Wi-Fi, BT, caméra et veille sont indiqués comme défaillants sur le travail upstream. À réserver à un projet de portage, pas à un smartphone quotidien.
- **Ubuntu Touch, Droidian, SailfishOS** : aucun port officiellement pris en charge et documenté pour le S55 confirmé dans cette recherche. Ne pas installer une image d'un autre MediaTek sous prétexte de SoC voisin. Sans pilote caméra, modem, power management, et boot compatibles, ce serait régressif.
- **LineageOS spécifique S55** : aucune image moderne propre à l'appareil, maintenue et vérifiée, trouvée. Les *GSI* sont le seul chemin réaliste sans développer un device tree complet.

## 6. Retours de spécialistes sur des incidents similaires

Les mainteneurs de [PHH Treble ont documenté un cas très proche](https://github.com/phhusson/treble_experimentations/discussions/2393) : sur un Samsung A50 sous GSI Android 12.1, un utilisateur relatait qu'après une extinction par batterie vide, le branchement provoquait l'animation de démarrage Android à la place de l'animation de charge, puis un bootloop jusqu'à une combinaison de touches. **C'est une analogie, pas une preuve du même défaut sur le S55.** Elle justifie de tester explicitement le mode charge autonome après changement de ROM, et de ne pas se contenter de vérifier Android quand la batterie est pleine.

Le [guide communautaire Treble](https://github.com/TadiT7/treble_experimentations_wiki/blob/master/Generic-System-Image-%28GSI%29-list.md) indique que ses GSI récentes sont **system-as-root par défaut**, sauf exception explicitement annoncée. Cette contrainte recoupe l'audit binaire de nos images. Les appareils Oreo ne peuvent pas recevoir une image SAR en remplaçant seulement `/system` sans adaptation du boot et du montage. Source : [AOSP, migration vers system-as-root](https://source.android.com/docs/core/architecture/partitions/system-as-root).

Sur le S55, le fait nouveau essentiel est la **recharge sur chargeur secteur jusqu'à 20 %**, alors que la charge depuis Pegasus/Hub s'effondrait. **Première hypothèse testable** : différence de courant fourni et de négociation USB ; **deuxième** : logiciel de démarrage en mode charge ; **troisième** : jauge/calibration ou batterie vieillissante. Un firmware plus récent pourrait corriger une incompatibilité GSI mais **aucune preuve n'établit qu'il guérirait la charge**.

## 7. Phase d'essais UNE FOIS la batterie suffisamment chargée

1. **Sauvegardes supplémentaires avant wipe autorisé** : lire `vendor`, `recovery`, `nvram`, `nvdata`, GPT et informations de partitions. Sauvegardes privées et SHA256. Prendre aussi les `getprop` Treble/VNDK et un diagnostic de batterie (tension réelle du pilote si root autorisé).
2. Mesurer la charge sous le chargeur secteur puis sous Pegasus : `dumpsys battery`, `dumpsys batterystats`, `dumpsys power`, `dumpsys deviceidle`, logs kernel avec permissions adéquates, recharge éteint. Ne pas interpréter 0 mV/0 °C Android comme des mesures de cellule.
3. Premier essai cible : **LineageOS 18.1 non-SAR + Core Android 11**, avec restauration contrôlée du correctif MicroArray si le binaire vendor correspond au hash. Répondre aux tests de SIM/réseau, appels, BT, GPS, 4G, caméra, autonomie, offline charging, Play Store, écran éteint.
4. Si stable, préparer **une migration SAR expérimentale pour Android 13** sur une copie du boot d'origine, en suivant la documentation Google sur le boot ramdisk, les points de montage, init, linker, VNDK et fstab. **Ne pas flasher un GSI SAR sur le boot non-SAR sans cette phase**. Un rollback TWRP/MTKClient validé est requis.
5. Comparer RAM, délais démarrage, ouverture apps, FPS/scroll, drain écran allumé et veille, reprises depuis veille, charge, température et stabilité. Garder **la ROM qui fonctionne**, pas nécessairement le plus grand numéro Android.
6. Ensuite vérifier Android 14 plus léger ; ne pas multiplier les essais 15–17 si le socle vendor/boot n'a pas été fiabilisé.

### Corrections matérielles à réintégrer dans toute nouvelle ROM

Le diagnostic du 10 octobre a résolu plusieurs incompatibilités vérifiées entre **crDroid 11 et le vendor Oreo**. Ces éléments doivent être considérés comme des *exigences de compatibilité* pour les ROM futures, et non appliqués aveuglément à un autre binaire :

- Chemin batterie ancien MediaTek `batt_vol` au lieu de `voltage_now` (healthd ARM64, version exacte uniquement) ; le contrôle physique de charge demeure natif
- Bibliothèques constructeur de `ipsec_mon` et `gesturewake_hal` perdues par l'isolation des espaces de liens entre système et vendor
- Exécutables ARM32 `msensord` et `memsicp` dépendant de `liblog.so` sans déclaration ELF correspondante
- Politique thermique `proc_mtktz` manquante pour `hal_thermal_default` : correctif **seulement compilé hors téléphone, non déployé**
- Patch fingerprint MicroArray à conserver sous contrôle de hash, ainsi que son contexte SELinux

Les correctifs exacts, preuves de redémarrage et scripts de retour arrière sont documentés dans [l'audit Android 11/vendor](ROOT-CAUSE-HEALTHD-VENDOR-2026-10.md). **Une mise à jour Android 13/14/15+ devra réévaluer ces API par version**, plutôt que copier un healthd 2022 ou la politique Oreo sur un framework récent.

## 8. Fabricant et firmwares

4PDA [Doogee S55 — firmware discussion](https://4pda.to/forum/index.php?showtopic=915045) liste des firmwares **2018** puis **8 novembre 2019**. La base ROM active utilise un kernel de juin 2020 (dump effectué sur cet appareil) et PhoneCopy [confirme un modem 2020](https://www.phonecopy.com/en/phones/view/doogee_s55) pour un S55. **Cela ne suffit pas à identifier un paquet constructeur complet de juin 2020 publiquement téléchargeable.** Aucun firmware constructeur Android 9+ n'a été vérifié pour le S55.

**Ne pas flasher la ROM S55 Lite, ni un paquet stock antérieur au kernel actuel sans sauvegarde complète.**

## 9. Réserve batterie / meilleure approche que « arrêt à 5 % »

La charge sur **secteur à au moins 20 %** annoncée par le propriétaire change le diagnostic : le S55 **peut** recharger et il faut d'abord contrôler pourquoi la charge depuis Pegasus/Hub était si faible et pourquoi le fuel gauge a annoncé 0–1 %. Ne pas remplacer arbitrairement la batterie.

Préférer **Battery Saver natif déclenché à 20 %**, alerte utilisateur à ~15 %, recharge avant ~10 % et **ne pas créer d'arrêt forcé à 5 %** tant que la jauge est instable : une fausse indication 5 % pourrait provoquer un arrêt prématuré irréversible sans chargeur. Après validation de la courbe de décharge, un avertissement/vrai shutdown de sécurité plus haut peut se discuter ; le PMIC possède déjà ses propres protections physiques.

Configuration **préparée mais non appliquée** en absence d'ADB après transfert au secteur : `settings put global automatic_power_save_mode 0`, `settings put global low_power_trigger_level 20`; vérifier uniquement quand l'appareil est de nouveau branché à Pegasus. Documenter les mesures et les réglages natifs, sans daemon inutile.

Sources : [AOSP Battery Saver Settings](https://android.googlesource.com/platform/frameworks/base/+/master/services/core/java/com/android/server/power/batterysaver/BatterySaverStateMachine.java) et [Healthd charger mode](https://android.googlesource.com/platform/system/core/+/refs/tags/android-cts-8.0_r26/healthd/healthd_mode_charger.cpp).
