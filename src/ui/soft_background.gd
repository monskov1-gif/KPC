class_name SoftBackground
extends Control
## Мягкий фон гардероба: вертикальный градиент, полупрозрачные арки и «облачные» пятна света.
## Рисуется кодом, поэтому подстраивается под любое соотношение сторон.

## Сколько арок по ширине; 0 — без арок (для всплывающих окон).
@export var arches := 3


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var w := size.x
	var h := size.y
	var bands := 24
	for i in bands:
		var t := float(i) / bands
		draw_rect(Rect2(0, h * t, w, h / bands + 1), UiTheme.BG_TOP.lerp(UiTheme.BG_BOTTOM, t))
	if arches > 0:
		var aw := w / arches
		for i in arches:
			var cx := aw * (i + 0.5)
			var half := aw * 0.32
			var top := h * 0.16
			var pts := PackedVector2Array()
			pts.append(Vector2(cx - half, h))
			for k in 33:
				var a := PI + PI * k / 32.0
				pts.append(Vector2(cx + cos(a) * half, top + half + sin(a) * half))
			pts.append(Vector2(cx + half, h))
			draw_colored_polygon(pts, UiTheme.ARCH)
	# Облачные блики.
	for b in [[0.18, 0.22, 0.16], [0.82, 0.12, 0.12], [0.6, 0.78, 0.2], [0.3, 0.9, 0.14]]:
		var c := Vector2(w * b[0], h * b[1])
		var rad: float = minf(w, h) * b[2]
		for k in 6:
			draw_circle(c, rad * (1.0 - k * 0.15), Color(1, 1, 1, 0.05))
	# Круглый подиум под персонажем рисует сам экран (он знает, где персонаж).
