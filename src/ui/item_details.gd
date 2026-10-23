class_name ItemDetails
extends RefCounted
## Содержимое окна характеристик вещи (открывается долгим нажатием на карточку).


static func fill(sheet: Sheet, screen: WardrobeScreen, item_id: String) -> void:
	var s := screen.session
	var it := s.catalog.get_item(item_id)
	if it == null:
		return
	sheet.clear()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	var thumb := PanelContainer.new()
	thumb.add_theme_stylebox_override("panel", UiTheme.cloud(UiTheme.CARD, 20, 10))
	thumb.custom_minimum_size = Vector2(120, 120)
	thumb.size_flags_horizontal = Control.SIZE_FILL
	var iv := UiTheme.icon(it.slot, 96, it.placeholder_color)
	iv.outline = it.placeholder_color.darkened(0.35).lerp(UiTheme.TEXT_DIM, 0.3)
	thumb.add_child(iv)
	head.add_child(thumb)
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stars := HBoxContainer.new()
	stars.add_theme_constant_override("separation", 2)
	var n := UiTheme.stars_for(it.rarity, s.config.rarities)
	for i in 5:
		stars.add_child(UiTheme.icon("star" if i < n else "star_empty", 20, UiTheme.STAR if i < n else UiTheme.CARD_EDGE))
	hv.add_child(stars)
	var slot_row := HBoxContainer.new()
	slot_row.add_child(UiTheme.icon(it.slot, 22, UiTheme.TEXT_DIM))
	slot_row.add_child(UiTheme.tag(Localization.t("slot." + it.slot), UiTheme.FONT_SIZE_SMALL, UiTheme.TEXT_DIM))
	hv.add_child(slot_row)
	hv.add_child(UiTheme.label(Localization.t(it.description_key), UiTheme.FONT_SIZE_SMALL, UiTheme.TEXT_DIM))
	var compat := Compatibility.check(it, screen.character_id, s.characters)
	var crow := HBoxContainer.new()
	var ok: bool = compat.status != Compatibility.Status.INCOMPATIBLE
	crow.add_child(UiTheme.icon("check" if ok else "lock", 20, UiTheme.OK if compat.status == Compatibility.Status.COMPATIBLE
		else (UiTheme.WARN if ok else UiTheme.BAD)))
	var ctext := Localization.text("ui.compatible_for", {"name": Localization.t(s.characters.get_data(screen.character_id).name_key)}) \
		if compat.status == Compatibility.Status.COMPATIBLE else \
		(Localization.t("compat.adapted") if ok else Localization.t(compat.reason_key))
	crow.add_child(UiTheme.label(ctext, UiTheme.FONT_SIZE_SMALL))
	hv.add_child(crow)
	head.add_child(hv)
	sheet.content.add_child(head)

	var attrs := it.attributes.keys().filter(func(a): return it.attr(a) > 0)
	attrs.sort_custom(func(a, b): return it.attr(a) > it.attr(b) if it.attr(a) != it.attr(b) else a < b)
	for a in attrs:
		sheet.content.add_child(attr_bar(Localization.t("attr." + a), it.attr(a), s.config.attribute_max))

	if not it.style_tags.is_empty():
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_theme_constant_override("v_separation", 6)
		for t in it.style_tags:
			flow.add_child(chip(Localization.t("tag." + t)))
		sheet.content.add_child(flow)

	var worn := screen.draft.has_item(it.id)
	var action := UiTheme.primary(UiTheme.button(Localization.t("ui.unequip") if worn else Localization.t("ui.equip"), func():
		if worn:
			screen.try_unequip(it.id)
		else:
			screen.try_equip(it.id)
		sheet.close()))
	action.custom_minimum_size = Vector2(240, 54)
	action.set_meta("silent", true)        # звучит «надеть»
	action.disabled = not worn and not ok
	sheet.add_footer(action)
	sheet.open(Localization.t(it.name_key), it.slot)


static func attr_bar(title: String, value: float, max_value: float) -> Control:
	var row := HBoxContainer.new()
	var l := UiTheme.tag(title, UiTheme.FONT_SIZE_SMALL)
	l.custom_minimum_size.x = 160
	row.add_child(l)
	var bar := ProgressBar.new()
	bar.max_value = max_value
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(100, 14)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override("background", UiTheme.pill(UiTheme.CARD, 0))
	bar.add_theme_stylebox_override("fill", UiTheme.pill(UiTheme.PINK, 0))
	row.add_child(bar)
	var n := UiTheme.tag(str(int(value)), UiTheme.FONT_SIZE_SMALL, UiTheme.TEXT_DIM)
	n.custom_minimum_size.x = 36
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(n)
	return row


static func chip(text: String, bg := UiTheme.CARD) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.pill(bg, 8))
	p.add_child(UiTheme.tag(text, UiTheme.FONT_SIZE_SMALL))
	return p
