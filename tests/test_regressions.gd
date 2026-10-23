extends TestCase
## Регрессии по находкам code-critic (ревью коммита c4a23b6).

const TEST_SAVE := "user://test_regress_slot.json"
const CH := "fashion_challenge_evening_ball_test_001"


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_save_with_wrong_data_type_is_corrupted_not_crash() -> void:
	var svc := SaveService.new(TEST_SAVE)
	svc.delete_all()
	_write(TEST_SAVE, '{"version":1,"data":null}')
	var r := svc.load_save()
	check(not r.ok, "повреждённое сохранение не загружено")
	eq(r.error_key, "save.corrupted")
	svc.delete_all()


func test_real_v0_file_is_migrated() -> void:
	var svc := SaveService.new(TEST_SAVE)
	svc.delete_all()
	_write(TEST_SAVE, '{"owned_items":["clothing_plain_shirt_001"]}')
	var r := svc.load_save()
	check(r.ok, "v0 загружен")
	var s := GameSession.create()
	s.load_save_dict(r.data)
	check(s.inventory.owns("clothing_plain_shirt_001"), "владение перенесено из файла v0")
	svc.delete_all()


func test_wrong_section_types_ignored() -> void:
	var s := GameSession.create()
	s.load_save_dict({"wardrobe": [], "equipment": "x", "presets": 5, "flags": null, "unlocked_characters": ["kot", "ghost"]})
	eq(s.inventory.count(), 0)
	eq(s.unlocked_characters, ["kot"] as Array[String])


func test_resource_cap_blocks_shop_purchase_without_charging() -> void:
	var s := fresh_session()
	s.resources.apply_deltas({"fabric_velvet": 999 - s.resources.amount("fabric_velvet")})
	var coins := s.resources.amount("coins")
	eq(s.shops.buy("shop_test_boutique", "fabric_velvet").error_key, "resource.cap_reached")
	eq(s.resources.amount("coins"), coins, "монеты не списаны")


func test_duplicate_at_currency_cap_is_ignored_not_fake_converted() -> void:
	var s := fresh_session()
	s.resources.apply_deltas({"coins": s.resources.max_amount("coins") - s.resources.amount("coins")})
	eq(s.grants.grant_item("clothing_plain_shirt_001", "test").status, "duplicate_ignored")


func test_new_game_twice_resets_state() -> void:
	var s := fresh_session()
	var coins := s.resources.amount("coins")
	var count := s.inventory.count()
	s.crafting.unlock("recipe_velvet_blazer_001")
	s.new_game()
	eq(s.resources.amount("coins"), coins, "валюта не удвоилась")
	eq(s.inventory.count(), count)
	check(not s.crafting.is_unlocked("recipe_velvet_blazer_001"), "выкройка сброшена")


func test_load_over_existing_state_replaces_it() -> void:
	var s := fresh_session()
	s.crafting.unlock("recipe_velvet_blazer_001")
	s.flags.set_flag("chapter1_started")
	s.load_save_dict({"recipes": {"unlocked": []}})
	check(not s.crafting.is_unlocked("recipe_velvet_blazer_001"), "выкройка не осталась от прошлого состояния")
	check(not s.flags.is_set("chapter1_started"), "флаги сброшены")


func test_shop_purchases_survive_save() -> void:
	var s := fresh_session()
	s.shops.buy("shop_test_boutique", "clothing_oxford_shoes_001")
	var s2 := GameSession.create()
	s2.load_save_dict(JSON.parse_string(JSON.stringify(s.to_save_dict())))
	eq(s2.shops.check("shop_test_boutique", "clothing_oxford_shoes_001"), "shop.limit_reached")


func test_orphan_restored_when_item_returns_to_catalog() -> void:
	var s := GameSession.create()
	s.load_save_dict({"orphaned_items": {"clothing_plain_shirt_001": {"order": 7, "source": "shop", "is_new": false, "favorite": true}}})
	check(s.inventory.owns("clothing_plain_shirt_001"), "вернулся в гардероб")
	check(s.inventory.is_favorite("clothing_plain_shirt_001"), "запись восстановлена целиком")
	check(not s.orphaned_items.has("clothing_plain_shirt_001"), "убран из сирот")


func test_conflicting_equipment_in_save_is_reported() -> void:
	var s := fresh_session()
	s.grants.grant_item("clothing_evening_dress_001", "test")
	var dropped := s.equipment.load_dict({"kot": {"full_body": "clothing_evening_dress_001", "upper_body": "clothing_plain_shirt_001"}})
	eq(dropped.size(), 1, "вытесненный предмет попал в отчёт: %s" % str(dropped))


func test_invalid_reward_disables_challenge() -> void:
	var cfg := WardrobeConfig.from_dict(DataLoader.load_json("res://data/wardrobe/config.json"))
	var s := GameSession.create()
	var cat := FashionChallengeCatalog.new(cfg)
	cat.load_from_array([{"id": "c", "reward_table": {"rank_rewards": {"A": [{"type": "item", "id": "clothing_typo"}]}}}])
	cat.validate_rewards(s.catalog, s.resources, s.crafting)
	check(not cat.has_challenge("c"), "испытание с битой наградой отключено")
	check(cat.errors.size() >= 1, "ошибка зафиксирована")


func test_invalid_min_clear_rank_rejected() -> void:
	var cfg := WardrobeConfig.from_dict(DataLoader.load_json("res://data/wardrobe/config.json"))
	var cat := FashionChallengeCatalog.new(cfg)
	cat.load_from_array([{"id": "c", "min_clear_rank": "b"}])
	check(not cat.has_challenge("c"), "опечатка в min_clear_rank отклонена")


func test_bounded_product_combination() -> void:
	var s := GameSession.create()
	s.config.combination_method = "bounded_product"
	s.config.combination_floor = 0.3
	var c := {"id": "c", "attribute_weights": {"elegance": 1.0}, "requirements": [
		{"id": "a", "type": "required_slot", "params": {"slot": "footwear"}, "severity": "major"},
		{"id": "b", "type": "required_slot", "params": {"slot": "bag"}, "severity": "minor"}]}
	var it := ClothingItem.from_dict({"id": "t", "name_key": "k", "category": "top", "slot": "upper_body", "rarity": "common", "attributes": {"elegance": 50}})
	near(s.scoring.score(c, [it] as Array[ClothingItem]).q, 0.4, "0.5 × 0.8")
	c.requirements[1].severity = "critical"
	near(s.scoring.score(c, [it] as Array[ClothingItem]).q, 0.3, "0.5 × 0.25 ограничено снизу 0.3")


func test_preset_counter_no_collision() -> void:
	var s := fresh_session()
	s.presets.load_dict({"presets": [
		{"id": "preset_kot_1", "name": "a", "character_id": "kot", "slots": {}},
		{"id": "preset_kot_5", "name": "b", "character_id": "kot", "slots": {}}]})
	var id := s.presets.create_from_current("kot", "c")
	check(id != "preset_kot_5" and id != "preset_kot_1", "новый ID уникален: %s" % id)


func test_non_dict_attributes_rejected_not_crash() -> void:
	var cfg := WardrobeConfig.from_dict(DataLoader.load_json("res://data/wardrobe/config.json"))
	var c := ItemCatalog.new(cfg)
	c.load_from_array([{"id": "x", "name_key": "k", "category": "top", "slot": "upper_body", "rarity": "common", "attributes": [1, 2]}])
	eq(c.size(), 0)
	check(c.errors.size() == 1 and c.errors[0].contains("[x]"), str(c.errors))


## Сохранение из прошлой версии (без одежды Кота-ребёнка): после загрузки вещи для испытания на склоне есть.
func test_old_save_gets_story_items_for_slope_challenge() -> void:
	var s := GameSession.create()
	s.new_game()
	var d := s.to_save_dict()
	var owned: Dictionary = d.wardrobe.owned
	for id in owned.keys():
		if str(id).begins_with("clothing_kotc_"):
			owned.erase(id)
	var s2 := GameSession.create()
	s2.load_save_dict(d)
	for id in ["clothing_kotc_puffer_jacket_001", "clothing_kotc_mittens_001", "clothing_kotc_yellow_hoodie_001"]:
		check(s2.inventory.owns(id), "после загрузки старого сохранения нет %s" % id)
	# даже при пустом гардеробе перед испытанием сюжетные вещи выдаёт ensure_story_items
	var s3 := GameSession.create()
	s3.load_save_dict({})
	s3.ensure_story_items("kot_child")
	check(s3.inventory.owns("clothing_kotc_mittens_001"), "перед испытанием варежки в сумке")
