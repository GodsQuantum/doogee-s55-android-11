<p align="center"><img src="docs/assets/logo.svg" width="136" alt="Logo de modernisation du DOOGEE S55"></p>

<h1 align="center">DOOGEE S55 · LineageOS 18.1</h1>

<p align="center"><strong>Une seconde vie pour le S55 : Android 11, Google Play et correctifs matériels.</strong><br>
Installation guidée depuis un dossier autonome, avec sauvegardes et vérifications.</p>

<p align="center">
  <a href="https://github.com/GodsQuantum/doogee-s55-android-11/actions/workflows/lint.yml"><img src="https://github.com/GodsQuantum/doogee-s55-android-11/actions/workflows/lint.yml/badge.svg" alt="Qualité du code"></a>
  <img src="https://img.shields.io/badge/Android-11%20%7C%20LineageOS%2018.1-3dd7cf" alt="Android 11">
  <img src="https://img.shields.io/badge/téléphone-DOOGEE%20S55-18283b" alt="S55 uniquement">
  <a href="LICENSE"><img src="https://img.shields.io/badge/licence-MIT-3dd7cf" alt="Licence MIT"></a>
</p>

<p align="center"><a href="README.md">English</a> · <strong>Français</strong> · <a href="README.zh-CN.md">简体中文</a></p>

---

## 🚀 Installation guidée en une commande

Le dossier **`local-kit/`**, préparé une première fois, contient la ROM, les Google Apps, TWRP, les images `boot` et `vendor` validées, les correctifs ainsi que leurs signatures. Sur le PC Linux branché au **DOOGEE S55 d'origine** :

```bash
cd local-kit
./INSTALL.sh
```

**Pas besoin d'exécuter dix scripts séparément.** L'installateur contrôle les fichiers, vérifie le S55 et la table de partitions, guide le déverrouillage OEM et TWRP, effectue les sauvegardes privées, installe LineageOS 18.1 + NikGapps Core, applique les corrections et vérifie le démarrage.

Le GitHub public contient le **code et la documentation**, pas les images constructeur ni Google. Sur la machine du mainteneur possédant déjà les fichiers exacts :

```bash
bash scripts/build-s55-lineage18-kit.sh
```

Cela construit `local-kit/`. Copie **tout le dossier** vers un PC Linux disposant d'ADB, Fastboot, Python 3, xz et zstd. pv est facultatif grâce au suivi de progression Python inclus. Exécute le script en tant qu'utilisateur normal, **pas avec `sudo`**.

**Avant de commencer :** sauvegarde tes photos et fichiers, charge la batterie à **40 % minimum**, active le débogage USB et le déverrouillage OEM sur Android 8. **Toutes les applications et les données internes seront effacées.** Le déverrouillage OEM et certaines manipulations de recovery exigent une validation physique.

[**Guide complet A à Z →**](installer/README.md) · [**Audit de sécurité et reprise**](docs/INSTALLER-SAFETY-AUDIT-2026-10.md)

**Optimisations batterie et performances :** [réglages natifs et limites mesurées](docs/POWER-PERFORMANCE-2026-10.md).

Pour contrôler le kit sans écriture (le mode --verify vérifie un S55 déjà démarré sous Android 11, sans reflasher) :

```bash
./INSTALL.sh --plan
./INSTALL.sh --check
./INSTALL.sh --verify
./INSTALL.sh --recovery-check
```

Le mode --recovery-check vérifie localement la GPT et les neuf sauvegardes d’origine, sans réécriture.

## ✨ Ce qui est réellement réparé

| Fonction | État vérifié sur notre S55 |
|---|---|
| **Système** | LineageOS 18.1 / Android 11 démarre et redémarre |
| **Google Play** | NikGapps Core, Play Store, services Google et GSF installés |
| **Empreinte MicroArray** | **Déverrouillage par empreinte réussi après redémarrage**, confirmé physiquement sur le S55 de référence (correctif MicroArray + rétention PHH) |
| **Batterie** | Tension et température réelles remontées à Android |
| **Thermique** | Températures CPU, GPU, batterie et châssis ; SELinux **Enforcing** |
| **Capteurs et gestes** | Correctifs de compatibilité des anciennes bibliothèques MediaTek |
| **Autonomie** | Économiseur Android natif dès 25 %, sans service supplémentaire |
| **Stockage** | Partition `/data` correctement initialisée pour Android 11 |

## 🛡️ Sécurité et limites

- **S55 standard exclusivement**, pas S55 Lite. Android 13 et plus ne sont pas directement compatibles avec la configuration non-SAR du téléphone.
- Sauvegarde des partitions d'origine (`system`, `boot`, `vendor`, `recovery`, NVRAM/NVDATA, protections et GPT) avant toute répartition ou écriture. Les identifiants radio restent propres à chaque appareil et hors GitHub.
- **Les mesures de batterie sont réparées, mais la récupération après décharge profonde n'est PAS validée.** Charge téléphone éteint, jauge et vieillissement restent à vérifier. Économiseur natif à 25 %, recharge conseillée vers 20 %, aucune décharge volontaire à 0 %. L'audit du 11 octobre identifie aussi un plantage radio MediaTek récurrent, à traiter avant usage d'une SIM. Le kit inclut le diagnostic sans écriture scripts/diagnose-battery.sh. Le redémarrage automatique PHH du RIL provoquait une boucle de démarrage et a été désactivé. Un patch binaire minimal a passé un test réel TEMPORAIRE de chargement et démarrage RIL pendant 32 secondes sur le S55, suivi d'un retour à l'original vérifié. Sans SIM, appels/SMS/données et correction durable ne sont pas encore validés. Voir docs/RADIO-RILPROXY-2026-10-11.md.
- **Test physique concluant le 10 octobre 2026 : déverrouillage par empreinte après redémarrage confirmé par le propriétaire.** Le kit applique automatiquement les deux corrections (vendor MicroArray + rétention PHH). Sur un autre S55, il faut inscrire un doigt, redémarrer et vérifier le déverrouillage ; le contrôle automatisé ne remplace pas ce test.
- Le kit passe les vérifications statiques et SHA256 ; **nous n'avons pas encore réalisé l'installation complète sur un second S55 jamais modifié**. Les variantes inconnues sont refusées plutôt que flashées aveuglément.

## 📚 Guides

- [Installation A à Z](installer/README.md)
- [Migration LineageOS 18.1 : cause du problème de démarrage](docs/LINEAGE18-MIGRATION-ROOT-CAUSE-2026-10.md)
- [Batterie, capteurs thermiques et autonomie](docs/BATTERY-THERMAL-LINEAGE18-2026-10.md)
- [Correctif empreinte MicroArray](docs/FINGERPRINT-FIX.md)
- [Choix des ROM et Android 13](docs/ROM-OPTIONS-FR.md)
- [Ancien guide crDroid conservé](docs/CRDROID-LEGACY.md)
- [Sécurité et confidentialité](SECURITY.md)

## 🧰 Développement

```bash
make lint
bash scripts/build-s55-lineage18-kit.sh
```

Projet communautaire **non affilié à DOOGEE, LineageOS ou NikGapps**. Les archives tierces, firmwares propriétaires et sauvegardes propres à chaque téléphone **ne sont jamais publiés sur GitHub**.

[Contribution](CONTRIBUTING.md) · [Mentions tierces](THIRD_PARTY_NOTICES.md) · [Licence MIT](LICENSE)
