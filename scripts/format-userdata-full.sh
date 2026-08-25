#!/usr/bin/env bash
set -Eeuo pipefail

ADB="${ADB:-adb}"
DISK="/dev/block/mmcblk0"
DATA_DEV="/dev/block/mmcblk0p30"
EXPECTED_P30_FIRST="8273920"

command -v "$ADB" >/dev/null 2>&1 || { echo "ERREUR: adb introuvable" >&2; exit 1; }
"$ADB" get-state >/dev/null
"$ADB" shell 'test -e /sbin/recovery || test -e /etc/recovery.fstab || { echo "ERREUR: téléphone pas en recovery/TWRP" >&2; exit 2; }'
"$ADB" shell 'command -v sgdisk >/dev/null 2>&1 || { echo "ERREUR: sgdisk absent dans TWRP" >&2; exit 2; }'
"$ADB" shell "test -b '$DATA_DEV'" || { echo "ERREUR: $DATA_DEV absent" >&2; exit 1; }

P30_INFO="$("$ADB" shell "sgdisk -i 30 '$DISK'" | tr -d '\r')"
P30_FIRST="$(awk -F: '/First sector/{sub(/^[[:space:]]*/,"",$2); split($2,a," "); print a[1]}' <<<"$P30_INFO")"

[[ "$P30_FIRST" == "$EXPECTED_P30_FIRST" ]] || {
  echo "ERREUR: p30 commence au secteur ${P30_FIRST:-inconnu}, attendu $EXPECTED_P30_FIRST." >&2
  echo "Aucun formatage effectué." >&2
  exit 1
}

cat <<MSG
ATTENTION: cette opération EFFACE TOUT /data sur $DATA_DEV.
Garde-fou validé: p30 commence bien au secteur $EXPECTED_P30_FIRST.
MSG
read -r -p "Tape exactement ERASE-DATA pour continuer: " ANSWER
[[ "$ANSWER" == "ERASE-DATA" ]] || { echo "Annulé."; exit 0; }

"$ADB" shell 'umount /sdcard 2>/dev/null || true; umount /data 2>/dev/null || true'

if "$ADB" shell "mount | grep -F '$DATA_DEV'" >/dev/null 2>&1; then
  echo "ERREUR: $DATA_DEV est encore monté. Aucun formatage effectué." >&2
  exit 1
fi

"$ADB" shell "mke2fs -t ext4 '$DATA_DEV'"
"$ADB" shell "tune2fs -l '$DATA_DEV' | grep -iE 'Block count|Block size'"
echo "OK. Tu peux maintenant rebooter Android."
