#!/usr/bin/env bash
set -Eeuo pipefail

ADB="${ADB:-adb}"
TARGET="/vendor/lib64/libfprint-x64.so"
ORIG_SHA="e76c3884ab9935ac60c38370210747465b76fadda5acd3470e199f7c7070af06"
PATCH_SHA="3d89603ed3025bdc14e65d6269024c52920808c747aeb2d79417741d7cc7f9f6"
PATCH_OFF=$((0x4ecc))
ORIG_BYTES="e203012a"
PATCH_BYTES="02008052"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="$ROOT/backups/fingerprint"
mkdir -p "$BACKUP_DIR"

command -v "$ADB" >/dev/null 2>&1 || { echo "ERREUR: adb introuvable" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERREUR: python3 introuvable" >&2; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { echo "ERREUR: sha256sum introuvable" >&2; exit 1; }

"$ADB" get-state >/dev/null
"$ADB" shell 'test -e /sbin/recovery || test -e /etc/recovery.fstab || { echo "ERREUR: téléphone pas en recovery/TWRP" >&2; exit 2; }'
"$ADB" shell 'twrp mount vendor >/dev/null 2>&1 || mount /vendor >/dev/null 2>&1 || true; mount -o rw,remount /vendor 2>/dev/null || mount -o remount,rw /vendor 2>/dev/null || true'

CURRENT_SHA="$("$ADB" shell "sha256sum '$TARGET'" | tr -d '\r' | awk '{print $1}')"
printf 'SHA actuel: %s\n' "$CURRENT_SHA"

if [[ "$CURRENT_SHA" == "$PATCH_SHA" ]]; then
  echo "Déjà patché: aucune modification nécessaire."
  "$ADB" shell "ls -lZ '$TARGET'"
  exit 0
fi

if [[ "$CURRENT_SHA" != "$ORIG_SHA" ]]; then
  echo "ERREUR: binaire fingerprint inconnu." >&2
  echo "Attendu original: $ORIG_SHA" >&2
  echo "Attendu patché  : $PATCH_SHA" >&2
  echo "Trouvé          : $CURRENT_SHA" >&2
  echo "Aucun octet n'a été modifié." >&2
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
ORIG_LOCAL="$BACKUP_DIR/libfprint-x64.$STAMP.original.so"
PATCH_LOCAL="$(mktemp --suffix=.libfprint-x64.patched.so)"
trap 'rm -f "$PATCH_LOCAL"' EXIT

printf '\n==> Métadonnées avant\n'
BEFORE_META="$("$ADB" shell "ls -lZ '$TARGET'" | tr -d '\r')"
printf '%s\n' "$BEFORE_META"

printf '\n==> Backup original\n'
"$ADB" pull "$TARGET" "$ORIG_LOCAL" >/dev/null
echo "$ORIG_SHA  $ORIG_LOCAL" | sha256sum -c -

python3 - "$ORIG_LOCAL" "$PATCH_LOCAL" "$PATCH_OFF" "$ORIG_BYTES" "$PATCH_BYTES" "$PATCH_SHA" <<'PY'
import hashlib, sys
src, dst, off_s, old_hex, new_hex, expected_sha = sys.argv[1:]
off = int(off_s)
data = bytearray(open(src, 'rb').read())
old = bytes.fromhex(old_hex)
new = bytes.fromhex(new_hex)
found = bytes(data[off:off+len(old)])
print(f"offset=0x{off:x} bytes_avant={found.hex()}")
if found != old:
    raise SystemExit(f"ERREUR: octets inattendus; attendu {old.hex()}, trouvé {found.hex()}")
data[off:off+len(old)] = new
open(dst, 'wb').write(data)
sha = hashlib.sha256(data).hexdigest()
print(f"sha256_patch={sha}")
if sha != expected_sha:
    raise SystemExit(f"ERREUR: hash patché inattendu; attendu {expected_sha}")
PY

printf '\n==> Push temporaire et vérification\n'
"$ADB" push "$PATCH_LOCAL" /tmp/libfprint-x64.s55-enumfix.so >/dev/null
REMOTE_TMP_SHA="$("$ADB" shell 'sha256sum /tmp/libfprint-x64.s55-enumfix.so' | tr -d '\r' | awk '{print $1}')"
[[ "$REMOTE_TMP_SHA" == "$PATCH_SHA" ]] || { echo "ERREUR: hash temporaire incorrect" >&2; exit 1; }

printf '\n==> Écriture dans le fichier existant (inode/xattrs conservés)\n'
"$ADB" shell "cat /tmp/libfprint-x64.s55-enumfix.so > '$TARGET' && sync"

FINAL_SHA="$("$ADB" shell "sha256sum '$TARGET'" | tr -d '\r' | awk '{print $1}')"
if [[ "$FINAL_SHA" != "$PATCH_SHA" ]]; then
  echo "ERREUR: vérification finale échouée; restauration de l'original." >&2
  "$ADB" push "$ORIG_LOCAL" /tmp/libfprint-x64.restore.so >/dev/null
  "$ADB" shell "cat /tmp/libfprint-x64.restore.so > '$TARGET' && sync"
  exit 1
fi

printf '\n==> Métadonnées après\n'
AFTER_META="$("$ADB" shell "ls -lZ '$TARGET'" | tr -d '\r')"
printf '%s\n' "$AFTER_META"

if ! grep -q 'u:object_r:vendor_file:s0' <<<"$AFTER_META"; then
  echo "Contexte vendor_file absent, tentative restorecon/chcon..."
  "$ADB" shell "restorecon '$TARGET' 2>/dev/null || chcon u:object_r:vendor_file:s0 '$TARGET'"
  AFTER_META="$("$ADB" shell "ls -lZ '$TARGET'" | tr -d '\r')"
  printf '%s\n' "$AFTER_META"
  grep -q 'u:object_r:vendor_file:s0' <<<"$AFTER_META" || { echo "ERREUR: contexte SELinux non restauré" >&2; exit 1; }
fi

printf '\nOK\nOriginal sauvegardé: %s\nSHA patché téléphone: %s\n' "$ORIG_LOCAL" "$FINAL_SHA"
