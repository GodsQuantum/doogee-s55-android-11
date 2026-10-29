#!/usr/bin/env bash
# Deprecated after KPOC USB bootloop observed 29 October 2026.
# Original owner-specific flash harness preserved ONLY in private backups.
printf '%s\n' 'ARRÊT : ancien flash KPOC invalidé (boucles Preloader). Ne pas réinjecter ce boot expérimental.' >&2
printf '%s\n' 'Voir docs/KPOC-FIRMWARE-DIFF-ROOT-CAUSE-2026-10-29.md et scripts/qa-s55-kpoc-usb-pegasus.sh' >&2
exit 78
