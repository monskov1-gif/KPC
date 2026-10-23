#!/usr/bin/env bash
# Сквозная проверка пролога на автопилоте (без окна). Код выхода 0 — пройден целиком.
set -uo pipefail
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
export KPC_SAVE_PATH="user://e2e_save.json" KPC_AUTOPILOT=1 KPC_STORY_FAST=1 KPC_STORY_SCENE=0
rm -f "$HOME/.local/share/godot/app_userdata/KPC — Kot's photo collection/e2e_save.json"*
"$GODOT" --headless --path . -s tools/e2e_prologue.gd 2>&1 | grep -vE "^(Godot Engine|$)" | grep -E "шаг|ПРОЙДЕН|ЗАСТРЯЛ|SCRIPT ERROR|at: " 
exit "${PIPESTATUS[0]}"
