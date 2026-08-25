#!/usr/bin/env bash
set -Eeuo pipefail

ADB="${ADB:-adb}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="$ROOT/backups/fstab"
mkdir -p "$BACKUP_DIR"

command -v "$ADB" >/dev/null 2>&1 || { echo "ERREUR: adb introuvable" >&2; exit 1; }
"$ADB" get-state >/dev/null
"$ADB" shell 'test -e /sbin/recovery || test -e /etc/recovery.fstab || { echo "ERREUR: téléphone pas en recovery/TWRP" >&2; exit 2; }'
"$ADB" shell 'twrp mount vendor >/dev/null 2>&1 || mount /vendor >/dev/null 2>&1 || true; mount -o rw,remount /vendor 2>/dev/null || mount -o remount,rw /vendor 2>/dev/null || true'

# shellcheck disable=SC2016  # $f expands in the remote Android shell.
mapfile -t FSTABS < <("$ADB" shell 'for f in /vendor/etc/fstab*; do [ -f "$f" ] && echo "$f"; done' | tr -d '\r')
((${#FSTABS[@]})) || { echo "ERREUR: aucun fstab vendor trouvé" >&2; exit 1; }

STAMP="$(date +%Y%m%d-%H%M%S)"
for f in "${FSTABS[@]}"; do
  base="$(basename "$f")"
  echo "==> $f"
  "$ADB" pull "$f" "$BACKUP_DIR/$base.$STAMP.original" >/dev/null

  "$ADB" shell "sed \
    -e 's/forceencrypt/encryptable/g' \
    -e 's/forcefdeorfbe/encryptable/g' \
    -e 's/fileencryption/encryptable/g' \
    -e 's#,encryptable=/dev/block/platform/mtk-msdc.0/11230000.msdc0/by-name/metadata##g' \
    -e 's#,=/dev/block/platform/mtk-msdc.0/11230000.msdc0/by-name/metadata##g' \
    '$f' > /tmp/fstab.s55.new && \
    cat /tmp/fstab.s55.new > '$f' && \
    (restorecon '$f' 2>/dev/null || chcon u:object_r:vendor_configs_file:s0 '$f') && sync"

  "$ADB" shell "ls -lZ '$f'; grep -n '/data' '$f' || true"
  META="$("$ADB" shell "ls -lZ '$f'" | tr -d '\r')"
  if grep -q 'unlabeled' <<<"$META"; then
    echo "ERREUR: $f est unlabeled. Stop." >&2
    exit 1
  fi
  if "$ADB" shell "grep -Eq 'forceencrypt|forcefdeorfbe|fileencryption' '$f'"; then
    echo "ERREUR: mot-clé de chiffrement encore présent dans $f" >&2
    exit 1
  fi
done

echo "OK: fstab(s) corrigé(s), backups dans $BACKUP_DIR"
