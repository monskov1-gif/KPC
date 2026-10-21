#!/usr/bin/env bash
# Новая версия игры для сайта (GitHub Pages).
# Правило проекта: КАЖДАЯ правка = новая версия, номер растёт на 0.01 (0.01, 0.02, …).
#   ./tools/release_web.sh "что изменилось"
# Делает: поднимает версию в project.godot и VERSION, записывает строку в docs/RELEASES.md,
# экспортирует веб-сборку в play/. Коммит и push — отдельно (git add -A && git commit && git push).
set -euo pipefail
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
NOTE="${1:-}"
OLD=$(grep -oP '^config/version="\K[0-9.]+' project.godot)
NEW=$(python3 -c "print(f'{round(float('$OLD') + 0.01, 2):.2f}')")
sed -i "s/^config\/version=\"$OLD\"/config\/version=\"$NEW\"/" project.godot
echo "$NEW" > VERSION
DATE=$(date -u +%Y-%m-%d)
[ -f docs/RELEASES.md ] || printf "# Версии на сайте\n\nКаждая правка публикуется как новая версия (+0.01).\n\n" > docs/RELEASES.md
sed -i "4a - **v$NEW** ($DATE) — ${NOTE:-без описания}" docs/RELEASES.md

"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
rm -rf play && mkdir -p play
"$GODOT" --headless --path . --export-release "Web" play/index.html 2>&1 | grep -vE "^(Godot Engine|$)" | grep -E "ERROR|error" || true
test -f play/index.wasm && test -f play/index.pck
touch play/.gdignore   # Godot не должен импортировать собранную игру как ресурсы проекта
touch .nojekyll        # GitHub Pages отдаёт файлы как есть

cat > index.html <<HTML
<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>KPC — Kot's photo collection · v$NEW</title>
<meta http-equiv="refresh" content="0; url=play/?v=$NEW">
<style>
  body { margin: 0; min-height: 100vh; display: grid; place-items: center;
         background: linear-gradient(#f8ede8, #ead6d4); font-family: system-ui, sans-serif; color: #6e5660; }
  a { background: #d8b36e; color: #4f3a42; padding: 14px 28px; border-radius: 999px; text-decoration: none; font-size: 20px; }
</style>
</head>
<body><a href="play/?v=$NEW">Играть · v$NEW</a></body>
</html>
HTML
echo "Версия v$NEW собрана в play/"
