# DOOGEE S55 — Batterie, températures et veille (10 octobre 2026)

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

Correctif du vendor MicroArray préservé avec contexte SELinux. Le service biométrique était actif sans mort de HAL après plusieurs démarrages. La mémoire utilisateur ayant été formatée, aucune empreinte n'est enregistrée : **il faudra une inscription physique**, puis authentifier ce même doigt après redémarrage pour valider la persistance. Ne jamais considérer l'absence d'empreintes après wipe comme un défaut du capteur.

## Réversibilité

Les deux scripts de correction refusent tout binaire, version ou appareil non reconnu, vérifient les SHA256, l'état de batterie et les montages exacts, puis rendent les partitions en lecture seule. Depuis le TWRP original, utiliser --restore pour revenir indépendamment au healthd tension seule ou à la politique vendeur originale. Le bootloader, le boot, les montages hôtes, NVRAM/NVDATA et la GPT n'ont pas été modifiés par ces corrections.
