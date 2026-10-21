class_name OutfitPresetManager
extends RefCounted
## Сохранённые комплекты персонажей. Применение не создаёт предметов; проблемы возвращаются списком.

signal presets_changed(character_id: String)

var equipment: CharacterEquipment
var _presets: Array[Dictionary] = []   # {id, name, character_id, slots, order}
var _counter := 0


func _init(p_equipment: CharacterEquipment) -> void:
	equipment = p_equipment


func create_from_current(character_id: String, preset_name: String) -> String:
	return create_from_outfit(character_id, preset_name, equipment.get_outfit(character_id))


func create_from_outfit(character_id: String, preset_name: String, outfit: Outfit) -> String:
	_counter += 1
	var id := "preset_%s_%d" % [character_id, _counter]
	_presets.append({"id": id, "name": preset_name, "character_id": character_id,
		"slots": outfit.to_dict(), "order": _counter})
	presets_changed.emit(character_id)
	return id


func presets_for(character_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in _presets:
		if p.character_id == character_id:
			out.append(p.duplicate(true))
	return out


func get_preset(preset_id: String) -> Dictionary:
	for p in _presets:
		if p.id == preset_id:
			return p
	return {}


func rename(preset_id: String, new_name: String) -> bool:
	var p := get_preset(preset_id)
	if p.is_empty():
		return false
	p.name = new_name
	presets_changed.emit(p.character_id)
	return true


func overwrite(preset_id: String, outfit: Outfit) -> bool:
	var p := get_preset(preset_id)
	if p.is_empty():
		return false
	p.slots = outfit.to_dict()
	presets_changed.emit(p.character_id)
	return true


func delete(preset_id: String) -> bool:
	for i in _presets.size():
		if _presets[i].id == preset_id:
			var c: String = _presets[i].character_id
			_presets.remove_at(i)
			presets_changed.emit(c)
			return true
	return false


func copy(preset_id: String, new_name: String) -> String:
	var p := get_preset(preset_id)
	if p.is_empty():
		return ""
	return create_from_outfit(p.character_id, new_name, Outfit.from_dict(p.slots))


## Собирает образ из комплекта: только совместимую часть. Возвращает {outfit, problems:[{item_id, error_key}]}.
func build_outfit(preset_id: String) -> Dictionary:
	var p := get_preset(preset_id)
	var outfit := Outfit.new()
	var problems: Array[Dictionary] = []
	if p.is_empty():
		return {"outfit": outfit, "problems": [{"item_id": "", "error_key": "preset.not_found"}]}
	var slots: Dictionary = p.slots
	var keys := slots.keys()
	keys.sort()
	for s in keys:
		var res := equipment.equip_into(outfit, p.character_id, str(slots[s]))
		if not res.ok:
			problems.append({"item_id": str(slots[s]), "error_key": res.error_key})
	return {"outfit": outfit, "problems": problems}


## Применяет совместимую часть комплекта к подтверждённому образу.
func apply(preset_id: String) -> Array[Dictionary]:
	var p := get_preset(preset_id)
	var built := build_outfit(preset_id)
	if not p.is_empty():
		equipment.set_outfit(p.character_id, built.outfit)
	return built.problems


func to_dict() -> Dictionary:
	return {"presets": _presets.duplicate(true), "counter": _counter}


func reset() -> void:
	_presets.clear()
	_counter = 0


func load_dict(d: Dictionary) -> void:
	_presets.clear()
	for p in d.get("presets", []):
		if typeof(p) == TYPE_DICTIONARY and p.has("id") and p.has("character_id"):
			if not p.has("slots") or typeof(p.slots) != TYPE_DICTIONARY:
				p["slots"] = {}
			_presets.append(p)
	# Счётчик не меньше максимального суффикса существующих ID, чтобы новые ID не совпали со старыми.
	_counter = int(d.get("counter", 0))
	for p in _presets:
		_counter = maxi(_counter, int(str(p.id).get_slice("_", str(p.id).get_slice_count("_") - 1)))
