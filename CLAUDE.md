# KPC — правила работы с проектом

Игра про Кота на Godot 4.4 (GDScript). Документация — `docs/`, исходные ТЗ и сценарий — `docs/source/`.

## Обязательные правила пользователя
1. **Версия на сайте — только за большие обновления.** Номер растёт на 0.01 за крупную правку или много
   мелких сразу; бесконечная доводка одной модели номер не меняет (счёт возвращён к 0.02 — 22.10.2026).
   Мелкие правки — просто `git commit && git push origin main`. Большое обновление:
   `GODOT=<путь> ./tools/release_web.sh "что изменилось"`, затем commit и push. Сайт: https://monskov1-gif.github.io/KPC/
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
