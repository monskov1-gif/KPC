class_name WardrobeScreen
extends Control
## Экран примерки. Изменения собираются в черновике (draft) и применяются только по кнопке «Подтвердить».
## Вся логика (совместимость, слоты, очки) — в доменных сервисах; экран только вызывает их и показывает результат.

signal closed

const NARROW_WIDTH := 1100.0

var session: GameSession
var character_id := ""
var draft: Outfit
var query := WardrobeQuery.new()
var selected_item_id := ""

var _narrow := false
var _char_buttons := {}
var _coins_label: Label
var _body_wide: HBoxContainer
var _body_narrow: TabContainer
var _left: PanelContainer
var _middle: PanelContainer
var _right: TabContainer
var _appearance: PlaceholderAppearance
var _equipped_list: VBoxContainer
var _search: LineEdit
var _slot_filter: OptionButton
var _tag_filter: OptionButton
var _compat_toggle: CheckBox
var _unequipped_toggle: CheckBox
var _count_label: Label
var _item_list: VBoxContainer
var _card: VBoxContainer
var _status_label: Label
var _confirm_btn: Button
var _revert_btn: Button
var _challenge_panel: ChallengePanel
var _presets_panel: PresetsPanel
var _dialog: ConfirmationDialog
var _pending_character := ""


func _ready() -> void:
	session = Game.session
	theme = UiTheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	query.compatible_with = ""
	var first: String = session.unlocked_characters[0] if not session.unlocked_characters.is_empty() else session.characters.ids()[0]
	_set_character(first)
	resized.connect(_update_layout)
	_update_layout()


# ---------- построение интерфейса ----------

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	root.add_child(_build_top_bar())
	_body_wide = HBoxContainer.new()
	_body_wide.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_wide.add_theme_constant_override("separation", 12)
	root.add_child(_body_wide)
	_body_narrow = TabContainer.new()
	_body_narrow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_narrow.visible = false
	root.add_child(_body_narrow)

	_left = _build_left()
	_middle = _build_middle()
	_right = _build_right()
	root.add_child(_build_bottom_bar())

	_dialog = ConfirmationDialog.new()
	_dialog.title = tr("ui.wardrobe")
	_dialog.dialog_text = tr("ui.unsaved_switch")
	_dialog.ok_button_text = tr("ui.confirm")
	_dialog.cancel_button_text = tr("ui.close")
	_dialog.add_button(tr("ui.revert"), true, "revert")
	_dialog.confirmed.connect(func(): commit_draft(); _set_character(_pending_character))
	_dialog.custom_action.connect(func(_a): _dialog.hide(); _set_character(_pending_character))
	add_child(_dialog)


func _build_top_bar() -> Control:
	var bar := HBoxContainer.new()
	var title := UiTheme.label(tr("ui.wardrobe"), UiTheme.FONT_SIZE_TITLE)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.size_flags_horizontal = Control.SIZE_FILL
	title.custom_minimum_size.x = 160
	bar.add_child(title)
	var group := ButtonGroup.new()
	for c in session.characters.ids():
		var b := Button.new()
		b.text = tr(session.characters.get_data(c).name_key)
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(110, UiTheme.TOUCH_MIN)
		b.disabled = not session.unlocked_characters.has(c)
		b.pressed.connect(_request_character.bind(c))
		_char_buttons[c] = b
		bar.add_child(b)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	_coins_label = UiTheme.label("", UiTheme.FONT_SIZE, UiTheme.ACCENT)
	_coins_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_coins_label.size_flags_horizontal = Control.SIZE_FILL
	bar.add_child(_coins_label)
	bar.add_child(UiTheme.button(tr("ui.close"), _on_close))
	return bar


func _build_left() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 0.85
	panel.name = tr("character.kot.name")
	var v := VBoxContainer.new()
	panel.add_child(v)

	var vpc := SubViewportContainer.new()
	vpc.stretch = true
	vpc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vpc.custom_minimum_size = Vector2(260, 300)
	v.add_child(vpc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vpc.add_child(vp)
	var cam := Camera3D.new()
	# Кадр рассчитан на самого высокого персонажа (Сора, 206 см).
	cam.position = Vector3(0, 1.15, 3.0)
	cam.rotation_degrees = Vector3(-4, 0, 0)
	cam.fov = 45
	vp.add_child(cam)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 30, 0)
	key.light_energy = 1.2
	key.light_color = Color("ffe8d2")
	vp.add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-1.5, 1.6, 1.5)
	fill.light_color = Color("9fd8ff")
	fill.light_energy = 0.6
	fill.omni_range = 6
	vp.add_child(fill)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("6b5a66")
	env.environment.ambient_light_energy = 0.8
	vp.add_child(env)
	var floor_disk := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.6; cyl.bottom_radius = 0.6; cyl.height = 0.04
	floor_disk.mesh = cyl
	floor_disk.position.y = -0.02
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("3a3238")
	floor_disk.material_override = fm
	vp.add_child(floor_disk)
	_appearance = PlaceholderAppearance.new()
	_appearance.rotation_degrees.y = -20
	vp.add_child(_appearance)

	v.add_child(UiTheme.label(tr("ui.placeholder_model"), UiTheme.FONT_SIZE_SMALL, UiTheme.WARN))
	_equipped_list = VBoxContainer.new()
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 180
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(_equipped_list)
	_equipped_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	return panel


func _build_middle() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.name = tr("ui.wardrobe")
	var v := VBoxContainer.new()
	panel.add_child(v)
	_search = LineEdit.new()
	_search.placeholder_text = tr("ui.search")
	_search.custom_minimum_size.y = UiTheme.TOUCH_MIN
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(t): query.text = t; _refresh_list())
	v.add_child(_search)

	var row := HBoxContainer.new()
	_slot_filter = OptionButton.new()
	_slot_filter.custom_minimum_size.y = UiTheme.TOUCH_MIN
	_slot_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slot_filter.add_item(tr("ui.all_slots"))
	_slot_filter.set_item_metadata(0, "")
	for s in session.config.slots:
		_slot_filter.add_item(tr("slot." + s))
		_slot_filter.set_item_metadata(_slot_filter.item_count - 1, s)
	_slot_filter.item_selected.connect(func(i): query.slot = _slot_filter.get_item_metadata(i); _refresh_list())
	row.add_child(_slot_filter)
	_tag_filter = OptionButton.new()
	_tag_filter.custom_minimum_size.y = UiTheme.TOUCH_MIN
	_tag_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tag_filter.add_item(tr("ui.all_tags"))
	_tag_filter.set_item_metadata(0, "")
	for t in session.config.style_tags:
		_tag_filter.add_item(tr("tag." + t))
		_tag_filter.set_item_metadata(_tag_filter.item_count - 1, t)
	_tag_filter.item_selected.connect(func(i): query.tag = _tag_filter.get_item_metadata(i); _refresh_list())
	row.add_child(_tag_filter)
	v.add_child(row)

	var toggles := HBoxContainer.new()
	_compat_toggle = CheckBox.new()
	_compat_toggle.text = tr("ui.only_compatible")
	_compat_toggle.custom_minimum_size.y = UiTheme.TOUCH_MIN
	_compat_toggle.toggled.connect(func(_on): _refresh_list())
	toggles.add_child(_compat_toggle)
	_unequipped_toggle = CheckBox.new()
	_unequipped_toggle.text = tr("ui.only_unequipped")
	_unequipped_toggle.custom_minimum_size.y = UiTheme.TOUCH_MIN
	_unequipped_toggle.toggled.connect(func(_on): _refresh_list())
	toggles.add_child(_unequipped_toggle)
	v.add_child(toggles)
	_count_label = UiTheme.label("", UiTheme.FONT_SIZE_SMALL, UiTheme.TEXT_DIM)
	v.add_child(_count_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_item_list = VBoxContainer.new()
	_item_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_item_list)
	v.add_child(scroll)
	return panel


func _build_right() -> TabContainer:
	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.name = tr("ui.challenge")
	var card_scroll := ScrollContainer.new()
	card_scroll.name = tr("ui.attr")
	card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_card = VBoxContainer.new()
	_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_scroll.add_child(_card)
	tabs.add_child(card_scroll)
	tabs.set_tab_title(0, "Вещь")
	_challenge_panel = ChallengePanel.new()
	_challenge_panel.screen = self
	tabs.add_child(_challenge_panel)
	tabs.set_tab_title(1, tr("ui.challenge"))
	_presets_panel = PresetsPanel.new()
	_presets_panel.screen = self
	tabs.add_child(_presets_panel)
	tabs.set_tab_title(2, tr("ui.presets"))
	return tabs


func _build_bottom_bar() -> Control:
	var bar := HBoxContainer.new()
	_status_label = UiTheme.label("", UiTheme.FONT_SIZE_SMALL, UiTheme.TEXT_DIM)
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_status_label)
	_revert_btn = UiTheme.button(tr("ui.revert"), revert_draft)
	bar.add_child(_revert_btn)
	_confirm_btn = UiTheme.button(tr("ui.confirm"), commit_draft)
	_confirm_btn.custom_minimum_size.x = 220
	bar.add_child(_confirm_btn)
	return bar


func _update_layout() -> void:
	var narrow := size.x < NARROW_WIDTH
	if narrow == _narrow and _left.get_parent() != null:
		return
	_narrow = narrow
	for p in [_left, _middle, _right]:
		if p.get_parent():
			p.get_parent().remove_child(p)
	var target: Container = _body_narrow if narrow else _body_wide
	target.add_child(_left)
	target.add_child(_middle)
	target.add_child(_right)
	if narrow:
		_body_narrow.set_tab_title(0, tr(session.characters.get_data(character_id).get("name_key", "")))
		_body_narrow.set_tab_title(1, tr("ui.wardrobe"))
		_body_narrow.set_tab_title(2, "Детали")
	_body_wide.visible = not narrow
	_body_narrow.visible = narrow


# ---------- состояние ----------

func is_dirty() -> bool:
	return not draft.is_equal(session.equipment.get_outfit(character_id))


func _request_character(c: String) -> void:
	if c == character_id:
		return
	if is_dirty():
		_pending_character = c
		_char_buttons[character_id].button_pressed = true
		_dialog.popup_centered()
		return
	_set_character(c)


func _set_character(c: String) -> void:
	character_id = c
	_char_buttons[c].button_pressed = true
	draft = session.equipment.get_outfit(c)
	_appearance.setup(c, session.characters)
	if _narrow:
		_body_narrow.set_tab_title(0, tr(session.characters.get_data(c).name_key))
	_presets_panel.refresh()
	_refresh_all()


func commit_draft() -> void:
	session.equipment.set_outfit(character_id, draft)
	Game.save_game()
	_set_status(tr("ui.saved"), UiTheme.OK)
	_refresh_all()


func revert_draft() -> void:
	draft = session.equipment.get_outfit(character_id)
	_refresh_all()


func set_draft(o: Outfit) -> void:
	draft = o
	_refresh_all()


func try_equip(item_id: String) -> void:
	var res := session.equipment.equip_into(draft, character_id, item_id)
	if not res.ok:
		var reason: String = res.get("reason_key", res.error_key)
		_set_status(tr(reason), UiTheme.BAD)
	else:
		var removed: Array = res.removed
		if not removed.is_empty():
			var names := removed.map(func(id): return _item_name(id))
			_set_status("Снято: " + ", ".join(names), UiTheme.WARN)
		else:
			_set_status("", UiTheme.TEXT_DIM)
	_refresh_all()


func try_unequip(item_id: String) -> void:
	draft.remove_item(item_id)
	_refresh_all()


func select_item(item_id: String) -> void:
	selected_item_id = item_id
	session.inventory.mark_seen(item_id)
	_right.current_tab = 0
	if _narrow:
		_body_narrow.current_tab = 2
	_refresh_card()


func _set_status(text: String, color: Color) -> void:
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", color)


func _on_close() -> void:
	if is_dirty():
		_pending_character = character_id
		_dialog.popup_centered()
		return
	closed.emit()


# ---------- обновление ----------

func _refresh_all() -> void:
	_appearance.apply_items(session.items_for_outfit(draft))
	_coins_label.text = Localization.text("ui.coins", {"n": session.resources.amount("coins")})
	_refresh_equipped()
	_refresh_list()
	_refresh_card()
	_challenge_panel.refresh()
	var dirty := is_dirty()
	_confirm_btn.disabled = not dirty
	_revert_btn.disabled = not dirty
	if dirty and _status_label.text == "":
		_set_status("● Есть неподтверждённые изменения", UiTheme.WARN)


func _refresh_equipped() -> void:
	_clear(_equipped_list)
	var items := session.items_for_outfit(draft)
	if items.is_empty():
		_equipped_list.add_child(UiTheme.label("—", UiTheme.FONT_SIZE_SMALL, UiTheme.TEXT_DIM))
	for it in items:
		var row := HBoxContainer.new()
		var slot_l := UiTheme.label(tr("slot." + it.slot), UiTheme.FONT_SIZE_SMALL, UiTheme.TEXT_DIM)
		slot_l.custom_minimum_size.x = 110
		slot_l.autowrap_mode = TextServer.AUTOWRAP_OFF
		slot_l.size_flags_horizontal = Control.SIZE_FILL
		row.add_child(slot_l)
		var name_b := Button.new()
		name_b.text = _item_name(it.id)
		name_b.flat = true
		name_b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_b.clip_text = true
		name_b.custom_minimum_size.y = UiTheme.TOUCH_MIN
		name_b.pressed.connect(select_item.bind(it.id))
		row.add_child(name_b)
		var x := UiTheme.button("✕", try_unequip.bind(it.id))
		x.tooltip_text = tr("ui.unequip")
		x.custom_minimum_size.x = UiTheme.TOUCH_MIN
		row.add_child(x)
		_equipped_list.add_child(row)


func _refresh_list() -> void:
	if _item_list == null:
		return
	query.compatible_with = character_id if _compat_toggle.button_pressed else ""
	query.only_unequipped_for = ""
	var items := query.run(session, func(it: ClothingItem): return tr(it.name_key))
	if _unequipped_toggle.button_pressed:
		items = items.filter(func(it): return not draft.has_item(it.id))
	_clear(_item_list)
	_count_label.text = "Вещей: %d из %d" % [items.size(), session.inventory.count()]
	if items.is_empty():
		_item_list.add_child(UiTheme.label(tr("ui.empty_list"), UiTheme.FONT_SIZE, UiTheme.TEXT_DIM))
		return
	for it in items:
		_item_list.add_child(_item_row(it))


func _item_row(it: ClothingItem) -> Control:
	var b := Button.new()
	b.custom_minimum_size.y = 68
	b.toggle_mode = true
	b.button_pressed = it.id == selected_item_id
	b.pressed.connect(select_item.bind(it.id))
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 10; h.offset_right = -10
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var sw := ColorRect.new()
	sw.color = it.placeholder_color
	sw.custom_minimum_size = Vector2(40, 40)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(sw)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var title := UiTheme.label(_item_name(it.id))
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(title)
	var compat := Compatibility.check(it, character_id, session.characters)
	var sub := UiTheme.label("%s · %s · %s" % [tr("rarity." + it.rarity), tr("slot." + it.slot), _compat_text(compat)],
		UiTheme.FONT_SIZE_SMALL, _compat_color(compat))
	sub.autowrap_mode = TextServer.AUTOWRAP_OFF
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sub)
	if draft.has_item(it.id):
		h.add_child(_badge("надето", UiTheme.ACCENT_2))
	elif session.inventory.is_new(it.id):
		h.add_child(_badge(tr("ui.new"), UiTheme.ACCENT))
	return b


func _refresh_card() -> void:
	_clear(_card)
	var it := session.catalog.get_item(selected_item_id)
	if it == null:
		_card.add_child(UiTheme.label("Выберите вещь в списке.", UiTheme.FONT_SIZE, UiTheme.TEXT_DIM))
		return
	_card.add_child(UiTheme.label(_item_name(it.id), 22))
	_card.add_child(UiTheme.label("%s · %s" % [tr("rarity." + it.rarity), tr("slot." + it.slot)],
		UiTheme.FONT_SIZE_SMALL, UiTheme.RARITY.get(it.rarity, UiTheme.TEXT)))
	_card.add_child(UiTheme.label(tr(it.description_key), UiTheme.FONT_SIZE_SMALL, UiTheme.TEXT_DIM))
	var compat := Compatibility.check(it, character_id, session.characters)
	var compat_l := UiTheme.label(_compat_text(compat), UiTheme.FONT_SIZE, _compat_color(compat))
	_card.add_child(compat_l)
	if compat.reason_key != "":
		_card.add_child(UiTheme.label(tr(compat.reason_key), UiTheme.FONT_SIZE_SMALL, UiTheme.TEXT_DIM))
	if draft.has_item(it.id):
		_card.add_child(UiTheme.button(tr("ui.unequip"), try_unequip.bind(it.id)))
	else:
		var eb := UiTheme.button(tr("ui.equip"), try_equip.bind(it.id))
		eb.disabled = compat.status == Compatibility.Status.INCOMPATIBLE
		_card.add_child(eb)
		var conflicts := draft.conflicts_with(it, session.catalog)
		if not conflicts.is_empty() and not eb.disabled:
			_card.add_child(UiTheme.label("Заменит: " + ", ".join(conflicts.map(func(id): return _item_name(id))),
				UiTheme.FONT_SIZE_SMALL, UiTheme.WARN))
	_card.add_child(UiTheme.label(tr("ui.attr"), UiTheme.FONT_SIZE, UiTheme.ACCENT))
	var attrs := it.attributes.keys()
	attrs.sort_custom(func(a, b): return it.attr(a) > it.attr(b))
	for a in attrs:
		_card.add_child(_attr_bar(tr("attr." + a), it.attr(a)))
	if not it.style_tags.is_empty():
		_card.add_child(UiTheme.label(tr("ui.tags"), UiTheme.FONT_SIZE, UiTheme.ACCENT))
		_card.add_child(UiTheme.label(", ".join(it.style_tags.map(func(t): return tr("tag." + t))), UiTheme.FONT_SIZE_SMALL))


func _attr_bar(title: String, value: float) -> Control:
	var row := HBoxContainer.new()
	var l := UiTheme.label(title, UiTheme.FONT_SIZE_SMALL)
	l.custom_minimum_size.x = 150
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.size_flags_horizontal = Control.SIZE_FILL
	row.add_child(l)
	var bar := ProgressBar.new()
	bar.max_value = session.config.attribute_max
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(120, 12)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override("background", UiTheme.box(UiTheme.BG, 6, 0))
	bar.add_theme_stylebox_override("fill", UiTheme.box(UiTheme.ACCENT, 6, 0))
	row.add_child(bar)
	var n := UiTheme.label(str(int(value)), UiTheme.FONT_SIZE_SMALL, UiTheme.TEXT_DIM)
	n.custom_minimum_size.x = 36
	n.size_flags_horizontal = Control.SIZE_FILL
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(n)
	return row


func _badge(text: String, color: Color) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.box(color.darkened(0.55), 8, 6))
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UiTheme.label(text, UiTheme.FONT_SIZE_SMALL, color)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.size_flags_horizontal = Control.SIZE_FILL
	p.add_child(l)
	return p


# ---------- вспомогательное ----------

func _item_name(id: String) -> String:
	var it := session.catalog.get_item(id)
	return tr(it.name_key) if it else id


func item_name(id: String) -> String:
	return _item_name(id)


func _compat_text(compat: Dictionary) -> String:
	match compat.status:
		Compatibility.Status.COMPATIBLE: return "✓ " + tr("compat.compatible")
		Compatibility.Status.ADAPTED: return "≈ " + tr("compat.adapted")
	return "✕ " + tr("compat.incompatible")


func _compat_color(compat: Dictionary) -> Color:
	match compat.status:
		Compatibility.Status.COMPATIBLE: return UiTheme.OK
		Compatibility.Status.ADAPTED: return UiTheme.WARN
	return UiTheme.BAD


static func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


# ---------- сценарии для скриншотов ----------

func debug_select_first_item() -> void:
	var items := query.run(session)
	if not items.is_empty():
		select_item(items[0].id)


func debug_challenge_tab() -> void:
	debug_select_first_item()
	_right.current_tab = 1


func debug_result() -> void:
	_right.current_tab = 1
	_challenge_panel.submit()
