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
## Пропуск катсцены: оставшиеся реплики проходят без ожидания.
var skipping := false
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	var st := UiTheme.panel_light()
	st.content_margin_top = 30          # место под ленту с именем, вынесенную за верхний край
	_panel.add_theme_stylebox_override("panel", st)
	_panel.anchor_left = 0.5; _panel.anchor_right = 0.5
	_panel.anchor_top = 1.0; _panel.anchor_bottom = 1.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.custom_minimum_size = Vector2(760, 124)
	_panel.offset_bottom = -12
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.gui_input.connect(_on_panel_input)
	add_child(_panel)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_panel.add_child(box)
	_text = UiTheme.label("", 24)
	_text.custom_minimum_size = Vector2(680, 56)
	_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(_text)
	_next = UiTheme.icon("down", 30, UiTheme.GOLD)
	_next.size_flags_vertical = Control.SIZE_SHRINK_END
	box.add_child(_next)
	# лента с именем — над верхним краем панели
	_name_tag = UiTheme.ribbon_title("", 22) as PanelContainer
	_name = _name_tag.get_child(0) as Label
	_name_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_tag)      # не в PanelContainer: он растянул бы ленту на всю панель
	visible = false
	resized.connect(_fit)
	_panel.resized.connect(_place_tag)
	_panel.item_rect_changed.connect(_place_tag)
	_fit()


## Узкий экран (телефон в портрете) — панель на всю ширину с полями.
func _fit() -> void:
	var w := minf(size.x - 32.0, 900.0)
	_panel.custom_minimum_size.x = maxf(w, 280.0)
	_panel.offset_left = -_panel.custom_minimum_size.x * 0.5
	_panel.offset_right = _panel.custom_minimum_size.x * 0.5
	_text.custom_minimum_size.x = _panel.custom_minimum_size.x - 90.0


func _place_tag() -> void:
	_name_tag.size = _name_tag.get_combined_minimum_size()
	_name_tag.position = _panel.position + Vector2(28, -_name_tag.size.y * 0.55)


## Показать реплики по очереди и дождаться конца: await box.play(lines, script).
func play(lines: Array, story: StoryScript) -> void:
	visible = true
	for l in lines:
		if skipping:
			break
		show_line(story.speaker_name(str(l.get("who", ""))), str(l.get("text", "")))
		await advanced
	visible = false


func skip() -> void:
	skipping = true
	if visible:
		advanced.emit()


func show_line(speaker: String, text: String) -> void:
	visible = true
	_name.text = speaker
	_name_tag.visible = speaker != ""
	_place_tag.call_deferred()
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
	if StoryOverlay._is_tap(e):
		accept_event()
		_advance()


func _unhandled_input(e: InputEvent) -> void:
	if not visible:
		return
	if e.is_action_pressed("interact") or e.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_advance()
