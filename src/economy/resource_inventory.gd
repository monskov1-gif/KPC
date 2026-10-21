class_name ResourceInventory
extends RefCounted
## Валюта и материалы. Количества не бывают отрицательными; изменения применяются транзакционно.

signal changed

var _defs: Dictionary = {}     # id -> {kind, name_key, max}
var _amounts: Dictionary = {}


func load_definitions(entries: Array) -> void:
	for e in entries:
		_defs[str(e.id)] = e


func is_known(id: String) -> bool:
	return _defs.has(id)


func definition(id: String) -> Dictionary:
	return _defs.get(id, {})


func amount(id: String) -> int:
	return int(_amounts.get(id, 0))


func can_afford(costs: Dictionary) -> bool:
	for id in costs.keys():
		if amount(id) < int(costs[id]):
			return false
	return true


## Применяет набор изменений целиком или не применяет ничего. Возвращает "" или код ошибки.
func apply_deltas(deltas: Dictionary) -> String:
	for id in deltas.keys():
		if not _defs.has(id):
			return "resource.unknown"
		var next := amount(id) + int(deltas[id])
		if next < 0:
			return "resource.not_enough"
	for id in deltas.keys():
		var max_v := int(_defs[id].get("max", 2147483647))
		_amounts[id] = mini(amount(id) + int(deltas[id]), max_v)
	changed.emit()
	return ""


func spend(costs: Dictionary) -> String:
	var deltas := {}
	for id in costs.keys():
		deltas[id] = -int(costs[id])
	return apply_deltas(deltas)


func to_dict() -> Dictionary:
	return _amounts.duplicate()


func load_dict(d: Dictionary) -> void:
	_amounts.clear()
	for id in d.keys():
		if _defs.has(id):
			_amounts[id] = maxi(0, int(d[id]))
	changed.emit()
