class_name VirtualStick
extends Control
## Экранный стик для сенсорного управления: левая нижняя четверть экрана, круг появляется под пальцем.
## value — направление (x вправо, y вперёд), длина 0..1.

const RADIUS := 70.0

var value := Vector2.ZERO
var _finger := -1
var _origin := Vector2.ZERO
var _pos := Vector2.ZERO


func _ready() -> void:
	anchor_top = 0.45
	anchor_right = 0.45
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_PASS
	_origin = Vector2(150, size.y - 150)


func reset() -> void:
	_finger = -1
	value = Vector2.ZERO
	queue_redraw()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed and _finger == -1:
			_finger = e.index
			_origin = e.position
			_pos = e.position
		elif not e.pressed and e.index == _finger:
			reset()
		accept_event()
	elif e is InputEventScreenDrag and e.index == _finger:
		_pos = e.position
		var d := (_pos - _origin).limit_length(RADIUS)
		value = Vector2(d.x, -d.y) / RADIUS
		accept_event()
	queue_redraw()


func _draw() -> void:
	var o := _origin if _finger != -1 else Vector2(150, size.y - 150)
	draw_circle(o, RADIUS, Color(1, 1, 1, 0.22))
	draw_arc(o, RADIUS, 0, TAU, 48, Color(UiTheme.GOLD, 0.7), 3.0, true)
	var k := o + Vector2(value.x, -value.y) * RADIUS
	draw_circle(k, 30, Color(1, 0.98, 0.95, 0.85))
	draw_arc(k, 30, 0, TAU, 32, UiTheme.GOLD, 2.5, true)
