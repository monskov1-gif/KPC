#!/usr/bin/env bash
# Снимок сцены в виртуальном дисплее (Xvfb + программный OpenGL).
# ./tools/capture.sh <scene.tscn> <out.png> [WxH] [frames] [method]
# Внимание: съёмка идёт через рендерер Compatibility (OpenGL), а игра настроена на Forward+;
# свет и постобработка на снимке проще, чем в реальной игре на видеокарте.
set -euo pipefail
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
SCENE="$1"; OUT="$2"; RES="${3:-1600x900}"; FRAMES="${4:-30}"; METHOD="${5:-}"
# Отдельное сохранение для снимков: каждый снимок начинается с новой игры.
export KPC_SAVE_PATH="user://capture_save.json"
rm -f "$HOME/.local/share/godot/app_userdata/KPC — Kot's photo collection/capture_save.json"*
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true   # новые текстуры должны быть импортированы
W="${RES%x*}"; H="${RES#*x}"
xvfb-run -a -s "-screen 0 ${W}x${H}x24" \
  "$GODOT" --path . --rendering-driver opengl3 --resolution "$RES" -s tools/capture.gd -- "$SCENE" "$OUT" "$FRAMES" "$METHOD" 2>&1 \
  | grep -vE "^(Godot Engine|OpenGL API|$)" || true
test -f "$OUT"
