class_name ItemCard
extends Control
## Карточка вещи в сетке гардероба: миниатюра-силуэт, звёзды редкости, отметки «надето» / «новое» / замок.
## Короткое нажатие — надеть или снять; долгое нажатие (или правая кнопка мыши) — характеристики.

signal tapped(item_id: String)
signal long_pressed(item_id: String)

const LONG_PRESS_SEC := 0.45
const MOVE_TOLERANCE := 14.0

var item: ClothingItem
var stars := 1
var worn := false
var is_new := false
var locked := false        # несовместима с текущим персонажем
var selected := false

var _press_time := -1.0
var _press_pos := Vector2.ZERO
var _long_fired := false
var _hover := false


func _ready() -> void:
	custom_minimum_size = Vector2(112, 128)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func(): _hover = true; queue_redraw())
	mouse_exited.connect(func(): _hover = false; _press_time = -1.0; queue_redraw())
	tooltip_text = tr(item.name_key) if item else ""


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		long_pressed.emit(item.id)
		accept_event()
		return
	var pressed := false
	var released := false
	var pos := Vector2.ZERO
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pressed = event.pressed
		released = not event.pressed
		pos = event.position
	elif event is InputEventScreenTouch:
		pressed = event.pressed
		released = not event.pressed
		pos = event.position
	elif (event is InputEventMouseMotion or event is InputEventScreenDrag) and _press_time >= 0.0:
		# Прокрутка списка пальцем отменяет нажатие.
		if event.position.distance_to(_press_pos) > MOVE_TOLERANCE:
			_press_time = -1.0
		return
	if pressed:
		_press_time = Time.get_ticks_msec() / 1000.0
		_press_pos = pos
		_long_fired = false
		queue_redraw()
	elif released and _press_time >= 0.0:
		_press_time = -1.0
		if not _long_fired:
			tapped.emit(item.id)
		queue_redraw()


func _process(_delta: float) -> void:
	if _press_time >= 0.0 and not _long_fired and Time.get_ticks_msec() / 1000.0 - _press_time >= LONG_PRESS_SEC:
		_long_fired = true
		_press_time = -1.0
		long_pressed.emit(item.id)
		queue_redraw()


static var _icons := {}


static func _icon(id: String) -> Texture2D:
	if not _icons.has(id):
		var path := "res://art/items/%s.png" % id
		_icons[id] = load(path) if ResourceLoader.exists(path) else null
	return _icons[id]


func _draw() -> void:
	# Подложка — текстура карточки по редкости (art/ui/card_rN.png); надетая — со свечением.
	var r := Rect2(Vector2.ZERO, size)
	if worn or selected:
		var pad := size.x * 12.0 / 128.0
		draw_texture_rect(UiTheme.tex("card_r%d_sel.png" % stars), Rect2(-Vector2(pad, pad), size + Vector2(pad, pad) * 2), false)
	else:
		draw_texture_rect(UiTheme.tex("card_r%d.png" % stars), r, false,
			Color(1.06, 1.06, 1.06) if _hover else Color.WHITE)

	# Миниатюра: рендер самой вещи из её 3D-меша (tools/render_icons.sh → art/items/<id>.png);
	# если рендера нет — силуэт слота в цвете вещи.
	var side := r.size.x * 0.62
	var thumb := Rect2(Vector2((r.size.x - side) / 2.0, r.size.y * 0.2), Vector2(side, side))
	var icon := _icon(item.id)
	if icon:
		var big := Rect2(Vector2(r.size.x * 0.1, r.size.y * 0.12), Vector2(r.size.x * 0.8, r.size.x * 0.8))
		draw_texture_rect(icon, big, false)
	else:
		var col := item.placeholder_color
		Icons.draw(self, item.slot, thumb.grow(1.5), Color(0.35, 0.2, 0.25, 0.18))
		Icons.draw(self, item.slot, thumb, col, col.darkened(0.4).lerp(UiTheme.TEXT_DIM, 0.25))

	# Звёзды редкости — золотые с тёмным контуром, в правом верхнем углу.
	var s := r.size.x * 0.12
	for i in stars:
		var p := Vector2(r.end.x - r.size.x * 0.07 - (i + 1) * (s + 1), r.position.y + r.size.y * 0.05)
		Icons.draw(self, "star", Rect2(p - Vector2(1.2, 1.2), Vector2(s + 2.4, s + 2.4)), Color("a4732c"))
		Icons.draw(self, "star", Rect2(p, Vector2(s, s)), UiTheme.STAR)

	if worn:
		var c := Vector2(r.size.x * 0.16, r.size.y * 0.13)
		draw_circle(c, r.size.x * 0.1 + 2, Color("a4732c"))
		draw_circle(c, r.size.x * 0.1, UiTheme.GOLD)
		var ic := r.size.x * 0.13
		Icons.draw(self, "check", Rect2(c - Vector2(ic, ic) / 2.0, Vector2(ic, ic)), Color.WHITE)
	elif is_new:
		var c2 := Vector2(r.size.x * 0.13, r.size.y * 0.1)
		Icons.draw(self, "sparkle", Rect2(c2 - Vector2(9, 9), Vector2(18, 18)), Color("e88aa6"))
	if locked:
		draw_rect(r.grow(-4), Color(1, 1, 1, 0.45))
		var lc := r.get_center() + Vector2(0, 4)
		draw_circle(lc, 18, Color(UiTheme.TEXT_DIM, 0.9))
		Icons.draw(self, "lock", Rect2(lc - Vector2(11, 12), Vector2(22, 22)), Color.WHITE)
	if _press_time >= 0.0:
		draw_rect(r.grow(-4), Color(UiTheme.GOLD_LIGHT, 0.3))
