#!/usr/bin/env bash
# Прохождение пролога «как игрок» (tools/playtest.gd): дважды — с новой игры и со старого сохранения.
set -uo pipefail
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
CODE=0
for mode in new old; do
  export KPC_SAVE_PATH="user://playtest_$mode.json" KPC_STORY_FAST=1 KPC_STORY_SCENE=0
  rm -f "$HOME/.local/share/godot/app_userdata/KPC — Kot's photo collection/playtest_$mode.json"*
  if [ "$mode" = old ]; then export KPC_PLAYTEST_OLD_SAVE=1; else unset KPC_PLAYTEST_OLD_SAVE; fi
  echo "== прохождение игроком: $( [ $mode = new ] && echo 'новая игра' || echo 'старое сохранение')"
  OUT="$("$GODOT" --headless --path . -s tools/playtest.gd 2>&1)"
  C=$?
  grep -E "шаг |ПРОЙДЕНО|ЗАСТРЯЛ|гардероб|старое|^  (позиция|обучение|нет|упёрся)|SCRIPT ERROR" <<<"$OUT" | grep -vE "^  шаг " ; grep -E "^  шаг " <<<"$OUT" | tail -1
  if grep -q "SCRIPT ERROR" <<<"$OUT"; then C=1; fi
  [ $C -ne 0 ] && CODE=$C
done
exit $CODE
