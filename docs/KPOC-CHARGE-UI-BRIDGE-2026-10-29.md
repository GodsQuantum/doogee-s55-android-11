# DOOGEE S55 — Off-mode charge: charge UI bridge (29 Oct 2026)

## Diagnostic, confirmed live

**The shutdown is genuine:** Pegasus observed USB disconnect at **18:07:51**, no device for approximately **56 s**, the MTK Preloader `0e8d:2000` at **18:08:47**, and the KPOC USB gadget `0e8d:2008` at **18:09:06**. That single KPOC gadget remained stable through at least **18:24:37**, with no Fastboot or repeated Preloader enumeration. External charger insertion wakes the PMIC and boots the off-mode charge environment. This does **not** mean normal Android shutdown failed.

**Orange State** is emitted by the unlocked LK bootloader **before KPOC userspace begins**, independent of the percentage or charging health. No safe Android setting suppresses this while preserving an unlocked GSI bootloader. Re-locking a GSI with non-stock vbmeta and/or rewriting LK is inappropriate and can brick the S55.

The red/depleted icon during KPOC is **not verified as a real 0% battery**: Android battery before tests was ~26%, kernel KPOC can measure `VChr≈4.7V` but its userspace charger had previously shown 50% defaults and unknown status; media LK/boot are separate from Android system. The faulty AOSP charge mode `/sbin/charger` service previously caused Preloader loops; it was removed by restoring the original 2020 boot.

## Safe approach: display from measured sysfs instead of the old AOSP charger

Source: `scripts/kpoc-s55-bridge.c`. Native init declaration: `scripts/s55-kpoc-bridge.rc`. Offline test `tests/test_kpoc_bridge.py`.

- Fully static **AArch64 ELF** with no dynamic interpreter, APEX, Android HAL, Java, shell, external libraries, or networking; built on CT700 from standalone C via LLVM/LLD.
- Reads `/sys/class/power_supply/{usb,ac}/online`, `battery/{capacity,present,status,batt_vol}` and **MTK-specific** `/sys/devices/platform/battery/ADC_Charger_Voltage`.
- Treats 4.2–6V measured VBUS as connected even if the older `usb/online` interface is incorrectly missing/zero in KPOC; this avoids the faulty AOSP software 'charger unplugged' conclusion.
- Only shows percentage if 0–100 with credible measured voltage and a present battery. **Never invents 0%, never claims charge when source unavailable**; shows unknown icon and **measured battery voltage in volts** instead.
- V1 installée à 19 h 15 : dessine une batterie sur `/dev/graphics/fb0` (16/32 bpp), allume l'écran six secondes par minute et ne modifie pas sysfs ; **problème observé ensuite : écran noir encore rétroéclairé**. La V2 décrite ci-dessous remplace cette cadence par un seul affichage et écrit uniquement la luminosité LCD à zéro ; elle n'écrit jamais les valeurs de charge/batterie, ne gère pas le courant ni la coupure du PMIC.
- Init service `s55_kpoc_bridge` in class `charger` only. Not `critical`. Android normal still starts the existing `/vendor/bin/fuelgauged`; KPOC retains the OEM `/sbin/fuelgauged_static` service already installed. Boot, LK, logo, preloader, IMEI, RIL, fingerprint, normal Android firmware untouched.
- Experimental limitations: no on-device FB/SELinux test yet; visual draw and percentage availability depend on framebuffer rights and whether the static fuel gauge initializes. Stable USB enumeration proves KPOC isn't rebooting, **not that it electrically charges battery at 0%**.

## Offline validation

- ARM64 ELF executable static, SHA-256 **`33185c51ee2b410ee5fd1d8e5b60aa15e2985d2206631a8d32c707cff5567865`** (private compiled candidate `files/candidates/kpoc-s55-bridge-UNINSTALLED-arm64`, never committed).
- ARM64 one-shot read-only probe SHA-256 **`e5fd0108d19a7e74d2a92ae175a441e7738d310b7c996e60b1fd1118bff3b4e5`** (private `files/candidates/kpoc-s55-probe-ONE-SHOT-arm64`).
- `scripts/s55-kpoc-bridge.rc` SHA-256 **`5a759cd1d13e6f765f2197e48613ea3630198d6795befacbb6d24d777ef0b994`**.
- Native test on CT700: mock USB online=1/26%, missing USB online but VCHR=4750mV (detected), real VCHR=0 (unplug), unknown gauge, invalid battery reading; no power control function; all PASS.
- `make lint` PASS, only build artifacts under `files/candidates` excluded from Git.

## Deployment, NOT YET PERFORMED

**Current phone state:** KPOC `0e8d:2008`, no ADB. Needs owner physically to return to normal Android via Power, then attach to Pegasus. Do not try to flash in Preloader or enable `off-mode-charge=0`.

Private install harness, *prepared but not executed*: `backups/device-2026-10-29-kpoc/install-kpoc-bridge-on-pegasus.sh`. It pins all SHA-256, preflights S55 serial, Android boot, SOC≥20%, vendor hashes, asks Android ADB root (must be explicitly enabled in Developer options if disabled), runs native *one-shot read-only* probe before any vendor write, then creates exclusively two files: `/vendor/bin/s55_kpoc_bridge`, `/vendor/etc/init/s55-kpoc-bridge.rc`. It leaves Android running; it does not automatically reboot to charger mode. Vendor is restored read-only.

**Post-install QA**: verify Android boot, stable USB KPOC >=5min with no Preloader cycle, inspect real image/voltage on phone screen, then boot Android and measure SOC/voltage. If startup/visualization fails, manually restore original behavior by removing only those two newly installed files and remounting vendor RO. Never flash the old experimental boot image again.

## Main limitation

A true physical low-battery recovery guarantee cannot be given without a full real-charge test on adequate 5V power with a measured current and a battery above the undervoltage safety threshold. An icon or Orange State warning alone does not establish actual charging performance. The UI bridge is not a charging driver.

References: `docs/KPOC-FIRMWARE-DIFF-ROOT-CAUSE-2026-10-29.md`, `docs/KPOC-STATIC-FUELGAUGE-2026-10-29.md`, and official AOSP `healthd_mode_charger.cpp` (unplugged shutdown logic).

## 19:23+ — Retour utilisateur du premier test et LCDv2

Le propriétaire a effectué l'extinction Android manuelle puis rebranché Pegasus. Résultat : avertissement Orange State, puis **batterie verte animée**, ensuite **écran noir mais toujours rétroéclairé**. Pegasus a constaté la transition unique Preloader à 19:22:34 puis KPOC 0e8d:2008 à 19:22:54 ; aucune boucle Fastboot. Cela prouve le démarrage du mode KPOC, PAS la capacité à charger une batterie vide.

La source du bridge installé (SHA 33185c51...) réveillait l'écran à `n%60==0` et appelait uniquement `FBIOBLANK=4` à `n%60==6`. Sur cette famille MediaTek, l'appel peut masquer l'image sans éteindre matériellement le rétroéclairage. Le ramdisk 2020 officiel donne le chemin du contrôleur LED : `/sys/class/leds/lcd-backlight/brightness` (init.rc lignes 598-600), cohérent avec les interfaces Linux rétroéclairage.

**LCDv2 préparé uniquement sur Cloud9, NON installé :**

- La source `scripts/kpoc-s55-bridge.c` n'éclaire l'écran qu'au lancement ; elle supprime le réveil périodique toutes les 60 secondes.
- À six secondes, elle demande `FBIOBLANK(4)` puis écrit `0\n` uniquement dans `/sys/class/leds/lcd-backlight/brightness` pour éteindre physiquement le rétroéclairage. Si le fichier est absent ou la permission SELinux refuse l'écriture, logge l'échec : aucune garantie écran noir non lumineux tant que le test matériel n'a pas été fait.
- Aucune écriture aux chemins `/sys/class/power_supply`, aucun système de contrôle du courant/tension/PMIC, aucun changement du reboot ni du noyau.
- Test hors ligne `tests.test_kpoc_bridge` : trois tests passés (états batterie USB et ADC, extinction rétroéclairage simulée luminosité 180 et 0, pas de syscall d'extinction).
- Image ARM64 statique candidate privée `files/candidates/kpoc-s55-bridge-LCDv2-UNINSTALLED-arm64`, SHA-256 **74db775607873a9b9e8e11ede169f87eae019e13dea8c6c25d1158f90fb53055**.
- Script privé de mise à jour UNIQUEMENT du binaire préparé, non exécuté : `backups/device-2026-10-29-kpoc/upgrade-kpoc-bridge-lcdv2-on-pegasus.sh` ; il exige le retour normal Android, ADB root disponible, la jauge >=20%, ancienne SHA 33185c... confirmée, RC/patchs intactes, existence du chemin `lcd-backlight/brightness`. Copie le nouveau binaire dans vendor de manière atomique, restitue vendor RO et ADB non-root. Pas de redémarrage automatique.
- Rollback ciblé privé `backups/device-2026-10-29-kpoc/rollback-kpoc-bridge-on-pegasus.sh` adapté pour supprimer l'ancienne ou la nouvelle version du bridge après vérification de SHA, sans toucher au fuelgauge KPOC original.

**Prochaine action requise** : demander au propriétaire de débrancher le S55 KPOC, l'allumer sous Android et le reconnecter Pegasus. Vérifier avec `adb` le chemin de luminosité (lecture seule, jamais écrire en Android normal) avant d'installer LCDv2, puis refaire un seul test hors Android et observer l'extinction physique de l'écran.
