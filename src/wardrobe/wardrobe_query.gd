class_name WardrobeQuery
extends RefCounted
## Фильтры, поиск и сортировка гардероба. Все условия комбинируются через «И».

enum Sort { CATALOG, NAME, RARITY, NEWEST, ATTRIBUTE }

var text := ""                         # поиск по локализованному названию
var slot := ""
var category := ""
var tag := ""
var rarity := ""
var color := ""
var material := ""
var source := ""
var min_attribute := ""                # характеристика для фильтра/сортировки
var min_attribute_value := 0
var compatible_with := ""              # character_id
var only_unequipped_for := ""          # character_id
var only_owned := true
var only_favorites := false
var sort := Sort.CATALOG
var sort_attribute := ""


func run(session: GameSession, name_resolver: Callable = Callable()) -> Array[ClothingItem]:
	var out: Array[ClothingItem] = []
	var equipped: Array[String] = []
	if only_unequipped_for != "":
		equipped = session.equipment.get_outfit(only_unequipped_for).item_ids()
	var needle := text.strip_edges().to_lower()
	for it in session.catalog.all_items():
		if only_owned and not session.inventory.owns(it.id):
			continue
		if only_favorites and not session.inventory.is_favorite(it.id):
			continue
		if slot != "" and not it.all_slots().has(slot):
			continue
		if category != "" and it.category != category:
			continue
		if tag != "" and not it.has_tag(tag):
			continue
		if rarity != "" and it.rarity != rarity:
			continue
		if color != "" and not it.color_tags.has(color):
			continue
		if material != "" and not it.material_tags.has(material):
			continue
		if source != "" and not it.acquisition_sources.has(source):
			continue
		if min_attribute != "" and it.attr(min_attribute) < min_attribute_value:
			continue
		if compatible_with != "" and not Compatibility.can_wear(it, compatible_with, session.characters):
			continue
		if equipped.has(it.id):
			continue
		if needle != "":
			var display: String = name_resolver.call(it) if name_resolver.is_valid() else it.id
			if not display.to_lower().contains(needle) and not it.id.contains(needle):
				continue
		out.append(it)
	_sort(out, session, name_resolver)
	return out


func _sort(items: Array[ClothingItem], session: GameSession, name_resolver: Callable) -> void:
	match sort:
		Sort.NAME:
			items.sort_custom(func(a, b):
				var na: String = name_resolver.call(a) if name_resolver.is_valid() else a.id
				var nb: String = name_resolver.call(b) if name_resolver.is_valid() else b.id
				return na.naturalnocasecmp_to(nb) < 0)
		Sort.RARITY:
			var order := session.config.rarities
			items.sort_custom(func(a, b):
				var ra := order.find(a.rarity)
				var rb := order.find(b.rarity)
				return ra > rb if ra != rb else a.id < b.id)
		Sort.NEWEST:
			items.sort_custom(func(a, b):
				return session.inventory.acquired_order(a.id) > session.inventory.acquired_order(b.id))
		Sort.ATTRIBUTE:
			var attr_name := sort_attribute
			items.sort_custom(func(a, b):
				return a.attr(attr_name) > b.attr(attr_name) if a.attr(attr_name) != b.attr(attr_name) else a.id < b.id)


## Количество принадлежащих предметов по категориям.
static func counts_by_category(session: GameSession) -> Dictionary:
	var d := {}
	for it in session.catalog.all_items():
		if session.inventory.owns(it.id):
			d[it.category] = int(d.get(it.category, 0)) + 1
	return d
