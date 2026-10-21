class_name PresetsPanel
extends RefCounted
## Окно сохранённых комплектов текущего персонажа. Применение загружает совместимую часть в черновик примерки.


static func fill(sheet: Sheet, screen: WardrobeScreen, message := "") -> void:
	var s := screen.session
	sheet.clear()
	var row := HBoxContainer.new()
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = TranslationServer.translate("ui.preset_name")
	name_edit.custom_minimum_size.y = UiTheme.TOUCH_MIN
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_edit)
	row.add_child(UiTheme.icon_button("plus", func():
		var n := name_edit.text.strip_edges()
		if n == "":
			n = Localization.text("ui.preset_default", {"n": s.presets.presets_for(screen.character_id).size() + 1})
		s.presets.create_from_outfit(screen.character_id, n, screen.draft)
		Game.save_game()
		fill(sheet, screen), 48, Color.WHITE, UiTheme.GOLD))
	sheet.content.add_child(row)
	if message != "":
		sheet.content.add_child(UiTheme.label(message, UiTheme.FONT_SIZE_SMALL, UiTheme.WARN))
	var presets := s.presets.presets_for(screen.character_id)
	if presets.is_empty():
		sheet.content.add_child(UiTheme.label(TranslationServer.translate("ui.no_presets"), UiTheme.FONT_SIZE_SMALL, UiTheme.TEXT_DIM))
	for p in presets:
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UiTheme.cloud(UiTheme.CARD, 18, 10))
		var h := HBoxContainer.new()
		card.add_child(h)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(UiTheme.label(p.name, UiTheme.FONT_SIZE))
		var icons := HBoxContainer.new()
		icons.add_theme_constant_override("separation", 4)
		var slots: Dictionary = p.slots
		for slot in slots.keys():
			var it := s.catalog.get_item(slots[slot])
			if it:
				var ic := UiTheme.icon(it.slot, 24, it.placeholder_color)
				ic.outline = it.placeholder_color.darkened(0.35)
				icons.add_child(ic)
		v.add_child(icons)
		h.add_child(v)
		h.add_child(UiTheme.icon_button("check", func():
			var built := s.presets.build_outfit(p.id)
			screen.set_draft(built.outfit)
			var problems: Array = built.problems
			if problems.is_empty():
				sheet.close()
			else:
				fill(sheet, screen, Localization.text("ui.preset_not_applied", {"items": ", ".join(
					problems.map(func(pr): return screen.item_name(pr.item_id)))})), 48, Color.WHITE, UiTheme.MINT))
		h.add_child(UiTheme.icon_button("close", func():
			s.presets.delete(p.id)
			Game.save_game()
			fill(sheet, screen), 48))
		sheet.content.add_child(card)
	sheet.open(TranslationServer.translate("ui.presets"), "hanger")
