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
var unlocked_characters: Array[String] = []
var orphaned_item_ids: Array[String] = []
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

	for e in errs:
		errors.append(str(e))
	for src in [catalog.errors, characters.errors, challenges.errors, crafting.errors, shops.errors]:
		errors.append_array(src)
	warnings.append_array(catalog.warnings)


## Состояние новой игры.
func new_game() -> void:
	unlocked_characters.clear()
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
		"orphaned_item_ids": orphaned_item_ids.duplicate(),
		"resources": resources.to_dict(),
		"equipment": equipment.to_dict(),
		"presets": presets.to_dict(),
		"recipes": crafting.to_dict(),
		"shops": shops.to_dict(),
		"challenge_results": rewards.to_dict(),
		"flags": flags.to_dict(),
		"unlocked_characters": unlocked_characters.duplicate(),
	}


## Загрузка уже мигрированных данных. Возвращает список предупреждений.
func load_save_dict(d: Dictionary) -> Array[String]:
	var notes: Array[String] = []
	orphaned_item_ids = DataLoader.to_string_array(d.get("orphaned_item_ids", []))
	for id in inventory.load_dict(d.get("wardrobe", {}), catalog):
		if not orphaned_item_ids.has(id):
			orphaned_item_ids.append(id)
		notes.append("Неизвестный предмет в сохранении сохранён отдельно: %s" % id)
	resources.load_dict(d.get("resources", {}))
	unlocked_characters = DataLoader.to_string_array(d.get("unlocked_characters", []))
	for dropped in equipment.load_dict(d.get("equipment", {})):
		notes.append("Из экипировки убран недоступный предмет: %s" % dropped)
	presets.load_dict(d.get("presets", {}))
	crafting.load_dict(d.get("recipes", {}))
	shops.load_dict(d.get("shops", {}))
	rewards.load_dict(d.get("challenge_results", {}))
	flags.load_dict(d.get("flags", {}))
	return notes
