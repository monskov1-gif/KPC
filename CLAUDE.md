# KPC — правила работы с проектом

Игра про Кота на Godot 4.4 (GDScript). Документация — `docs/`, исходные ТЗ и сценарий — `docs/source/`.

## Обязательные правила пользователя
1. **Каждая правка — новая версия на сайте.** Номер версии растёт на 0.01 (0.01, 0.02, 0.03 …).
   После любых изменений: `GODOT=<путь> ./tools/release_web.sh "что изменилось"`, затем
   `git add -A && git commit && git push origin main`. Сайт: https://monskov1-gif.github.io/KPC/
   (GitHub Pages из ветки `main`, корень; игра — в `play/`). Список версий — `docs/RELEASES.md`.
2. **Скриншоты на каждом этапе** присылать пользователю (`tools/capture.sh`, папка `docs/screenshots/`).
3. **Агенты-критики** (`.claude/agents/`: tz-critic, canon-critic, visual-critic, code-critic, ui-critic,
   model-critic) запускать после этапов и исправлять найденное. Модели персонажей сверять с оригиналом
   **наложением** (`tools/art/ref_overlay.sh <portrait|front> <id>`) — цель «1 в 1», ошибки в таблице ориентиров.
4. **Стиль интерфейса** — мягкий, «облачный», светлый, больше иконок, редкость звёздами,
   характеристики по долгому нажатию; подробно в `docs/UI_STYLE.md`.
5. Не выдумывать сюжет и канон: источник — `docs/source/story_and_chapter1_script.txt`;
   спорное — в `docs/OPEN_QUESTIONS.md`.

## Команды
- Тесты: `GODOT=<путь> ./tools/run_tests.sh` (любая SCRIPT ERROR = провал).
- Скриншот: `GODOT=<путь> ./tools/capture.sh <scene> <out.png> [WxH] [frames] [debug_метод]`.
- Веб-сборка требует шаблонов экспорта Godot 4.4.1 (web_nothreads) в
  `~/.local/share/godot/export_templates/4.4.1.stable/`.
