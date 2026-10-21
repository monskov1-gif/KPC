class_name SaveService
extends RefCounted
## Локальные сохранения: версия схемы, явные миграции, атомарная запись, резервная копия.

const CURRENT_VERSION := 1

var path: String
var last_error := ""


func _init(p_path: String = "user://save_slot_1.json") -> void:
	path = p_path


## Атомарная запись: пишем во временный файл, текущий файл переносим в .bak, затем переименовываем.
func save(data: Dictionary) -> bool:
	last_error = ""
	var payload := {"version": CURRENT_VERSION, "saved_at": Time.get_datetime_string_from_system(true), "data": data}
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		last_error = "save.open_failed"
		return false
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		last_error = "save.dir_failed"
		return false
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(path + ".bak"):
			dir.remove(path.get_file() + ".bak")
		dir.rename(path.get_file(), path.get_file() + ".bak")
	if dir.rename(tmp.get_file(), path.get_file()) != OK:
		last_error = "save.rename_failed"
		return false
	return true


func exists() -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak")


## Возвращает {ok, data, from_backup, error_key}. Повреждённый основной файл → попытка из .bak.
func load_save() -> Dictionary:
	var main := _read(path)
	if main.ok:
		return main
	var backup := _read(path + ".bak")
	if backup.ok:
		backup.from_backup = true
		return backup
	return {"ok": false, "data": {}, "from_backup": false, "error_key": main.error_key}


func _read(p: String) -> Dictionary:
	var fail := func(key): return {"ok": false, "data": {}, "from_backup": false, "error_key": key}
	if not FileAccess.file_exists(p):
		return fail.call("save.not_found")
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(p)) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return fail.call("save.corrupted")
	var payload: Dictionary = json.data
	var version := int(payload.get("version", 0))
	if version > CURRENT_VERSION:
		return fail.call("save.newer_version")
	var data: Dictionary = payload.get("data", {})
	data = SaveMigrations.migrate(data, version, CURRENT_VERSION)
	return {"ok": true, "data": data, "from_backup": false, "error_key": ""}


func delete_all() -> void:
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			dir.remove(path.get_file() + suffix)
