class_name SketchbookView
extends Control
## Скетчбук Кота: страница-рисунок на бумаге, подпись, листание стрелками/свайпом; закрывается после последней.

signal closed

var _page: TextureRect
var _sheet: Control
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
	dim.color = Color(0.95, 0.9, 0.92, 0.55)
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
	head.add_child(UiTheme.icon("pencil", 26, UiTheme.GOLD_DEEP))
	var t := UiTheme.title("Скетчбук", 26)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	_counter = UiTheme.tag("", 16, UiTheme.TEXT_DIM)
	head.add_child(_counter)
	head.add_child(UiTheme.icon_button("close", close, 44))
	v.add_child(head)
	# лист альбома: спираль сверху, рисунок чуть наклонён и приклеен скотчем по углам
	var sheet := Control.new()
	sheet.custom_minimum_size = Vector2(720, 470)
	sheet.draw.connect(func(): _draw_sheet(sheet))
	v.add_child(sheet)
	_sheet = sheet
	_page = TextureRect.new()
	_page.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_page.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_page.offset_left = 18; _page.offset_right = -18; _page.offset_top = 26; _page.offset_bottom = -10
	_page.rotation_degrees = -1.2
	sheet.add_child(_page)
	var tape := Control.new()
	tape.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tape.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tape.draw.connect(func(): _draw_tape(tape))
	sheet.add_child(tape)
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
	_sheet.custom_minimum_size = Vector2(w, w * 0.65 + 36)
	_page.pivot_offset = (_sheet.custom_minimum_size - Vector2(36, 36)) * 0.5


## Тень листа и спираль альбома.
func _draw_sheet(c: Control) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	c.draw_rect(Rect2(r.position + Vector2(6, 22), r.size - Vector2(8, 18)), Color(0.45, 0.3, 0.3, 0.12))
	c.draw_rect(Rect2(r.position + Vector2(0, 16), r.size - Vector2(4, 16)), Color("fffcf5"))
	var n := int(r.size.x / 34.0)
	for i in n:
		var x := 22.0 + i * (r.size.x - 44.0) / maxf(1, n - 1)
		c.draw_circle(Vector2(x, 20), 4.5, Color(0.55, 0.48, 0.5, 0.5))
		c.draw_arc(Vector2(x, 12), 9, PI * 0.15, PI * 1.05, 12, UiTheme.GOLD_DEEP, 2.5, true)


## Полоски скотча по двум углам рисунка.
func _draw_tape(c: Control) -> void:
	var tape := Color(0.98, 0.93, 0.78, 0.75)
	for p in [[Vector2(36, 36), -0.6], [Vector2(c.size.x - 36, c.size.y - 22), -0.6]]:
		c.draw_set_transform(p[0], p[1], Vector2.ONE)
		c.draw_rect(Rect2(-34, -10, 68, 20), tape)
	c.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


## Показать страницы и дождаться закрытия: await view.open(pages).
func open(pages: Array) -> void:
	if pages.is_empty():
		return
	_pages = pages
	visible = true
	Audio.ui("ui_page")
	Audio.sfx("sketch")
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
