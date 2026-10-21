#!/usr/bin/env bash
# Снять рендер для наложения и собрать сравнение с референсом.
# GODOT=<путь> tools/art/ref_overlay.sh <view: portrait|front> <id> [out.png]   (KPC_YAW — поворот модели)
set -euo pipefail
cd "$(dirname "$0")/../.."
VIEW="${1:-portrait}"; ID="${2:-kot}"; OUT="${3:-docs/screenshots/overlay_${ID}_${VIEW}.png}"
TMP="$(mktemp -d)"
export KPC_LANDMARKS="$TMP/lm.json"
./tools/capture.sh res://scenes/dev/character_lineup.tscn "$TMP/render.png" 1000x1040 40 "debug_ref_${VIEW}_${ID}" >/dev/null
python3 tools/art/ref_overlay.py --render "$TMP/render.png" --lm "$TMP/lm.json" --view "$VIEW" --out "$OUT"
echo "Наложение: $OUT"
