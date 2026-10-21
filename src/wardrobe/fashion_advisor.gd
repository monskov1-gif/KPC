class_name FashionAdvisor
extends RefCounted
## Конкретные советы по улучшению образа: какие вещи из гардероба игрока закрывают
## невыполненные условия или заменяют неподходящие теме вещи. Оценка — через FashionScoringService.

const MAX_PER_ADVICE := 2


## Возвращает [{kind, target, item_ids:[...], gains:[...]}], kind: "requirement" | "replace".
static func suggest(session: GameSession, challenge: Dictionary, character_id: String, outfit: Outfit) -> Array:
	var base_items := session.items_for_outfit(outfit)
	var base_score: int = session.scoring.score(challenge, base_items).final_score
	var candidates: Array[ClothingItem] = []
	for it in session.catalog.all_items():
		if session.inventory.owns(it.id) and not outfit.has_item(it.id) \
				and Compatibility.can_wear(it, character_id, session.characters):
			candidates.append(it)

	var out: Array = []
	for req in challenge.get("requirements", []):
		if RequirementEvaluator.is_met(req, base_items) or req.get("severity", "") == "informational":
			continue
		var fixes := _rank(session, challenge, character_id, outfit, base_score,
			candidates.filter(func(it): return RequirementEvaluator.is_met(req, [it] as Array[ClothingItem])))
		out.append({"kind": "requirement", "target": req.id, "text_key": req.get("text_key", ""),
			"item_ids": fixes.map(func(f): return f.id), "gains": fixes.map(func(f): return f.gain)})

	var report := session.scoring.score(challenge, base_items)
	for i in report.items:
		if i.theme_level != "contradicts" and i.theme_level != "weak":
			continue
		var worn := session.catalog.get_item(i.item_id)
		var same_slot := candidates.filter(func(it): return it.slot == worn.slot)
		var fixes := _rank(session, challenge, character_id, outfit, base_score, same_slot)
		if not fixes.is_empty():
			out.append({"kind": "replace", "target": i.item_id, "text_key": "",
				"item_ids": fixes.map(func(f): return f.id), "gains": fixes.map(func(f): return f.gain)})
	return out


## Лучшие кандидаты по приросту итоговых очков (только с положительным приростом).
static func _rank(session: GameSession, challenge: Dictionary, character_id: String, outfit: Outfit,
		base_score: int, items: Array) -> Array:
	var scored: Array = []
	for it in items:
		var trial := outfit.duplicate_outfit()
		if not session.equipment.equip_into(trial, character_id, it.id).ok:
			continue
		var gain: int = session.scoring.score(challenge, session.items_for_outfit(trial)).final_score - base_score
		if gain > 0:
			scored.append({"id": it.id, "gain": gain})
	scored.sort_custom(func(a, b): return a.gain > b.gain if a.gain != b.gain else a.id < b.id)
	return scored.slice(0, MAX_PER_ADVICE)
