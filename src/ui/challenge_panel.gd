class_name ChallengePanel
extends ScrollContainer
## Вкладка модного испытания: условия, живая предварительная оценка, подтверждение и отчёт.
## Очки берутся только из FashionScoringService.

var screen: WardrobeScreen
var challenge_id := ""
var _box: VBoxContainer
var _result: ResultPopup


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_box)
	_result = ResultPopup.new()
	_result.screen = screen
	screen.add_child.call_deferred(_result)
	refresh()


func refresh() -> void:
	if _box == null or screen == null or screen.draft == null:
		return
	var s := screen.session
	if challenge_id == "" and not s.challenges.ids().is_empty():
		challenge_id = s.challenges.ids()[0]
	WardrobeScreen._clear(_box)
	var ch := s.challenges.get_challenge(challenge_id)
	if ch.is_empty():
		_box.add_child(UiTheme.label("Нет доступных испытаний.", UiTheme.FONT_SIZE, UiTheme.TEXT_DIM))
		return
	_box.add_child(UiTheme.label(tr(ch.title_key), 22))
	_box.add_child(UiTheme.label(tr(ch.description_key), UiTheme.FONT_SIZE_SMALL, UiTheme.TEXT_DIM))

	var weights: Dictionary = ch.get("attribute_weights", {})
	var important := weights.keys().filter(func(a): return float(weights[a]) >= 1.0)
	important.sort_custom(func(a, b): return float(weights[a]) > float(weights[b]))
	_box.add_child(UiTheme.label("Важно: " + ", ".join(important.map(func(a): return tr("attr." + a))),
		UiTheme.FONT_SIZE_SMALL, UiTheme.ACCENT))

	var report := s.scoring.score(ch, s.items_for_outfit(screen.draft))
	var preview := PanelContainer.new()
	preview.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PANEL_LIGHT, 12, 14))
	var pv := VBoxContainer.new()
	preview.add_child(pv)
	pv.add_child(UiTheme.label(Localization.text("ui.preview_score", {"score": report.final_score, "rank": report.rank}),
		20, UiTheme.ACCENT))
	var best := s.rewards.result(challenge_id)
	if not best.is_empty():
		pv.add_child(UiTheme.label("Лучший результат: %d (%s)" % [best.best_score, best.best_rank],
			UiTheme.FONT_SIZE_SMALL, UiTheme.TEXT_DIM))
	_box.add_child(preview)

	_box.add_child(UiTheme.label(tr("ui.requirements"), UiTheme.FONT_SIZE, UiTheme.ACCENT))
	for r in report.requirements:
		_box.add_child(_check_row(r.met, tr(r.text_key), tr("severity." + r.severity)))
	for o in report.optional:
		_box.add_child(_check_row(o.met, tr(o.text_key), "бонус +%d" % int(o.bonus if o.met else 0)))
	_box.add_child(UiTheme.label(tr("ui.synergies"), UiTheme.FONT_SIZE, UiTheme.ACCENT))
	for syn in report.synergies:
		_box.add_child(_check_row(syn.triggered, tr(syn.text_key), "%d/%d" % [syn.count, syn.needed]))

	var submit_btn := UiTheme.button(tr("ui.submit"), submit)
	submit_btn.custom_minimum_size.y = 56
	_box.add_child(submit_btn)


func _check_row(met: bool, text: String, note: String) -> Control:
	var row := HBoxContainer.new()
	var mark := UiTheme.label("✓" if met else "✕", UiTheme.FONT_SIZE, UiTheme.OK if met else UiTheme.BAD)
	mark.custom_minimum_size.x = 24
	row.add_child(mark)
	var l := UiTheme.label(text, UiTheme.FONT_SIZE_SMALL)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var n := UiTheme.label(note, UiTheme.FONT_SIZE_SMALL, UiTheme.TEXT_DIM)
	n.autowrap_mode = TextServer.AUTOWRAP_OFF
	n.size_flags_horizontal = Control.SIZE_FILL
	row.add_child(n)
	return row


## Подтверждает черновик образа, считает результат и выдаёт награды.
func submit() -> void:
	var s := screen.session
	if challenge_id == "" and not s.challenges.ids().is_empty():
		challenge_id = s.challenges.ids()[0]
	var ch := s.challenges.get_challenge(challenge_id)
	if ch.is_empty():
		return
	if screen.is_dirty():
		screen.commit_draft()
	var report := s.scoring.score(ch, s.outfit_items(screen.character_id))
	var outcome := s.rewards.submit(ch, report)
	Game.save_game()
	_result.show_result(ch, report, outcome)
	screen._refresh_all()
