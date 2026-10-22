#!/usr/bin/env bash
# Иконки вещей из 3D-мешей одежды → art/items/<id>.png. GODOT=<путь> tools/render_icons.sh
set -euo pipefail
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
xvfb-run -a -s "-screen 0 640x480x24" "$GODOT" --path . --rendering-driver opengl3 --resolution 640x480 -s tools/render_icons.gd 2>&1 \
  | grep -vE "^(Godot Engine|OpenGL API|$)" | grep -v ALSA || true
