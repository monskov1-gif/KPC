extends TestCase

const TEST_SAVE := "user://test_save_slot.json"
const BLAZER := "clothing_velvet_blazer_001"
const RECIPE := "recipe_velvet_blazer_001"
const CH := "fashion_challenge_evening_ball_test_001"


func test_cannot_buy_without_currency() -> void:
	var s := fresh_session()
	s.resources.spend({"coins": s.resources.amount("coins")})
	var r := s.shops.buy("shop_test_boutique", "clothing_oxford_shoes_001")
	eq(r.error_key, "shop.not_enough_currency")
	check(not s.inventory.owns("clothing_oxford_shoes_001"), "предмет не выдан")


func test_buy_spends_and_grants_once() -> void:
	var s := fresh_session()
	var coins := s.resources.amount("coins")
	check(s.shops.buy("shop_test_boutique", "clothing_oxford_shoes_001").ok, "покупка")
	eq(s.resources.amount("coins"), coins - 300)
	check(s.inventory.owns("clothing_oxford_shoes_001"), "выдано")
	eq(s.shops.buy("shop_test_boutique", "clothing_oxford_shoes_001").error_key, "shop.limit_reached")


func test_cannot_craft_locked_or_without_materials() -> void:
	var s := fresh_session()
	eq(s.crafting.craft(RECIPE).error_key, "craft.locked")
	s.crafting.unlock(RECIPE)
	var before := s.resources.to_dict()
	eq(s.crafting.craft(RECIPE).error_key, "craft.not_enough_resources")
	eq(s.resources.to_dict(), before, "ресурсы не потеряны")
	check(not s.inventory.owns(BLAZER), "предмет не создан")


func test_successful_craft_spends_and_adds() -> void:
	var s := fresh_session()
	s.crafting.unlock(RECIPE)
	s.resources.apply_deltas({"fabric_velvet": 5, "thread_silk": 5})
	var velvet := s.resources.amount("fabric_velvet")
	var coins := s.resources.amount("coins")
	var r := s.crafting.craft(RECIPE)
	check(r.ok, "крафт успешен")
	eq(s.resources.amount("fabric_velvet"), velvet - 3)
	eq(s.resources.amount("coins"), coins - 100)
	check(s.inventory.owns(BLAZER), "блейзер в гардеробе")
	eq(s.crafting.craft(RECIPE).error_key, "craft.already_owned", "повторный крафт не тратит ресурсы")


func test_resources_never_negative_and_atomic() -> void:
	var s := fresh_session()
	var before := s.resources.to_dict()
	eq(s.resources.apply_deltas({"coins": 10, "thread_silk": -1}), "resource.not_enough")
	eq(s.resources.to_dict(), before, "частичное изменение не применилось")


func _clear_items(s: GameSession) -> Array[ClothingItem]:
	return s.items_for_outfit(Outfit.from_dict({"upper_body": "clothing_plain_shirt_001", "footwear": "clothing_dark_mary_janes_001"}))


func test_one_time_rewards_not_duplicated() -> void:
	var s := fresh_session()
	var ch := s.challenges.get_challenge(CH)
	var report := {"final_score": 700, "rank": "A"}
	var first := s.rewards.submit(ch, report)
	check(first.first_clear, "первое прохождение")
	check(s.crafting.is_unlocked(RECIPE), "выкройка за ранг A")
	var velvet := s.resources.amount("fabric_velvet")
	var coins := s.resources.amount("coins")
	var second := s.rewards.submit(ch, report)
	check(not second.first_clear, "повторно первое прохождение не засчитано")
	eq(s.resources.amount("fabric_velvet"), velvet, "награда за первое прохождение не выдана повторно")
	eq(s.resources.amount("coins"), coins + 20, "только награда за повтор")


func test_new_best_rank_gives_only_new_rank_reward() -> void:
	var s := fresh_session()
	var ch := s.challenges.get_challenge(CH)
	s.rewards.submit(ch, {"final_score": 500, "rank": "B"})
	check(not s.inventory.owns("clothing_evening_dress_001"), "S-награды ещё нет")
	var r := s.rewards.submit(ch, {"final_score": 900, "rank": "S"})
	check(r.new_best, "новый лучший результат")
	check(s.inventory.owns("clothing_evening_dress_001"), "S-награда выдана")
	check(s.crafting.is_unlocked(RECIPE), "A-награда тоже выдана при прыжке через ранг")
	eq(s.rewards.result(CH).best_rank, "S")


func test_save_roundtrip_restores_progress() -> void:
	var svc := SaveService.new(TEST_SAVE)
	svc.delete_all()
	var s := fresh_session()
	s.grants.grant_item(BLAZER, "test")
	s.equipment.equip("kot", BLAZER)
	s.presets.create_from_current("kot", "Бал")
	s.rewards.submit(s.challenges.get_challenge(CH), {"final_score": 500, "rank": "B"})
	s.flags.set_flag("chapter1_started")
	check(svc.save(s.to_save_dict()), "сохранено")
	var loaded := svc.load_save()
	check(loaded.ok, "загружено")
	var s2 := GameSession.create()
	s2.load_save_dict(loaded.data)
	check(s2.inventory.owns(BLAZER), "гардероб")
	check(s2.equipment.get_outfit("kot").has_item(BLAZER), "экипировка")
	eq(s2.presets.presets_for("kot").size(), 1, "комплекты")
	eq(int(s2.rewards.result(CH).best_score), 500, "лучший результат")
	eq(s2.resources.amount("coins"), s.resources.amount("coins"), "валюта")
	check(s2.flags.is_set("chapter1_started"), "сюжетный флаг")
	svc.delete_all()


func test_corrupted_save_falls_back_to_backup() -> void:
	var svc := SaveService.new(TEST_SAVE)
	svc.delete_all()
	var s := fresh_session()
	svc.save(s.to_save_dict())
	svc.save(s.to_save_dict())   # теперь есть .bak
	var f := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string("{ повреждено")
	f.close()
	var r := svc.load_save()
	check(r.ok, "загружено из резервной копии")
	check(r.from_backup, "флаг резервной копии")
	svc.delete_all()


func test_migration_from_v0() -> void:
	var d := SaveMigrations.migrate({"owned_items": ["clothing_plain_shirt_001"]}, 0, SaveService.CURRENT_VERSION)
	var s := GameSession.create()
	s.load_save_dict(d)
	check(s.inventory.owns("clothing_plain_shirt_001"), "владение перенесено из v0")
