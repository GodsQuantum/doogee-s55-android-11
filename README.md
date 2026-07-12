# Doogee S55 → crDroid 11 (Android 11) GSI — Complete Guide

> Turn a stock **Doogee S55** (MediaTek **MT6750**, Android 8 Oreo) into a clean, rooted **crDroid 11 (Android 11)** running a Generic System Image (GSI).
> **Functional steps only** — no trial-and-error. Every command here is one that actually mattered.

🇫🇷 **Version française plus bas** ([aller à la version française](#-guide-en-français)).

---

## ⚠️ Disclaimer
Flashing wipes your phone and can brick it if you skip steps. You do this at your own risk. The Doogee S55 is a **hard** GSI target (obscure MediaTek, A-only, Oreo vendor, FDE encryption). This guide exists because getting it to boot cleanly required solving several non-obvious traps. Read the whole thing once before starting.

## ✅ End result
- crDroid 11 (Android 11) booting cleanly under **SELinux enforcing**, on every reboot.
- Root (crDroid dynamic superuser), no bloat, security-patched Android 11.
- Why A11 and not newer: the S55 is **A-only (non-SaR)**, which caps usable GSIs at **Android 11**. Newer GSIs (12/13/14) are A/B system-as-root and will NOT boot. A11 is also the sweet spot for this weak SoC.

---

## Why do this? (a rugged phone that deserves to be off-grid)
The Doogee S55 is a **rugged, all-terrain** phone — IP68/IP69K, shockproof, big battery. It's *built* to be your outdoors / off-grid / backup device. But out of the box it ships **Android 8.0 Oreo, frozen on a 2019 security patch, with vendor bloat and Google baked in** — the opposite of off-grid. This project makes the hardware live up to its purpose: **private, de-Googleable, updatable, yours.**

**What you gain**
- **Security & app compatibility.** Stock is stuck on API 26 (Android 8). A growing number of modern apps set `minSdk` to Android 9/10/11 and simply won't install or update on Oreo. Concrete examples that want a newer base:
  - **Meshtastic** (off-grid LoRa mesh messaging) and **Briar** (P2P offline messaging over Bluetooth/Wi-Fi/Tor) — the exact "off-grid comms" a rugged phone is for.
  - **OsmAnd~ / Organic Maps** (offline maps & navigation) — heavy users run far better on a newer base.
  - **Aegis** (2FA), **Molly** (hardened Signal), modern **Nextcloud** client — privacy staples that track recent Android.
  - Many **banking / payment / 2FA** apps refuse an outdated security-patch level; A11 + 2022 patches pass where Oreo-2019 fails.
- **Off-grid / self-hosted.** No Google required (vanilla + F-Droid/Aurora/MicroG), system-wide ad & tracker blocking (AdAway), a real firewall (AFWall+), and clean pairing with self-hosted services (Nextcloud/Immich/Jellyfin) instead of Big-Tech clouds.
- **Control.** Root, full backups, automation, no forced updates, no telemetry.

**Performance & debloat — evaluated for the MT6750 (8×A53, 4 GB RAM)**
This is a low-end SoC, so the goal isn't raw speed — it's **removing weight**. Stock Doogee = MediaTek vendor bloat + a heavy skin + Google Play Services running 24/7. crDroid **vanilla** (no GApps) strips all of that.

| Metric (idle) | Stock Doogee A8 (typical) | crDroid 11 vanilla (typical) | Note |
|---|---|---|---|
| RAM used / 4 GB | ~2.0–2.4 GB | ~1.0–1.4 GB | **≈0.8–1.2 GB freed** for your apps |
| Background services | Doogee daemons + GMS | minimal (no GMS) | fewer wakelocks → better battery |
| Pre-installed apps | 30–50 (incl. bloat) | ~15 essentials | less storage, less CPU churn |
| Security patch | 2019 | 2022 (crDroid A11) | 3 years of fixes |

> ⚠️ **These figures are indicative ranges** from comparable MT6750 / 4 GB devices, **not measured on this exact unit.** Get *your* real numbers (great to paste into an issue/PR here):
> ```bash
> adb shell free -m                 # RAM used/free
> adb shell dumpsys meminfo | head  # per-process memory
> adb shell top -o %CPU -n 1 | head # idle CPU
> adb shell dumpsys batterystats --charged | head -40   # battery drain
> ```
> Honest trade-off: Android 11 is heavier *per frame* than Android 8, but the debloat + no-GApps more than offsets it on this SoC — expect **more free RAM, smoother idle, better battery, and vastly better privacy**, rather than a benchmark jump. Keep the boot animation short (few frames) to spare the weak GPU.

---

## 0. What you need
- A **Doogee S55** (this exact model; MT6750, arm64, A-only).
- A computer. **Linux strongly recommended** (the guide uses it). Windows works too but its `fastboot` package is broken for `-w` — use Google's official platform-tools everywhere.
- A good USB cable.
- **Google platform-tools (official)** — https://developer.android.com/tools/releases/platform-tools
  (⚠️ On Linux do NOT use `apt install fastboot`; its `mke2fs` is broken and `fastboot -w` fails. Use the official zip.)
- The files in [`files/`](files/) of this repo:
  - `twrp-3.1.1-doogee-s55.img` — TWRP recovery for the S55.
  - `Disable_Dm-Verity_ForceEncrypt.zip` — [Zackptg5's](https://github.com/Zackptg5/Disable_Dm-Verity_ForceEncrypt) verity/forceencrypt disabler.
- The **crDroid 11 GSI** — **download it yourself** (it is *not* in this repo: it's ~700 MB and GitHub caps files at 100 MB; also, always get it from the maintainer so it stays current):
  **File:** `crdrom-v316-220330-arm64-avZ.img.xz`
  **Direct link:** https://sourceforge.net/projects/treblerom/files/crDRom11/2022.03.30/crdrom-v316-220330-arm64-avZ.img.xz/download
  Name decoded: `arm64` = your CPU · `a` = **A-only** (mandatory for the S55) · `v` = vanilla / no Google apps · `Z` = dynamic root.
  Want the Play Store built in instead? Use the `...-arm64-agZ.img.xz` variant from the same folder (`g` = GApps).

Set an env var for the official fastboot/adb so the commands below are copy-paste ready:
```bash
export PT="$HOME/platform-tools"     # folder where you unzipped Google's platform-tools
FB="$PT/fastboot"; ADB="$PT/adb"
```

---

## The 10 steps that matter

> **Two modes you switch between:** 🔧 **fastboot** (bootloader — for `fastboot` commands) and 🛠️ **TWRP recovery** (for sideload, Format Data, and the fstab fix). Each step says which one to be in. `$FB` = fastboot, `$ADB` = adb (both from Google's platform-tools). To go **fastboot → TWRP**: `$FB reboot recovery`. To go **TWRP → fastboot**: menu *Reboot → Bootloader*.
>
> Flow at a glance: `unlock → flash TWRP → (TWRP) sideload no-verity → (fastboot) flash system + -w → (TWRP) fix fstab + Format Data → reboot`.

### 1. Enable Developer options
On the phone: Settings → About → tap *Build number* 7×. Then Developer options → enable **OEM unlocking** and **USB debugging**.

### 2. Unlock the bootloader (⚠️ wipes the phone)
```bash
$ADB reboot bootloader
$FB flashing unlock        # confirm on-screen with Volume + Power
```
An **orange "unlocked" warning** now shows at every boot — this is normal and permanent (removing it means re-locking, which breaks the ROM).

### 3. Flash TWRP recovery
```bash
$FB flash recovery files/twrp-3.1.1-doogee-s55.img
```

### 4. Boot into TWRP
Power off (hold Power ~15 s), then **Volume Up + Power** → TWRP. (Or from fastboot: `$FB reboot recovery`.)

### 5. Disable dm-verity & forced encryption
TWRP → **Advanced → ADB Sideload** (swipe), then on PC:
```bash
$ADB sideload files/Disable_Dm-Verity_ForceEncrypt.zip
```
On the phone answer the prompts with Volume keys: **disable dm-verity = yes, disable forceencrypt = yes, disk quota = no**.
(If sideload can't read the prompts, instead `adb push` the zip to `/sdcard` and use TWRP → Install.)

### 6. Get the crDroid GSI onto your PC
Download the `.img.xz` (link above), then:
```bash
unxz crdrom-v316-220330-arm64-avZ.img.xz     # → crdrom-v316-220330-arm64-avZ.img
```

### 7. Flash the system image + wipe
Boot to fastboot (TWRP → Reboot → Bootloader), then:
```bash
$FB flash system crdrom-v316-220330-arm64-avZ.img
$FB -w
```
> If `flash system` throws `std::bad_alloc` on Windows: you're on the wrong fastboot. Use Google's official one (or flash from Linux).

### 8. Decrypt /data at the vendor level **+ restore the SELinux label** (the two-part critical step)
Android 11 dropped Full-Disk-Encryption, but the Oreo vendor only does FDE → `/data` can't be set up → boot loops into a factory reset. Fix: strip encryption from the vendor fstab. **Then immediately restore its SELinux label** (editing with `sed` blanks the label, which later kills `nvram_daemon` and hangs the boot — see [The gotcha](#the-gotcha-that-cost-a-whole-night)).

Boot to TWRP, connect ADB, then run [`scripts/decrypt-fstab.sh`](scripts/decrypt-fstab.sh), or manually:
```bash
$ADB shell 'mount -o rw,remount /vendor
for f in /vendor/etc/fstab*; do
  sed -i "s/forceencrypt/encryptable/g; s/forcefdeorfbe/encryptable/g; s/fileencryption/encryptable/g" "$f"
  sed -i "s#,encryptable=/dev/block/platform/mtk-msdc.0/11230000.msdc0/by-name/metadata##g" "$f"
  sed -i "s#,=/dev/block/platform/mtk-msdc.0/11230000.msdc0/by-name/metadata##g" "$f"
done
restorecon -Rv /vendor/etc/fstab*'          # <-- DO NOT SKIP. Restores u:object_r:vendor_configs_file:s0
```
Verify the /data line ends at `...quota,resize` with no encryption keyword, and that `ls -Z /vendor/etc/fstab.mt6755` is **not** `unlabeled`.

### 9. Format /data as ext4
TWRP → **Wipe → Format Data → type `yes`**. (This gives a clean, unencrypted /data that vold can mount.)

### 10. Reboot
```bash
$FB reboot     # or TWRP → Reboot → System
```
First boot builds ART caches — allow **up to ~5 min**. It should land on the crDroid setup wizard. Confirm from PC:
```bash
$ADB wait-for-device; $ADB shell getprop sys.boot_completed   # → 1 when done
```

Done. 🎉

---

## The gotcha that cost a whole night
If you edit the vendor fstab with `sed -i` and **don't** `restorecon` it, the file becomes SELinux `unlabeled`. Under **enforcing**, MediaTek's `nvram_daemon` can't read `/vendor/etc/fstab.mt6755`, so it dies (`exited with status 1`). The audio HAL (`audio.primary.mt6750.so`) then spins forever in `checkNvramReady()` waiting for NVRAM to become ready → `media.audio_policy` is never published → `system_server` waits → **boot never completes** (endless boot animation, no crash, no SELinux denial visible unless you dig).

**Root cause & fix, in one line:**
```bash
$ADB root; $ADB shell "mount -o rw,remount /vendor; restorecon -Rv /vendor/etc/fstab.mt6755"
```
This is already included in step 8. If you ever see an endless boot animation with `adb logcat` showing `Waiting for service 'media.audio_policy'`, this is your fix.

---

## Change the boot animation
The animated crDroid logo is just `/system/media/bootanimation.zip` (path may be `/product/media/` or `/system_ext/media/`). The *first* Doogee/orange screen is the bootloader splash and cannot be changed without re-locking.

Use [`scripts/bootanim-replace.sh`](scripts/bootanim-replace.sh), or manually:
```bash
$ADB root; sleep 1
$ADB shell "find /system /product /system_ext -name bootanimation.zip 2>/dev/null"   # locate it
$ADB shell "mount -o rw,remount /"
$ADB push my-bootanimation.zip /system/media/bootanimation.zip
$ADB shell "chmod 644 /system/media/bootanimation.zip; chcon u:object_r:system_file:s0 /system/media/bootanimation.zip"
```
For **no logo at all**, use a bootanimation.zip containing a single black frame.

## Create your own boot animation (correct zip format)
A bootanimation is a ZIP (stored, **no compression**) with:
```
bootanimation.zip
├── desc.txt
├── part0/   (PNG frames, played once)
└── part1/   (PNG frames, looped)
```
`desc.txt` format: `WIDTH HEIGHT FPS` then one line per part `p COUNT PAUSE FOLDER`
(`COUNT`=loops, 0=infinite; `PAUSE`=frames to pause after).
Example (480×960, 30 fps, intro once then loop):
```
480 960 30
p 1 0 part0
p 0 0 part1
```
Build it (use [`scripts/make-bootanimation.sh`](scripts/make-bootanimation.sh)):
```bash
cd my_anim/                       # contains desc.txt, part0/, part1/
zip -r -0 ../bootanimation.zip .  # -0 = STORE, mandatory (no deflate)
```
Match `WIDTH HEIGHT` to your screen (S55 = 480×960). Keep frame count low on this weak SoC.

---

## Troubleshooting
| Symptom | Cause | Fix |
|---|---|---|
| `std::bad_alloc` on `flash system` | Wrong/old fastboot | Use Google official platform-tools |
| `mke2fs failed ... userdata` on `-w` | Distro `fastboot` package broken | Use Google official platform-tools |
| Boot loops into factory-reset / recovery | /data still encrypted | Step 8 (decrypt fstab) + Step 9 (Format Data ext4) |
| Endless boot animation, log shows `media.audio_policy` waiting | fstab `unlabeled` → nvram_daemon dies | `restorecon` the vendor fstab (step 8) |
| Can't reach TWRP by keys | timing | From fastboot: `fastboot reboot recovery` |

## Credits
- [AndyYan](https://github.com/AndyCGYan) & [phhusson](https://github.com/phhusson) — GSI foundations.
- [eremitein](https://github.com/eremitein/treble-patches) — crDRom11 (crDroid GSI) with legacy MediaTek fixes.
- [Zackptg5](https://github.com/Zackptg5/Disable_Dm-Verity_ForceEncrypt) — verity/forceencrypt disabler.
- TWRP maintainers & the Treble community.

---
---

# 🇫🇷 Guide en français

> Transformer un **Doogee S55** d'origine (MediaTek **MT6750**, Android 8) en **crDroid 11 (Android 11)** rooté, propre, via une image système générique (GSI).
> **Uniquement les étapes qui marchent** — pas d'essais-erreurs.

## ⚠️ Avertissement
Le flash efface le téléphone et peut le briquer si tu sautes une étape. À tes risques. Le S55 est une cible GSI **difficile** (MediaTek obscur, A-only, vendor Oreo, chiffrement FDE) : ce guide existe parce qu'il a fallu résoudre plusieurs pièges non évidents. Lis tout une fois avant de commencer.

## ✅ Résultat
crDroid 11 (Android 11) qui boote proprement sous **SELinux enforcing**, à chaque reboot. Root, zéro bloatware, patché. **Pourquoi A11 et pas plus récent** : le S55 est **A-only** → plafond = Android 11 (les GSI 12/13/14 sont A/B system-as-root et **ne booteront pas**). A11 est aussi idéal pour ce petit CPU.

## Pourquoi le faire ? (un rugged qui mérite d'être off-grid)
Le Doogee S55 est un téléphone **rugged, tout-terrain** (IP68/IP69K, antichoc, grosse batterie) — pensé pour être ton appareil outdoor / de secours / off-grid. Mais d'origine il tourne sous **Android 8.0, figé sur un patch de sécurité 2019, avec du bloatware constructeur et Google intégré** — l'inverse de l'off-grid. Ce projet fait enfin correspondre le matériel à sa vocation : **privé, dé-googlisable, à jour, à toi.**

**Ce que tu gagnes**
- **Sécurité & compatibilité apps.** Bloqué en API 26 (Android 8), le stock ne peut plus installer beaucoup d'apps modernes qui exigent Android 9/10/11 (`minSdk`). Exemples parlants pour un rugged :
  - **Meshtastic** (messagerie mesh LoRa off-grid) et **Briar** (messagerie P2P hors-ligne Bluetooth/Wi-Fi/Tor) — précisément l'usage off-grid d'un tel baroudeur.
  - **OsmAnd~ / Organic Maps** (cartes & navigation hors-ligne), **Aegis** (2FA), **Molly** (Signal durci), client **Nextcloud** récent.
  - Beaucoup d'apps **bancaires / paiement / 2FA** refusent un patch de sécurité trop vieux : A11 + patchs 2022 passent là où Oreo-2019 échoue.
- **Off-grid / auto-hébergé.** Zéro Google obligatoire (vanilla + F-Droid/Aurora/MicroG), blocage pub & traceurs système (AdAway), pare-feu (AFWall+), et couplage propre avec tes services auto-hébergés (Nextcloud/Immich/Jellyfin) plutôt que les clouds des GAFAM.
- **Contrôle.** Root, backups complets, automatisation, aucune MàJ forcée, aucune télémétrie.

**Perf & debloat — évalués pour le MT6750 (8×A53, 4 Go RAM)**
SoC d'entrée de gamme : le but n'est pas la vitesse brute mais **retirer du poids**. Stock Doogee = bloat MediaTek + surcouche lourde + Google Play Services 24/7. crDroid **vanilla** (sans GApps) supprime tout ça.

| Mesure (repos) | Stock Doogee A8 (typique) | crDroid 11 vanilla (typique) | Note |
|---|---|---|---|
| RAM utilisée / 4 Go | ~2,0–2,4 Go | ~1,0–1,4 Go | **≈0,8–1,2 Go libérés** |
| Services en fond | daemons Doogee + GMS | minimal (sans GMS) | moins de wakelocks → meilleure autonomie |
| Apps préinstallées | 30–50 (bloat) | ~15 essentielles | moins de stockage/CPU |
| Patch de sécurité | 2019 | 2022 | 3 ans de correctifs |

> ⚠️ **Chiffres indicatifs** (appareils MT6750/4 Go comparables), **pas mesurés sur cette unité.** Mesure les tiens :
> ```bash
> adb shell free -m ; adb shell dumpsys meminfo | head ; adb shell top -o %CPU -n 1 | head
> ```
> Compromis honnête : A11 est plus lourd *par image* qu'A8, mais le debloat + sans-GApps compense largement sur ce SoC → **plus de RAM libre, repos plus fluide, meilleure batterie, vie privée incomparable**, plutôt qu'un bond de benchmark. Garde l'animation de boot courte (peu de frames) pour ménager le GPU.

## 0. Nécessaire
- Un **Doogee S55** (ce modèle précis).
- Un PC, **Linux fortement conseillé**. (Sous Linux **n'utilise pas** `apt install fastboot` : son `mke2fs` est cassé, `fastboot -w` échoue. Prends les platform-tools officiels Google.)
- Câble USB correct.
- **platform-tools officiels** : https://developer.android.com/tools/releases/platform-tools
- Fichiers du dossier [`files/`](files/) : `twrp-3.1.1-doogee-s55.img`, `Disable_Dm-Verity_ForceEncrypt.zip`.
- **GSI crDroid 11** (non inclus, ~700 Mo) : `crdrom-v316-220330-arm64-avZ.img.xz` depuis
  https://sourceforge.net/projects/treblerom/files/crDRom11/2022.03.30/
  (`arm64` + `a` = A-only + `v` = vanilla/sans-GApps + `Z` = root dynamique.)

```bash
export PT="$HOME/platform-tools"; FB="$PT/fastboot"; ADB="$PT/adb"
```

## Les 10 étapes qui comptent
1. **Options développeur** : Réglages → À propos → 7 tapes sur *Numéro de build*. Active **Déverrouillage OEM** + **Débogage USB**.
2. **Déverrouiller le bootloader** (efface tout) :
   ```bash
   $ADB reboot bootloader
   $FB flashing unlock       # confirmer à l'écran (Volume + Power)
   ```
   L'avertissement orange à chaque boot est **normal et permanent**.
3. **Flasher TWRP** : `$FB flash recovery files/twrp-3.1.1-doogee-s55.img`
4. **Aller dans TWRP** : éteindre, puis **Volume Haut + Power** (ou `$FB reboot recovery`).
5. **Désactiver dm-verity + forceencrypt** : TWRP → Advanced → ADB Sideload, puis
   `$ADB sideload files/Disable_Dm-Verity_ForceEncrypt.zip`
   (réponses aux invites Volume : dm-verity = oui, forceencrypt = oui, disc quota = non).
6. **Décompresser le GSI** : `unxz crdrom-v316-220330-arm64-avZ.img.xz`
7. **Flasher system + wipe** (en fastboot) :
   ```bash
   $FB flash system crdrom-v316-220330-arm64-avZ.img
   $FB -w
   ```
8. **Déchiffrer /data (fstab vendor) + RESTAURER le label SELinux** (l'étape critique en deux temps) :
   Sous TWRP + ADB, lance [`scripts/decrypt-fstab.sh`](scripts/decrypt-fstab.sh) ou manuellement le bloc du guide anglais.
   **Ne saute PAS le `restorecon`** : sans lui, le fstab devient `unlabeled` → `nvram_daemon` meurt en enforcing → le HAL audio boucle sur `checkNvramReady()` → boot bloqué (voir *Le piège*).
9. **Formater /data en ext4** : TWRP → Wipe → Format Data → `yes`.
10. **Reboot** : `$FB reboot`. Premier boot ~5 min (caches ART). → assistant crDroid.

## Le piège qui coûte une nuit
Éditer le fstab vendor avec `sed -i` **sans** `restorecon` le laisse SELinux `unlabeled`. En enforcing, `nvram_daemon` ne peut plus lire `/vendor/etc/fstab.mt6755`, il meurt, et le HAL audio MTK boucle indéfiniment dans `checkNvramReady()` → `media.audio_policy` jamais publié → boot infini (aucun crash visible). **Correctif (déjà dans l'étape 8) :**
```bash
$ADB root; $ADB shell "mount -o rw,remount /vendor; restorecon -Rv /vendor/etc/fstab.mt6755"
```

## Changer / créer l'animation de démarrage
- **Changer** : voir [`scripts/bootanim-replace.sh`](scripts/bootanim-replace.sh). L'écran Doogee/orange (bootloader) ne se change pas sans reverrouiller.
- **Créer** : un ZIP **STORE (sans compression)** contenant `desc.txt` + `part0/` + `part1/` (PNG). `desc.txt` : `LARGEUR HAUTEUR FPS` puis `p BOUCLES PAUSE DOSSIER`. Zippe avec `zip -r -0` (le `-0` est obligatoire). Écran S55 = 480×960. Voir [`scripts/make-bootanimation.sh`](scripts/make-bootanimation.sh).

## Crédits
AndyYan, phhusson (bases GSI) · eremitein (crDRom11 + fixes MediaTek legacy) · Zackptg5 (disabler verity) · TWRP & la communauté Treble.
