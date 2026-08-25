#!/usr/bin/env bash
set -Eeuo pipefail

ADB="${ADB:-adb}"
DATA_DEV="/dev/block/mmcblk0p30"

command -v "$ADB" >/dev/null 2>&1 || { echo "ERREUR: adb introuvable" >&2; exit 1; }
"$ADB" get-state >/dev/null
"$ADB" shell 'test -e /sbin/recovery || test -e /etc/recovery.fstab || { echo "ERREUR: téléphone pas en recovery/TWRP" >&2; exit 2; }'
"$ADB" shell "test -b '$DATA_DEV'" || { echo "ERREUR: $DATA_DEV absent" >&2; exit 1; }

cat <<MSG
ATTENTION: cette opération EFFACE TOUT /data sur $DATA_DEV.
Elle est destinée au Doogee S55 dont userdata commence au secteur 8273920.
MSG
read -r -p "Tape exactement ERASE-DATA pour continuer: " ANSWER
[[ "$ANSWER" == "ERASE-DATA" ]] || { echo "Annulé."; exit 0; }

"$ADB" shell 'umount /sdcard 2>/dev/null || true; umount /data 2>/dev/null || true'
"$ADB" shell "mke2fs -t ext4 '$DATA_DEV'"
"$ADB" shell "tune2fs -l '$DATA_DEV' | grep -iE 'Block count|Block size'"
echo "OK. Tu peux maintenant rebooter Android."
