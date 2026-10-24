class_name StoryOverlay
extends CanvasLayer
## Интерфейс сюжетной сцены: затемнение, титры, текущая цель, подсказка взаимодействия, обрывки фраз,
## окно реплик, скетчбук и экранное управление (стик + кнопка) на сенсорных экранах.

signal interact_pressed
signal menu_requested
signal skip_pressed

const SKETCH_DIR := "res://art/story/sketches/"

var dialogue: DialogueBox
var sketchbook: SketchbookView
var stick: VirtualStick
## Игровой интерфейс исследования: профиль, разделы, валюта, мини-карта, кнопки действий (прячется в катсценах).
var hud: GameHud
var _root: Control
var _fade: ColorRect
var _caption: VBoxContainer
var _caption_title: Label
var _caption_sub: Label
var _objective: PanelContainer
var _objective_text: Label
var _prompt: PanelContainer
var _prompt_text: Label
var _prompt_key: Label
var _fragments: VBoxContainer
var _touch_btn: Button
var _skip_btn: Button
var _bars: Array[Control] = []
var _bars_tween: Tween
var _touch := false
var _tweens: Array[Tween] = []
var _hint: PanelContainer
var _hint_keys: HBoxContainer
var _hint_icon: IconView
var _hint_title: Label
var _hint_text: Label
var _toast: PanelContainer
var _toast_text: Label
var _toast_tween: Tween
var _flash: ColorRect


func _ready() -> void:
	layer = 5
	_touch = DisplayServer.is_touchscreen_available() or OS.has_environment("KPC_TOUCH")
	_root = Control.new()
	_root.theme = UiTheme.build()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_objective = PanelContainer.new()
	var ost := UiTheme.cloud(Color(1, 0.99, 0.97, 0.94), 999, 10)
	ost.content_margin_left = 16; ost.content_margin_right = 20
	_objective.add_theme_stylebox_override("panel", ost)
	_objective.position = Vector2(24, 22)
	var oh := HBoxContainer.new()
	oh.add_child(UiTheme.icon("sparkle", 22, UiTheme.GOLD))
	_objective_text = UiTheme.tag("", 18)
	oh.add_child(_objective_text)
	_objective.add_child(oh)
	_objective.visible = false
	_root.add_child(_objective)
	hud = GameHud.new()
	hud.name = "Hud"
	_root.add_child(hud)
	hud.set_touch(_touch)
	hud.visible = false                 # появляется, когда герой управляется (set_gameplay_ui)
	hud.modulate.a = 0.0
	_root.move_child(_objective, -1)

	var menu := UiTheme.icon_button("menu", func(): menu_requested.emit(), 58)
	menu.anchor_left = 1.0; menu.anchor_right = 1.0
	menu.offset_left = -82; menu.offset_right = -24; menu.offset_top = 18; menu.offset_bottom = 76
	_root.add_child(menu)
	# «Пропустить» — только во время катсцен
	# кинорамка катсцен: мягкие полосы сверху и снизу
	for top in [true, false]:
		var bar := TextureRect.new()
		var g := Gradient.new()
		g.set_color(0, Color(0.16, 0.12, 0.18, 0.78 if top else 0.0))
		g.set_color(1, Color(0.16, 0.12, 0.18, 0.0 if top else 0.78))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill_from = Vector2(0, 0)
		gt.fill_to = Vector2(0, 1)
		bar.texture = gt
		bar.stretch_mode = TextureRect.STRETCH_SCALE
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_right = 1.0
		if top:
			bar.anchor_bottom = 0.1
		else:
			bar.anchor_top = 0.9
			bar.anchor_bottom = 1.0
		bar.modulate.a = 0.0
		_root.add_child(bar)
		_root.move_child(bar, 0)
		_bars.append(bar)
	# «Пропустить» — круглая кнопка рядом с меню, только во время катсцен
	_skip_btn = UiTheme.icon_button("skip", func(): skip_pressed.emit(), 58)
	_skip_btn.anchor_left = 1.0; _skip_btn.anchor_right = 1.0
	_skip_btn.offset_left = -152; _skip_btn.offset_right = -94; _skip_btn.offset_top = 18; _skip_btn.offset_bottom = 76
	_skip_btn.tooltip_text = "Пропустить"
	var skl := UiTheme.tag("Пропустить", 13, UiTheme.TEXT_DIM)
	skl.position = Vector2(-12, 60)
	skl.custom_minimum_size.x = 82
	skl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_skip_btn.add_child(skl)
	_skip_btn.visible = false
	_root.add_child(_skip_btn)

	_fragments = VBoxContainer.new()
	_fragments.anchor_left = 0.5; _fragments.anchor_right = 0.5
	_fragments.anchor_top = 0.62; _fragments.anchor_bottom = 0.62
	_fragments.offset_left = -360; _fragments.offset_right = 360
	_fragments.alignment = BoxContainer.ALIGNMENT_CENTER
	_fragments.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_fragments)

	_prompt = PanelContainer.new()
	_prompt.add_theme_stylebox_override("panel", UiTheme.chip())
	_prompt.anchor_left = 0.5; _prompt.anchor_right = 0.5
	_prompt.anchor_top = 1.0; _prompt.anchor_bottom = 1.0
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.offset_top = -120; _prompt.offset_bottom = -76
	var ph := HBoxContainer.new()
	var key := PanelContainer.new()
	key.add_theme_stylebox_override("panel", UiTheme.pill(UiTheme.GOLD, 4))
	_prompt_key = UiTheme.tag("E", 17, Color.WHITE)
	key.add_child(_prompt_key)
	ph.add_child(key)
	_prompt_text = UiTheme.tag("", 18)
	ph.add_child(_prompt_text)
	_prompt.add_child(ph)
	_prompt.mouse_filter = Control.MOUSE_FILTER_STOP
	_prompt.gui_input.connect(func(e):
		if _is_tap(e):
			interact_pressed.emit())
	_prompt.visible = false
	_root.add_child(_prompt)

	if _touch:
		stick = VirtualStick.new()
		_root.add_child(stick)
		_touch_btn = UiTheme.icon_button("sparkle", func(): interact_pressed.emit(), 92, UiTheme.GOLD_DEEP)
		_touch_btn.anchor_left = 1.0; _touch_btn.anchor_right = 1.0
		_touch_btn.anchor_top = 1.0; _touch_btn.anchor_bottom = 1.0
		# слева от кнопок действий HUD (удар, прыжок, рывок, снимок)
		_touch_btn.offset_left = -334; _touch_btn.offset_right = -246
		_touch_btn.offset_top = -156; _touch_btn.offset_bottom = -68
		_touch_btn.visible = false
		_root.add_child(_touch_btn)
		_prompt_key.get_parent().visible = false

	_build_hint()
	_toast = PanelContainer.new()
	_toast.add_theme_stylebox_override("panel", UiTheme.cloud(Color(1, 0.99, 0.97, 0.95), 999, 10))
	_toast.anchor_left = 0.5; _toast.anchor_right = 0.5
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.offset_top = 96
	var th := HBoxContainer.new()
	th.add_child(UiTheme.icon("sparkle", 20, UiTheme.GOLD))
	_toast_text = UiTheme.tag("", 17)
	th.add_child(_toast_text)
	_toast.add_child(th)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.modulate.a = 0.0
	_root.add_child(_toast)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.modulate.a = 0.0
	_root.add_child(_flash)
	dialogue = DialogueBox.new()
	_root.add_child(dialogue)
	sketchbook = SketchbookView.new()
	_root.add_child(sketchbook)

	_caption = VBoxContainer.new()
	_caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_caption.alignment = BoxContainer.ALIGNMENT_CENTER
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption_title = UiTheme.title("", 54, Color.WHITE)
	_caption_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_caption_title.add_theme_color_override("font_shadow_color", Color(0.25, 0.15, 0.2, 0.7))
	_caption_title.add_theme_constant_override("shadow_offset_y", 3)
	_caption_title.add_theme_constant_override("shadow_outline_size", 8)
	_caption_sub = UiTheme.tag("", 24, Color(1, 0.96, 0.92))
	_caption_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption_sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_caption_sub.add_theme_color_override("font_shadow_color", Color(0.25, 0.15, 0.2, 0.7))
	_caption_sub.add_theme_constant_override("shadow_outline_size", 6)
	_caption.add_child(_caption_title)
	_caption.add_child(_caption_sub)
	_caption.modulate.a = 0.0
	_root.add_child(_caption)

	_fade = ColorRect.new()
	_fade.color = Color(0.06, 0.04, 0.08)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_fade)
	_root.move_child(_caption, -1)   # титры поверх затемнения


func fade(to_black: bool, seconds: float) -> void:
	var a := 1.0 if to_black else 0.0
	if seconds <= 0.0:
		_fade.modulate.a = a
		return
	var tw := _track(create_tween())
	tw.tween_property(_fade, "modulate:a", a, seconds)
	await tw.finished


func set_black(on: bool) -> void:
	_fade.modulate.a = 1.0 if on else 0.0


func caption(text: String, sub: String, seconds: float) -> void:
	_caption_title.text = text
	_caption_title.visible = text != ""
	_caption_sub.text = sub
	_caption_sub.visible = sub != ""
	var f := minf(0.6, seconds * 0.25)
	var tw := _track(create_tween())
	tw.tween_property(_caption, "modulate:a", 1.0, f)
	tw.tween_interval(maxf(0.0, seconds - 2.0 * f))
	tw.tween_property(_caption, "modulate:a", 0.0, f)
	await tw.finished


## Короткое сообщение сверху по центру (снимок сохранён, награда получена…).
func toast(text: String, seconds := 2.2) -> void:
	_toast_text.text = text
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.2)
	_toast_tween.tween_interval(seconds)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)


## Вспышка (снимок).
func flash() -> void:
	_flash.modulate.a = 0.85
	create_tween().tween_property(_flash, "modulate:a", 0.0, 0.45)


func set_objective(text: String) -> void:
	_objective.position = Vector2(24, hud.objective_y() if hud else 22.0)
	if text != "" and text.get_slice("  ·  ", 0) != _objective_text.text.get_slice("  ·  ", 0):
		Audio.sfx("objective")
	_objective_text.text = text
	_objective.visible = text != ""
	_objective.modulate.a = 0.0
	create_tween().tween_property(_objective, "modulate:a", 1.0, 0.4)


## Подсказка «можно поговорить / осмотреть»; пустой текст — скрыть.
func set_prompt(text: String) -> void:
	_prompt.visible = text != ""
	_prompt_text.text = text
	_prompt.offset_left = 0; _prompt.offset_right = 0
	if _touch_btn:
		_touch_btn.visible = text != ""


## Обрывок фразы, услышанный на ходу (больница): курсив, сам тает через несколько секунд.
func fragment(speaker: String, text: String, seconds := 3.2) -> void:
	# облачко-подложка: читается и на белом коридоре, и на тёмной улице
	var l := PanelContainer.new()
	l.add_theme_stylebox_override("panel", UiTheme.cloud(Color(0.25, 0.2, 0.3, 0.55), 999, 10))
	l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var t := UiTheme.label(("%s: %s" % [speaker, text]) if speaker != "" else text, 20, Color(1, 0.97, 0.94))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_override("font", UiTheme.title_font())
	l.add_child(t)
	l.modulate.a = 0.0
	_fragments.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "modulate:a", 0.95, 0.5)
	tw.tween_interval(seconds)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)


func clear_fragments() -> void:
	for c in _fragments.get_children():
		c.queue_free()


func touch_controls() -> bool:
	return _touch


func _track(tw: Tween) -> Tween:
	# оверлей работает и на паузе (меню), но затемнения и титры сюжета на паузе стоят
	tw.set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	_tweens = _tweens.filter(func(t): return t.is_valid())
	_tweens.append(tw)
	return tw


## Пропуск: довести затемнения и титры до конца мгновенно.
func finish_tweens() -> void:
	for t in _tweens:
		if t.is_valid() and t.is_running():
			t.custom_step(1000.0)
	_tweens.clear()


## Карточка обучения слева: иконка, заголовок, что нажать (под текущее устройство).
func _build_hint() -> void:
	_hint = PanelContainer.new()
	var hst := UiTheme.panel_light()
	hst.content_margin_left = 22; hst.content_margin_right = 26; hst.content_margin_top = 18; hst.content_margin_bottom = 18
	_hint.add_theme_stylebox_override("panel", hst)
	_hint.anchor_top = 0.5; _hint.anchor_bottom = 0.5
	_hint.offset_left = 24; _hint.offset_top = -60
	_hint.custom_minimum_size = Vector2(340, 0)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	# золотой медальон с иконкой действия; мягко «дышит», пока подсказка на экране
	var medal := PanelContainer.new()
	var mst := UiTheme.cloud(UiTheme.GOLD_LIGHT, 999, 13)
	mst.border_color = UiTheme.GOLD
	mst.set_border_width_all(3)
	medal.add_theme_stylebox_override("panel", mst)
	_hint_icon = UiTheme.icon("sparkle", 32, UiTheme.GOLD_DEEP)
	medal.add_child(_hint_icon)
	medal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	medal.pivot_offset = Vector2(29, 29)
	h.add_child(medal)
	medal.ready.connect(func():
		var pulse := medal.create_tween().set_loops()
		pulse.tween_property(medal, "scale", Vector2(1.07, 1.07), 0.6).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(medal, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_SINE))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	_hint_title = UiTheme.title("", 22)
	_hint_text = UiTheme.label("", 18, UiTheme.TEXT)
	_hint_text.custom_minimum_size.x = 250
	_hint_keys = HBoxContainer.new()
	_hint_keys.add_theme_constant_override("separation", 6)
	v.add_child(_hint_title)
	v.add_child(_hint_keys)
	v.add_child(_hint_text)
	h.add_child(v)
	_hint.add_child(h)
	_hint.visible = false
	_root.add_child(_hint)


func _keycap(key: String) -> Control:
	var p := PanelContainer.new()
	var st := UiTheme.cloud(UiTheme.PANEL_SOLID, 8, 6)
	st.border_color = UiTheme.GOLD
	st.set_border_width_all(2)
	st.border_width_bottom = 4
	st.content_margin_left = 10; st.content_margin_right = 10
	p.add_theme_stylebox_override("panel", st)
	p.custom_minimum_size = Vector2(36, 36)
	var l := UiTheme.label(key, 16, UiTheme.GOLD_DEEP)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


func show_hint(icon_name: String, title_text: String, body: String) -> void:
	_hint_icon.icon = icon_name
	_hint_icon.queue_redraw()
	_hint_title.text = title_text
	# клавиши в тексте пишутся в квадратных скобках: «[W] [A] [S] [D] — идти» → клавиши-колпачки и подпись
	for c in _hint_keys.get_children():
		c.queue_free()
	var rest := body
	var re := RegEx.create_from_string("\\[([^\\]]+)\\]")
	var found := re.search_all(body)
	for m in found:
		_hint_keys.add_child(_keycap(m.get_string(1)))
	if not found.is_empty():
		rest = re.sub(body, "", true).strip_edges().trim_prefix("—").strip_edges()
	_hint_keys.visible = not found.is_empty()
	_hint_text.text = rest
	if not _hint.visible:
		Audio.ui("ui_hint")
		_hint.visible = true
		_hint.modulate.a = 0.0
		_hint.position.x = -40
		var tw := create_tween().set_parallel()
		tw.tween_property(_hint, "modulate:a", 1.0, 0.35)
		tw.tween_property(_hint, "position:x", 24.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Скрыть подсказку; done — с отметкой «выполнено» (зелёная галочка и исчезновение).
func hide_hint(done := false) -> void:
	if not _hint.visible:
		return
	if done:
		_hint_icon.icon = "check"
		_hint_icon.color = UiTheme.OK
		_hint_icon.queue_redraw()
	var tw := create_tween()
	tw.tween_interval(0.6 if done else 0.0)
	tw.tween_property(_hint, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func():
		_hint.visible = false
		_hint_icon.color = UiTheme.GOLD_DEEP)


## Добавить окно поверх интерфейса сцены (тема и масштаб — общие).
func add_ui(c: Control) -> void:
	_root.add_child(c)


func set_skippable(on: bool) -> void:
	_skip_btn.visible = on


## Скрыть игровые подсказки на время катсцены.
func set_gameplay_ui(on: bool) -> void:
	# катсцена: кинорамка, цель прячется (вернётся после)
	if _bars_tween and _bars_tween.is_valid():
		_bars_tween.kill()
	_bars_tween = create_tween().set_parallel()
	for b in _bars:
		_bars_tween.tween_property(b, "modulate:a", 0.0 if on else 1.0, 0.5)
	if _objective_text.text != "":
		_bars_tween.tween_property(_objective, "modulate:a", 1.0 if on else 0.0, 0.4)
	if hud:
		if on:
			hud.visible = true
			hud.refresh()
		_bars_tween.tween_property(hud, "modulate:a", 1.0 if on else 0.0, 0.4)
		if not on:
			_bars_tween.chain().tween_callback(func(): hud.visible = false)
	if stick:
		stick.visible = on
		if not on:
			stick.reset()
	if not on:
		set_prompt("")


## Нажатие пальцем или кнопкой мыши — одно. Мышь, эмулированная из касания, не считается (иначе двойное срабатывание).
static func _is_tap(e: InputEvent) -> bool:
	if e is InputEventScreenTouch:
		return e.pressed
	if e is InputEventMouseButton:
		return e.pressed and e.button_index == MOUSE_BUTTON_LEFT and e.device != InputEvent.DEVICE_ID_EMULATION
	return false
