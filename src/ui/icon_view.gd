class_name IconView
extends Control
## Control, рисующий иконку из Icons. Квадратная область по центру своего прямоугольника.

@export var icon := "":
	set(v):
		icon = v
		queue_redraw()
@export var color := UiTheme.TEXT:
	set(v):
		color = v
		queue_redraw()
@export var outline := Color.TRANSPARENT:
	set(v):
		outline = v
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var side := minf(size.x, size.y)
	var r := Rect2((size - Vector2(side, side)) / 2.0, Vector2(side, side))
	Icons.draw(self, icon, r, color, outline)
