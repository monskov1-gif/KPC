class_name WardrobeScreen
extends Control
## Экран гардероба в мягком «облачном» стиле.
## ПК: слева условия испытания, по центру персонаж на подиуме, справа полоса категорий и сетка вещей.
## Телефон: персонаж сверху, вещи снизу, условия испытания — по кнопке-кубку.
## Тап по вещи — надеть/снять, долгое нажатие — характеристики.
## Изменения собираются в черновике (draft) и применяются кнопкой «Сохранить».
## Логика (совместимость, слоты, очки) — только в доменных сервисах.

signal closed

const NARROW_WIDTH := 1000.0
const MARGIN := 20.0
const TOP_BAR := 76.0
const CATEGORY_GROUPS := [
	{"id": "all", "icon": "all"},
	{"id": "headwear", "slot": "headwear", "icon": "headwear"},
	{"id": "face_accessory", "slot": "face_accessory", "icon": "face_accessory"},
	{"id": "upper_body", "slot": "upper_body", "icon": "upper_body"},
	{"id": "outerwear", "slot": "outerwear", "icon": "outerwear"},
	{"id": "lower_body", "slot": "lower_body", "icon": "lower_body"},
	{"id": "full_body", "slot": "full_body", "icon": "full_body"},
	{"id": "socks", "slot": "socks", "icon": "socks"},
	{"id": "footwear", "slot": "footwear", "icon": "footwear"},
	{"id": "gloves", "slot": "gloves", "icon": "gloves"},
	{"id": "jewelry", "category": "jewelry", "icon": "neck_accessory"},
	{"id": "bag", "slot": "bag", "icon": "bag"},
]

var session: GameSession
var character_id := ""
var draft: Outfit
var query := WardrobeQuery.new()
var category := "all"

var _narrow := false
var _top: HBoxContainer
var _avatars := {}
var _coins_label: Label
var _stage: SubViewportContainer
var _appearance: PlaceholderAppearance
var _preview_cam: Camera3D
var _placeholder_note: Label
var _challenge_cloud: PanelContainer
var _challenge_scroll: ScrollContainer
var _challenge: ChallengePanel
var _grid_cloud: PanelContainer
var _grid_box: BoxContainer
var _strip_scroll: ScrollContainer
var _strip: BoxContainer
var _strip_buttons := {}
var _grid: GridContainer
var _grid_scroll: ScrollContainer
var _search: LineEdit
var _sort: OptionButton
var _actions: HBoxContainer
var _save_btn: Button
var _undo_btn: Button
var _trophy_btn: Button
var _trophy_rank: RankBadge
var _toast: PanelContainer
var _sheet: Sheet
var _pending_character := ""


func _ready() -> void:
	session = Game.session
	theme = UiTheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	query.sort = WardrobeQuery.Sort.CATALOG
	_build()
	var first: String = session.unlocked_characters[0] if not session.unlocked_characters.is_empty() else session.characters.ids()[0]
	_set_character(first)
	resized.connect(_layout)
	_layout()


# ---------- построение ----------

func _build() -> void:
	var bg := SoftBackground.new()
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_stage()
	_build_top_bar()
	_build_challenge()
	_build_grid()
	_build_actions()
	_toast = PanelContainer.new()
	_toast.add_theme_stylebox_override("panel", UiTheme.cloud(UiTheme.PANEL_SOLID, 999, 12))
	_toast.visible = false
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast)
	_sheet = Sheet.new()
	add_child(_sheet)


func _build_top_bar() -> void:
	_top = HBoxContainer.new()
	_top.add_theme_constant_override("separation", 12)
	add_child(_top)
	_top.add_child(UiTheme.icon_button("back", _on_close, 52))
	var title := PanelContainer.new()
	title.add_theme_stylebox_override("panel", UiTheme.pill(Color("fff6e3"), 14))
	title.add_child(UiTheme.tag(tr("ui.wardrobe"), 22, UiTheme.GOLD.darkened(0.3)))
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_top.add_child(title)
	for c in session.characters.ids():
		var b := Button.new()
		b.flat = true
		b.custom_minimum_size = Vector2(60, 60)
		b.tooltip_text = tr(session.characters.get_data(c).name_key)
		b.disabled = not session.unlocked_characters.has(c)
		var av := AvatarView.new()
		av.hair = session.characters.placeholder_color(c)
		av.cat_ears = c == "kot"
		b.add_child(av)
		av.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		b.pressed.connect(_request_character.bind(c))
		_avatars[c] = av
		_top.add_child(b)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top.add_child(spacer)
	# Номер версии сборки (растёт на 0.01 с каждой правкой) — видно, какая версия открыта на сайте.
	_top.add_child(UiTheme.tag("v" + str(ProjectSettings.get_setting("application/config/version", "?")), 14, UiTheme.TEXT_DIM))
	var coins := PanelContainer.new()
	coins.add_theme_stylebox_override("panel", UiTheme.pill(UiTheme.PANEL_SOLID, 10))
	coins.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ch := HBoxContainer.new()
	ch.add_child(UiTheme.icon("coin", 28))
	_coins_label = UiTheme.tag("", 20)
	ch.add_child(_coins_label)
	coins.add_child(ch)
	_top.add_child(coins)


func _build_stage() -> void:
	_stage = SubViewportContainer.new()
	_stage.stretch = true
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	_stage.add_child(vp)
	_preview_cam = Camera3D.new()
	_preview_cam.fov = 32
	vp.add_child(_preview_cam)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 25, 0)
	key.light_energy = 0.7
	key.light_color = Color("fff1e6")
	key.shadow_enabled = true
	vp.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(0.7, 2.0, -1.3)
	rim.light_color = Color("ffd9e4")
	rim.light_energy = 0.9
	rim.omni_range = 4
	vp.add_child(rim)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("f3dcd8")
	env.environment.ambient_light_energy = 0.55
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	vp.add_child(env)
	for ring in [[0.62, 0.03, "f1dcd7"], [0.5, 0.05, "f9ebe6"]]:
		var disk := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = ring[0]; cyl.bottom_radius = ring[0]; cyl.height = ring[1]
		disk.mesh = cyl
		disk.position.y = ring[1] / 2.0 - 0.03
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(ring[2])
		m.roughness = 0.9
		disk.material_override = m
		vp.add_child(disk)
	_appearance = PlaceholderAppearance.new()
	_appearance.rotation_degrees.y = -18
	vp.add_child(_appearance)
	_placeholder_note = UiTheme.tag(tr("ui.placeholder_model"), 13, UiTheme.TEXT_DIM)
	add_child(_placeholder_note)


func _build_challenge() -> void:
	_challenge_cloud = PanelContainer.new()
	_challenge_cloud.add_theme_stylebox_override("panel", UiTheme.cloud())
	add_child(_challenge_cloud)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_challenge_cloud.add_child(v)
	_challenge_scroll = ScrollContainer.new()
	_challenge_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_challenge_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_challenge_scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_right", 10)
	_challenge_scroll.add_child(pad)
	_challenge = ChallengePanel.new()
	_challenge.screen = self
	_challenge.show_submit = false
	pad.add_child(_challenge)
	# Кнопка всегда видна внизу панели, не уезжает при прокрутке условий.
	var submit := UiTheme.secondary(UiTheme.button(tr("ui.submit"), submit_challenge))
	submit.custom_minimum_size.y = 56
	v.add_child(submit)


func _build_grid() -> void:
	_grid_cloud = PanelContainer.new()
	_grid_cloud.add_theme_stylebox_override("panel", UiTheme.cloud())
	add_child(_grid_cloud)
	_grid_box = BoxContainer.new()
	_grid_box.add_theme_constant_override("separation", 12)
	_grid_cloud.add_child(_grid_box)

	_strip_scroll = ScrollContainer.new()
	_grid_box.add_child(_strip_scroll)
	_strip = BoxContainer.new()
	_strip.vertical = true
	_strip.add_theme_constant_override("separation", 8)
	_strip_scroll.add_child(_strip)
	for g in CATEGORY_GROUPS:
		var b := UiTheme.icon_button(g.icon, _set_category.bind(g.id), 50)
		b.tooltip_text = tr("ui.all_slots") if g.id == "all" else (tr("slot." + g.slot) if g.has("slot") else tr("ui.jewelry"))
		_strip_buttons[g.id] = b
		_strip.add_child(b)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid_box.add_child(right)
	_grid_scroll = ScrollContainer.new()
	_grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(_grid_scroll)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	_grid_scroll.add_child(_grid)

	var bottom := HBoxContainer.new()
	_search = LineEdit.new()
	_search.placeholder_text = tr("ui.search")
	_search.custom_minimum_size.y = UiTheme.TOUCH_MIN
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.visible = false
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(t): query.text = t; _refresh_grid())
	bottom.add_child(UiTheme.icon_button("search", _toggle_search, 44))
	bottom.add_child(_search)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer)
	_sort = OptionButton.new()
	_sort.custom_minimum_size.y = UiTheme.TOUCH_MIN
	for pair in [["sort.catalog", WardrobeQuery.Sort.CATALOG], ["sort.newest", WardrobeQuery.Sort.NEWEST],
			["sort.rarity", WardrobeQuery.Sort.RARITY], ["sort.name", WardrobeQuery.Sort.NAME]]:
		_sort.add_item(tr(pair[0]))
		_sort.set_item_metadata(_sort.item_count - 1, pair[1])
	_sort.item_selected.connect(func(i): query.sort = _sort.get_item_metadata(i); _refresh_grid())
	bottom.add_child(_sort)
	right.add_child(bottom)


func _toggle_search() -> void:
	_search.visible = not _search.visible
	if _search.visible:
		_search.grab_focus()
	elif _search.text != "":
		_search.text = ""
		query.text = ""
		_refresh_grid()


func _build_actions() -> void:
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 12)
	add_child(_actions)
	_save_btn = UiTheme.primary(UiTheme.button(tr("ui.save"), commit_draft))
	_save_btn.custom_minimum_size = Vector2(180, 56)
	_actions.add_child(_save_btn)
	_undo_btn = UiTheme.icon_button("undo", revert_draft, 52)
	_undo_btn.tooltip_text = tr("ui.revert")
	_actions.add_child(_undo_btn)
	var hanger := UiTheme.icon_button("hanger", func(): PresetsPanel.fill(_sheet, self), 52)
	hanger.tooltip_text = tr("ui.presets")
	_actions.add_child(hanger)
	_trophy_btn = UiTheme.icon_button("trophy", open_challenge_sheet, 52, Color.WHITE, UiTheme.GOLD)
	_trophy_btn.tooltip_text = tr("ui.challenge")
	# Бейдж текущего ранга на кубке: на телефоне видно оценку без открытия окна.
	_trophy_rank = RankBadge.make("D", 24)
	_trophy_rank.position = Vector2(34, -6)
	_trophy_rank.size = Vector2(24, 24)
	_trophy_btn.add_child(_trophy_rank)
	_actions.add_child(_trophy_btn)


# ---------- раскладка ----------

func _layout() -> void:
	var w := size.x
	var h := size.y
	_narrow = w < NARROW_WIDTH
	_top.position = Vector2(MARGIN, 10)
	_top.size = Vector2(w - MARGIN * 2, TOP_BAR - 10)
	var body_top := TOP_BAR + 8
	if not _narrow:
		var left_w := clampf(w * 0.24, 320, 400)
		var grid_w := clampf(w * 0.32, 440, 560)
		_challenge_cloud.visible = true
		_trophy_btn.visible = false
		_challenge_cloud.position = Vector2(MARGIN, body_top)
		_challenge_cloud.size = Vector2(left_w, h - body_top - MARGIN)
		_grid_cloud.position = Vector2(w - MARGIN - grid_w, body_top)
		_grid_cloud.size = Vector2(grid_w, h - body_top - MARGIN)
		var stage_x := MARGIN + left_w
		var stage_w := w - grid_w - MARGIN * 2 - left_w
		_stage.position = Vector2(stage_x, body_top)
		_stage.size = Vector2(stage_w, h - body_top - 96)
		_actions.position = Vector2(stage_x + 24, h - 84)
		_grid_box.vertical = false
		_strip.vertical = true
		_strip_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_strip_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		_strip_scroll.custom_minimum_size = Vector2(54, 0)
		_grid.columns = 3
		_placeholder_note.position = Vector2(stage_x + 24, body_top + 4)
	else:
		_challenge_cloud.visible = false
		_trophy_btn.visible = true
		var stage_h := (h - body_top) * 0.40
		_stage.position = Vector2(0, body_top)
		_stage.size = Vector2(w, stage_h)
		var grid_top := body_top + stage_h
		_grid_cloud.position = Vector2(MARGIN * 0.5, grid_top)
		_grid_cloud.size = Vector2(w - MARGIN, h - grid_top - 92)
		_actions.position = Vector2(MARGIN, h - 80)
		_grid_box.vertical = true
		_strip.vertical = false
		_strip_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		_strip_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_strip_scroll.custom_minimum_size = Vector2(0, 54)
		_grid.columns = maxi(3, int((w - MARGIN * 2) / 130.0))
		_placeholder_note.position = Vector2(MARGIN, body_top + 4)
	_actions.size = _actions.get_combined_minimum_size()
	_place_toast()
	_challenge.refresh()
	_refresh_grid.call_deferred()


func _place_toast() -> void:
	_toast.size = _toast.get_combined_minimum_size()
	_toast.position = Vector2(_stage.position.x + (_stage.size.x - _toast.size.x) / 2.0, _stage.position.y + _stage.size.y - _toast.size.y - 8)


# ---------- состояние ----------

func is_dirty() -> bool:
	return not draft.is_equal(session.equipment.get_outfit(character_id))


func _request_character(c: String) -> void:
	if c == character_id:
		return
	if is_dirty():
		_pending_character = c
		_ask_unsaved()
		return
	_set_character(c)


func _ask_unsaved() -> void:
	_sheet.clear()
	_sheet.content.add_child(UiTheme.label(tr("ui.unsaved_switch"), UiTheme.FONT_SIZE))
	var save := UiTheme.primary(UiTheme.button(tr("ui.save"), func():
		_sheet.close()
		commit_draft()
		_after_unsaved()))
	save.custom_minimum_size = Vector2(180, 52)
	_sheet.add_footer(save)
	_sheet.add_footer(UiTheme.button(tr("ui.revert"), func():
		_sheet.close()
		revert_draft()
		_after_unsaved()))
	_sheet.max_size = Vector2(560, 320)
	_sheet.open(tr("ui.wardrobe"), "hanger")


func _after_unsaved() -> void:
	_sheet.max_size = Vector2(720, 820)
	if _pending_character == "__close__":
		closed.emit()
	elif _pending_character != "":
		_set_character(_pending_character)
	_pending_character = ""


func _set_character(c: String) -> void:
	character_id = c
	for id in _avatars:
		_avatars[id].active = id == c
		_avatars[id].queue_redraw()
	draft = session.equipment.get_outfit(c)
	_appearance.setup(c, session.characters)
	_frame_camera()
	_refresh_all()


## Кадрирование под рост персонажа, чтобы фигура одинаково заполняла сцену.
func _frame_camera() -> void:
	var hgt := 1.6 * _appearance.scale.y
	_preview_cam.position = Vector3(0, hgt * 0.62, hgt * 3.1)
	_preview_cam.rotation_degrees = Vector3(-5, 0, 0)


func _set_category(id: String) -> void:
	category = id
	query.slot = ""
	query.category = ""
	for g in CATEGORY_GROUPS:
		if g.id == id:
			query.slot = g.get("slot", "")
			query.category = g.get("category", "")
	_refresh_strip()
	_refresh_grid()


func commit_draft() -> void:
	session.equipment.set_outfit(character_id, draft)
	Game.save_game()
	show_toast(tr("ui.saved"), "check")
	_refresh_all()


func revert_draft() -> void:
	draft = session.equipment.get_outfit(character_id)
	_refresh_all()


func set_draft(o: Outfit) -> void:
	draft = o
	_refresh_all()


func toggle_item(item_id: String) -> void:
	if draft.has_item(item_id):
		try_unequip(item_id)
	else:
		try_equip(item_id)


func try_equip(item_id: String) -> void:
	var res := session.equipment.equip_into(draft, character_id, item_id)
	if not res.ok:
		var key: String = res.get("reason_key", "")
		show_toast(tr(key if key != "" else res.error_key), "lock")
	elif not res.removed.is_empty():
		show_toast(Localization.text("ui.removed", {"items": ", ".join(res.removed.map(func(id): return item_name(id)))}), "undo")
	_refresh_all()


func try_unequip(item_id: String) -> void:
	draft.remove_item(item_id)
	_refresh_all()


func show_long_press(item_id: String) -> void:
	session.inventory.mark_seen(item_id)
	ItemDetails.fill(_sheet, self, item_id)
	_refresh_grid()


func open_challenge_sheet() -> void:
	_sheet.clear()
	var panel := ChallengePanel.new()
	panel.screen = self
	panel.show_header = false
	panel.challenge_id = _challenge.challenge_id
	panel.submitted.connect(func():
		_sheet.close()
		submit_challenge())
	_sheet.content.add_child(panel)
	panel.refresh()
	_sheet.open(tr(panel.challenge().get("title_key", "ui.challenge")), "trophy")


func submit_challenge() -> void:
	var ch := _challenge.challenge()
	if ch.is_empty():
		return
	if is_dirty():
		commit_draft()
	var report := session.scoring.score(ch, session.outfit_items(character_id))
	var outcome := session.rewards.submit(ch, report)
	var advice := FashionAdvisor.suggest(session, ch, character_id, session.equipment.get_outfit(character_id))
	Game.save_game()
	_refresh_all()
	ResultPopup.fill(_sheet, self, ch, report, outcome, advice)


func show_toast(text: String, icon := "sparkle") -> void:
	for c in _toast.get_children():
		_toast.remove_child(c)
		c.queue_free()
	var row := HBoxContainer.new()
	row.add_child(UiTheme.icon(icon, 20, UiTheme.GOLD))
	row.add_child(UiTheme.tag(text, UiTheme.FONT_SIZE_SMALL))
	_toast.add_child(row)
	_toast.visible = text != ""
	_place_toast.call_deferred()


func _on_close() -> void:
	if is_dirty():
		_pending_character = "__close__"
		_ask_unsaved()
		return
	closed.emit()


# ---------- обновление ----------

func _refresh_all() -> void:
	_appearance.apply_items(session.items_for_outfit(draft))
	_coins_label.text = str(session.resources.amount("coins"))
	var dirty := is_dirty()
	_save_btn.disabled = not dirty
	_undo_btn.disabled = not dirty
	_refresh_strip()
	_refresh_grid()
	_challenge.refresh()
	var ch := _challenge.challenge()
	if not ch.is_empty():
		_trophy_rank.rank = session.scoring.score(ch, session.items_for_outfit(draft)).rank
		_trophy_rank.queue_redraw()


func _refresh_strip() -> void:
	var present := {}
	for it in session.catalog.all_items():
		if session.inventory.owns(it.id):
			for g in CATEGORY_GROUPS:
				if (g.has("slot") and it.all_slots().has(g.slot)) or (g.has("category") and it.category == g.category):
					present[g.id] = true
	for g in CATEGORY_GROUPS:
		var b: Button = _strip_buttons[g.id]
		b.visible = g.id == "all" or present.has(g.id)
		var active: bool = g.id == category
		var st := UiTheme.pill(UiTheme.GOLD_LIGHT if active else UiTheme.PANEL_SOLID, 0)
		st.shadow_color = UiTheme.SHADOW
		st.shadow_size = 6
		b.add_theme_stylebox_override("normal", st)
		(b.get_child(0) as IconView).color = UiTheme.GOLD.darkened(0.25) if active else UiTheme.TEXT_DIM


func _refresh_grid() -> void:
	if _grid == null or draft == null:
		return
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	var items := query.run(session, func(it: ClothingItem): return tr(it.name_key))
	if items.is_empty():
		var l := UiTheme.label(tr("ui.empty_list"), UiTheme.FONT_SIZE_SMALL, UiTheme.TEXT_DIM)
		l.custom_minimum_size.x = 200
		_grid.add_child(l)
		return
	var cols := _grid.columns
	var avail := _grid_scroll.size.x - 8.0 * (cols - 1) - 12.0
	var cw := clampf(avail / cols, 96, 150) if avail > 0 else 120.0
	for it in items:
		var card := ItemCard.new()
		card.item = it
		card.stars = UiTheme.stars_for(it.rarity, session.config.rarities)
		card.worn = draft.has_item(it.id)
		card.is_new = session.inventory.is_new(it.id)
		card.locked = not Compatibility.can_wear(it, character_id, session.characters)
		card.custom_minimum_size = Vector2(cw, cw * 1.12)
		card.tapped.connect(toggle_item)
		card.long_pressed.connect(show_long_press)
		_grid.add_child(card)


# ---------- вспомогательное ----------

func item_name(id: String) -> String:
	var it := session.catalog.get_item(id)
	return tr(it.name_key) if it else id


# ---------- сценарии для скриншотов ----------

func debug_select_first_item() -> void:
	_refresh_grid()


func debug_long_press() -> void:
	var items := query.run(session)
	if not items.is_empty():
		show_long_press(items[0].id)


func debug_try_on() -> void:
	try_equip("clothing_plain_shirt_001")
	try_equip("clothing_sport_sneakers_001")


func debug_challenge_tab() -> void:
	if _narrow:
		open_challenge_sheet()


func debug_result() -> void:
	submit_challenge()


func debug_presets() -> void:
	PresetsPanel.fill(_sheet, self)
