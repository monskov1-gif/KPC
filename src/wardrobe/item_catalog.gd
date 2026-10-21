class_name ItemCatalog
extends RefCounted
## Загрузка и валидация каталога одежды.
## Некорректная запись пропускается с ошибкой, содержащей ID; остальные предметы загружаются.

var config: WardrobeConfig
var errors: Array[String] = []
var warnings: Array[String] = []
var _items: Dictionary = {}   # id -> ClothingItem
var _ordered: Array[ClothingItem] = []


func _init(p_config: WardrobeConfig) -> void:
	config = p_config


func load_from_array(entries: Array) -> void:
	for entry in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			errors.append("Запись каталога не является объектом: %s" % str(entry))
			continue
		var item := ClothingItem.from_dict(entry)
		var item_errors := validate(item)
		if not item_errors.is_empty():
			for e in item_errors:
				errors.append("[%s] %s" % [item.id if item.id != "" else "<без id>", e])
			continue
		_items[item.id] = item
		_ordered.append(item)
	_ordered.sort_custom(func(a: ClothingItem, b: ClothingItem):
		return a.sort_order < b.sort_order if a.sort_order != b.sort_order else a.id < b.id)


func validate(item: ClothingItem) -> Array[String]:
	var out: Array[String] = item.parse_errors.duplicate()
	if item.id == "":
		out.append("пустой id")
	elif _items.has(item.id):
		out.append("повторяющийся id")
	if item.name_key == "":
		out.append("нет name_key")
	if not config.categories.has(item.category):
		out.append("неизвестная категория '%s'" % item.category)
	if not config.slots.has(item.slot):
		out.append("неизвестный слот '%s'" % item.slot)
	elif config.categories.has(item.category) and not (config.categories[item.category] as Array).has(item.slot):
		out.append("слот '%s' не допускается для категории '%s'" % [item.slot, item.category])
	for s in item.occupied_slots:
		if not config.slots.has(s):
			out.append("неизвестный дополнительный слот '%s'" % s)
	if not config.rarities.has(item.rarity):
		out.append("неизвестная редкость '%s'" % item.rarity)
	for t in item.style_tags:
		if not config.style_tags.has(t):
			out.append("неизвестный стилевой тег '%s'" % t)
	for c in item.color_tags:
		if not config.color_tags.has(c):
			out.append("неизвестный цветовой тег '%s'" % c)
	for m in item.material_tags:
		if not config.material_tags.has(m):
			out.append("неизвестный материал '%s'" % m)
	for b in item.compatible_body_types:
		if not config.body_types.has(b):
			out.append("неизвестный тип тела '%s'" % b)
	for key in item.attributes.keys():
		var v = item.attributes[key]
		if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
			out.append("характеристика '%s' не число" % key)
		elif v < config.attribute_min or v > config.attribute_max:
			out.append("характеристика '%s'=%s вне шкалы %d–%d" % [key, v, config.attribute_min, config.attribute_max])
		elif not config.attributes.has(key):
			# Неизвестная характеристика — не ошибка: предупреждаем, в оценке она просто не участвует.
			warnings.append("[%s] неизвестная характеристика '%s'" % [item.id, key])
	if item.model_asset != "" and not ResourceLoader.exists(item.model_asset):
		warnings.append("[%s] нет модели %s — будет использована заглушка" % [item.id, item.model_asset])
	for char_id in item.model_variants.keys():
		var path := str(item.model_variants[char_id])
		if path != "" and not ResourceLoader.exists(path):
			warnings.append("[%s] нет адаптированной модели для '%s' (%s) — будет использована заглушка" % [item.id, char_id, path])
	return out


## Проверка ссылок на рецепты выполняется после загрузки рецептов.
func validate_recipe_links(recipe_ids: Array) -> void:
	for item in _ordered:
		if item.recipe_id != "" and not recipe_ids.has(item.recipe_id):
			warnings.append("[%s] ссылка на неизвестную выкройку '%s'" % [item.id, item.recipe_id])


func has_item(id: String) -> bool:
	return _items.has(id)


func get_item(id: String) -> ClothingItem:
	return _items.get(id)


func all_items() -> Array[ClothingItem]:
	return _ordered.duplicate()


func size() -> int:
	return _ordered.size()
