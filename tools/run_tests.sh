#!/usr/bin/env bash
# Импорт проекта (регистрация class_name) и запуск автотестов в headless-режиме.
# Любая ошибка скрипта (SCRIPT ERROR) считается падением, даже если тест-раннер её не перехватил.
set -uo pipefail
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
export KPC_SAVE_PATH="user://test_autoload_save.json"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
OUT="$("$GODOT" --headless --path . -s tests/run_tests.gd 2>&1)"
CODE=$?
echo "$OUT"
if grep -qE "SCRIPT ERROR|Parse Error|Compile Error" <<<"$OUT"; then
  echo "Обнаружены ошибки скриптов — прогон считается проваленным."
  exit 1
fi
if [ "$CODE" = "0" ] && [ -z "${KPC_SKIP_E2E:-}" ]; then
  echo "Сквозная проверка пролога (автопилот)…"
  E2E="$(./tools/e2e_prologue.sh)"
  CODE=$?
  grep -E "ПРОЙДЕН|ЗАСТРЯЛ|SCRIPT ERROR" <<<"$E2E" || echo "$E2E" | tail -20
  if grep -q "SCRIPT ERROR" <<<"$E2E"; then CODE=1; fi
fi
exit $CODE
