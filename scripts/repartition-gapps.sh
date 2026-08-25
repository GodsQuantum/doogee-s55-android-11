#!/usr/bin/env bash
set -Eeuo pipefail

ADB="${ADB:-adb}"
DISK="/dev/block/mmcblk0"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="$ROOT/backups/gpt"
mkdir -p "$BACKUP_DIR"

command -v "$ADB" >/dev/null 2>&1 || { echo "ERREUR: adb introuvable" >&2; exit 1; }
"$ADB" get-state >/dev/null
"$ADB" shell 'command -v sgdisk >/dev/null 2>&1 || { echo "ERREUR: sgdisk absent dans TWRP" >&2; exit 2; }'
"$ADB" shell 'test -e /sbin/recovery || test -e /etc/recovery.fstab || { echo "ERREUR: téléphone pas en recovery/TWRP" >&2; exit 2; }'

part_bounds() {
  local n="$1" info first last
  info="$("$ADB" shell "sgdisk -i $n '$DISK'" | tr -d '\r')"
  first="$(awk -F: '/First sector/{gsub(/[^0-9]/,"",$2); print $2}' <<<"$info")"
  last="$(awk -F: '/Last sector/{gsub(/[^0-9]/,"",$2); print $2}' <<<"$info")"
  printf '%s %s\n' "$first" "$last"
}

read -r P27_FIRST P27_LAST < <(part_bounds 27)
read -r P28_FIRST P28_LAST < <(part_bounds 28)
read -r P29_FIRST P29_LAST < <(part_bounds 29)
read -r P30_FIRST P30_LAST < <(part_bounds 30)

printf 'p27 %s..%s\np28 %s..%s\np29 %s..%s\np30 %s..%s\n' \
  "$P27_FIRST" "$P27_LAST" "$P28_FIRST" "$P28_LAST" "$P29_FIRST" "$P29_LAST" "$P30_FIRST" "$P30_LAST"

PATCHED=0
if [[ "$P27_FIRST:$P27_LAST:$P28_FIRST:$P28_LAST:$P29_FIRST:$P29_LAST:$P30_FIRST" == \
      "491520:1540095:1540096:7389183:7389184:8273919:8273920" ]]; then
  : # stock geometry detected
elif [[ "$P27_FIRST:$P27_LAST:$P28_FIRST:$P28_LAST:$P29_FIRST:$P29_LAST:$P30_FIRST" == \
        "491520:1540095:1540096:7913471:7913472:8273919:8273920" ]]; then
  PATCHED=1
else
  echo "ERREUR: géométrie inconnue. Aucun repartitionnement effectué." >&2
  exit 1
fi

if (( PATCHED )); then
  echo "La géométrie GApps est déjà appliquée. Rien à faire."
  exit 0
fi

# Preserve the original partition type GUIDs.
get_type_guid() {
  "$ADB" shell "sgdisk -i $1 '$DISK'" | tr -d '\r' | awk -F: '/Partition GUID code/{gsub(/^ +| +$/,"",$2); split($2,a," "); print a[1]}'
}
TYPE28="$(get_type_guid 28)"
TYPE29="$(get_type_guid 29)"
[[ -n "$TYPE28" && -n "$TYPE29" ]] || { echo "ERREUR: impossible de lire les GUID de type" >&2; exit 1; }

STAMP="$(date +%Y%m%d-%H%M%S)"
REMOTE_BACKUP="/tmp/S55-gpt-before-gapps-$STAMP.bin"
LOCAL_BACKUP="$BACKUP_DIR/S55-gpt-before-gapps-$STAMP.bin"

printf '\n==> Backup GPT\n'
"$ADB" shell "sgdisk --backup='$REMOTE_BACKUP' '$DISK'"
"$ADB" pull "$REMOTE_BACKUP" "$LOCAL_BACKUP" >/dev/null
sha256sum "$LOCAL_BACKUP"

printf '\n==> Repartitionnement system/cache\n'
"$ADB" shell "sgdisk \
  -d 28 -d 29 \
  -n 28:1540096:7913471 -t 28:$TYPE28 -c 28:system \
  -n 29:7913472:8273919 -t 29:$TYPE29 -c 29:cache \
  '$DISK'"

printf '\n==> Vérification GPT\n'
"$ADB" shell "sgdisk -v '$DISK'"

read -r N28_FIRST N28_LAST < <(part_bounds 28)
read -r N29_FIRST N29_LAST < <(part_bounds 29)
read -r N30_FIRST _ < <(part_bounds 30)
[[ "$N28_FIRST:$N28_LAST:$N29_FIRST:$N29_LAST:$N30_FIRST" == \
   "1540096:7913471:7913472:8273919:8273920" ]] || {
  echo "ERREUR: géométrie finale inattendue. NE PAS FLASHER SYSTEM." >&2
  echo "Backup: $LOCAL_BACKUP" >&2
  exit 1
}

printf '\nGPT OK. Backup: %s\n' "$LOCAL_BACKUP"
echo "Redémarrage de TWRP pour relire proprement la table de partitions..."
"$ADB" reboot recovery
"$ADB" wait-for-device
sleep 3
echo "TWRP revenu. Reprendre le guide GApps à l'étape flash de l'image."
