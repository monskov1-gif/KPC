class_name Sheet
extends Control
## Мягкое всплывающее «облако» поверх экрана: затемнение, панель по центру, заголовок с иконкой и крестик.
## Содержимое кладётся в content (прокручивается). Закрывается крестиком или нажатием на фон.

signal closed

var max_size := Vector2(720, 820)
var content: VBoxContainer
var _panel: PanelContainer
var _title_icon: IconView
var _title: Label
var _scroll: ScrollContainer
var _footer: HBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.42, 0.28, 0.32, 0.28)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e):
		if (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed:
			close())
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiTheme.cloud(UiTheme.PANEL_SOLID, 28, 22))
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_panel.add_child(v)
	var head := HBoxContainer.new()
	_title_icon = UiTheme.icon("sparkle", 28, UiTheme.GOLD)
	head.add_child(_title_icon)
	_title = UiTheme.label("", 24)
	# Однострочный заголовок: переносимый текст до раскладки запрашивает огромную высоту.
	_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.clip_text = true
	head.add_child(_title)
	head.add_child(UiTheme.icon_button("close", close, 44))
	v.add_child(head)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_right", 12)
	_scroll.add_child(pad)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	pad.add_child(content)
	_footer = HBoxContainer.new()
	_footer.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(_footer)
	resized.connect(_layout)


func open(title: String, icon := "sparkle") -> void:
	_title.text = title
	_title_icon.icon = icon
	visible = true
	_scroll.scroll_vertical = 0
	_layout.call_deferred()


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func clear() -> void:
	for n in [content, _footer]:
		for c in n.get_children():
			n.remove_child(c)
			c.queue_free()


func add_footer(c: Control) -> void:
	_footer.add_child(c)


func _layout() -> void:
	var w := minf(size.x - 32, max_size.x)
	# Высота по содержимому, но не больше экрана и max_size.
	var wanted := content.get_combined_minimum_size().y + _footer.get_combined_minimum_size().y + 130
	var h := minf(minf(size.y - 48, max_size.y), wanted)
	_panel.position = (size - Vector2(w, h)) / 2.0
	_panel.size = Vector2(w, h)
