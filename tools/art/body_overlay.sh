#!/usr/bin/env bash
# Сверка телосложения с референс-листом наложением силуэтов (спереди и сбоку).
# tools/art/body_overlay.sh [model.glb] [out.png]
set -euo pipefail
cd "$(dirname "$0")/../.."
GLB="${1:-art/characters/kot.glb}"; OUT="${2:-docs/screenshots/overlay_kot_body.png}"
TMP="$(mktemp -d)"
"${BLENDER_PY:-/home/user/tools/bpyenv/bin/python}" -I tools/art/body_overlay_render.py -- "$GLB" "$TMP/sil" 2>&1 | grep -E "Error|Traceback" || true
python3 tools/art/body_overlay.py --model-prefix "$TMP/sil" --out "$OUT"
