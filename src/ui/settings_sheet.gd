class_name SettingsSheet
extends RefCounted
## Содержимое окна настроек (в «облаке» Sheet): язык, звук, графика, управление, доступность.
## Всё применяется сразу и сохраняется (Settings, Audio). Открывается с титульного экрана (⋯) и из паузы.

const LANG_NAMES := {"ru": "Русский", "en": "English"}


static func open(sheet: Sheet, back := Callable()) -> void:
	sheet.clear()
	if back.is_valid():
		sheet.add_footer(UiTheme.secondary(UiTheme.button("Назад", back)))
	var c := sheet.content
	_section(c, "globe", "Язык")
	var langs: Array[String] = Settings.languages()
	var opts: Array = []
	for l in langs:
		opts.append([l, LANG_NAMES.get(l, l)])
	c.add_child(_choice(opts, Settings.get_value("language"), func(v): Settings.set_value("language", v)))
	if not langs.has("en"):
		c.add_child(UiTheme.label("English — скоро: перевод ещё не готов.", 15, UiTheme.TEXT_DIM))

	_section(c, "speaker", "Звук")
	for row in [["Master", "Общая", "speaker"], ["Music", "Музыка", "note"], ["Ambient", "Окружение", "wind"],
			["SFX", "Эффекты", "sparkle"], ["Voice", "Голоса", "voice"]]:
		var bus: String = row[0]
		var sl := UiTheme.slider(Audio.get_volume(bus), func(v: float): Audio.set_volume(bus, v, false))
		sl.drag_ended.connect(func(_changed: bool): Audio.save_settings())
		c.add_child(_row(row[2], row[1], sl))

	_section(c, "display", "Графика")
	c.add_child(_row("", "Качество", _choice([["low", "Низкое"], ["medium", "Среднее"], ["high", "Высокое"]],
		Settings.get_value("quality"), func(v): Settings.set_value("quality", v))))
	var rs := UiTheme.slider(inverse_lerp(0.5, 1.0, float(Settings.get_value("render_scale"))),
		func(v: float): Settings.set_value("render_scale", lerpf(0.5, 1.0, v), false))
	rs.drag_ended.connect(func(_changed: bool): Settings.save_settings())
	c.add_child(_row("", "Чёткость 3D", rs))
	c.add_child(_toggle("Тени", "shadows"))
	c.add_child(_toggle("Контуры персонажей", "outlines"))
	c.add_child(_toggle("Свечение (bloom)", "bloom"))
	c.add_child(_row("", "Кадров в секунду", _choice([[30, "30"], [60, "60"], [0, "Без предела"]],
		Settings.get_value("fps_limit"), func(v): Settings.set_value("fps_limit", v))))

	_section(c, "gamepad", "Управление")
	var cs := UiTheme.slider(inverse_lerp(0.3, 2.0, float(Settings.get_value("camera_sensitivity"))),
		func(v: float): Settings.set_value("camera_sensitivity", lerpf(0.3, 2.0, v), false))
	cs.drag_ended.connect(func(_changed: bool): Settings.save_settings())
	c.add_child(_row("rotate", "Чувствительность камеры", cs))
	c.add_child(_toggle("Инвертировать камеру по вертикали", "invert_y"))
	c.add_child(_toggle("Вибрация", "vibration"))

	_section(c, "person", "Удобство")
	c.add_child(_row("", "Размер интерфейса", _choice([[0.9, "Мельче"], [1.0, "Обычный"], [1.15, "Крупнее"], [1.3, "Крупный"]],
		Settings.get_value("ui_scale"), func(v): Settings.set_value("ui_scale", v))))
	c.add_child(_toggle("Меньше движения на экране", "reduce_motion"))
	c.add_child(_toggle("Показывать FPS", "show_fps"))
	sheet.open("Настройки", "gear")


static func _section(c: Control, icon: String, text: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.add_child(UiTheme.icon(icon, 26, UiTheme.GOLD_DEEP))
	h.add_child(UiTheme.title(text, 22))
	c.add_child(h)


static func _row(icon: String, text: String, ctl: Control) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	if icon != "":
		h.add_child(UiTheme.icon(icon, 22, UiTheme.TEXT_DIM))
	var l := UiTheme.label(text, 17)
	l.custom_minimum_size.x = 170
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(l)
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ctl)
	return h


## Переключатель «пилюлей»: включено — золотая, выключено — молочная.
static func _toggle(text: String, key: String) -> Control:
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = bool(Settings.get_value(key))
	b.custom_minimum_size = Vector2(76, 38)
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	var on := UiTheme.pill(UiTheme.GOLD, 6)
	var off := UiTheme.pill(UiTheme.PANEL_SOLID.darkened(0.08), 6)
	b.add_theme_stylebox_override("normal", off)
	b.add_theme_stylebox_override("hover", off)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.text = "Вкл" if b.button_pressed else "Выкл"
	b.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	b.add_theme_color_override("font_pressed_color", UiTheme.TEXT_LIGHT)
	b.add_theme_color_override("font_hover_pressed_color", UiTheme.TEXT_LIGHT)
	b.toggled.connect(func(v: bool):
		b.text = "Вкл" if v else "Выкл"
		Audio.ui("tap")
		Settings.set_value(key, v))
	var h := _row("", text, Control.new())
	h.get_child(h.get_child_count() - 1).queue_free()
	h.add_child(b)
	return h


## Выбор из вариантов: ряд «пилюль», выбранная — золотая.
static func _choice(opts: Array, current: Variant, cb: Callable) -> Control:
	var h := HFlowContainer.new()
	h.add_theme_constant_override("h_separation", 8)
	h.add_theme_constant_override("v_separation", 8)
	var group := ButtonGroup.new()
	for o in opts:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.text = str(o[1])
		b.button_pressed = str(o[0]) == str(current)
		var on := UiTheme.pill(UiTheme.GOLD, 8)
		var off := UiTheme.pill(UiTheme.PANEL_SOLID.darkened(0.06), 8)
		b.add_theme_stylebox_override("normal", off)
		b.add_theme_stylebox_override("hover", off)
		b.add_theme_stylebox_override("pressed", on)
		b.add_theme_stylebox_override("hover_pressed", on)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.add_theme_color_override("font_color", UiTheme.TEXT)
		b.add_theme_color_override("font_pressed_color", UiTheme.TEXT_LIGHT)
		b.add_theme_color_override("font_hover_pressed_color", UiTheme.TEXT_LIGHT)
		var val = o[0]
		b.pressed.connect(func():
			Audio.ui("tap")
			cb.call(val))
		h.add_child(b)
	return h
