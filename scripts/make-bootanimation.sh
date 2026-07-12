#!/usr/bin/env bash
# Build a valid bootanimation.zip from a folder.
# The folder must contain: desc.txt, part0/ (PNG frames), part1/ (PNG frames).
# desc.txt example (Doogee S55 screen = 480x960, 30 fps):
#   480 960 30
#   p 1 0 part0     # play part0 once, no pause
#   p 0 0 part1     # loop part1 forever
# Usage: ./make-bootanimation.sh <folder> [output.zip]
set -euo pipefail
SRC="${1:?Usage: make-bootanimation.sh <folder> [out.zip]}"
OUT="${2:-bootanimation.zip}"

[ -f "$SRC/desc.txt" ] || { echo "ERROR: $SRC/desc.txt missing"; exit 1; }

# -0 = STORE (no compression) is MANDATORY for bootanimation.zip
( cd "$SRC" && zip -r -0 -X "$OLDPWD/$OUT" desc.txt part* )

echo ">> Created $OUT"
echo ">> Install with: ./bootanim-replace.sh $OUT"
