class_name ChallengePanel
extends VBoxContainer
## Условия модного испытания и живая предварительная оценка.
## На больших экранах стоит в левой части, на телефоне открывается кнопкой-кубком в отдельном окне.
## Очки берутся только из FashionScoringService — то же, что будет в результате.

signal submitted

var screen: WardrobeScreen
var challenge_id := ""
var show_header := true
var show_submit := true


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)


func challenge() -> Dictionary:
	var s := screen.session
	if challenge_id == "" and not s.challenges.ids().is_empty():
		challenge_id = s.challenges.ids()[0]
	return s.challenges.get_challenge(challenge_id)


func refresh() -> void:
	if screen == null or screen.draft == null or not is_inside_tree():
		return
	var s := screen.session
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var ch := challenge()
	if ch.is_empty():
		add_child(UiTheme.label(tr("ui.no_challenges"), UiTheme.FONT_SIZE, UiTheme.TEXT_DIM))
		return
	if show_header:
		var head := HBoxContainer.new()
		head.add_child(UiTheme.icon("trophy", 30, UiTheme.GOLD))
		head.add_child(UiTheme.label(tr(ch.title_key), 21))
		add_child(head)
	add_child(UiTheme.label(tr(ch.description_key), UiTheme.FONT_SIZE_SMALL, UiTheme.TEXT_DIM))

	# Важные характеристики: чипы, вес показан искрами.
	var weights: Dictionary = ch.get("attribute_weights", {})
	var important := weights.keys().filter(func(a): return float(weights[a]) >= 1.0)
	important.sort_custom(func(a, b): return float(weights[a]) > float(weights[b]))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	for a in important:
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", UiTheme.pill(Color("fdeef1"), 8))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		row.add_child(UiTheme.tag(tr("attr." + a), UiTheme.FONT_SIZE_SMALL))
		var sparks := 3 if float(weights[a]) >= 1.5 else (2 if float(weights[a]) >= 1.2 else 1)
		for i in sparks:
			row.add_child(UiTheme.icon("sparkle", 14, UiTheme.GOLD))
		p.add_child(row)
		flow.add_child(p)
	add_child(flow)

	var report := s.scoring.score(ch, s.items_for_outfit(screen.draft))
	add_child(_preview(report, s.rewards.result(challenge_id)))

	for r in report.requirements:
		var soft: bool = r.severity == "informational"
		var note := "" if r.met else (Localization.text("ui.penalty", {"q": "%.2f" % r.q}) if r.q < 1.0 else "")
		add_child(condition_row(r.met, soft, _req_icon(ch, r.id), tr(r.text_key), note,
			UiTheme.BAD if r.severity == "critical" else UiTheme.TEXT_DIM))
	for p in report.penalties:
		if p.source == "theme_ignored":
			add_child(condition_row(false, false, "sparkle", tr("ui.theme_ignored"),
				Localization.text("ui.penalty", {"q": "%.2f" % p.q}), UiTheme.BAD))
	for o in report.optional:
		add_child(condition_row(o.met, true, "star", tr(o.text_key),
			"+%d" % int(_optional_bonus(ch, o.id)), UiTheme.OK if o.met else UiTheme.TEXT_DIM))
	for syn in report.synergies:
		add_child(condition_row(syn.triggered, true, "hanger", tr(syn.text_key), "%d/%d" % [syn.count, syn.needed], UiTheme.TEXT_DIM))

	if show_submit:
		var submit_btn := UiTheme.primary(UiTheme.button(tr("ui.submit"), func(): submitted.emit()))
		submit_btn.custom_minimum_size.y = 56
		add_child(submit_btn)


func _preview(report: Dictionary, best: Dictionary) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.cloud(Color.WHITE, 20, 14))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	p.add_child(row)
	row.add_child(RankBadge.make(report.rank, 64))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var score_row := HBoxContainer.new()
	score_row.add_child(UiTheme.icon("sparkle", 22, UiTheme.GOLD))
	score_row.add_child(UiTheme.tag(str(report.final_score), 28))
	score_row.add_child(UiTheme.tag(tr("rank." + report.rank), UiTheme.FONT_SIZE_SMALL, UiTheme.TEXT_DIM))
	v.add_child(score_row)
	if not best.is_empty():
		var b := HBoxContainer.new()
		b.add_child(UiTheme.icon("trophy", 16, UiTheme.TEXT_DIM))
		b.add_child(UiTheme.tag("%d · %s" % [best.best_score, best.best_rank], UiTheme.FONT_SIZE_SMALL, UiTheme.TEXT_DIM))
		v.add_child(b)
	row.add_child(v)
	return p


func _req_icon(ch: Dictionary, req_id: String) -> String:
	for r in ch.get("requirements", []):
		if r.id == req_id:
			match str(r.type):
				"required_slot": return str(r.params.slot)
				"required_category":
					var slots: Array = screen.session.config.categories.get(str(r.params.category), [])
					return slots[0] if not slots.is_empty() else "all"
				"forbidden_tag": return "close"
	return "sparkle"


func _optional_bonus(ch: Dictionary, id: String) -> float:
	for o in ch.get("optional_requirements", []):
		if o.id == id:
			return float(o.get("bonus", 0))
	return 0.0


## Строка условия: иконка условия, текст, заметка и маркер состояния (✓ выполнено / ✕ провал / ○ подсказка).
static func condition_row(met: bool, soft: bool, icon: String, text: String, note: String, note_color: Color) -> Control:
	var row := HBoxContainer.new()
	var state_col := UiTheme.OK if met else (UiTheme.CARD_EDGE.darkened(0.15) if soft else UiTheme.BAD)
	var bubble := PanelContainer.new()
	bubble.add_theme_stylebox_override("panel", UiTheme.pill(Color(state_col, 0.22), 4))
	bubble.custom_minimum_size = Vector2(38, 34)
	bubble.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bubble.add_child(UiTheme.icon(icon, 20, state_col.darkened(0.2)))
	row.add_child(bubble)
	row.add_child(UiTheme.label(text, UiTheme.FONT_SIZE_SMALL))
	if note != "":
		row.add_child(UiTheme.tag(note, UiTheme.FONT_SIZE_SMALL, note_color))
	row.add_child(UiTheme.icon("check" if met else ("minus" if soft else "close"), 16, state_col))
	return row
