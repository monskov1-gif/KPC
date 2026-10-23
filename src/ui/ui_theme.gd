class_name UiTheme
extends RefCounted
## Дизайн-система игрового интерфейса KPC.
## Не «веб-кнопки»: панели, кнопки, медальоны и карточки — это текстуры с золотой окантовкой и орнаментом
## (art/ui/, генерируются tools/art/gen_ui.py). Ориентир — art/references/ui/ui_03 (гардероб Infinity Nikki).
## Все экраны берут цвета, шрифты и стили только отсюда.

const UI_DIR := "res://art/ui/"

const BG_TOP := Color("f8ede8")
const BG_BOTTOM := Color("ead6d4")
const ARCH := Color(1, 1, 1, 0.35)
const PANEL := Color(1, 0.99, 0.98, 0.78)
const PANEL_SOLID := Color("fffaf6")
const CARD := Color("fbf3ee")
const CARD_EDGE := Color("ead8d0")
const TEXT := Color("5e4650")                    # тёмный сливовый на светлых панелях
const TEXT_DIM := Color("8a7179")
const TEXT_LIGHT := Color("fff6ee")              # текст на тёмном стекле и золоте
const GOLD := Color("d8b36e")
const GOLD_DEEP := Color("9c6c36")
const GOLD_LIGHT := Color("f0d9a4")
const MINT := Color("86cfc0")
const PINK := Color("efb3c2")
const OK := Color("6fb98f")
const WARN := Color("dfa54c")
const BAD := Color("de8080")
const SHADOW := Color(0.4, 0.2, 0.25, 0.22)
const STAR := Color("f2c55c")

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

static var _body_font: Font
static var _title_font: Font
static var _cache := {}


static func body_font() -> Font:
	if _body_font == null:
		_body_font = load("res://art/fonts/Inter-Medium.otf")
	return _body_font


## Декоративный шрифт заголовков (с засечками).
static func title_font() -> Font:
	if _title_font == null:
		_title_font = load("res://art/fonts/LiberationSerif-Bold.ttf")
	return _title_font


static func tex(file: String) -> Texture2D:
	if not _cache.has(file):
		_cache[file] = load(UI_DIR + file)
	return _cache[file]


## Текстурная панель с 9-сегментной растяжкой: углы с орнаментом не искажаются.
static func nine(file: String, margin: float, pad: float = -1.0) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = tex(file)
	s.texture_margin_left = margin
	s.texture_margin_right = margin
	s.texture_margin_top = margin
	s.texture_margin_bottom = margin
	s.set_content_margin_all(pad if pad >= 0.0 else margin * 0.7)
	return s


static func build() -> Theme:
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = FONT_SIZE
	for type in ["Label", "Button", "CheckBox", "LineEdit", "OptionButton", "PopupMenu"]:
		t.set_color("font_color", type, TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", TEXT)
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", TEXT_DIM)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)
	t.set_color("caret_color", "LineEdit", TEXT)

	t.set_stylebox("panel", "PanelContainer", nine("panel_light.png", 44, 26))
	var rose := nine("button_rose.png", 30, 0)
	rose.texture_margin_top = 20; rose.texture_margin_bottom = 20
	rose.content_margin_left = 34; rose.content_margin_right = 34
	t.set_stylebox("normal", "Button", rose)
	t.set_stylebox("hover", "Button", rose)
	t.set_stylebox("pressed", "Button", rose)
	var rose_dis := rose.duplicate(); rose_dis.modulate_color = Color(1, 1, 1, 0.5)
	t.set_stylebox("disabled", "Button", rose_dis)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT_LIGHT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_outline_color", "Button", Color("7a4a56"))
	t.set_constant("outline_size", "Button", 4)
	t.set_stylebox("normal", "LineEdit", chip())
	t.set_stylebox("focus", "LineEdit", chip())
	var opt := chip()
	opt.content_margin_right = 34
	for st in ["normal", "hover", "pressed", "focus"]:
		t.set_stylebox(st, "OptionButton", opt)
	t.set_color("font_color", "OptionButton", TEXT)
	t.set_color("font_hover_color", "OptionButton", TEXT)
	t.set_color("font_pressed_color", "OptionButton", TEXT)
	t.set_constant("outline_size", "OptionButton", 0)
	t.set_stylebox("panel", "PopupMenu", nine("panel_light.png", 44, 18))
	t.set_color("font_hover_color", "PopupMenu", TEXT)
	t.set_stylebox("hover", "PopupMenu", pill(GOLD_LIGHT))
	t.set_stylebox("panel", "PopupPanel", nine("panel_light.png", 44, 18))
	var grabber := pill(Color(GOLD, 0.7), 6)
	t.set_stylebox("grabber", "VScrollBar", grabber)
	t.set_stylebox("grabber_highlight", "VScrollBar", grabber)
	t.set_stylebox("grabber_pressed", "VScrollBar", grabber)
	t.set_stylebox("scroll", "VScrollBar", StyleBoxEmpty.new())
	t.set_constant("separation", "VBoxContainer", 8)
	t.set_constant("separation", "HBoxContainer", 8)
	return t


## Небольшая плашка с золотым ободком (монеты, сортировка, поиск, подсказки).
static func chip() -> StyleBoxTexture:
	var s := nine("chip.png", 26, 0)
	s.content_margin_left = 18; s.content_margin_right = 22
	s.content_margin_top = 8; s.content_margin_bottom = 10
	return s


## Светлая панель с золотой рамкой и угловыми орнаментами.
static func panel_light() -> StyleBoxTexture:
	return nine("panel_light.png", 44, 26)


## Тёмное тёплое стекло (как боковые панели в референсе) — под светлые карточки.
static func panel_glass() -> StyleBoxTexture:
	return nine("panel_glass.png", 44, 22)


## Молочная плашка без орнамента: для мелких блоков внутри панелей.
static func cloud(c: Color = PANEL, radius := RADIUS, pad := 16) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	s.shadow_color = SHADOW
	s.shadow_size = 10
	s.shadow_offset = Vector2(0, 3)
	s.anti_aliasing = true
	s.border_color = Color(GOLD, 0.55)
	s.set_border_width_all(1 if c.a > 0.5 else 0)
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


## Декоративный заголовок (шрифт с засечками, мягкая тень).
static func title(text: String, size := 26, color := TEXT) -> Label:
	var l := tag(text, size, color)
	l.add_theme_font_override("font", title_font())
	l.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.6) if color.v < 0.5 else Color(0.35, 0.18, 0.22, 0.6))
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


static func button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 56
	b.pressed.connect(cb)
	return b


## Главная кнопка: золотой картуш с орнаментом на концах (как «Salvar» в референсе).
static func primary(b: Button) -> Button:
	var g := nine("button_gold.png", 30, 0)
	g.texture_margin_top = 20; g.texture_margin_bottom = 20
	g.content_margin_left = 40; g.content_margin_right = 40
	b.add_theme_stylebox_override("normal", g)
	b.add_theme_stylebox_override("hover", g)
	var gp := g.duplicate(); gp.modulate_color = Color(0.94, 0.9, 0.86)
	b.add_theme_stylebox_override("pressed", gp)
	var gd := g.duplicate(); gd.modulate_color = Color(1, 1, 1, 0.5)
	b.add_theme_stylebox_override("disabled", gd)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.75))
	b.add_theme_color_override("font_outline_color", GOLD_DEEP)
	b.add_theme_constant_override("outline_size", 6)
	b.add_theme_font_override("font", title_font())
	b.add_theme_font_size_override("font_size", 26)
	b.custom_minimum_size.y = 64
	return b


## Вторая по важности кнопка — розовый картуш.
static func secondary(b: Button) -> Button:
	b.add_theme_font_override("font", title_font())
	b.add_theme_font_size_override("font_size", 24)
	b.custom_minimum_size.y = 60
	return b


## Круглая кнопка: перламутровый круг в золотом ободке, с нарисованной иконкой.
static func icon_button(icon: String, cb: Callable, size := 52.0, tint := GOLD_DEEP, _bg := PANEL_SOLID) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(size, size)
	var n := StyleBoxTexture.new(); n.texture = tex("round.png")
	var s := StyleBoxTexture.new(); s.texture = tex("round_sel.png")
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", s)
	b.add_theme_stylebox_override("pressed", s)
	var d := n.duplicate(); d.modulate_color = Color(1, 1, 1, 0.5)
	b.add_theme_stylebox_override("disabled", d)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var iv := IconView.new()
	iv.icon = icon
	iv.color = tint
	b.add_child(iv)
	iv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var m := size * 0.3
	iv.offset_left = m; iv.offset_top = m; iv.offset_right = -m; iv.offset_bottom = -m
	iv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


## Медальон категории: тёмный круг в золотом ободке; выбранный — светлый со свечением.
static func medallion(icon: String, cb: Callable, size := 64.0) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(size, size)
	b.toggle_mode = true
	var n := StyleBoxTexture.new(); n.texture = tex("medallion.png")
	var s := StyleBoxTexture.new(); s.texture = tex("medallion_sel.png")
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", n)
	b.add_theme_stylebox_override("pressed", s)
	b.add_theme_stylebox_override("hover_pressed", s)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var iv := IconView.new()
	iv.icon = icon
	iv.color = TEXT_LIGHT
	b.add_child(iv)
	iv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var m := size * 0.31
	iv.offset_left = m; iv.offset_top = m; iv.offset_right = -m; iv.offset_bottom = -m
	b.toggled.connect(func(on): iv.color = GOLD_DEEP if on else TEXT_LIGHT)
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


## Лента-картуш под заголовком экрана.
static func ribbon_title(text: String, size := 26) -> Control:
	var p := PanelContainer.new()
	var st := nine("ribbon.png", 24, 0)
	st.texture_margin_top = 8; st.texture_margin_bottom = 8
	st.content_margin_left = 44; st.content_margin_right = 44
	st.content_margin_top = 8; st.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", st)
	p.add_child(title(text, size, TEXT_LIGHT))
	return p


## Орнаментальный разделитель.
static func divider() -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex("divider.png")
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(0, 16)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return r


## Золотая «жемчужина» — ручка ползунка (рисуется один раз и кэшируется).
static var _pearl_cache: Texture2D
static func _pearl(size: int) -> Texture2D:
	if _pearl_cache:
		return _pearl_cache
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c) / (size * 0.5)
			if d > 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var hl := clampf(1.0 - Vector2(x + 0.5, y + 0.5).distance_to(c - Vector2(size, size) * 0.16) / (size * 0.45), 0.0, 1.0)
			var col := GOLD.lerp(Color("fff6dc"), hl * 0.9)
			if d > 0.82:
				col = GOLD_DEEP.lerp(GOLD, (1.0 - d) / 0.18)
			col.a = clampf((1.0 - d) * size * 0.5, 0.0, 1.0)
			img.set_pixel(x, y, col)
	_pearl_cache = ImageTexture.create_from_image(img)
	return _pearl_cache


## Ползунок 0…1 в облачном стиле (громкость и т. п.): толстая мягкая дорожка, золотая заливка.
static func slider(value: float, cb: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.custom_minimum_size = Vector2(220, 36)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var track := pill(Color(PANEL_SOLID.darkened(0.08)), 0)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	var fill := pill(GOLD, 0)
	fill.content_margin_top = 5
	fill.content_margin_bottom = 5
	track.content_margin_top = 7
	track.content_margin_bottom = 7
	track.border_color = GOLD_LIGHT
	track.set_border_width_all(2)
	fill.content_margin_top = 7
	fill.content_margin_bottom = 7
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	var pearl := _pearl(30)
	s.add_theme_icon_override("grabber", pearl)
	s.add_theme_icon_override("grabber_highlight", pearl)
	s.value_changed.connect(cb)
	return s


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
