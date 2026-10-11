# DOOGEE S55 — Batterie, températures et veille (10 octobre 2026)

## 11 October 2026 — current state and remaining risks

**Repaired telemetry is not the same thing as a repaired charging system.** The real S55 on Pegasus reports 100%, around 4.30 V, a battery temperature around 24 C, Enforcing SELinux and working biometric unlocking (10 accepted authentications, no fingerprint HAL deaths). Android's Battery Saver threshold is 25% and Doze is enabled. This confirms the Android-facing readings, not battery capacity, wear, actual reserve, low-voltage boot recovery, or charging while powered off.

**Power-off KPOC**: the 2020 boot/kernel already has MediaTek KPOC support, the charger/fuel-gauge services and bootloader off-mode-charge=1. Previous 9 October low-voltage testing nonetheless produced preloader/fastboot cycles and an actual bootloader refusal. The remaining failure can therefore be in powered-off charge transitions, the USB connector, an aged/high-resistance cell, the PMIC or fuel gauge. No safe justification exists to remove the undervoltage cutoff, spoof SOC or install a custom 5% shutdown daemon.

**New real-world radio finding:** on 11 October, the reference S55 with *both SIM slots empty* has init.svc.ril-proxy=stopped following another identical SIGSEGV in librilproxy.so / radio::networkInfoInd on 10 October 23:34. Android event logs show repeated com.android.phone process deaths (130 matching event entries in the captured buffer), and ttyC0 incurred 86 seconds of kernel wakelock out of approximately four minutes of historical batterystats on-battery accounting. These are real stability / standby concerns; they do NOT prove the battery failure mechanism. The exact same symbol was described for other historical MediaTek devices. PHH Android 11 includes a restart_ril property, but blindly enabling it on a repeat-crashing RIL could produce a restart loop and worse drain. No radio or cellular settings were changed, to preserve potential SIM service, emergency calls and recoverability.

**Conservative prevention and next diagnostics:**
1. Recharge at about 20%, never deliberately discharge the cell to 0%. Retain Android native 25% Battery Saver and thermal/low-voltage protections; do not trust a 5% auto-power-off threshold as a physical reserve.
2. Test **powered-off charging at a safe moderate indicated SOC, for example 40–60%**, with a known-good 5 V / 2 A charger and cable. Confirm stable charging screen/current and an increasing SOC, with the ability to boot without a PC. This cannot be validated merely by Android ADB while the device is running.
3. For autonomy, compare unplugged standby readings over an extended interval with radio and SIM state recorded. USB ADB powers the phone and hides real standby current. Do not automatically enable flight mode (which removes cellular/emergency functionality) or an unconditional PHH restart-RIL loop.
4. If the phone returns to boot loops, refuses low-voltage boot, discharges abruptly or does not charge while off, have the 5 V input, connector, battery voltage under load, battery health/internal resistance and PMIC path measured safely by a repair professional. Avoid forcing power into a lithium-ion cell.

**Latest operator-visible tooling:** scripts/diagnose-battery.sh is read-only and now includes S55-specific batt_vol / batt_temp plus thermal/charging and Battery Saver settings. Permission errors are explicitly recorded; it does not silently treat inaccessible kernel files as zero.

**Fingerprint note:** the 10 October owner physically confirmed successful fingerprint unlock after reboot. An older sentence later in this historical report reporting zero registered fingers was written immediately after a data wipe and does not reflect the final result. See FINGERPRINT-FIX.md.

---

État : LineageOS 18.1 / Android 11, ancien noyau MediaTek, vendor constructeur Oreo. Corrections **testées physiquement** avec SELinux **Enforcing**. Les originaux binaires, données radio et journaux privés sont ignorés par Git.

## Réparations validées

**Température batterie / healthd :** le noyau expose une sonde réelle sur /sys/class/power_supply/battery/batt_temp, en dixièmes de degré Celsius : 310 à 320 pendant les essais = 31–32 °C. Le healthd LineageOS 18.1 ne cherchait que /sys/class/power_supply/battery/temp, inexistant. Correction d'une référence ARM64 ADRP+ADD vers une nouvelle chaîne format placée dans l'espace inutilisé du segment ELF lecture seule (extension 0x63f4 → 0x6420), sans changement de logique de charge ou seuils de protection. Taille inchangée : 84096 octets. Disassembly, segments, emplacement et hashes vérifiés hors appareil.

- SHA256 healthd tension seule : 5f66b4c372d09eb84f2b23dadedaad0a53242bc44f31fdd7787a5467bee9e3ee.
- SHA256 healthd tension + température : 4421bd4794a9470e74b28c63e3ba9a2528e83a7635314ae27e5375c136555381.
- Installation et rollback : scripts/fix-lineage18-healthd-temperature.sh (--check, --apply, --restore) depuis TWRP d'origine.
- **Android : dumpsys battery temperature 310–320 et voltage ~3900–3950 mV ; SELinux Enforcing après redémarrage.**

**HAL thermique / SELinux :** kernel AVC exact refusait au service hal_thermal_default la traversée du dossier /proc/mtktz de type proc_mtktz. L'ancienne politique vendeur comprenait les types mais pas la règle pour ce domaine. Deux seules autorisations, en lecture seule, ajoutées au CIL de l'ancien vendor : (allow hal_thermal_default proc_mtktz (dir (search getattr open read))) et (allow hal_thermal_default proc_mtktz (file (getattr open read))). Pas de permissive, pas de permission d'écriture, aucun service de fond.

- Compilation offline des CIL réels de LineageOS 18.1, mapping 26.0 et vendor S55 original et modifié avec secilc -N (les conflits neverallow existaient déjà dans le couple logiciel originel).
- SHA256 CIL original : e33ed85bb209b373030e6d4f0a48bbe05038e738e801255052a8da1229567491.
- SHA256 CIL modifié : e0602bae3099274aec52e4fdf8ba6b121859e8ff35dea08dbc89cce967bd6daf.
- Installation et rollback : scripts/fix-lineage18-thermal-sepolicy.sh (--check, --apply, --restore) en TWRP, label vendor_configs_file conservé et vendor remount RO.
- **Android : dumpsys thermalservice lit BAT_T=32°C, CPU_T=62,6°C, GPU_T=62,6°C, SKIN_T=39°C au moment du test ; aucun nouveau refus SELinux du HAL thermique.**

Ces valeurs évoluent avec la charge ; la température n'est pas artificiellement figée.

## Optimisations natives après migration

Paramètres installés et relus :
- low_power_trigger_level = 25 : économie de batterie automatique dès 25 %.
- automatic_power_save_mode = 0.
- mobile_data_always_on = 0 : pas de maintien superflu de données mobiles avec Wi-Fi.
- ble_scan_always_enabled = 0 : réduit les recherches BLE de localisation en arrière-plan, sans éteindre le Bluetooth classique.
- wifi_scan_always_enabled = 0 : valeur existante conservée.
- Doze léger et profond : activés.

Aucune application, service de surveillance ou daemon spécifique n'a été installé. Le téléphone conserve Wi-Fi, Bluetooth, capteurs, appareil photo, GPS, lecteur d'empreinte et possibilité de SIM.

**Test A/B sans SIM, écran éteint, câble USB branché :** sur 113 secondes, le wakelock modem MediaTek `ttyC0` cumulait **44 076 ms** et 62 événements avec la radio cellulaire active. Avec le mode avion temporaire et Wi-Fi/Bluetooth réactivés, le même wakelock a cumulé **0 ms et 0 événement** sur 70 secondes. Les wakelocks `USB.lock` et `battery suspend wakelock` restaient quant à eux actifs pendant la totalité des deux tests : **on ne peut pas mesurer ou promettre l'autonomie réelle hors câble à partir de ces relevés**. Le test a rétabli les paramètres initiaux : `airplane_mode_on=0`, Wi-Fi=ON et Bluetooth=ON, vérifiés en retour. Pour maximiser ponctuellement l'autonomie sans SIM, le mode avion avec Wi-Fi/Bluetooth réactivés est efficace contre le bruit modem, mais il coupe aussi la radio d'appels d'urgence ; **il n'est donc pas imposé en permanence**. Le mode avion devra être désactivé si une SIM est introduite.

Les relevés A/B bruts sont conservés uniquement dans `backups/device-2026-10-10/standby-power-audit-private/` (privé, non publié).

## Charge, récupération et garanties réelles

Sur USB Pegasus, le driver expose Charging, tension du chargeur ~4,79 V, tension batterie ~3,8–3,96 V, température ~31–32 °C, courant instantané de charge non nul et augmentation observée du pourcentage 46 → 47 %. Cela **démontre une recharge effective**, pas le courant disponible avec un chargeur mural ni une batterie en parfait état.

Le bootloader actif possède déjà off-mode-charge=1. Le noyau actif 2020 a CONFIG_MTK_KERNEL_POWER_OFF_CHARGING=y, CONFIG_MTK_SMART_BATTERY=y, CONFIG_MTK_HAFG_20=y et les exécutables charge/fuelgauged dans le ramdisk. **Il ne manque pas une option KPOC à réactiver.**

Lorsqu'il indiquait 0–1 %, le bootloader avait refusé une commande avec « low power, need battery charging » : c'est une protection indépendante d'Android, cohérente avec une tension trop basse ou une lecture de jauge erronée. Une recharge sur chargeur mural avait ensuite permis le retour à 20 % ; ne pas déduire que le circuit charge/PMIC est mort.

L'économiseur à 25 % réduit les risques de décharge rapide, mais **aucun logiciel ne peut garantir qu'un accumulateur lithium-ion physiquement trop déchargé, usé ou défectueux pourra redémarrer**. Ne pas contourner le seuil du bootloader, falsifier le pourcentage ni désactiver les limites thermiques. Laisser le système éteint très longtemps peut également consommer la réserve restante. Une source adaptée en 5 V / 2 A permet normalement une précharge plus efficace qu'un port USB de hub limité, tant que le circuit matériel l'accepte.

## Fingerprint

**État de cette ancienne étape après effacement, maintenant dépassé :** aucune empreinte n'était initialement enregistrée après le formatage des données. **État définitif du 10 octobre 2026 :** le propriétaire a ensuite enregistré son doigt et confirmé un déverrouillage fonctionnel APRÈS redémarrage complet. Le protocole valide combine le patch binaire d'énumération MicroArray et la rétention PHH persistante. Voir FINGERPRINT-FIX.md.

## Réversibilité

Les deux scripts de correction refusent tout binaire, version ou appareil non reconnu, vérifient les SHA256, l'état de batterie et les montages exacts, puis rendent les partitions en lecture seule. Depuis le TWRP original, utiliser --restore pour revenir indépendamment au healthd tension seule ou à la politique vendeur originale. Le bootloader, le boot, les montages hôtes, NVRAM/NVDATA et la GPT n'ont pas été modifiés par ces corrections.


## New live audit, 10 October 2026 — battery recovery still NOT proven

On the reference S55 connected to Pegasus USB, charging and reboot readings included: battery 100% / Full, real voltage 4.216–4.355 V, battery temperature 28–29 C, USB charger voltage approximately 4.79 V, advertised USB maximum charge current 500 mA, and a reported charge counter 4,708,000 microamp-hours. These are plausible live telemetry but are NOT a measured capacity, battery health certificate, or proof of successful deep-discharge recovery.

The phone booted successfully after one reboot at 100% with USB power. Native low-power settings and Doze remained enabled, with 25% automatic Battery Saver; thermal CPU, GPU, SKIN and BAT readings and enforcing SELinux remained available. KPOC kernel support is compiled in and historical fastboot reported off-mode-charge=1. The kernel's and bootloader's safeguards have not been bypassed. An actual powered-off charge, 0% recovery or unplugged standby experiment was NOT performed: repeating the previous failure by intentionally draining an aged battery is unsafe.

NEW RADIO BUG: three separate private tombstones dated 10 October 2026 (01:50, 02:37, 17:52) show the MediaTek vendor rilproxy crashing with a null-pointer SIGSEGV in librilproxy.so at radio::networkInfoInd+272. After a subsequent successful reboot the process was alive and no fresh crash had appeared at the time checked. Comparable rilproxy crashes were also discussed by LineageOS/MediaTek users on a different handset: https://forum.shiftphones.com/threads/lineageos-15-1-android-8-1.1950/page-2 . No evidence yet attributes the past deep-discharge or all modem wakelocks to this crash. Preserve cellular calls, emergency access, and future SIM functionality; no blind modem, vendor binary or radio disablement is justified.

A controlled, safe unplugged idle observation plus calibrated discharge/charging measurements on a wall 5 V / 2 A charger remain necessary before claiming the battery issue resolved. Preserve original radio partition backups and original KPOC protections. Avoid forced shutdown triggered by an untrusted percentage reading and avoid thermal/low-voltage threshold bypasses.
