class_name FashionScoringService
extends RefCounted
## Детерминированный расчёт очков модного испытания и отчёт с объяснением.
##   ItemScore(i) = BaseContribution(i) * ThemeMultiplier(i) * ItemSpecificMultiplier(i)
##   RawScore     = Σ ItemScore + бонусы синергий + бонусы доп. условий
##   FinalScore   = round(RawScore * Q)
## UI только показывает отчёт и не считает очки сам.

var config: WardrobeConfig


func _init(p_config: WardrobeConfig) -> void:
	config = p_config


func score(challenge: Dictionary, outfit_items: Array[ClothingItem]) -> Dictionary:
	# Порядок предметов фиксируется, чтобы результат не зависел от порядка надевания.
	var items: Array[ClothingItem] = outfit_items.duplicate()
	items.sort_custom(func(a: ClothingItem, b: ClothingItem): return a.id < b.id)

	var weights: Dictionary = challenge.get("attribute_weights", {})
	var levels: Dictionary = _merged_levels(challenge)
	var item_mults: Dictionary = challenge.get("item_multipliers", {})

	var report := {
		"challenge_id": challenge.get("id", ""),
		"items": [], "synergies": [], "optional": [], "requirements": [],
		"penalties": [], "recommendations": [],
		"raw_score": 0.0, "q": 1.0, "final_score": 0, "rank": "",
	}
	var raw := 0.0
	var theme_matched := false
	var scored_count := 0

	for it in items:
		var base := 0.0
		var attr_names := weights.keys()
		attr_names.sort()
		for a in attr_names:
			base += it.attr(a) * float(weights[a])
		var rule := _theme_rule_for(challenge, it)
		var level: String = rule.get("level", challenge.get("default_theme_level", "neutral"))
		var theme_mult := float(levels.get(level, 1.0))
		var item_mult := float(item_mults.get(it.id, 1.0))
		var s := base * theme_mult * item_mult
		raw += s
		if theme_mult > 0.0:
			scored_count += 1
		if config.theme_matching_levels.has(level):
			theme_matched = true
		report.items.append({
			"item_id": it.id, "base": base, "theme_level": level, "theme_rule": rule.get("id", ""),
			"theme_multiplier": theme_mult, "item_multiplier": item_mult, "score": s,
		})

	for syn in challenge.get("synergy_rules", []):
		var r := SynergyEvaluator.evaluate(syn, items)
		var bonus: float = float(syn.get("bonus", 0)) * r.triggers
		raw += bonus
		report.synergies.append({"id": syn.id, "text_key": syn.get("text_key", ""), "triggered": r.triggers > 0,
			"triggers": r.triggers, "bonus": bonus, "count": r.count, "needed": r.needed})

	for opt in challenge.get("optional_requirements", []):
		var met := RequirementEvaluator.is_met(opt, items)
		var bonus := float(opt.get("bonus", 0)) if met else 0.0
		raw += bonus
		report.optional.append({"id": opt.id, "text_key": opt.get("text_key", ""), "met": met, "bonus": bonus})

	var q_values: Array[float] = []
	for req in challenge.get("requirements", []):
		var met := RequirementEvaluator.is_met(req, items)
		var severity: String = req.get("severity", "minor")
		var q := 1.0 if met else float(config.severity_q.get(severity, 1.0))
		report.requirements.append({"id": req.id, "text_key": req.get("text_key", ""), "met": met,
			"severity": severity, "q": q})
		if q < 1.0:
			q_values.append(q)
			report.penalties.append({"source": "requirement", "id": req.id, "q": q})

	# Штраф применяется только если испытание вообще задаёт тематические правила с «хорошими» уровнями.
	var theme_defined := (challenge.get("theme_rules", []) as Array).any(
		func(r): return config.theme_matching_levels.has(str(r.get("level", ""))))
	if theme_defined and scored_count > 0 and not theme_matched:
		q_values.append(config.theme_ignored_q)
		report.penalties.append({"source": "theme_ignored", "id": "theme_ignored", "q": config.theme_ignored_q})

	var q_total := _combine(q_values)
	report.raw_score = raw
	report.q = q_total
	report.final_score = int(round(raw * q_total))
	report.rank = rank_for(challenge, report.final_score)
	report.recommendations = _recommendations(report)
	return report


func rank_for(challenge: Dictionary, final_score: int) -> String:
	var thresholds: Dictionary = challenge.get("rank_thresholds", config.default_rank_thresholds)
	var best := ""
	var best_value := -INF
	for rank in thresholds.keys():
		var v := float(thresholds[rank])
		if final_score >= v and v > best_value:
			best = rank
			best_value = v
	return best if best != "" else (config.rank_order[0] if not config.rank_order.is_empty() else "")


## Первое подходящее правило темы в порядке данных; пустой словарь — правило по умолчанию.
func _theme_rule_for(challenge: Dictionary, it: ClothingItem) -> Dictionary:
	for rule in challenge.get("theme_rules", []):
		if _rule_matches(rule.get("when", {}), it):
			return rule
	return {}


func _rule_matches(when: Dictionary, it: ClothingItem) -> bool:
	if when.is_empty():
		return false
	if when.has("item_ids") and not (when.item_ids as Array).has(it.id):
		return false
	if when.has("categories") and not (when.categories as Array).has(it.category):
		return false
	if when.has("slots") and not (when.slots as Array).has(it.slot):
		return false
	if when.has("tags_any"):
		var any := false
		for t in when.tags_any:
			if it.has_tag(str(t)):
				any = true
				break
		if not any:
			return false
	if when.has("tags_all"):
		for t in when.tags_all:
			if not it.has_tag(str(t)):
				return false
	return true


func _merged_levels(challenge: Dictionary) -> Dictionary:
	var levels := config.theme_levels.duplicate()
	var overrides: Dictionary = challenge.get("theme_levels", {})
	for k in overrides.keys():
		levels[k] = overrides[k]
	return levels


## Объединение штрафов не зависит от порядка проверки.
func _combine(q_values: Array[float]) -> float:
	if q_values.is_empty():
		return 1.0
	if config.combination_method == "bounded_product":
		var p := 1.0
		for q in q_values:
			p *= q
		return maxf(p, config.combination_floor)
	var m := 1.0
	for q in q_values:
		m = minf(m, q)
	return m


func _recommendations(report: Dictionary) -> Array:
	var recs: Array = []
	for r in report.requirements:
		if not r.met:
			recs.append({"key": "rec.requirement", "params": {"text_key": r.text_key, "severity": r.severity}})
	if report.penalties.any(func(p): return p.source == "theme_ignored"):
		recs.append({"key": "rec.theme_ignored", "params": {}})
	for i in report.items:
		if i.theme_level == "contradicts" or i.theme_level == "weak":
			recs.append({"key": "rec.replace_item", "params": {"item_id": i.item_id, "level": i.theme_level}})
	for s in report.synergies:
		if not s.triggered and s.needed > 1 and s.count == s.needed - 1:
			recs.append({"key": "rec.synergy_near", "params": {"text_key": s.text_key}})
	for o in report.optional:
		if not o.met:
			recs.append({"key": "rec.optional", "params": {"text_key": o.text_key}})
	return recs
