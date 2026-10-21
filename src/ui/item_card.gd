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


func _draw() -> void:
	var r := Rect2(Vector2(3, 3), size - Vector2(6, 6))
	var bg := UiTheme.CARD
	if worn:
		bg = Color("fdf6e6")
	elif _hover:
		bg = Color.WHITE
	var sb := UiTheme.cloud(bg, 16, 0)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 2)
	if worn or selected:
		sb.border_color = UiTheme.GOLD if worn else UiTheme.MINT
		sb.set_border_width_all(3)
	draw_style_box(sb, r)

	# Миниатюра: силуэт слота в цвете вещи (PLACEHOLDER до рендеров вещей).
	var thumb := Rect2(r.position + Vector2(r.size.x * 0.17, r.size.y * 0.2), Vector2(r.size.x * 0.66, r.size.x * 0.66))
	var col := item.placeholder_color
	Icons.draw(self, item.slot, thumb, col, col.darkened(0.35).lerp(UiTheme.TEXT_DIM, 0.3))

	# Звёзды редкости — в правом верхнем углу.
	var s := 12.0
	for i in stars:
		var p := Vector2(r.end.x - 10 - (i + 1) * (s + 1), r.position.y + 8)
		Icons.draw(self, "star", Rect2(p, Vector2(s, s)), UiTheme.STAR)

	if worn:
		var c := r.position + Vector2(18, 18)
		draw_circle(c, 12, UiTheme.GOLD)
		Icons.draw(self, "check", Rect2(c - Vector2(8, 8), Vector2(16, 16)), Color.WHITE)
	elif is_new:
		draw_circle(r.position + Vector2(14, 14), 6, UiTheme.PINK.darkened(0.1))
	if locked:
		draw_style_box(UiTheme.cloud(Color(1, 1, 1, 0.55), 16, 0), r)
		var lc := r.get_center() + Vector2(0, 6)
		draw_circle(lc, 18, Color(UiTheme.TEXT_DIM, 0.85))
		Icons.draw(self, "lock", Rect2(lc - Vector2(11, 12), Vector2(22, 22)), Color.WHITE)
	if _press_time >= 0.0:
		draw_style_box(UiTheme.cloud(Color(UiTheme.GOLD_LIGHT, 0.35), 16, 0), r)
