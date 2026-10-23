#!/usr/bin/env bash
# Снимок локации: ./tools/shoot_loc.sh <loc> <time> "<cam x,y,z>" "<look x,y,z>" <out.png> [WxH] [cast]
# (координаты Blender: z — вверх). Для цикла критиков по docs/location-kit/critics.md.
set -euo pipefail
cd "$(dirname "$0")/.."
KPC_LOC="$1" KPC_TIME="$2" KPC_CAM="$3" KPC_LOOK="$4" KPC_CAST="${7:-}" \
  ./tools/capture.sh res://scenes/dev/location_view.tscn "$5" "${6:-1280x720}" 12 2>&1 | grep -E "SCRIPT|Снимок" || true
