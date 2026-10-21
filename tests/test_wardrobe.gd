extends TestCase

const DRESS := "clothing_evening_dress_001"
const BLAZER := "clothing_velvet_blazer_001"
const SHIRT := "clothing_plain_shirt_001"
const TROUSERS := "clothing_kot_black_trousers_001"
const PAWS := "clothing_gabi_paw_gloves_001"
const SNEAKERS := "clothing_sport_sneakers_001"


func test_grant_adds_item_to_shared_wardrobe() -> void:
	var s := fresh_session()
	check(not s.inventory.owns(BLAZER), "блейзера нет на старте")
	var r := s.grants.grant_item(BLAZER, "test")
	eq(r.status, "added")
	check(s.inventory.owns(BLAZER), "предмет появился в гардеробе")
	check(s.inventory.is_new(BLAZER), "отмечен как новый")


func test_duplicate_converted_by_single_policy() -> void:
	var s := fresh_session()
	var coins := s.resources.amount("coins")
	var r := s.grants.grant_item(SHIRT, "test")   # common, уже есть на старте
	eq(r.status, "duplicate_converted")
	eq(s.resources.amount("coins"), coins + 10)
	eq(s.inventory.count(), s.inventory.owned_ids().size())


func test_cannot_equip_unowned() -> void:
	var s := fresh_session()
	var r := s.equipment.equip("kot", BLAZER)
	check(not r.ok, "нельзя надеть чужой предмет")
	eq(r.error_key, CharacterEquipment.ERR_NOT_OWNED)


func test_cannot_equip_incompatible_but_item_stays_owned() -> void:
	var s := fresh_session()
	s.grants.grant_item(DRESS, "test")
	var r := s.equipment.equip("sora", DRESS)
	eq(r.error_key, CharacterEquipment.ERR_INCOMPATIBLE)
	var r2 := s.equipment.equip("kot", PAWS)   # белый список только для Габи
	eq(r2.error_key, CharacterEquipment.ERR_INCOMPATIBLE)
	check(s.inventory.owns(DRESS), "несовместимая вещь остаётся в коллекции")


func test_adapted_version_status() -> void:
	var s := fresh_session()
	var it := ClothingItem.from_dict({"id": "x", "name_key": "k", "category": "top", "slot": "upper_body", "rarity": "common",
		"compatible_body_types": ["compact"], "model_variants": {"sora": ""}})
	eq(Compatibility.check(it, "sora", s.characters).status, Compatibility.Status.ADAPTED)
	eq(Compatibility.check(it, "kot", s.characters).status, Compatibility.Status.COMPATIBLE)


func test_full_body_replaces_top_and_bottom_and_back() -> void:
	var s := fresh_session()
	s.grants.grant_item(DRESS, "test")
	s.equipment.equip("kot", SHIRT)
	s.equipment.equip("kot", TROUSERS)
	var r := s.equipment.equip("kot", DRESS)
	check(r.ok, "платье надето")
	eq(r.removed, [TROUSERS, SHIRT] as Array[String], "сняты верх и низ (отсортированы по ID)")
	var r2 := s.equipment.equip("kot", SHIRT)
	eq(r2.removed, [DRESS] as Array[String], "верх снимает цельный наряд")
	eq(s.equipment.get_outfit("kot").item_in_slot("lower_body", s.catalog), "", "низ пуст после снятия платья")


func test_same_item_on_several_characters() -> void:
	var s := fresh_session()
	check(s.equipment.equip("kot", SNEAKERS).ok, "Кот")
	check(s.equipment.equip("sora", SNEAKERS).ok, "Сора")
	check(s.equipment.get_outfit("kot").has_item(SNEAKERS), "у Кота не сняли")


func test_unequip_keeps_item_in_collection() -> void:
	var s := fresh_session()
	s.equipment.equip("kot", SNEAKERS)
	check(s.equipment.unequip("kot", SNEAKERS), "снято")
	check(s.inventory.owns(SNEAKERS), "осталось в коллекции")


func test_try_on_draft_does_not_change_committed_outfit() -> void:
	var s := fresh_session()
	var before := s.equipment.get_outfit("kot")
	var draft := s.equipment.get_outfit("kot")
	s.equipment.equip_into(draft, "kot", SNEAKERS)
	check(s.equipment.get_outfit("kot").is_equal(before), "до подтверждения образ не изменился")
	s.equipment.set_outfit("kot", draft)
	check(s.equipment.get_outfit("kot").has_item(SNEAKERS), "после подтверждения изменился")


func test_signature_outfit_equipped_on_new_game() -> void:
	var s := fresh_session()
	var kot := s.equipment.get_outfit("kot")
	check(kot.has_item("clothing_kot_flower_turtleneck_001"), "свитер Кота")
	check(kot.has_item("clothing_kot_eyepatch_001"), "повязка — аксессуар, надета по умолчанию")
	check(s.equipment.unequip("kot", "clothing_kot_eyepatch_001"), "повязку можно снять")


func test_preset_save_and_apply() -> void:
	var s := fresh_session()
	var pid := s.presets.create_from_current("kot", "Домашний")
	s.equipment.equip("kot", SNEAKERS)
	var problems := s.presets.apply(pid)
	eq(problems.size(), 0)
	check(not s.equipment.get_outfit("kot").has_item(SNEAKERS), "комплект восстановлен")
	check(s.presets.rename(pid, "Новое имя"), "переименование")
	var copy_id := s.presets.copy(pid, "Копия")
	eq(s.presets.presets_for("kot").size(), 2)
	check(s.presets.delete(copy_id), "удаление")


func test_preset_with_missing_item_applies_compatible_part() -> void:
	var s := fresh_session()
	s.presets.load_dict({"presets": [{"id": "p1", "name": "Старый", "character_id": "kot",
		"slots": {"upper_body": SHIRT, "footwear": "clothing_removed_from_game_999", "outerwear": BLAZER}}]})
	var problems := s.presets.apply("p1")
	eq(problems.size(), 2, "неизвестный и не принадлежащий предметы")
	check(s.equipment.get_outfit("kot").has_item(SHIRT), "совместимая часть применена")


func test_old_save_with_unknown_items_does_not_break() -> void:
	var s := GameSession.create()
	var notes := s.load_save_dict({
		"wardrobe": {"owned": {SHIRT: {"order": 1}, "clothing_ghost_001": {"order": 2}}, "counter": 2},
		"equipment": {"kot": {"upper_body": SHIRT, "footwear": "clothing_ghost_001"}, "unknown_hero": {}},
	})
	check(s.inventory.owns(SHIRT), "известный предмет загружен")
	check(s.orphaned_items.has("clothing_ghost_001"), "неизвестный ID сохранён отдельно")
	eq(s.equipment.get_outfit("kot").item_ids(), [SHIRT] as Array[String])
	check(notes.size() >= 2, "есть диагностические сообщения")


func test_query_filters_combine() -> void:
	var s := fresh_session()
	s.grants.grant_item("clothing_oxford_shoes_001", "test")
	var q := WardrobeQuery.new()
	q.slot = "footwear"
	q.tag = "elegant"
	var res := q.run(s)
	eq(res.size(), 1)
	eq(res[0].id, "clothing_oxford_shoes_001")
	q.tag = "underwater"
	eq(q.run(s).size(), 0, "пустой результат без ошибок")


func test_query_compatibility_and_unequipped() -> void:
	var s := fresh_session()
	var q := WardrobeQuery.new()
	q.compatible_with = "sora"
	for it in q.run(s):
		check(Compatibility.can_wear(it, "sora", s.characters), "%s подходит Соре" % it.id)
	var q2 := WardrobeQuery.new()
	q2.only_unequipped_for = "kot"
	for it in q2.run(s):
		check(not s.equipment.get_outfit("kot").has_item(it.id), "%s не надет" % it.id)
