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
var _touch := false
var _tweens: Array[Tween] = []
var _hint: PanelContainer
var _hint_icon: IconView
var _hint_title: Label
var _hint_text: Label


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

	var menu := UiTheme.icon_button("menu", func(): menu_requested.emit(), 58)
	menu.anchor_left = 1.0; menu.anchor_right = 1.0
	menu.offset_left = -82; menu.offset_right = -24; menu.offset_top = 18; menu.offset_bottom = 76
	_root.add_child(menu)
	# «Пропустить» — только во время катсцен
	_skip_btn = Button.new()
	var skst := UiTheme.chip()
	skst.content_margin_left = 36       # место под иконку
	_skip_btn.add_theme_stylebox_override("normal", skst)
	_skip_btn.add_theme_stylebox_override("hover", skst)
	_skip_btn.add_theme_stylebox_override("pressed", skst)
	_skip_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_skip_btn.add_theme_color_override("font_color", UiTheme.TEXT)
	_skip_btn.add_theme_color_override("font_hover_color", UiTheme.TEXT)
	_skip_btn.add_theme_constant_override("outline_size", 0)
	_skip_btn.text = "Пропустить"
	_skip_btn.anchor_left = 1.0; _skip_btn.anchor_right = 1.0
	_skip_btn.offset_left = -250; _skip_btn.offset_right = -96; _skip_btn.offset_top = 26; _skip_btn.offset_bottom = 68
	_skip_btn.pressed.connect(func(): skip_pressed.emit())
	var sk := UiTheme.icon("skip", 18, UiTheme.GOLD_DEEP)
	sk.position = Vector2(14, 12)
	_skip_btn.add_child(sk)
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
		_touch_btn.offset_left = -130; _touch_btn.offset_right = -38
		_touch_btn.offset_top = -150; _touch_btn.offset_bottom = -58
		_touch_btn.visible = false
		_root.add_child(_touch_btn)
		_prompt_key.get_parent().visible = false

	_build_hint()
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


func set_objective(text: String) -> void:
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
	_hint.add_theme_stylebox_override("panel", UiTheme.cloud(Color(1, 0.99, 0.97, 0.95), 22, 16))
	_hint.anchor_top = 0.5; _hint.anchor_bottom = 0.5
	_hint.offset_left = 24; _hint.offset_top = -60
	_hint.custom_minimum_size = Vector2(340, 0)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var medal := PanelContainer.new()
	medal.add_theme_stylebox_override("panel", UiTheme.pill(UiTheme.GOLD_LIGHT, 10))
	_hint_icon = UiTheme.icon("sparkle", 30, UiTheme.GOLD_DEEP)
	medal.add_child(_hint_icon)
	medal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(medal)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	_hint_title = UiTheme.title("", 22)
	_hint_text = UiTheme.label("", 18, UiTheme.TEXT)
	_hint_text.custom_minimum_size.x = 250
	v.add_child(_hint_title)
	v.add_child(_hint_text)
	h.add_child(v)
	_hint.add_child(h)
	_hint.visible = false
	_root.add_child(_hint)


func show_hint(icon_name: String, title_text: String, body: String) -> void:
	_hint_icon.icon = icon_name
	_hint_icon.queue_redraw()
	_hint_title.text = title_text
	_hint_text.text = body
	if not _hint.visible:
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
