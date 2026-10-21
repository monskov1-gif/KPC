# Сборка, запуск и тесты

## Требования
- Godot **4.4.1** (стандартная сборка, не .NET).

## Запуск
Открыть папку репозитория в Godot и нажать F5. Сейчас главная сцена — экран гардероба
(`scenes/main.tscn`). Сохранение лежит в `user://save_slot_1.json`
(Linux: `~/.local/share/godot/app_userdata/KPC — Kot's photo collection/`).

## Автотесты
```bash
GODOT=/путь/к/godot ./tools/run_tests.sh
```
Скрипт импортирует проект и запускает `tests/run_tests.gd` в headless-режиме.
Любая `SCRIPT ERROR` считается падением. Тесты используют отдельный файл сохранения.

## Скриншоты для проверки интерфейса
```bash
GODOT=/путь/к/godot ./tools/capture.sh res://scenes/ui/wardrobe.tscn docs/screenshots/x.png 1600x900 25 debug_long_press
```
Нужны `xvfb-run` и Mesa (программный OpenGL). Съёмка идёт через рендерер Compatibility, поэтому свет
проще, чем в игре на видеокарте. Последний аргумент — метод сцены, который вызывается перед снимком
(`debug_try_on`, `debug_long_press`, `debug_result`, `debug_challenge_tab`, `debug_presets`).
Снимки берут отдельное сохранение и каждый раз начинают новую игру.

## Агенты-критики
В `.claude/agents/` лежат роли: `tz-critic` (соответствие ТЗ), `canon-critic` (канон и сюжет),
`visual-critic` (скриншоты и стиль), `code-critic` (баги и тесты). Их запускают после каждого этапа.
