class_name ClothingItem
extends RefCounted
## Запись каталога одежды. Одна запись на ID; владение хранится отдельно (WardrobeInventory).

var id := ""
var name_key := ""
var description_key := ""
var category := ""
var slot := ""
var occupied_slots: Array[String] = []
var rarity := ""
var style_tags: Array[String] = []
var attributes: Dictionary = {}
var color_tags: Array[String] = []
var material_tags: Array[String] = []
var compatible_body_types: Array[String] = []
var compatible_character_ids: Array[String] = []
var excluded_character_ids: Array[String] = []
var model_variants: Dictionary = {}      # character_id -> путь к адаптированной модели
var set_id := ""
var is_signature_item := false
var is_dyeable := false
var dye_options: Array[String] = []
var acquisition_sources: Array[String] = []
var shop_price := 0
var recipe_id := ""
var model_asset := ""
## Шаблон 3D-меша одежды у моделей персонажей: «слот__шаблон» (garment__… в .glb).
var model_template := ""
var icon_asset := ""
var placeholder_color := Color(0.6, 0.6, 0.6)
var sort_order := 0
var parse_errors: Array[String] = []


static func from_dict(d: Dictionary) -> ClothingItem:
	var it := ClothingItem.new()
	it.id = str(d.get("id", ""))
	it.name_key = str(d.get("name_key", ""))
	it.description_key = str(d.get("description_key", ""))
	it.category = str(d.get("category", ""))
	it.slot = str(d.get("slot", ""))
	it.occupied_slots = DataLoader.to_string_array(d.get("occupied_slots", []))
	it.rarity = str(d.get("rarity", ""))
	it.style_tags = DataLoader.to_string_array(d.get("style_tags", []))
	it.attributes = _dict_field(d, "attributes", it)
	it.color_tags = DataLoader.to_string_array(d.get("color_tags", []))
	it.material_tags = DataLoader.to_string_array(d.get("material_tags", []))
	it.compatible_body_types = DataLoader.to_string_array(d.get("compatible_body_types", []))
	it.compatible_character_ids = DataLoader.to_string_array(d.get("compatible_character_ids", []))
	it.excluded_character_ids = DataLoader.to_string_array(d.get("excluded_character_ids", []))
	it.model_variants = _dict_field(d, "model_variants", it)
	it.set_id = str(d.get("set_id", ""))
	it.is_signature_item = bool(d.get("is_signature_item", false))
	it.is_dyeable = bool(d.get("is_dyeable", false))
	it.dye_options = DataLoader.to_string_array(d.get("dye_options", []))
	it.acquisition_sources = DataLoader.to_string_array(d.get("acquisition_sources", []))
	it.shop_price = int(d.get("shop_price", 0))
	it.recipe_id = str(d.get("recipe_id", ""))
	it.model_asset = str(d.get("model_asset", ""))
	it.model_template = str(d.get("model_template", ""))
	it.icon_asset = str(d.get("icon_asset", ""))
	if d.has("placeholder_color"):
		it.placeholder_color = Color.from_string(str(d["placeholder_color"]), it.placeholder_color)
	it.sort_order = int(d.get("sort_order", 0))
	return it


static func _dict_field(d: Dictionary, key: String, it: ClothingItem) -> Dictionary:
	var v = d.get(key, {})
	if typeof(v) != TYPE_DICTIONARY:
		it.parse_errors.append("поле '%s' должно быть объектом" % key)
		return {}
	return v


## Отсутствующая характеристика считается нулевой.
func attr(name: String) -> float:
	return float(attributes.get(name, 0))


## Все слоты, которые предмет занимает (основной + дополнительные).
func all_slots() -> Array[String]:
	var out: Array[String] = [slot]
	for s in occupied_slots:
		if not out.has(s):
			out.append(s)
	return out


func has_tag(tag: String) -> bool:
	return style_tags.has(tag)
