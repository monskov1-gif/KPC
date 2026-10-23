class_name StoryOverlay
extends CanvasLayer
## Интерфейс сюжетной сцены: затемнение, титры, текущая цель, подсказка взаимодействия, обрывки фраз,
## окно реплик, скетчбук и экранное управление (стик + кнопка) на сенсорных экранах.

signal interact_pressed
signal menu_requested

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
var _touch := false


func _ready() -> void:
	layer = 5
	_touch = DisplayServer.is_touchscreen_available() or OS.has_environment("KPC_TOUCH")
	_root = Control.new()
	_root.theme = UiTheme.build()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_objective = PanelContainer.new()
	_objective.add_theme_stylebox_override("panel", UiTheme.chip())
	_objective.position = Vector2(20, 18)
	var oh := HBoxContainer.new()
	oh.add_child(UiTheme.icon("sparkle", 22, UiTheme.GOLD))
	_objective_text = UiTheme.tag("", 18)
	oh.add_child(_objective_text)
	_objective.add_child(oh)
	_objective.visible = false
	_root.add_child(_objective)

	var menu := UiTheme.icon_button("back", func(): menu_requested.emit(), 52)
	menu.anchor_left = 1.0; menu.anchor_right = 1.0
	menu.offset_left = -72; menu.offset_right = -20; menu.offset_top = 14; menu.offset_bottom = 66
	_root.add_child(menu)

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
		if (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed:
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
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", a, seconds)
	await tw.finished


func set_black(on: bool) -> void:
	_fade.modulate.a = 1.0 if on else 0.0


func caption(text: String, sub: String, seconds: float) -> void:
	_caption_title.text = text
	_caption_title.visible = text != ""
	_caption_sub.text = sub
	_caption_sub.visible = sub != ""
	var tw := create_tween()
	tw.tween_property(_caption, "modulate:a", 1.0, 0.6)
	tw.tween_interval(maxf(0.0, seconds - 1.2))
	tw.tween_property(_caption, "modulate:a", 0.0, 0.6)
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
	var l := UiTheme.label(("%s: %s" % [speaker, text]) if speaker != "" else text, 20, Color(1, 0.97, 0.94))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_shadow_color", Color(0.15, 0.1, 0.2, 0.8))
	l.add_theme_constant_override("shadow_outline_size", 6)
	l.modulate.a = 0.0
	_fragments.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "modulate:a", 0.95, 0.5)
	tw.tween_interval(seconds)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)


func touch_controls() -> bool:
	return _touch


## Скрыть игровые подсказки на время катсцены.
func set_gameplay_ui(on: bool) -> void:
	if stick:
		stick.visible = on
		if not on:
			stick.reset()
	if not on:
		set_prompt("")
