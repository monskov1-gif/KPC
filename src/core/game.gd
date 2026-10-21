extends Node
## Автозагрузка Game: держит GameSession, сохранения и локализацию на время работы игры.

signal session_ready
signal saved(ok: bool)

const SAVE_PATH := "user://save_slot_1.json"

var session: GameSession
var save_service := SaveService.new(SAVE_PATH)
var load_notes: Array[String] = []


func _ready() -> void:
	Localization.load_all("res://data/localization")
	session = GameSession.create()
	for e in session.errors:
		push_error("Данные: " + e)
	for w in session.warnings:
		push_warning("Данные: " + w)
	load_or_new()
	session_ready.emit()


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
