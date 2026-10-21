extends TestCase


func _config() -> WardrobeConfig:
	return WardrobeConfig.from_dict(DataLoader.load_json("res://data/wardrobe/config.json"))


func _valid(id: String) -> Dictionary:
	return {"id": id, "name_key": "k", "category": "top", "slot": "upper_body", "rarity": "common",
		"compatible_body_types": ["compact"]}


func test_project_data_loads_without_errors() -> void:
	var s := GameSession.create()
	eq(s.errors.size(), 0, "ошибки данных: %s" % str(s.errors))
	check(s.catalog.size() >= 10, "в каталоге должно быть не меньше 10 предметов")
	check(s.challenges.ids().size() >= 1, "должно быть хотя бы одно испытание")


func test_ids_unique_duplicate_rejected_with_id() -> void:
	var c := ItemCatalog.new(_config())
	c.load_from_array([_valid("a"), _valid("a")])
	eq(c.size(), 1)
	check(c.errors.size() == 1 and c.errors[0].contains("[a]"), "ошибка должна содержать ID: %s" % str(c.errors))


func test_invalid_slot_category_rarity_tag_rejected_others_kept() -> void:
	var c := ItemCatalog.new(_config())
	var bad_slot := _valid("bad_slot"); bad_slot.slot = "tail"
	var bad_cat := _valid("bad_cat"); bad_cat.category = "spaceship"
	var bad_rarity := _valid("bad_rarity"); bad_rarity.rarity = "mythic"
	var bad_tag := _valid("bad_tag"); bad_tag["style_tags"] = ["not_a_tag"]
	var wrong_pair := _valid("wrong_pair"); wrong_pair.slot = "footwear"
	c.load_from_array([bad_slot, bad_cat, bad_rarity, bad_tag, wrong_pair, _valid("ok")])
	eq(c.size(), 1, "должен остаться только корректный предмет")
	check(c.has_item("ok"), "корректный предмет загружен")
	eq(c.errors.size(), 5)


func test_optional_fields_may_be_absent() -> void:
	var c := ItemCatalog.new(_config())
	c.load_from_array([_valid("minimal")])
	var it := c.get_item("minimal")
	eq(it.attr("elegance"), 0.0, "отсутствующая характеристика = 0")
	eq(it.set_id, "")
	eq(it.all_slots(), ["upper_body"] as Array[String])


func test_unknown_attribute_is_warning_not_error() -> void:
	var c := ItemCatalog.new(_config())
	var d := _valid("x"); d["attributes"] = {"sparkle": 10}
	c.load_from_array([d])
	eq(c.size(), 1)
	eq(c.errors.size(), 0)
	check(c.warnings.size() == 1, "ожидалось предупреждение")


func test_attribute_out_of_scale_rejected() -> void:
	var c := ItemCatalog.new(_config())
	var d := _valid("x"); d["attributes"] = {"elegance": 150}
	c.load_from_array([d])
	eq(c.size(), 0)


func test_missing_model_asset_is_warning() -> void:
	var c := ItemCatalog.new(_config())
	var d := _valid("x"); d["model_asset"] = "res://nope/model.glb"
	c.load_from_array([d])
	eq(c.size(), 1, "предмет без модели всё равно доступен")
	check(c.warnings.size() == 1, "ожидалось предупреждение о модели")


func test_challenge_validation() -> void:
	var cat := FashionChallengeCatalog.new(_config())
	cat.load_from_array([{"id": "c1", "attribute_weights": {"nope": 1.0},
		"requirements": [{"id": "r", "type": "teleport", "severity": "critical"}]}])
	eq(cat.ids().size(), 0)
	eq(cat.errors.size(), 2)
