class_name Outfit
extends RefCounted
## Образ одного персонажа: основной слот предмета -> item_id.
## Занятые дополнительные слоты вычисляются из данных предметов, а не хранятся.

var items: Dictionary = {}   # primary slot -> item_id


func duplicate_outfit() -> Outfit:
	var o := Outfit.new()
	o.items = items.duplicate()
	return o


func item_ids() -> Array[String]:
	var out: Array[String] = []
	for s in items.keys():
		out.append(str(items[s]))
	out.sort()
	return out


func has_item(item_id: String) -> bool:
	return items.values().has(item_id)


## Какие уже надетые предметы конфликтуют по слотам с новым предметом.
func conflicts_with(item: ClothingItem, catalog: ItemCatalog) -> Array[String]:
	var new_slots := item.all_slots()
	var out: Array[String] = []
	for s in items.keys():
		var other_id: String = items[s]
		if other_id == item.id:
			continue
		var other := catalog.get_item(other_id)
		var other_slots: Array[String] = other.all_slots() if other else ([s] as Array[String])
		for os in other_slots:
			if new_slots.has(os):
				out.append(other_id)
				break
	out.sort()
	return out


## Предмет, занимающий слот (основной или дополнительный), либо "".
func item_in_slot(slot: String, catalog: ItemCatalog) -> String:
	if items.has(slot):
		return items[slot]
	for s in items.keys():
		var it := catalog.get_item(items[s])
		if it and it.occupied_slots.has(slot):
			return it.id
	return ""


func remove_item(item_id: String) -> bool:
	for s in items.keys():
		if items[s] == item_id:
			items.erase(s)
			return true
	return false


func is_equal(other: Outfit) -> bool:
	return items == other.items


func to_dict() -> Dictionary:
	return items.duplicate()


static func from_dict(d: Dictionary) -> Outfit:
	var o := Outfit.new()
	for k in d.keys():
		o.items[str(k)] = str(d[k])
	return o
