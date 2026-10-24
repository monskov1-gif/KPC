class_name GameSession
extends RefCounted
## Корень сборки игровых систем: загружает данные и связывает сервисы.
## Не зависит от сцен — используется и в игре (через автозагрузку Game), и в тестах.

const DATA_DIR := "res://data"

var errors: Array[String] = []
var warnings: Array[String] = []

var config: WardrobeConfig
var catalog: ItemCatalog
var characters: CharacterCatalog
var challenges: FashionChallengeCatalog
var inventory: WardrobeInventory
var resources: ResourceInventory
var equipment: CharacterEquipment
var presets: OutfitPresetManager
var scoring: FashionScoringService
var grants: ItemGrantService
var crafting: CraftingService
var shops: ShopService
var rewards: ChallengeRewardService
var flags: StoryFlags
var gacha: GachaService
var events: EventService
var profile := PlayerProfile.new()
var unlocked_characters: Array[String] = []
var orphaned_items: Dictionary = {}   # item_id -> запись владения; предметы, которых нет в текущем каталоге
var _starting_state: Dictionary = {}


static func create(data_dir: String = DATA_DIR) -> GameSession:
	var s := GameSession.new()
	s._load(data_dir)
	return s


func _load(dir: String) -> void:
	var errs: Array = []
	config = WardrobeConfig.from_dict(DataLoader.load_json(dir + "/wardrobe/config.json", errs))
	catalog = ItemCatalog.new(config)
	catalog.load_from_array(DataLoader.load_json(dir + "/wardrobe/items.json", errs).get("items", []))
	characters = CharacterCatalog.new()
	characters.load_from_array(DataLoader.load_json(dir + "/characters/characters.json", errs).get("characters", []), config)
	challenges = FashionChallengeCatalog.new(config)
	challenges.load_from_array(DataLoader.load_json(dir + "/wardrobe/challenges.json", errs).get("challenges", []))

	inventory = WardrobeInventory.new()
	resources = ResourceInventory.new()
	resources.load_definitions(DataLoader.load_json(dir + "/wardrobe/materials.json", errs).get("resources", []))
	equipment = CharacterEquipment.new(catalog, characters, inventory)
	presets = OutfitPresetManager.new(equipment)
	scoring = FashionScoringService.new(config)
	grants = ItemGrantService.new(catalog, inventory, resources, config)
	crafting = CraftingService.new(grants, resources)
	crafting.load_recipes(DataLoader.load_json(dir + "/wardrobe/recipes.json", errs).get("recipes", []))
	catalog.validate_recipe_links(crafting.recipe_ids())
	shops = ShopService.new(grants, resources)
	shops.load_shops(DataLoader.load_json(dir + "/wardrobe/shops.json", errs).get("shops", []))
	rewards = ChallengeRewardService.new(config, grants, crafting)
	flags = StoryFlags.new()
	_starting_state = DataLoader.load_json(dir + "/wardrobe/starting_state.json", errs)
	gacha = GachaService.new(grants, resources)
	gacha.load_data(DataLoader.load_json(dir + "/gacha/banners.json", errs), catalog, characters)
	events = EventService.new(resources)
	events.load_data(DataLoader.load_json(dir + "/events/events.json", errs).get("events", []), challenges)

	challenges.validate_rewards(catalog, resources, crafting)
	for e in errs:
		errors.append(str(e))
	for src in [catalog.errors, characters.errors, challenges.errors, crafting.errors, shops.errors, gacha.errors,
			events.errors]:
		errors.append_array(src)
	warnings.append_array(catalog.warnings)


## Полный сброс состояния игрока (данные каталогов не трогаются).
func reset_state() -> void:
	inventory.reset()
	resources.reset()
	equipment.reset()
	presets.reset()
	crafting.reset()
	shops.reset()
	rewards.reset()
	flags.reset()
	gacha.reset()
	events.reset()
	profile.reset()
	unlocked_characters.clear()
	orphaned_items.clear()


## Состояние новой игры.
func new_game() -> void:
	reset_state()
	for c in characters.ids():
		if characters.get_data(c).get("unlocked_by_default", false):
			unlocked_characters.append(c)
	for id in _starting_state.get("items", []):
		grants.grant_item(str(id), "starter")
	var res: Dictionary = _starting_state.get("resources", {})
	resources.apply_deltas(res)
	if _starting_state.get("equip_signature_outfits", false):
		for c in unlocked_characters:
			equipment.equip_signature(c)
	profile.ensure_uid(int(Time.get_unix_time_from_system() * 1000.0))


## Молитвы на баннере; новый персонаж сразу получает фирменный образ (открыт в гардеробе).
func gacha_pull(banner_id: String, count: int) -> Dictionary:
	var before := unlocked_characters.duplicate()
	var res := gacha.pull(banner_id, count, unlocked_characters)
	for c in unlocked_characters:
		if not before.has(c) and equipment.get_outfit(c).items.is_empty():
			equipment.equip_signature(c)
	return res


## Награда события; для конкурса условие — испытание события пройдено.
func claim_event(event_id: String, day: int) -> Dictionary:
	var e := events.get_event(event_id)
	var cleared := bool(rewards.result(str(e.get("challenge_id", ""))).get("cleared", false))
	return events.claim(event_id, day, cleared)


## Сводка для профиля игрока (уровень считается из неё).
func profile_stats() -> Dictionary:
	var cleared := 0
	var best := ""
	var order: Array = config.rank_order
	for id in challenges.ids():
		var r := rewards.result(id)
		if r.get("cleared", false):
			cleared += 1
		var rk := str(r.get("best_rank", ""))
		if rk != "" and (best == "" or order.find(rk) > order.find(best)):
			best = rk
	var playable := characters.ids().filter(func(c): return not characters.get_data(c).get("story_only", false))
	return {"item": inventory.count(), "items_total": catalog.all_items().size(), "challenge": cleared,
		"best_rank": best, "pull": gacha.total_pulls(), "event": events.claims_total(), "photo": profile.photos.size(),
		"characters": unlocked_characters.filter(func(c): return playable.has(c)).size(), "characters_total": playable.size()}


func outfit_items(character_id: String) -> Array[ClothingItem]:
	return equipment.equipped_items(character_id)


func items_for_outfit(outfit: Outfit) -> Array[ClothingItem]:
	var out: Array[ClothingItem] = []
	for id in outfit.item_ids():
		var it := catalog.get_item(id)
		if it:
			out.append(it)
	return out


## Сериализуемое состояние (без вычисляемых значений).
func to_save_dict() -> Dictionary:
	return {
		"wardrobe": inventory.to_dict(),
		"orphaned_items": orphaned_items.duplicate(true),
		"resources": resources.to_dict(),
		"equipment": equipment.to_dict(),
		"presets": presets.to_dict(),
		"recipes": crafting.to_dict(),
		"shops": shops.to_dict(),
		"challenge_results": rewards.to_dict(),
		"flags": flags.to_dict(),
		"unlocked_characters": unlocked_characters.duplicate(),
		"gacha": gacha.to_dict(),
		"events": events.to_dict(),
		"profile": profile.to_dict(),
	}


## Загрузка уже мигрированных данных. Разделы неверного типа заменяются пустыми. Возвращает предупреждения.
func load_save_dict(d: Dictionary) -> Array[String]:
	reset_state()
	var notes: Array[String] = []
	var saved_orphans := _section(d, "orphaned_items")
	var loaded_orphans := inventory.load_dict(_section(d, "wardrobe"), catalog)
	for id in loaded_orphans.keys():
		notes.append("Неизвестный предмет в сохранении сохранён отдельно: %s" % id)
	orphaned_items = loaded_orphans
	for id in saved_orphans.keys():
		if catalog.has_item(id) and not inventory.owns(id):
			# Предмет вернулся в каталог после обновления — возвращаем его владельцу.
			var rec = saved_orphans[id]
			inventory.restore(id, rec if typeof(rec) == TYPE_DICTIONARY else {})
			notes.append("Предмет снова доступен и возвращён в гардероб: %s" % id)
		elif not catalog.has_item(id):
			orphaned_items[id] = saved_orphans[id]
	resources.load_dict(_section(d, "resources"))
	var chars = d.get("unlocked_characters", [])
	# тот же массив, а не новый: на него ссылаются сервисы (молитвы открывают персонажей)
	unlocked_characters.assign(DataLoader.to_string_array(chars).filter(func(c): return characters.has_character(c)))
	for dropped in equipment.load_dict(_section(d, "equipment")):
		notes.append("Из экипировки убран недоступный предмет: %s" % dropped)
	presets.load_dict(_section(d, "presets"))
	crafting.load_dict(_section(d, "recipes"))
	shops.load_dict(_section(d, "shops"))
	rewards.load_dict(_section(d, "challenge_results"))
	flags.load_dict(_section(d, "flags"))
	gacha.load_dict(_section(d, "gacha"))
	events.load_dict(_section(d, "events"))
	profile.load_dict(_section(d, "profile"))
	profile.ensure_uid(hash(JSON.stringify(_section(d, "wardrobe"))))
	# Сохранение из прошлой версии: стартовых вещей, добавленных обновлением (одежда Кота-ребёнка для пролога),
	# в нём нет — выдать их, иначе сюжетное испытание нечем пройти.
	if inventory.count() > 0:
		for id in _starting_state.get("items", []):
			var it := catalog.get_item(str(id))
			if it and it.acquisition_sources.has("story") and not inventory.owns(it.id):
				grants.grant_item(it.id, "update")
				notes.append("Добавлена сюжетная вещь из обновления: %s" % it.id)
	return notes


## Сюжетные вещи персонажа (только для него, источник «story») — выдать недостающие. Вызывается перед
## сюжетным испытанием: в сумке персонажа должно быть всё, из чего сценарий предлагает выбирать.
func ensure_story_items(character_id: String) -> Array[String]:
	var given: Array[String] = []
	for it in catalog.all_items():
		if it.compatible_character_ids.has(character_id) and it.acquisition_sources.has("story") and not inventory.owns(it.id):
			grants.grant_item(it.id, "story")
			given.append(it.id)
	return given


static func _section(d: Dictionary, key: String) -> Dictionary:
	var v = d.get(key, {})
	return v if typeof(v) == TYPE_DICTIONARY else {}
