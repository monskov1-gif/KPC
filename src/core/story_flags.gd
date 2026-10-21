class_name StoryFlags
extends RefCounted
## Сюжетные флаги. Набор флагов задаётся сценарными данными, код их не придумывает.

signal flag_changed(flag: String, value: Variant)

var _flags: Dictionary = {}


func set_flag(flag: String, value: Variant = true) -> void:
	if _flags.get(flag) == value:
		return
	_flags[flag] = value
	flag_changed.emit(flag, value)


func get_flag(flag: String, default: Variant = false) -> Variant:
	return _flags.get(flag, default)


func is_set(flag: String) -> bool:
	return bool(_flags.get(flag, false))


func to_dict() -> Dictionary:
	return _flags.duplicate(true)


func reset() -> void:
	_flags.clear()


func load_dict(d: Dictionary) -> void:
	_flags = d.duplicate(true)
