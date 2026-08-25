#!/usr/bin/env bash
set -Eeuo pipefail

SRC="${1:-}"
OUT="${2:-bootanimation.zip}"
[[ -n "$SRC" && -d "$SRC" ]] || { echo "Usage: $0 <dossier-animation> [sortie.zip]" >&2; exit 1; }
[[ -f "$SRC/desc.txt" ]] || { echo "ERREUR: $SRC/desc.txt absent" >&2; exit 1; }
command -v zip >/dev/null 2>&1 || { echo "ERREUR: zip absent" >&2; exit 1; }

read -r W H FPS < "$SRC/desc.txt"
[[ "$W" =~ ^[0-9]+$ && "$H" =~ ^[0-9]+$ && "$FPS" =~ ^[0-9]+$ ]] || { echo "ERREUR: première ligne desc.txt invalide" >&2; exit 1; }
if [[ "$W:$H" != "720:1440" ]]; then
  echo "NOTE: le S55 est 720×1440 en portrait; desc.txt indique ${W}×${H}."
fi

rm -f "$OUT"
(
  cd "$SRC"
  zip -0 -r "$OLDPWD/$OUT" desc.txt part* >/dev/null
)
echo "Créé: $OUT (ZIP STORE / sans compression)"
