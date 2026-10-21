class_name ResultPopup
extends Control
## Экран результата испытания: очки, ранг, вклад вещей, условия, бонусы, штрафы, рекомендации, награды.

var screen: WardrobeScreen
var _content: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 40; panel.offset_right = -40; panel.offset_top = 30; panel.offset_bottom = -30
	add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)
	var close := UiTheme.button(tr("ui.close"), func(): visible = false)
	close.custom_minimum_size = Vector2(240, 52)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(close)


func show_result(ch: Dictionary, report: Dictionary, outcome: Dictionary) -> void:
	WardrobeScreen._clear(_content)
	var s := screen.session
	_content.add_child(UiTheme.label(tr(ch.title_key), UiTheme.FONT_SIZE_TITLE))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 32)
	var rank := UiTheme.label(report.rank, 72, UiTheme.ACCENT)
	rank.autowrap_mode = TextServer.AUTOWRAP_OFF
	rank.size_flags_horizontal = Control.SIZE_FILL
	head.add_child(rank)
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_child(UiTheme.label(Localization.text("ui.score", {"score": report.final_score}), 28))
	hv.add_child(UiTheme.label("Сумма %.0f × коэффициент условий %.2f" % [report.raw_score, report.q],
		UiTheme.FONT_SIZE_SMALL, UiTheme.TEXT_DIM))
	if outcome.get("new_best", false):
		hv.add_child(UiTheme.label("Новый лучший результат!", UiTheme.FONT_SIZE, UiTheme.OK))
	head.add_child(hv)
	_content.add_child(head)

	_section(tr("ui.items_contribution"))
	var items: Array = report.items.duplicate()
	items.sort_custom(func(a, b): return a.score > b.score)
	for i in items:
		var row := HBoxContainer.new()
		var n := UiTheme.label(screen.item_name(i.item_id), UiTheme.FONT_SIZE_SMALL)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(n)
		var formula := "%.0f × %.1f (%s)" % [i.base, i.theme_multiplier, tr("theme." + i.theme_level)]
		if not is_equal_approx(i.item_multiplier, 1.0):
			formula += " × %.1f" % i.item_multiplier
		var f := UiTheme.label(formula, UiTheme.FONT_SIZE_SMALL, UiTheme.TEXT_DIM)
		f.autowrap_mode = TextServer.AUTOWRAP_OFF
		f.size_flags_horizontal = Control.SIZE_FILL
		row.add_child(f)
		var sc := UiTheme.label("= %.0f" % i.score, UiTheme.FONT_SIZE_SMALL, UiTheme.ACCENT)
		sc.custom_minimum_size.x = 80
		sc.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(sc)
		_content.add_child(row)

	_section(tr("ui.requirements"))
	for r in report.requirements:
		var txt := "%s %s — %s" % ["✓" if r.met else "✕", tr(r.text_key), tr("ui.met") if r.met else tr("ui.not_met")]
		if not r.met and r.q < 1.0:
			txt += " (штраф ×%.2f)" % r.q
		_content.add_child(UiTheme.label(txt, UiTheme.FONT_SIZE_SMALL, UiTheme.OK if r.met else UiTheme.BAD))
	for p in report.penalties:
		if p.source == "theme_ignored":
			_content.add_child(UiTheme.label("✕ Тема проигнорирована (штраф ×%.2f)" % p.q, UiTheme.FONT_SIZE_SMALL, UiTheme.BAD))

	_section(tr("ui.synergies"))
	var any_syn := false
	for syn in report.synergies:
		if syn.triggered:
			any_syn = true
			_content.add_child(UiTheme.label("✓ %s: +%.0f" % [tr(syn.text_key), syn.bonus], UiTheme.FONT_SIZE_SMALL, UiTheme.OK))
	for o in report.optional:
		if o.met:
			any_syn = true
			_content.add_child(UiTheme.label("✓ %s: +%.0f" % [tr(o.text_key), o.bonus], UiTheme.FONT_SIZE_SMALL, UiTheme.OK))
	if not any_syn:
		_content.add_child(UiTheme.label("—", UiTheme.FONT_SIZE_SMALL, UiTheme.TEXT_DIM))

	if not report.recommendations.is_empty():
		_section(tr("ui.recommendations"))
		for rec in report.recommendations:
			_content.add_child(UiTheme.label("• " + _rec_text(rec), UiTheme.FONT_SIZE_SMALL))

	_section(tr("ui.rewards"))
	var rewards: Array = outcome.get("rewards", [])
	if rewards.is_empty():
		_content.add_child(UiTheme.label("Новых наград нет.", UiTheme.FONT_SIZE_SMALL, UiTheme.TEXT_DIM))
	for g in rewards:
		_content.add_child(UiTheme.label("★ " + _reward_text(g, s), UiTheme.FONT_SIZE_SMALL, UiTheme.WARN))
	visible = true


func _section(title: String) -> void:
	var l := UiTheme.label(title, UiTheme.FONT_SIZE, UiTheme.ACCENT)
	l.custom_minimum_size.y = 36
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_content.add_child(l)


func _rec_text(rec: Dictionary) -> String:
	var p: Dictionary = rec.params
	match rec.key:
		"rec.requirement", "rec.synergy_near", "rec.optional":
			return Localization.text(rec.key, {"text": tr(p.text_key)})
		"rec.replace_item":
			return Localization.text(rec.key, {"item": screen.item_name(p.item_id), "level": tr("theme." + p.level)})
	return tr(rec.key)


func _reward_text(g: Dictionary, s: GameSession) -> String:
	var r: Dictionary = g.reward
	match r.type:
		"item":
			var t := Localization.text("ui.reward_item", {"name": screen.item_name(r.id)})
			if g.result.status == "duplicate_converted":
				t += " " + Localization.text("ui.duplicate", {"n": g.result.amount})
			return t
		"resource":
			return Localization.text("ui.reward_resource", {"name": tr(s.resources.definition(r.id).get("name_key", r.id)), "n": r.get("amount", 1)})
		"recipe":
			return Localization.text("ui.reward_recipe", {"name": tr(s.crafting.get_recipe(r.id).get("name_key", r.id))})
	return str(r)
