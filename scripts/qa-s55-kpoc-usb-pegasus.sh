#!/usr/bin/env bash
# QA lecture seule : detecte les boucles USB Preloader (que Fastboot seul ne voit pas).
# Usage depuis Pegasus : bash qa-s55-kpoc-usb-pegasus.sh "2026-10-29 15:28:00"
set -euo pipefail
since=${1:-"5 minutes ago"}
if ! command -v journalctl >/dev/null || ! command -v lsusb >/dev/null;then
  echo "INCONCLUSIF : journalctl/lsusb absents" >&2;exit 3
fi
log=$(journalctl -k --since "$since" --no-pager)
if test -z "$log";then echo "INCONCLUSIF : aucun evenement noyau depuis $since";exit 3;fi
preloader=$(printf '%s\n' "$log" | grep -Ec 'usb 1-1: New USB device found, idVendor=0e8d, idProduct=2000' || :)
kpoc=$(printf '%s\n' "$log" | grep -Ec 'usb 1-1: New USB device found, idVendor=0e8d, idProduct=2008' || :)
fastboot=$(printf '%s\n' "$log" | grep -Ec 'usb 1-1: New USB device found, idVendor=0bb4, idProduct=0c01' || :)
disconnect=$(printf '%s\n' "$log" | grep -Ec 'usb 1-1: USB disconnect' || :)
echo "QA KPOC depuis: $since"
printf 'preloader=%s kpoc=%s fastboot=%s deconnexions=%s\n' "$preloader" "$kpoc" "$fastboot" "$disconnect"
echo 'ETAT USB ACTUEL'
lsusb | grep -Ei '0e8d|0bb4' || true
if test "$preloader" -gt 1 || test "$fastboot" -gt 0 || test "$kpoc" -gt 2;then
  echo 'FAIL : boucle boot/Preloader ou retour Fastboot; absence de Fastboot seule ne prouve rien.';exit 2
fi
if test "$kpoc" -eq 1 && test "$preloader" -le 1;then
  echo 'PASS USB SEUL : KPOC enumere une fois; charge electrique et ecran NON certifies.';exit 0
fi
echo 'INCONCLUSIF : capture USB incomplete ou etat different du KPOC attendu.';exit 3
