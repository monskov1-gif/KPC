class_name FashionChallengeCatalog
extends RefCounted
## Загрузка и валидация модных испытаний. Испытание — данные; логика в FashionScoringService.

const REQUIREMENT_TYPES := ["required_slot", "required_category", "tag_any", "attribute_min",
	"item_count_max", "item_count_min", "forbidden_tag", "color_any", "material_any"]
const SYNERGY_TYPES := ["set_pieces", "tags_all", "color_count", "material_count"]

var config: WardrobeConfig
var errors: Array[String] = []
var _challenges: Dictionary = {}
var _order: Array[String] = []


func _init(p_config: WardrobeConfig) -> void:
	config = p_config


func load_from_array(entries: Array) -> void:
	for c in entries:
		var errs := validate(c)
		var id := str(c.get("id", "<без id>"))
		if not errs.is_empty():
			for e in errs:
				errors.append("[%s] %s" % [id, e])
			continue
		_challenges[id] = c
		_order.append(id)


func validate(c: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var id := str(c.get("id", ""))
	if id == "" or _challenges.has(id):
		out.append("пустой или повторяющийся id")
	for a in c.get("attribute_weights", {}).keys():
		if not config.attributes.has(a):
			out.append("неизвестная характеристика в весах '%s'" % a)
	for r in c.get("theme_rules", []):
		if not config.theme_levels.has(str(r.get("level", ""))):
			out.append("правило темы '%s': неизвестный уровень '%s'" % [r.get("id"), r.get("level")])
	if not config.theme_levels.has(str(c.get("default_theme_level", "neutral"))):
		out.append("неизвестный default_theme_level")
	for r in c.get("requirements", []):
		if not REQUIREMENT_TYPES.has(str(r.get("type", ""))):
			out.append("требование '%s': неизвестный тип '%s'" % [r.get("id"), r.get("type")])
		if not config.severity_q.has(str(r.get("severity", ""))):
			out.append("требование '%s': неизвестная severity '%s'" % [r.get("id"), r.get("severity")])
	for r in c.get("optional_requirements", []):
		if not REQUIREMENT_TYPES.has(str(r.get("type", ""))):
			out.append("доп. условие '%s': неизвестный тип" % r.get("id"))
	for s in c.get("synergy_rules", []):
		if not SYNERGY_TYPES.has(str(s.get("type", ""))):
			out.append("синергия '%s': неизвестный тип '%s'" % [s.get("id"), s.get("type")])
	if c.has("min_clear_rank") and not config.rank_order.has(str(c.min_clear_rank)):
		out.append("неизвестный min_clear_rank '%s'" % c.min_clear_rank)
	for rank in c.get("rank_thresholds", {}).keys():
		if not config.rank_order.has(rank):
			out.append("неизвестный ранг '%s'" % rank)
	return out


## Проверка ссылок в таблице наград после загрузки предметов, ресурсов и выкроек.
## Испытание с битой наградой отключается целиком, чтобы награда не была «засчитана» без выдачи.
func validate_rewards(catalog: ItemCatalog, resources: ResourceInventory, crafting: CraftingService) -> void:
	for id in _order.duplicate():
		var c: Dictionary = _challenges[id]
		var table: Dictionary = c.get("reward_table", {})
		var lists: Array = [table.get("first_clear", []), table.get("repeat", [])]
		var rank_rewards: Dictionary = table.get("rank_rewards", {})
		for r in rank_rewards.keys():
			if not config.rank_order.has(r):
				errors.append("[%s] награда за неизвестный ранг '%s'" % [id, r])
			lists.append(rank_rewards[r])
		var bad := false
		for list in lists:
			for reward in list:
				var rid := str(reward.get("id", ""))
				var ok := false
				match str(reward.get("type", "")):
					"item": ok = catalog.has_item(rid)
					"resource": ok = resources.is_known(rid) and int(reward.get("amount", 1)) > 0
					"recipe": ok = not crafting.get_recipe(rid).is_empty()
				if not ok:
					bad = true
					errors.append("[%s] некорректная награда %s" % [id, str(reward)])
		if bad:
			_challenges.erase(id)
			_order.erase(id)


func has_challenge(id: String) -> bool:
	return _challenges.has(id)


func get_challenge(id: String) -> Dictionary:
	return _challenges.get(id, {})


func ids() -> Array[String]:
	return _order.duplicate()
