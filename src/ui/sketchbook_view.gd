class_name SketchbookView
extends Control
## Скетчбук Кота: страница-рисунок на бумаге, подпись, листание стрелками/свайпом; закрывается после последней.

signal closed

var _page: TextureRect
var _caption: Label
var _counter: Label
var _prev: Button
var _next: Button
var _pages: Array = []
var _i := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.3, 0.2, 0.24, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var paper := PanelContainer.new()
	var st := UiTheme.cloud(Color("fbf6ec"), 18, 22)
	st.border_color = Color("d8c6a8")
	st.set_border_width_all(2)
	paper.add_theme_stylebox_override("panel", st)
	center.add_child(paper)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	paper.add_child(v)
	var head := HBoxContainer.new()
	head.add_child(UiTheme.icon("recipe", 26, UiTheme.GOLD_DEEP))
	var t := UiTheme.title("Скетчбук", 26)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	_counter = UiTheme.tag("", 16, UiTheme.TEXT_DIM)
	head.add_child(_counter)
	head.add_child(UiTheme.icon_button("close", close, 44))
	v.add_child(head)
	_page = TextureRect.new()
	_page.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_page.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_page.custom_minimum_size = Vector2(720, 470)
	v.add_child(_page)
	var nav := HBoxContainer.new()
	_prev = UiTheme.icon_button("back", func(): _show(_i - 1), 48)
	nav.add_child(_prev)
	_caption = UiTheme.label("", 21)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_font_override("font", UiTheme.title_font())
	nav.add_child(_caption)
	_next = UiTheme.icon_button("next", _forward, 48)
	nav.add_child(_next)
	v.add_child(nav)
	resized.connect(_fit)


func _fit() -> void:
	var w := clampf(size.x - 90.0, 280.0, 720.0)
	_page.custom_minimum_size = Vector2(w, w * 0.65)


## Показать страницы и дождаться закрытия: await view.open(pages).
func open(pages: Array) -> void:
	_pages = pages
	visible = true
	_fit()
	_show(0)
	await closed


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func _forward() -> void:
	if _i >= _pages.size() - 1:
		close()
	else:
		_show(_i + 1)


func _show(i: int) -> void:
	_i = clampi(i, 0, _pages.size() - 1)
	var p: Dictionary = _pages[_i]
	var path := StoryOverlay.SKETCH_DIR + str(p.get("image", "")) + ".png"
	_page.texture = load(path) if ResourceLoader.exists(path) else null
	_caption.text = str(p.get("caption", ""))
	_counter.text = "%d / %d" % [_i + 1, _pages.size()]
	_prev.disabled = _i == 0


func _unhandled_input(e: InputEvent) -> void:
	if not visible:
		return
	if e.is_action_pressed("interact") or e.is_action_pressed("ui_accept") or e.is_action_pressed("ui_right"):
		get_viewport().set_input_as_handled()
		_forward()
	elif e.is_action_pressed("ui_left"):
		get_viewport().set_input_as_handled()
		_show(_i - 1)
