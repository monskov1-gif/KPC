class_name DialogueBox
extends Control
## Окно реплик: светлая «облачная» панель внизу экрана, имя говорящего на ленте, текст печатается.
## Дальше — касание, клик, «E»/«Пробел»/«Enter»; если текст ещё печатается — сначала допечатать.

signal advanced

const CHARS_PER_SEC := 42.0

var _panel: PanelContainer
var _name_tag: PanelContainer
var _name: Label
var _text: Label
var _next: IconView
var _typing := false
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiTheme.panel_light())
	_panel.anchor_left = 0.5; _panel.anchor_right = 0.5
	_panel.anchor_top = 1.0; _panel.anchor_bottom = 1.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.custom_minimum_size = Vector2(760, 150)
	_panel.offset_bottom = -24
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.gui_input.connect(_on_panel_input)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)
	_name_tag = UiTheme.ribbon_title("", 22) as PanelContainer
	_name_tag.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_name = _name_tag.get_child(0) as Label
	box.add_child(_name_tag)
	_text = UiTheme.label("", 21)
	_text.custom_minimum_size = Vector2(680, 60)
	box.add_child(_text)
	_next = UiTheme.icon("down", 22, UiTheme.GOLD_DEEP)
	_next.size_flags_horizontal = Control.SIZE_SHRINK_END
	box.add_child(_next)
	visible = false
	resized.connect(_fit)
	_fit()


## Узкий экран (телефон в портрете) — панель на всю ширину с полями.
func _fit() -> void:
	var w := minf(size.x - 32.0, 900.0)
	_panel.custom_minimum_size.x = maxf(w, 280.0)
	_panel.offset_left = -_panel.custom_minimum_size.x * 0.5
	_panel.offset_right = _panel.custom_minimum_size.x * 0.5
	_text.custom_minimum_size.x = _panel.custom_minimum_size.x - 70.0


## Показать реплики по очереди и дождаться конца: await box.play(lines, script).
func play(lines: Array, story: StoryScript) -> void:
	visible = true
	for l in lines:
		show_line(story.speaker_name(str(l.get("who", ""))), str(l.get("text", "")))
		await advanced
	visible = false


func show_line(speaker: String, text: String) -> void:
	visible = true
	_name.text = speaker
	_name_tag.visible = speaker != ""
	_text.text = text
	_text.visible_ratio = 0.0
	_typing = true
	_t = 0.0
	_next.visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	if _typing:
		_t += delta
		var n := maxi(1, _text.get_total_character_count())
		_text.visible_ratio = minf(1.0, _t * CHARS_PER_SEC / n)
		if _text.visible_ratio >= 1.0:
			_typing = false
			_next.visible = true
	else:
		_next.modulate.a = 0.65 + 0.35 * sin(Time.get_ticks_msec() * 0.006)


func _advance() -> void:
	if _typing:
		_typing = false
		_text.visible_ratio = 1.0
		_next.visible = true
	else:
		advanced.emit()


func _on_panel_input(e: InputEvent) -> void:
	if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed):
		accept_event()
		_advance()


func _unhandled_input(e: InputEvent) -> void:
	if not visible:
		return
	if e.is_action_pressed("interact") or e.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_advance()
