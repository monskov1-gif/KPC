class_name AvatarView
extends Control
## Круглый аватар персонажа для переключателя: кружок с цветом волос и лицом (PLACEHOLDER до портретов).

var hair := Color.GRAY
var cat_ears := false
var active := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var side := minf(size.x, size.y)
	var c := size / 2.0
	var rad := side * 0.5 - 3
	draw_circle(c, rad + 3, UiTheme.GOLD if active else Color(1, 1, 1, 0.9))
	draw_circle(c, rad, UiTheme.CARD)
	var skin := Color("f6dfd3")
	if cat_ears:
		for sx in [-1, 1]:
			draw_colored_polygon(PackedVector2Array([c + Vector2(sx * rad * 0.62, -rad * 0.25),
				c + Vector2(sx * rad * 0.48, -rad * 0.86), c + Vector2(sx * rad * 0.18, -rad * 0.45)]), hair)
	draw_circle(c + Vector2(0, rad * 0.12), rad * 0.52, skin)
	# Причёска: шапка волос + чёлка.
	draw_arc(c + Vector2(0, rad * 0.05), rad * 0.56, PI * 1.05, PI * 1.95, 24, hair, rad * 0.28, true)
	draw_circle(c + Vector2(-rad * 0.18, -rad * 0.2), rad * 0.22, hair)
	# Глаза.
	for sx in [-1, 1]:
		draw_circle(c + Vector2(sx * rad * 0.2, rad * 0.16), rad * 0.06, UiTheme.TEXT)
