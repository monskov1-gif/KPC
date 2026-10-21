class_name UiTheme
extends RefCounted
## Общая тема интерфейса. Палитра — тёплая приглушённая (референсы 2, 8): тёмное дерево, крем, персик.
## Цвета держим здесь, чтобы не разбрасывать по экранам.

const BG := Color("1d1a1f")
const PANEL := Color("29242b")
const PANEL_LIGHT := Color("352f37")
const TEXT := Color("f3ece4")
const TEXT_DIM := Color("b9aea6")
const ACCENT := Color("e8a87c")      # персиковый
const ACCENT_2 := Color("3fbfae")    # бирюза Кота
const OK := Color("8fd19e")
const WARN := Color("f2c66d")
const BAD := Color("ee7d7d")
const RARITY := {
	"common": Color("c9c2bb"), "uncommon": Color("8fd19e"), "rare": Color("7fb2f0"),
	"epic": Color("c99af0"), "legendary": Color("f2c66d"),
}

const FONT_SIZE := 18
const FONT_SIZE_SMALL := 15
const FONT_SIZE_TITLE := 26
const TOUCH_MIN := 44   # минимальная высота интерактивного элемента


static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = FONT_SIZE
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", BG)
	t.set_color("font_disabled_color", "Button", TEXT_DIM.darkened(0.3))
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)
	t.set_color("font_color", "OptionButton", TEXT)
	t.set_color("font_color", "TabContainer", TEXT_DIM)
	t.set_color("font_selected_color", "TabContainer", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)

	t.set_stylebox("panel", "PanelContainer", box(PANEL, 14))
	t.set_stylebox("panel", "Panel", box(PANEL, 14))
	t.set_stylebox("normal", "Button", box(PANEL_LIGHT, 10, 10))
	t.set_stylebox("hover", "Button", box(PANEL_LIGHT.lightened(0.12), 10, 10))
	t.set_stylebox("pressed", "Button", box(ACCENT, 10, 10))
	t.set_stylebox("disabled", "Button", box(PANEL_LIGHT.darkened(0.25), 10, 10))
	t.set_stylebox("focus", "Button", outline(ACCENT_2, 10))
	t.set_stylebox("normal", "LineEdit", box(BG, 10, 10))
	t.set_stylebox("focus", "LineEdit", outline(ACCENT_2, 10))
	t.set_stylebox("normal", "OptionButton", box(PANEL_LIGHT, 10, 10))
	t.set_stylebox("hover", "OptionButton", box(PANEL_LIGHT.lightened(0.12), 10, 10))
	t.set_stylebox("pressed", "OptionButton", box(PANEL_LIGHT.lightened(0.12), 10, 10))
	t.set_stylebox("panel", "TabContainer", box(PANEL, 14))
	t.set_stylebox("tab_selected", "TabContainer", box(PANEL_LIGHT, 10, 12))
	t.set_stylebox("tab_unselected", "TabContainer", box(BG, 10, 12))
	t.set_stylebox("tab_hovered", "TabContainer", box(PANEL_LIGHT.darkened(0.1), 10, 12))
	t.set_stylebox("panel", "PopupPanel", box(PANEL, 14))
	t.set_stylebox("panel", "AcceptDialog", box(PANEL, 14))
	t.set_constant("separation", "VBoxContainer", 8)
	t.set_constant("separation", "HBoxContainer", 8)
	return t


static func box(c: Color, radius := 12, pad := 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	return s


static func outline(c: Color, radius := 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center = false
	s.border_color = c
	s.set_border_width_all(2)
	s.set_corner_radius_all(radius)
	return s


static func label(text: String, size := FONT_SIZE, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Переносимый текст без растяжения в горизонтальном ряду получает нулевую ширину
	# и переносится по буквам — поэтому по умолчанию растягиваем.
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = TOUCH_MIN
	b.pressed.connect(cb)
	return b
