#!/usr/bin/env bash
set -Eeuo pipefail

ADB="${ADB:-adb}"
FSTAB="${FSTAB:-/vendor/etc/fstab.mt6755}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="$ROOT/backups/fstab"
mkdir -p "$BACKUP_DIR"

command -v "$ADB" >/dev/null 2>&1 || { echo "ERREUR: adb introuvable" >&2; exit 1; }
"$ADB" get-state >/dev/null
"$ADB" shell 'test -e /sbin/recovery || test -e /etc/recovery.fstab || { echo "ERREUR: téléphone pas en recovery/TWRP" >&2; exit 2; }'
"$ADB" shell 'twrp mount vendor >/dev/null 2>&1 || mount /vendor >/dev/null 2>&1 || true; mount -o rw,remount /vendor 2>/dev/null || mount -o remount,rw /vendor 2>/dev/null || true'
"$ADB" shell "test -f '$FSTAB'" || { echo "ERREUR: fstab S55 attendu absent: $FSTAB" >&2; exit 1; }

DATA_LINE="$("$ADB" shell "grep -n '/data' '$FSTAB' 2>/dev/null || true" | tr -d '\r')"
[[ -n "$DATA_LINE" ]] || { echo "ERREUR: aucune entrée /data dans $FSTAB" >&2; exit 1; }

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$BACKUP_DIR/$(basename "$FSTAB").$STAMP.original"

echo "==> $FSTAB"
"$ADB" pull "$FSTAB" "$BACKUP" >/dev/null
sha256sum "$BACKUP"

"$ADB" shell "sed \
  -e 's/forceencrypt/encryptable/g' \
  -e 's/forcefdeorfbe/encryptable/g' \
  -e 's/fileencryption/encryptable/g' \
  -e 's#,encryptable=/dev/block/platform/mtk-msdc.0/11230000.msdc0/by-name/metadata##g' \
  -e 's#,=/dev/block/platform/mtk-msdc.0/11230000.msdc0/by-name/metadata##g' \
  '$FSTAB' > /tmp/fstab.s55.new && \
  cat /tmp/fstab.s55.new > '$FSTAB' && \
  (restorecon '$FSTAB' 2>/dev/null || chcon u:object_r:vendor_configs_file:s0 '$FSTAB') && sync"

META="$("$ADB" shell "ls -lZ '$FSTAB'" | tr -d '\r')"
printf '%s\n' "$META"
"$ADB" shell "grep -n '/data' '$FSTAB' || true"

if grep -q 'unlabeled' <<<"$META" || ! grep -q 'vendor_configs_file' <<<"$META"; then
  echo "ERREUR: contexte SELinux inattendu pour $FSTAB" >&2
  exit 1
fi

if "$ADB" shell "grep -Eq 'forceencrypt|forcefdeorfbe|fileencryption' '$FSTAB'"; then
  echo "ERREUR: mot-clé de chiffrement encore présent dans $FSTAB" >&2
  exit 1
fi

echo "OK: fstab.mt6755 corrigé, backup: $BACKUP"
