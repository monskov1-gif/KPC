class_name ResultPopup
extends RefCounted
## Содержимое окна результата испытания: ранг, очки, награды (с иконками), советы, вклад вещей, условия.


static func fill(sheet: Sheet, screen: WardrobeScreen, ch: Dictionary, report: Dictionary, outcome: Dictionary, advice: Array) -> void:
	var s := screen.session
	sheet.clear()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	head.add_child(RankBadge.make(report.rank, 96))
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.alignment = BoxContainer.ALIGNMENT_CENTER
	var sr := HBoxContainer.new()
	sr.add_child(UiTheme.icon("sparkle", 28, UiTheme.GOLD))
	sr.add_child(UiTheme.tag(str(report.final_score), 36))
	sr.add_child(UiTheme.tag(Localization.t("rank." + report.rank), 20, UiTheme.TEXT_DIM))
	hv.add_child(sr)
	hv.add_child(UiTheme.label(Localization.text("ui.formula", {"raw": "%.0f" % report.raw_score, "q": "%.2f" % report.q}),
		UiTheme.FONT_SIZE_SMALL, UiTheme.TEXT_DIM))
	if outcome.get("new_best", false):
		var nb := HBoxContainer.new()
		nb.add_child(UiTheme.icon("trophy", 20, UiTheme.OK))
		nb.add_child(UiTheme.label(Localization.t("ui.new_best"), UiTheme.FONT_SIZE, UiTheme.OK))
		hv.add_child(nb)
	head.add_child(hv)
	sheet.content.add_child(head)

	# Награды — сразу под результатом, карточками с иконками.
	var rewards: Array = outcome.get("rewards", [])
	if not rewards.is_empty():
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 10)
		for g in rewards:
			flow.add_child(_reward_chip(g, screen))
		sheet.content.add_child(flow)
	else:
		sheet.content.add_child(UiTheme.label(Localization.t("ui.no_rewards"), UiTheme.FONT_SIZE_SMALL, UiTheme.TEXT_DIM))

	var lines := _advice_lines(screen, report, advice)
	if not lines.is_empty():
		_section(sheet, Localization.t("ui.recommendations"), "sparkle")
		for line in lines:
			sheet.content.add_child(UiTheme.label("• " + line, UiTheme.FONT_SIZE_SMALL))

	_section(sheet, Localization.t("ui.items_contribution"), "hanger")
	var items: Array = report.items.duplicate()
	items.sort_custom(func(a, b): return a.score > b.score if a.score != b.score else a.item_id < b.item_id)
	for i in items:
		var it := s.catalog.get_item(i.item_id)
		var row := HBoxContainer.new()
		var ic := UiTheme.icon(it.slot, 26, it.placeholder_color)
		ic.outline = it.placeholder_color.darkened(0.35)
		row.add_child(ic)
		row.add_child(UiTheme.label(screen.item_name(i.item_id), UiTheme.FONT_SIZE_SMALL))
		row.add_child(UiTheme.tag("%.0f × %.1f" % [i.base, i.theme_multiplier], UiTheme.FONT_SIZE_SMALL, UiTheme.TEXT_DIM))
		var sc := UiTheme.tag("%.0f" % i.score, UiTheme.FONT_SIZE_SMALL, UiTheme.GOLD.darkened(0.2))
		sc.custom_minimum_size.x = 48
		sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(sc)
		sheet.content.add_child(row)

	_section(sheet, Localization.t("ui.requirements"), "check")
	for r in report.requirements:
		var note := "" if r.met else (Localization.text("ui.penalty", {"q": "%.2f" % r.q}) if r.q < 1.0 else "")
		sheet.content.add_child(ChallengePanel.condition_row(r.met, r.severity == "informational", "sparkle",
			Localization.t(r.text_key), note, UiTheme.BAD if r.severity == "critical" else UiTheme.TEXT_DIM))
	for p in report.penalties:
		if p.source == "theme_ignored":
			sheet.content.add_child(ChallengePanel.condition_row(false, false, "sparkle", Localization.t("ui.theme_ignored"),
				Localization.text("ui.penalty", {"q": "%.2f" % p.q}), UiTheme.BAD))
	var close_btn := UiTheme.primary(UiTheme.button(Localization.t("ui.close"), sheet.close))
	close_btn.custom_minimum_size = Vector2(220, 54)
	sheet.add_footer(close_btn)
	sheet.open(Localization.t(ch.title_key), "trophy")


static func _section(sheet: Sheet, title: String, icon: String) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 40
	row.add_child(UiTheme.icon(icon, 22, UiTheme.GOLD))
	var l := UiTheme.label(title, UiTheme.FONT_SIZE, UiTheme.GOLD.darkened(0.25))
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	sheet.content.add_child(row)


static func _reward_chip(g: Dictionary, screen: WardrobeScreen) -> Control:
	var s := screen.session
	var r: Dictionary = g.reward
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.cloud(Color("fff6e3"), 18, 10))
	var row := HBoxContainer.new()
	p.add_child(row)
	match r.type:
		"item":
			var it := s.catalog.get_item(r.id)
			var ic := UiTheme.icon(it.slot, 40, it.placeholder_color)
			ic.outline = it.placeholder_color.darkened(0.35)
			row.add_child(ic)
			var t := screen.item_name(r.id)
			if g.result.status == "duplicate_converted":
				row.add_child(UiTheme.tag(t + " →", UiTheme.FONT_SIZE_SMALL))
				row.add_child(UiTheme.icon("coin", 24))
				row.add_child(UiTheme.tag("+%d" % g.result.amount, UiTheme.FONT_SIZE))
			else:
				row.add_child(UiTheme.tag(t, UiTheme.FONT_SIZE_SMALL))
		"resource":
			var icon := "coin" if r.id == "coins" else ("thread" if r.id.begins_with("thread") else "fabric")
			row.add_child(UiTheme.icon(icon, 36, Color("b5446a") if icon == "fabric" else Color("c9b8e8")))
			row.add_child(UiTheme.tag("×%d" % int(r.get("amount", 1)), 22))
			row.tooltip_text = Localization.t(s.resources.definition(r.id).get("name_key", r.id))
		"recipe":
			row.add_child(UiTheme.icon("recipe", 36, Color("f3e3c8")))
			row.add_child(UiTheme.tag(Localization.t(s.crafting.get_recipe(r.id).get("name_key", r.id)), UiTheme.FONT_SIZE_SMALL))
	return p


## Советы: конкретные вещи из гардероба (FashionAdvisor), затем общие рекомендации без готовой вещи.
static func _advice_lines(screen: WardrobeScreen, report: Dictionary, advice: Array) -> Array[String]:
	var lines: Array[String] = []
	var covered := {}
	for a in advice:
		if a.item_ids.is_empty():
			continue
		var opts: Array = []
		for k in a.item_ids.size():
			opts.append(Localization.text("rec.gain", {"name": screen.item_name(a.item_ids[k]), "gain": a.gains[k]}))
		if a.kind == "requirement":
			lines.append(Localization.text("rec.wear_for_requirement", {"text": Localization.t(a.text_key), "items": " или ".join(opts)}))
			covered[a.text_key] = true
		else:
			lines.append(Localization.text("rec.replace_with", {"item": screen.item_name(a.target), "items": " или ".join(opts)}))
			covered[a.target] = true
	for rec in report.recommendations:
		var p: Dictionary = rec.params
		match rec.key:
			"rec.requirement":
				if p.severity != "informational" and not covered.has(p.text_key):
					lines.append(Localization.text(rec.key, {"text": Localization.t(p.text_key)}))
			"rec.replace_item":
				if not covered.has(p.item_id):
					lines.append(Localization.text(rec.key, {"item": screen.item_name(p.item_id), "level": Localization.t("theme." + p.level)}))
			"rec.synergy_near", "rec.optional":
				lines.append(Localization.text(rec.key, {"text": Localization.t(p.text_key)}))
			_:
				lines.append(Localization.t(rec.key))
	return lines

