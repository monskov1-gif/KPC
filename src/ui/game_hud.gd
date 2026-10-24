class_name GameHud
extends Control
## Игровой интерфейс исследования (просьба пользователя 24.10): слева сверху — профиль игрока (аватар, имя,
## уровень), справа сверху — разделы (события, молитвы, гардероб, сумка) и валюта, под ними — мини-карта;
## справа снизу — кнопки действий: удар (комбо), прыжок, рывок, снимок. На кнопках — кольцо перезарядки,
## на ПК — клавиша. Красная точка — есть что забрать (награда события, ежедневный подарок).
## Логики здесь нет: кнопки шлют сигналы, StoryGame открывает окна и вызывает действия игрока.

signal nav(kind: String)             # profile, events, gacha, wardrobe, inventory
signal action(kind: String)          # attack, jump, dodge, photo

const NAV := [
	["events", "calendar", "События"],
	["gacha", "gacha", "Молитвы"],
	["wardrobe", "hanger", "Гардероб"],
	["inventory", "bag", "Сумка"],
]
const ACTIONS := {
	# вид: [иконка, диаметр, отступ справа, отступ снизу, клавиша]
	"attack": ["sword", 104.0, 30.0, 34.0, "F"],
	"jump": ["jump", 72.0, 152.0, 30.0, "Space"],
	"dodge": ["dodge", 72.0, 46.0, 158.0, "Q"],
	"photo": ["camera", 62.0, 150.0, 132.0, "P"],
}

var player: StoryPlayer
var minimap: MiniMap
var touch := false
var _avatar: AvatarView
var _name: Label
var _level: Label
var _xp: ProgressBar
var _tickets: Label
var _coins: Label
var _badges := {}
var _buttons := {}
var _rings := {}
var _nav_row: HBoxContainer
var _money_row: HBoxContainer
var _profile: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_profile()
	_build_nav()
	minimap = MiniMap.new()
	minimap.name = "MiniMap"
	add_child(minimap)
	_build_actions()
	var s := Game.session
	if s:
		s.resources.changed.connect(refresh)
	resized.connect(_layout)
	refresh()
	_layout.call_deferred()


# ---------- построение ----------

func _build_profile() -> void:
	_profile = Button.new()
	_profile.name = "Profile"
	_profile.flat = true
	_profile.focus_mode = Control.FOCUS_NONE
	var st := UiTheme.cloud(Color(1, 0.99, 0.97, 0.9), 999, 6)
	st.content_margin_left = 6; st.content_margin_right = 18
	_profile.add_theme_stylebox_override("normal", st)
	_profile.add_theme_stylebox_override("hover", st)
	_profile.add_theme_stylebox_override("pressed", st)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_avatar = AvatarView.new()
	_avatar.custom_minimum_size = Vector2(56, 56)
	h.add_child(_avatar)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name = UiTheme.tag("", 17, UiTheme.TEXT)
	v.add_child(_name)
	var lr := HBoxContainer.new()
	lr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level = UiTheme.tag("", 14, UiTheme.GOLD_DEEP)
	lr.add_child(_level)
	_xp = ProgressBar.new()
	_xp.show_percentage = false
	_xp.custom_minimum_size = Vector2(96, 8)
	_xp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_xp.add_theme_stylebox_override("background", UiTheme.box(Color(0.9, 0.84, 0.82, 0.7), 4, 0))
	_xp.add_theme_stylebox_override("fill", UiTheme.box(UiTheme.GOLD, 4, 0))
	_xp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lr.add_child(_xp)
	v.add_child(lr)
	h.add_child(v)
	_profile.add_child(h)
	h.position = Vector2(6, 4)
	_profile.custom_minimum_size = Vector2(230, 64)
	_profile.pressed.connect(_emit_nav.bind("profile"))
	add_child(_profile)


func _build_nav() -> void:
	_nav_row = HBoxContainer.new()
	_nav_row.name = "Nav"
	_nav_row.add_theme_constant_override("separation", 10)
	for n in NAV:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		var b := UiTheme.icon_button(n[1], _emit_nav.bind(n[0]), 56)
		b.name = n[0]
		b.tooltip_text = n[2]
		b.focus_mode = Control.FOCUS_NONE
		col.add_child(b)
		var badge := Panel.new()
		badge.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.BAD, 999, 0))
		badge.custom_minimum_size = Vector2(14, 14)
		badge.position = Vector2(40, 2)
		badge.size = Vector2(14, 14)
		badge.visible = false
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(badge)
		_badges[n[0]] = badge
		var l := UiTheme.tag(n[2], 13, UiTheme.TEXT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.85))
		l.add_theme_constant_override("outline_size", 5)
		col.add_child(l)
		_nav_row.add_child(col)
	add_child(_nav_row)
	_money_row = HBoxContainer.new()
	_money_row.name = "Money"
	_money_row.add_theme_constant_override("separation", 8)
	_tickets = _money_chip("ticket", Color("b58be0"), "gacha")
	_coins = _money_chip("coin", UiTheme.GOLD, "inventory")
	add_child(_money_row)


func _money_chip(icon: String, tint: Color, open: String) -> Label:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	var st := UiTheme.cloud(Color(1, 0.99, 0.97, 0.88), 999, 4)
	st.content_margin_left = 8; st.content_margin_right = 14
	b.add_theme_stylebox_override("normal", st)
	b.add_theme_stylebox_override("hover", st)
	b.add_theme_stylebox_override("pressed", st)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(UiTheme.icon(icon, 22, tint))
	var l := UiTheme.tag("0", 16, UiTheme.TEXT)
	h.add_child(l)
	b.add_child(h)
	h.position = Vector2(8, 4)
	b.custom_minimum_size = Vector2(108, 34)
	b.pressed.connect(_emit_nav.bind(open))
	_money_row.add_child(b)
	return l


func _build_actions() -> void:
	for kind in ACTIONS:
		var a: Array = ACTIONS[kind]
		var d: float = a[1]
		var b := UiTheme.icon_button(a[0], _emit_action.bind(kind), d, UiTheme.GOLD_DEEP if kind != "attack" else Color("c0607a"))
		b.name = kind
		b.focus_mode = Control.FOCUS_NONE
		b.anchor_left = 1.0; b.anchor_right = 1.0; b.anchor_top = 1.0; b.anchor_bottom = 1.0
		b.offset_right = -a[2]; b.offset_left = -a[2] - d
		b.offset_bottom = -a[3]; b.offset_top = -a[3] - d
		var ring := Control.new()
		ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.draw.connect(_draw_ring.bind(ring, kind))
		b.add_child(ring)
		_rings[kind] = ring
		var key := PanelContainer.new()
		key.name = "Key"
		key.add_theme_stylebox_override("panel", UiTheme.pill(Color(1, 1, 1, 0.85), 3))
		key.add_child(UiTheme.tag(a[4], 12, UiTheme.TEXT_DIM))
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(key)
		key.position = Vector2(d * 0.5 - 14, d - 8)
		_buttons[kind] = b
		add_child(b)


func _draw_ring(ring: Control, kind: String) -> void:
	if player == null:
		return
	var k := player.cooldown(kind)
	var c := ring.size * 0.5
	var r := minf(ring.size.x, ring.size.y) * 0.5 - 3.0
	if k > 0.0:
		ring.draw_arc(c, r, -PI / 2, -PI / 2 + TAU * k, 32, Color(0.45, 0.3, 0.4, 0.55), 6.0, true)
	if kind == "attack" and player.combo() > 0:
		for i in player.combo():                       # точки комбо под кнопкой
			ring.draw_circle(c + Vector2((i - 1) * 12.0, r * 0.62), 3.5, UiTheme.GOLD)


# ---------- данные ----------

func refresh() -> void:
	var s := Game.session
	if s == null:
		return
	var lv := PlayerProfile.level_of(PlayerProfile.xp_from(s.profile_stats()))
	_name.text = s.profile.display_name()
	_level.text = "Ур. %d" % lv.level
	_xp.value = lv.progress * 100.0
	_tickets.text = str(s.resources.amount(s.gacha.currency))
	_coins.text = str(s.resources.amount("coins"))
	var hero := player.model.character_id if player and player.model else "kot"
	if s.characters.has_character(hero):
		_avatar.hair = s.characters.placeholder_color(hero)
	_avatar.cat_ears = hero.begins_with("kot")
	_avatar.queue_redraw()
	var day := EventService.today()
	var claim := false
	for e in s.events.all_events():
		var cleared := bool(s.rewards.result(str(e.get("challenge_id", ""))).get("cleared", false))
		claim = claim or s.events.can_claim(e, day, cleared)
	_badges["events"].visible = claim
	_badges["gacha"].visible = s.resources.amount(s.gacha.currency) >= 10


func _process(_delta: float) -> void:
	if not visible:
		return
	for kind in _rings:
		(_rings[kind] as Control).queue_redraw()


func _emit_nav(kind: String) -> void:
	Audio.ui("tap")
	nav.emit(kind)


func _emit_action(kind: String) -> void:
	action.emit(kind)


## Подсказки клавиш — только без сенсорного экрана.
func set_touch(on: bool) -> void:
	touch = on
	for kind in _buttons:
		(_buttons[kind] as Control).get_node("Key").visible = not on


## Кнопки действий прячутся, когда герой не управляется (катсцена) — HUD целиком прячет StoryOverlay.
func _layout() -> void:
	var narrow := size.x < 900.0
	_profile.position = Vector2(20, 16)
	var nav_w := _nav_row.get_combined_minimum_size()
	_nav_row.position = Vector2(size.x - nav_w.x - 96, 14)
	for col in _nav_row.get_children():
		(col.get_child(1) as Control).visible = not narrow
	var mw := _money_row.get_combined_minimum_size()
	var mm := 150.0 if narrow else 176.0
	if narrow:
		# телефон: валюта под профилем, мини-карта под разделами
		_money_row.position = Vector2(20, 88)
		minimap.position = Vector2(size.x - mm - 20, 14 + nav_w.y + 8)
	else:
		_money_row.position = Vector2(size.x - mw.x - 24, 14 + nav_w.y + 6)
		minimap.position = Vector2(size.x - mm - 24, _money_row.position.y + mw.y + 10)
	minimap.size = Vector2(mm, mm)


## Место под цель и подсказки слева сверху (StoryOverlay ставит туда «текущую цель»).
func objective_y() -> float:
	return (_money_row.position.y + 44.0) if size.x < 900.0 else 92.0
