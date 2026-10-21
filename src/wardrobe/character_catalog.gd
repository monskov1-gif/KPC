class_name CharacterCatalog
extends RefCounted
## Технические данные персонажей (тип тела, фирменный образ). Сюжетные данные здесь не хранятся.

var errors: Array[String] = []
var _chars: Dictionary = {}
var _order: Array[String] = []


func load_from_array(entries: Array, config: WardrobeConfig) -> void:
	for e in entries:
		var id := str(e.get("id", ""))
		if id == "" or _chars.has(id):
			errors.append("Персонаж с пустым или повторяющимся id: '%s'" % id)
			continue
		if not config.body_types.has(str(e.get("body_type", ""))):
			errors.append("[%s] неизвестный тип тела '%s'" % [id, e.get("body_type")])
			continue
		_chars[id] = e
		_order.append(id)


func has_character(id: String) -> bool:
	return _chars.has(id)


func get_data(id: String) -> Dictionary:
	return _chars.get(id, {})


func body_type(id: String) -> String:
	return str(_chars.get(id, {}).get("body_type", ""))


func signature_outfit(id: String) -> Dictionary:
	return _chars.get(id, {}).get("signature_outfit", {})


func ids() -> Array[String]:
	return _order.duplicate()


func placeholder_color(id: String) -> Color:
	return Color.from_string(str(_chars.get(id, {}).get("placeholder_color", "#888888")), Color.GRAY)
