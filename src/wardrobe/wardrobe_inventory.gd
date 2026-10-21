class_name WardrobeInventory
extends RefCounted
## Общий гардероб: факт владения предметами. Один на игрока, не копируется по персонажам.

signal changed

var _owned: Dictionary = {}   # item_id -> {order, source, is_new, favorite}
var _counter := 0


func owns(item_id: String) -> bool:
	return _owned.has(item_id)


## Добавляет предмет. Возвращает false, если он уже есть (дубликаты обрабатывает ItemGrantService).
func add(item_id: String, source: String) -> bool:
	if _owned.has(item_id):
		return false
	_counter += 1
	_owned[item_id] = {"order": _counter, "source": source, "is_new": true, "favorite": false}
	changed.emit()
	return true


func owned_ids() -> Array[String]:
	var ids: Array[String] = []
	for k in _owned.keys():
		ids.append(k)
	ids.sort_custom(func(a, b): return _owned[a].order < _owned[b].order)
	return ids


func acquired_order(item_id: String) -> int:
	return int(_owned.get(item_id, {}).get("order", 0))


func is_new(item_id: String) -> bool:
	return bool(_owned.get(item_id, {}).get("is_new", false))


func mark_seen(item_id: String) -> void:
	if _owned.has(item_id) and _owned[item_id].is_new:
		_owned[item_id].is_new = false
		changed.emit()


func is_favorite(item_id: String) -> bool:
	return bool(_owned.get(item_id, {}).get("favorite", false))


func set_favorite(item_id: String, value: bool) -> void:
	if _owned.has(item_id):
		_owned[item_id].favorite = value
		changed.emit()


func reset() -> void:
	_owned.clear()
	_counter = 0
	changed.emit()


## Восстановление записи (например, предмета, вернувшегося в каталог).
func restore(item_id: String, record: Dictionary) -> void:
	_owned[item_id] = record.duplicate()
	_counter = maxi(_counter, int(record.get("order", 0)))
	changed.emit()


func count() -> int:
	return _owned.size()


func to_dict() -> Dictionary:
	return {"owned": _owned.duplicate(true), "counter": _counter}


## Неизвестные ID не теряются молча: их записи целиком возвращаются вызывающему для хранения.
func load_dict(d: Dictionary, catalog: ItemCatalog) -> Dictionary:
	_owned.clear()
	var orphaned := {}
	var owned = d.get("owned", {})
	if typeof(owned) != TYPE_DICTIONARY:
		owned = {}
	for id in owned.keys():
		var rec = owned[id]
		if typeof(rec) != TYPE_DICTIONARY:
			rec = {"order": 0, "source": "unknown", "is_new": false, "favorite": false}
		if catalog.has_item(id):
			_owned[id] = rec
		else:
			orphaned[id] = rec
	_counter = int(d.get("counter", _owned.size()))
	changed.emit()
	return orphaned
