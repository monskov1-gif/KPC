extends TestCase

var s: GameSession
var ch: Dictionary


func before_each() -> void:
	s = GameSession.create()
	s.new_game()
	ch = s.challenges.get_challenge("fashion_challenge_evening_ball_test_001")


func _items(ids: Array) -> Array[ClothingItem]:
	var out: Array[ClothingItem] = []
	for id in ids:
		out.append(s.catalog.get_item(id))
	return out


func _item(d: Dictionary) -> ClothingItem:
	var base := {"id": "t", "name_key": "k", "category": "top", "slot": "upper_body", "rarity": "common"}
	base.merge(d, true)
	return ClothingItem.from_dict(base)


func _simple_challenge(extra: Dictionary = {}) -> Dictionary:
	var c := {"id": "c", "attribute_weights": {"elegance": 2.0}, "theme_rules": [],
		"default_theme_level": "neutral", "requirements": [], "rank_thresholds": {"D": 0, "C": 100, "S": 1000}}
	c.merge(extra, true)
	return c


func test_same_outfit_same_score_independent_of_order() -> void:
	var ids := ["clothing_oxford_shoes_001", "clothing_silk_blouse_001", "clothing_pearl_necklace_001"]
	var a := s.scoring.score(ch, _items(ids))
	ids.reverse()
	var b := s.scoring.score(ch, _items(ids))
	eq(a.final_score, b.final_score)
	eq(a.rank, b.rank)
	eq(s.scoring.score(ch, _items(ids)).final_score, a.final_score, "повторный расчёт")


func test_relevant_attribute_scales_with_weight() -> void:
	var it := _item({"attributes": {"elegance": 50, "sportiness": 90}})
	var r := s.scoring.score(_simple_challenge(), [it] as Array[ClothingItem])
	near(r.items[0].base, 100.0, "50 * 2.0; спортивность не в весах")
	eq(r.final_score, 100)
	eq(r.rank, "C")


func test_zero_multiplier_zeroes_item() -> void:
	var c := _simple_challenge({"theme_rules": [{"id": "z", "when": {"slots": ["upper_body"]}, "level": "not_scored"}]})
	var r := s.scoring.score(c, [_item({"attributes": {"elegance": 80}})] as Array[ClothingItem])
	eq(r.items[0].score, 0.0)
	eq(r.final_score, 0)


func test_irrelevant_item_gets_nothing() -> void:
	var r := s.scoring.score(_simple_challenge(), [_item({"attributes": {"sportiness": 90}})] as Array[ClothingItem])
	eq(r.items[0].score, 0.0, "вклад нерелевантного предмета")


func test_lower_theme_multiplier_lowers_contribution() -> void:
	var it := _item({"attributes": {"elegance": 50}, "style_tags": ["sporty"]})
	var neutral := s.scoring.score(_simple_challenge(), [it] as Array[ClothingItem])
	var c := _simple_challenge({"theme_rules": [{"id": "x", "when": {"tags_any": ["sporty"]}, "level": "contradicts"}]})
	var bad := s.scoring.score(c, [it] as Array[ClothingItem])
	check(bad.items[0].score < neutral.items[0].score, "противоречащий теме предмет даёт меньше")
	near(bad.items[0].theme_multiplier, 0.1)


func test_missing_critical_requirement_cuts_score() -> void:
	var with_shoes := s.scoring.score(ch, _items(["clothing_silk_blouse_001", "clothing_tailored_trousers_001", "clothing_oxford_shoes_001"]))
	var without := s.scoring.score(ch, _items(["clothing_silk_blouse_001", "clothing_tailored_trousers_001"]))
	near(without.q, 0.25, "критическое условие — обувь")
	check(without.final_score < with_shoes.final_score, "без обуви результат ниже")
	check(without.requirements.any(func(r): return r.id == "req_footwear" and not r.met), "в отчёте есть невыполненное условие")
	check(without.recommendations.any(func(r): return r.key == "rec.requirement"), "есть рекомендация")


func test_strictest_penalty_is_order_independent() -> void:
	var c := _simple_challenge({"requirements": [
		{"id": "a", "type": "required_slot", "params": {"slot": "footwear"}, "severity": "minor"},
		{"id": "b", "type": "required_slot", "params": {"slot": "bag"}, "severity": "major"}]})
	var r1 := s.scoring.score(c, [_item({"attributes": {"elegance": 50}})] as Array[ClothingItem])
	(c.requirements as Array).reverse()
	var r2 := s.scoring.score(c, [_item({"attributes": {"elegance": 50}})] as Array[ClothingItem])
	near(r1.q, 0.5)
	near(r2.q, 0.5)


func test_synergy_triggers_once() -> void:
	var four := s.scoring.score(ch, _items(["clothing_silk_blouse_001", "clothing_tailored_trousers_001",
		"clothing_oxford_shoes_001", "clothing_pearl_necklace_001"]))
	var syn: Dictionary = four.synergies.filter(func(x): return x.id == "syn_evening_classic_set")[0]
	eq(syn.triggers, 1, "4 предмета набора — одно срабатывание")
	near(syn.bonus, 200.0)
	var two := s.scoring.score(ch, _items(["clothing_silk_blouse_001", "clothing_oxford_shoes_001"]))
	var syn2: Dictionary = two.synergies.filter(func(x): return x.id == "syn_evening_classic_set")[0]
	eq(syn2.triggers, 0)
	check(two.recommendations.any(func(r): return r.key == "rec.synergy_near"), "подсказка «не хватает одной вещи»")


func test_rank_thresholds() -> void:
	var c := _simple_challenge()
	eq(s.scoring.rank_for(c, 0), "D")
	eq(s.scoring.rank_for(c, 99), "D")
	eq(s.scoring.rank_for(c, 100), "C")
	eq(s.scoring.rank_for(c, 5000), "S")


func test_empty_outfit_does_not_crash() -> void:
	var r := s.scoring.score(ch, [] as Array[ClothingItem])
	eq(r.final_score, 0)
	eq(r.rank, "D")


func test_theme_ignored_penalty() -> void:
	var r := s.scoring.score(ch, _items(["clothing_plain_shirt_001", "clothing_kot_black_trousers_001", "clothing_dark_mary_janes_001"]))
	check(r.penalties.any(func(p): return p.source == "theme_ignored"), "тема проигнорирована")


func test_rarity_does_not_guarantee_win() -> void:
	# Эпическое платье без обуви против продуманного набора из необычных вещей.
	var epic := s.scoring.score(ch, _items(["clothing_evening_dress_001"]))
	var planned := s.scoring.score(ch, _items(["clothing_silk_blouse_001", "clothing_tailored_trousers_001",
		"clothing_oxford_shoes_001", "clothing_pearl_necklace_001"]))
	check(planned.final_score > epic.final_score, "набор (%d) > эпик без обуви (%d)" % [planned.final_score, epic.final_score])


func test_socks_small_but_harmless() -> void:
	var r := s.scoring.score(ch, _items(["clothing_white_knee_socks_001"]))
	eq(r.items[0].theme_level, "not_scored")
	eq(r.items[0].score, 0.0)


func test_balance_progression_path() -> void:
	# Цепочка тестового испытания: набор из магазина → A (выкройка) → блейзер из крафта → S.
	var classic := ["clothing_silk_blouse_001", "clothing_tailored_trousers_001", "clothing_oxford_shoes_001", "clothing_pearl_necklace_001"]
	eq(s.scoring.score(ch, _items(classic)).rank, "A", "набор из магазина")
	eq(s.scoring.score(ch, _items(classic + ["clothing_velvet_blazer_001"])).rank, "S", "с блейзером из крафта")
	eq(s.scoring.score(ch, s.outfit_items("kot")).rank, "D", "повседневный фирменный образ не подходит балу")


func test_advisor_suggests_owned_items_for_missing_requirement() -> void:
	s.grants.grant_item("clothing_oxford_shoes_001", "test")
	var outfit := Outfit.from_dict({"upper_body": "clothing_plain_shirt_001"})
	var advice := FashionAdvisor.suggest(s, ch, "kot", outfit)
	var shoes: Array = advice.filter(func(a): return a.target == "req_footwear")
	check(not shoes.is_empty(), "есть совет по обуви")
	eq(shoes[0].item_ids[0], "clothing_oxford_shoes_001", "лучший вариант — оксфорды, а не кроссовки")
	check(shoes[0].gains[0] > 0, "прирост очков положительный")
	for a in advice:
		for id in a.item_ids:
			check(s.inventory.owns(id), "советуются только свои вещи")


func test_advisor_suggests_replacement_for_weak_item() -> void:
	s.grants.grant_item("clothing_silk_blouse_001", "test")
	var outfit := Outfit.from_dict({"upper_body": "clothing_kot_flower_turtleneck_001", "footwear": "clothing_dark_mary_janes_001"})
	var advice := FashionAdvisor.suggest(s, ch, "kot", outfit)
	var rep: Array = advice.filter(func(a): return a.kind == "replace" and a.target == "clothing_kot_flower_turtleneck_001")
	check(not rep.is_empty() and rep[0].item_ids.has("clothing_silk_blouse_001"), "предложена шёлковая блузка: %s" % str(advice))
