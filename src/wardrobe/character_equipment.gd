class_name CharacterEquipment
extends RefCounted
## Экипировка каждого персонажа. Хранит только ссылки на ID предметов.
## Один предмет может быть одновременно надет на нескольких совместимых персонажах.

signal outfit_changed(character_id: String)

const ERR_NOT_OWNED := "equip.not_owned"
const ERR_UNKNOWN_ITEM := "equip.unknown_item"
const ERR_UNKNOWN_CHARACTER := "equip.unknown_character"
const ERR_INCOMPATIBLE := "equip.incompatible"

var catalog: ItemCatalog
var characters: CharacterCatalog
var inventory: WardrobeInventory
var _outfits: Dictionary = {}   # character_id -> Outfit


func _init(p_catalog: ItemCatalog, p_characters: CharacterCatalog, p_inventory: WardrobeInventory) -> void:
	catalog = p_catalog
	characters = p_characters
	inventory = p_inventory


## Текущий подтверждённый образ (копия — изменения не применяются без set_outfit).
func get_outfit(character_id: String) -> Outfit:
	var o: Outfit = _outfits.get(character_id)
	return o.duplicate_outfit() if o else Outfit.new()


func set_outfit(character_id: String, outfit: Outfit) -> void:
	_outfits[character_id] = outfit.duplicate_outfit()
	outfit_changed.emit(character_id)


## Шаги 1–4 алгоритма надевания из ТЗ. Меняет переданный outfit (черновик примерки или копию).
## Возвращает {ok, error_key, removed}.
func equip_into(outfit: Outfit, character_id: String, item_id: String) -> Dictionary:
	if not characters.has_character(character_id):
		return {"ok": false, "error_key": ERR_UNKNOWN_CHARACTER, "removed": []}
	var item := catalog.get_item(item_id)
	if item == null:
		return {"ok": false, "error_key": ERR_UNKNOWN_ITEM, "removed": []}
	if not inventory.owns(item_id):
		return {"ok": false, "error_key": ERR_NOT_OWNED, "removed": []}
	var compat := Compatibility.check(item, character_id, characters)
	if compat.status == Compatibility.Status.INCOMPATIBLE:
		return {"ok": false, "error_key": ERR_INCOMPATIBLE, "reason_key": compat.reason_key, "removed": []}
	var removed := outfit.conflicts_with(item, catalog)
	for r in removed:
		outfit.remove_item(r)
	outfit.items[item.slot] = item.id
	return {"ok": true, "error_key": "", "removed": removed}


## Надеть сразу в подтверждённый образ.
func equip(character_id: String, item_id: String) -> Dictionary:
	var o := get_outfit(character_id)
	var res := equip_into(o, character_id, item_id)
	if res.ok:
		set_outfit(character_id, o)
	return res


func unequip(character_id: String, item_id: String) -> bool:
	var o := get_outfit(character_id)
	if o.remove_item(item_id):
		set_outfit(character_id, o)
		return true
	return false


func equipped_items(character_id: String) -> Array[ClothingItem]:
	var out: Array[ClothingItem] = []
	for id in get_outfit(character_id).item_ids():
		var it := catalog.get_item(id)
		if it:
			out.append(it)
	return out


## Надевает фирменный образ персонажа из данных (только принадлежащие и совместимые предметы).
func equip_signature(character_id: String) -> void:
	var o := Outfit.new()
	var sig := characters.signature_outfit(character_id)
	for slot in sig.keys():
		equip_into(o, character_id, str(sig[slot]))
	set_outfit(character_id, o)


func to_dict() -> Dictionary:
	var d := {}
	for c in _outfits.keys():
		d[c] = (_outfits[c] as Outfit).to_dict()
	return d


func reset() -> void:
	_outfits.clear()


## Безопасная загрузка: неизвестные, не принадлежащие, несовместимые и конфликтующие предметы отбрасываются.
func load_dict(d: Dictionary) -> Array[String]:
	_outfits.clear()
	var dropped: Array[String] = []
	for c in d.keys():
		if not characters.has_character(c):
			dropped.append("%s:*" % c)
			continue
		if typeof(d[c]) != TYPE_DICTIONARY:
			dropped.append("%s:*" % c)
			continue
		var raw := Outfit.from_dict(d[c])
		var clean := Outfit.new()
		var slots := raw.items.keys()
		slots.sort()
		for slot in slots:
			var res := equip_into(clean, c, raw.items[slot])
			if not res.ok:
				dropped.append("%s:%s" % [c, raw.items[slot]])
			for r in res.removed:
				dropped.append("%s:%s" % [c, r])
		_outfits[c] = clean
		outfit_changed.emit(c)
	return dropped
