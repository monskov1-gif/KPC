extends Node
## Автозагрузка Game: держит GameSession, сохранения и локализацию на время работы игры.

signal session_ready
signal saved(ok: bool)

const SAVE_PATH := "user://save_slot_1.json"
## Опорная короткая сторона экрана: при ней масштаб интерфейса = 1.
const UI_REFERENCE_SHORT_SIDE := 900.0

var session: GameSession
## Путь можно переопределить переменной окружения (снимки экрана и тесты не трогают настоящее сохранение).
var save_service := SaveService.new(OS.get_environment("KPC_SAVE_PATH") if OS.has_environment("KPC_SAVE_PATH") else SAVE_PATH)
var load_notes: Array[String] = []
## Пользовательский множитель масштаба интерфейса (настройка доступности).
var ui_scale := 1.0:
	set(v):
		ui_scale = clampf(v, 0.75, 1.5)
		_update_ui_scale()


func _ready() -> void:
	get_tree().root.size_changed.connect(_update_ui_scale)
	_update_ui_scale()
	Localization.load_all("res://data/localization")
	session = GameSession.create()
	for e in session.errors:
		push_error("Данные: " + e)
	for w in session.warnings:
		push_warning("Данные: " + w)
	load_or_new()
	session_ready.emit()


## Масштаб по короткой стороне: на телефоне в портрете логическая ширина уменьшается,
## и экраны переключаются на узкую раскладку вместо того, чтобы мельчить.
func _update_ui_scale() -> void:
	var win := get_tree().root
	var sz := Vector2(win.size)
	if sz.x <= 0 or sz.y <= 0:
		return
	win.content_scale_factor = minf(sz.x, sz.y) / UI_REFERENCE_SHORT_SIDE * ui_scale


func load_or_new() -> void:
	var res := save_service.load_save()
	if res.ok:
		load_notes = session.load_save_dict(res.data)
		if res.from_backup:
			load_notes.append("Основной файл сохранения повреждён — загружена резервная копия.")
	else:
		if res.error_key != "save.not_found":
			load_notes.append("Не удалось загрузить сохранение (%s) — начата новая игра. Файл не удалён." % res.error_key)
			save_service.path = "user://save_slot_1_recovered.json"
		session.new_game()
	for n in load_notes:
		push_warning(n)


func save_game() -> bool:
	var ok := save_service.save(session.to_save_dict())
	if not ok:
		push_error("Ошибка сохранения: %s" % save_service.last_error)
	saved.emit(ok)
	return ok


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		if session:
			save_game()
