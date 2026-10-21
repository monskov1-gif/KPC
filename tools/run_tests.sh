#!/usr/bin/env bash
# Импорт проекта (регистрация class_name) и запуск автотестов в headless-режиме.
# Любая ошибка скрипта (SCRIPT ERROR) считается падением, даже если тест-раннер её не перехватил.
set -uo pipefail
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
OUT="$("$GODOT" --headless --path . -s tests/run_tests.gd 2>&1)"
CODE=$?
echo "$OUT"
if grep -qE "SCRIPT ERROR|Parse Error|Compile Error" <<<"$OUT"; then
  echo "Обнаружены ошибки скриптов — прогон считается проваленным."
  exit 1
fi
exit $CODE
