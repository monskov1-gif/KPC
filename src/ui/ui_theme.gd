class_name UiTheme
extends RefCounted
## Дизайн-система интерфейса: мягкая, «облачная», светлая.
## Тёплый кремово-розовый фон, полупрозрачные молочные панели, мягкие тени, золото для главных действий,
## мята — цвет Кота — для выбранного. Все экраны берут цвета и стили только отсюда.

const BG_TOP := Color("f8ede8")
const BG_BOTTOM := Color("ead6d4")
const ARCH := Color(1, 1, 1, 0.35)
const PANEL := Color(1, 0.99, 0.98, 0.78)       # молочное «облако»
const PANEL_SOLID := Color("fffaf6")
const CARD := Color("fbf3ee")
const CARD_EDGE := Color("ead8d0")
const TEXT := Color("6e5660")                    # мягкий сливово-коричневый вместо чёрного
const TEXT_DIM := Color("8f7882")
const GOLD := Color("d8b36e")
const GOLD_LIGHT := Color("f0d9a4")
const MINT := Color("86cfc0")
const PINK := Color("efb3c2")
const OK := Color("72bf93")
const WARN := Color("e3ad55")
const BAD := Color("e48a8a")
const SHADOW := Color(0.45, 0.25, 0.3, 0.14)
const STAR := Color("e8b94f")

# Совместимость со старыми именами.
const ACCENT := GOLD
const ACCENT_2 := MINT
const BG := BG_BOTTOM
const PANEL_LIGHT := CARD

const FONT_SIZE := 18
const FONT_SIZE_SMALL := 15
const FONT_SIZE_TITLE := 26
const TOUCH_MIN := 44
const RADIUS := 22


static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = FONT_SIZE
	for type in ["Label", "Button", "CheckBox", "LineEdit", "OptionButton", "PopupMenu"]:
		t.set_color("font_color", type, TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", TEXT)
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", TEXT_DIM)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)
	t.set_color("caret_color", "LineEdit", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)

	t.set_stylebox("panel", "PanelContainer", cloud())
	t.set_stylebox("normal", "Button", pill(PANEL_SOLID))
	t.set_stylebox("hover", "Button", pill(Color.WHITE))
	t.set_stylebox("pressed", "Button", pill(GOLD_LIGHT))
	t.set_stylebox("disabled", "Button", pill(Color(1, 1, 1, 0.4)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("normal", "LineEdit", pill(PANEL_SOLID))
	t.set_stylebox("focus", "LineEdit", pill_outline(MINT))
	t.set_stylebox("normal", "OptionButton", pill(PANEL_SOLID))
	t.set_stylebox("hover", "OptionButton", pill(Color.WHITE))
	t.set_stylebox("pressed", "OptionButton", pill(Color.WHITE))
	t.set_stylebox("panel", "PopupMenu", cloud(PANEL_SOLID))
	t.set_color("font_hover_color", "PopupMenu", TEXT)
	t.set_stylebox("hover", "PopupMenu", pill(GOLD_LIGHT))
	t.set_stylebox("panel", "PopupPanel", cloud(PANEL_SOLID))
	t.set_stylebox("panel", "AcceptDialog", cloud(PANEL_SOLID))
	var grabber := pill(Color(TEXT_DIM, 0.5), 6)
	t.set_stylebox("grabber", "VScrollBar", grabber)
	t.set_stylebox("grabber_highlight", "VScrollBar", grabber)
	t.set_stylebox("grabber_pressed", "VScrollBar", grabber)
	t.set_stylebox("scroll", "VScrollBar", StyleBoxEmpty.new())
	t.set_constant("separation", "VBoxContainer", 8)
	t.set_constant("separation", "HBoxContainer", 8)
	return t


## Молочная панель с мягкой тенью.
static func cloud(c: Color = PANEL, radius := RADIUS, pad := 16) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	s.shadow_color = SHADOW
	s.shadow_size = 14
	s.shadow_offset = Vector2(0, 4)
	s.anti_aliasing = true
	return s


static func pill(c: Color, pad := 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(999)
	s.content_margin_left = pad + 6
	s.content_margin_right = pad + 6
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	s.anti_aliasing = true
	return s


static func pill_outline(c: Color) -> StyleBoxFlat:
	var s := pill(PANEL_SOLID)
	s.border_color = c
	s.set_border_width_all(2)
	return s


## Совместимость: прямоугольная плашка с радиусом.
static func box(c: Color, radius := 12, pad := 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	s.anti_aliasing = true
	return s


static func label(text: String, size := FONT_SIZE, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Переносимый текст без растяжения в горизонтальном ряду получает нулевую ширину — растягиваем.
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## Короткая подпись в одну строку, не растягивается.
static func tag(text: String, size := FONT_SIZE_SMALL, color := TEXT) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.size_flags_horizontal = Control.SIZE_FILL
	return l


static func button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = TOUCH_MIN
	b.pressed.connect(cb)
	return b


## Главная кнопка: золотая «таблетка» (как «Сохранить» в референсе).
static func primary(b: Button) -> Button:
	var g := pill(GOLD, 14)
	g.shadow_color = SHADOW
	g.shadow_size = 10
	g.shadow_offset = Vector2(0, 3)
	b.add_theme_stylebox_override("normal", g)
	var gh := g.duplicate(); gh.bg_color = GOLD.lightened(0.1)
	b.add_theme_stylebox_override("hover", gh)
	var gp := g.duplicate(); gp.bg_color = GOLD.darkened(0.08)
	b.add_theme_stylebox_override("pressed", gp)
	var gd := g.duplicate(); gd.bg_color = Color(GOLD, 0.45)
	b.add_theme_stylebox_override("disabled", gd)
	# Тёмный текст на золоте: белый давал контраст ниже 2:1.
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, Color("4f3a42"))
	b.add_theme_color_override("font_disabled_color", Color("4f3a42", 0.55))
	b.add_theme_font_size_override("font_size", 22)
	return b


## Вторая по важности «таблетка» (мятная), чтобы на экране была одна золотая.
static func secondary(b: Button) -> Button:
	primary(b)
	for st_name in ["normal", "hover", "pressed", "disabled"]:
		var st: StyleBoxFlat = b.get_theme_stylebox(st_name).duplicate()
		st.bg_color = MINT if st_name == "normal" else (MINT.lightened(0.1) if st_name == "hover" else
			(MINT.darkened(0.08) if st_name == "pressed" else Color(MINT, 0.45)))
		b.add_theme_stylebox_override(st_name, st)
	return b


## Круглая кнопка с нарисованной иконкой.
static func icon_button(icon: String, cb: Callable, size := 52.0, tint := TEXT, bg := PANEL_SOLID) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(size, size)
	var st := pill(bg, 0)
	st.shadow_color = SHADOW
	st.shadow_size = 8
	st.shadow_offset = Vector2(0, 2)
	b.add_theme_stylebox_override("normal", st)
	var sh := st.duplicate(); sh.bg_color = Color.WHITE
	b.add_theme_stylebox_override("hover", sh)
	var sp := st.duplicate(); sp.bg_color = GOLD_LIGHT
	b.add_theme_stylebox_override("pressed", sp)
	var iv := IconView.new()
	iv.icon = icon
	iv.color = tint
	iv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var m := size * 0.24
	iv.offset_left = m; iv.offset_top = m; iv.offset_right = -m; iv.offset_bottom = -m
	iv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(iv)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


static func icon(name: String, size := 24.0, color := TEXT) -> IconView:
	var iv := IconView.new()
	iv.icon = name
	iv.color = color
	iv.custom_minimum_size = Vector2(size, size)
	iv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return iv


## Число звёзд по редкости (common = 1 … legendary = 5).
static func stars_for(rarity: String, rarities: Array) -> int:
	return clampi(rarities.find(rarity) + 1, 1, 5)


static func rank_color(rank: String) -> Color:
	match rank:
		"S", "A": return OK
		"B": return GOLD
		"C": return WARN
	return BAD
