class_name Icons
extends RefCounted
## Векторные иконки интерфейса, нарисованные кодом (собственная графика проекта, без внешних лицензий).
## Координаты фигур заданы в единичном квадрате 0..1 и масштабируются под прямоугольник.
## Силуэты одежды используются и как иконки категорий, и как миниатюры вещей (PLACEHOLDER до появления рендеров).

const SHAPES := {
	"upper_body": [[0.30, 0.16], [0.42, 0.12], [0.50, 0.20], [0.58, 0.12], [0.70, 0.16], [0.92, 0.34], [0.80, 0.48],
		[0.72, 0.42], [0.72, 0.88], [0.28, 0.88], [0.28, 0.42], [0.20, 0.48], [0.08, 0.34]],
	"outerwear": [[0.28, 0.12], [0.42, 0.10], [0.50, 0.40], [0.58, 0.10], [0.72, 0.12], [0.94, 0.40], [0.94, 0.86],
		[0.80, 0.86], [0.78, 0.46], [0.76, 0.90], [0.24, 0.90], [0.22, 0.46], [0.20, 0.86], [0.06, 0.86], [0.06, 0.40]],
	"lower_body": [[0.26, 0.10], [0.74, 0.10], [0.80, 0.90], [0.58, 0.90], [0.50, 0.36], [0.42, 0.90], [0.20, 0.90]],
	"full_body": [[0.38, 0.08], [0.46, 0.14], [0.54, 0.14], [0.62, 0.08], [0.66, 0.30], [0.60, 0.40], [0.86, 0.90],
		[0.14, 0.90], [0.40, 0.40], [0.34, 0.30]],
	"footwear": [[0.14, 0.30], [0.36, 0.30], [0.40, 0.50], [0.62, 0.56], [0.86, 0.62], [0.90, 0.74], [0.88, 0.80],
		[0.14, 0.80]],
	"socks": [[0.34, 0.08], [0.62, 0.08], [0.62, 0.58], [0.84, 0.70], [0.86, 0.84], [0.74, 0.92], [0.40, 0.88],
		[0.34, 0.76]],
	"gloves": [[0.30, 0.90], [0.30, 0.46], [0.22, 0.30], [0.30, 0.24], [0.40, 0.36], [0.40, 0.14], [0.52, 0.10],
		[0.62, 0.14], [0.72, 0.24], [0.72, 0.90]],
	"headwear": [[0.30, 0.56], [0.32, 0.30], [0.44, 0.20], [0.56, 0.20], [0.68, 0.30], [0.70, 0.56], [0.92, 0.64],
		[0.88, 0.72], [0.12, 0.72], [0.08, 0.64]],
	"bag": [[0.16, 0.38], [0.84, 0.38], [0.80, 0.88], [0.20, 0.88]],
	"hair": [[0.50, 0.08], [0.72, 0.14], [0.84, 0.32], [0.86, 0.60], [0.80, 0.90], [0.66, 0.80], [0.66, 0.42],
		[0.50, 0.30], [0.34, 0.42], [0.34, 0.80], [0.20, 0.90], [0.14, 0.60], [0.16, 0.32], [0.28, 0.14]],
	"back_accessory": [[0.50, 0.40], [0.30, 0.14], [0.10, 0.20], [0.12, 0.50], [0.30, 0.70], [0.50, 0.56],
		[0.70, 0.70], [0.88, 0.50], [0.90, 0.20], [0.70, 0.14]],
	"trophy": [[0.24, 0.14], [0.76, 0.14], [0.72, 0.44], [0.58, 0.58], [0.56, 0.72], [0.70, 0.78], [0.70, 0.88],
		[0.30, 0.88], [0.30, 0.78], [0.44, 0.72], [0.42, 0.58], [0.28, 0.44]],
	"recipe": [[0.22, 0.10], [0.64, 0.10], [0.80, 0.26], [0.80, 0.90], [0.22, 0.90]],
	"fabric": [[0.12, 0.30], [0.70, 0.20], [0.88, 0.40], [0.88, 0.76], [0.30, 0.86], [0.12, 0.66]],
}


static func draw(ci: CanvasItem, name: String, r: Rect2, c: Color, outline := Color.TRANSPARENT) -> void:
	var w := r.size.x
	if SHAPES.has(name):
		var pts := _poly(SHAPES[name], r)
		ci.draw_colored_polygon(pts, c)
		if outline.a > 0.0:
			var closed := pts.duplicate()
			closed.append(pts[0])
			ci.draw_polyline(closed, outline, maxf(1.5, w * 0.035), true)
		_details(ci, name, r, c, outline)
		return
	var lw := maxf(2.0, w * 0.09)
	match name:
		"coin":
			ci.draw_circle(_p(r, 0.5, 0.5), w * 0.46, Color("e3b75c"))
			ci.draw_circle(_p(r, 0.5, 0.5), w * 0.36, Color("f4d68c"))
			_sparkle(ci, _p(r, 0.5, 0.5), w * 0.2, Color("e3b75c"))
		"star":
			ci.draw_colored_polygon(_star(_p(r, 0.5, 0.53), w * 0.5, w * 0.22), c)
		"star_empty":
			var s := _star(_p(r, 0.5, 0.53), w * 0.5, w * 0.22)
			s.append(s[0])
			ci.draw_polyline(s, c, maxf(1.5, w * 0.07), true)
		"sparkle":
			_sparkle(ci, _p(r, 0.5, 0.5), w * 0.5, c)
		"back":
			ci.draw_polyline(_poly([[0.62, 0.18], [0.30, 0.50], [0.62, 0.82]], r), c, lw, true)
		"check":
			ci.draw_polyline(_poly([[0.18, 0.52], [0.42, 0.76], [0.84, 0.26]], r), c, lw, true)
		"plus":
			ci.draw_line(_p(r, 0.5, 0.16), _p(r, 0.5, 0.84), c, lw, true)
			ci.draw_line(_p(r, 0.16, 0.5), _p(r, 0.84, 0.5), c, lw, true)
		"minus":
			ci.draw_line(_p(r, 0.16, 0.5), _p(r, 0.84, 0.5), c, lw, true)
		"close":
			ci.draw_line(_p(r, 0.22, 0.22), _p(r, 0.78, 0.78), c, lw, true)
			ci.draw_line(_p(r, 0.78, 0.22), _p(r, 0.22, 0.78), c, lw, true)
		"search":
			ci.draw_arc(_p(r, 0.42, 0.42), w * 0.26, 0, TAU, 32, c, lw, true)
			ci.draw_line(_p(r, 0.62, 0.62), _p(r, 0.86, 0.86), c, lw, true)
		"undo":
			ci.draw_arc(_p(r, 0.52, 0.56), w * 0.30, PI * 1.05, PI * 2.25, 24, c, lw, true)
			ci.draw_colored_polygon(_poly([[0.08, 0.46], [0.36, 0.48], [0.18, 0.72]], r), c)
		"hanger":
			ci.draw_arc(_p(r, 0.5, 0.22), w * 0.1, PI * 0.9, PI * 2.4, 16, c, lw * 0.7, true)
			ci.draw_polyline(_poly([[0.5, 0.34], [0.10, 0.74], [0.90, 0.74], [0.5, 0.34]], r), c, lw * 0.8, true)
		"lock":
			ci.draw_arc(_p(r, 0.5, 0.40), w * 0.18, PI, TAU, 16, c, lw * 0.8, true)
			ci.draw_rect(Rect2(_p(r, 0.24, 0.42), Vector2(w * 0.52, w * 0.42)), c)
		"face_accessory":
			ci.draw_line(_p(r, 0.06, 0.40), _p(r, 0.94, 0.30), c.darkened(0.15), lw * 0.6, true)
			_ellipse(ci, _p(r, 0.42, 0.52), Vector2(w * 0.24, w * 0.20), c)
			if outline.a > 0.0:
				_ellipse_outline(ci, _p(r, 0.42, 0.52), Vector2(w * 0.24, w * 0.20), outline, maxf(1.5, w * 0.035))
		"neck_accessory":
			ci.draw_arc(_p(r, 0.5, 0.30), w * 0.32, PI * 0.15, PI * 0.85, 24, c, lw * 0.7, true)
			ci.draw_circle(_p(r, 0.5, 0.70), w * 0.11, c)
			if outline.a > 0.0:
				ci.draw_arc(_p(r, 0.5, 0.70), w * 0.11, 0, TAU, 20, outline, maxf(1.5, w * 0.03), true)
		"earrings":
			for x in [0.32, 0.68]:
				ci.draw_line(_p(r, x, 0.16), _p(r, x, 0.42), c, lw * 0.5, true)
				ci.draw_circle(_p(r, x, 0.56), w * 0.12, c)
		"wrist_accessory":
			ci.draw_arc(_p(r, 0.5, 0.5), w * 0.30, 0, TAU, 32, c, lw, true)
			ci.draw_circle(_p(r, 0.5, 0.2), w * 0.08, c.lightened(0.3))
		"all":
			for x in [0.14, 0.54]:
				for y in [0.14, 0.54]:
					ci.draw_rect(Rect2(_p(r, x, y), Vector2(w * 0.32, w * 0.32)), c)
		"thread":
			ci.draw_rect(Rect2(_p(r, 0.26, 0.14), Vector2(w * 0.48, w * 0.10)), c.darkened(0.2))
			ci.draw_rect(Rect2(_p(r, 0.26, 0.76), Vector2(w * 0.48, w * 0.10)), c.darkened(0.2))
			ci.draw_rect(Rect2(_p(r, 0.32, 0.24), Vector2(w * 0.36, w * 0.52)), c)
		_:
			ci.draw_circle(_p(r, 0.5, 0.5), w * 0.3, c)


## Дополнительные детали поверх силуэта (швы, ручки), чтобы силуэты читались.
static func _details(ci: CanvasItem, name: String, r: Rect2, c: Color, outline: Color) -> void:
	var line := outline if outline.a > 0.0 else c.darkened(0.25)
	var lw := maxf(1.2, r.size.x * 0.03)
	match name:
		"bag":
			ci.draw_arc(_p(r, 0.5, 0.40), r.size.x * 0.2, PI, TAU, 16, line, lw * 1.6, true)
		"outerwear":
			ci.draw_line(_p(r, 0.5, 0.40), _p(r, 0.5, 0.90), line, lw, true)
		"recipe":
			for y in [0.40, 0.55, 0.70]:
				ci.draw_line(_p(r, 0.32, y), _p(r, 0.70, y), line, lw, true)
		"trophy":
			ci.draw_arc(_p(r, 0.24, 0.28), r.size.x * 0.1, PI * 0.5, PI * 1.5, 12, c, lw * 2.0, true)
			ci.draw_arc(_p(r, 0.76, 0.28), r.size.x * 0.1, -PI * 0.5, PI * 0.5, 12, c, lw * 2.0, true)


static func _p(r: Rect2, x: float, y: float) -> Vector2:
	return r.position + Vector2(x * r.size.x, y * r.size.y)


static func _poly(pts: Array, r: Rect2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(_p(r, p[0], p[1]))
	return out


static func _star(center: Vector2, outer: float, inner: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + i * PI / 5.0
		var rad := outer if i % 2 == 0 else inner
		pts.append(center + Vector2(cos(a), sin(a)) * rad)
	return pts


static func _sparkle(ci: CanvasItem, center: Vector2, rad: float, c: Color) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		var a := -PI / 2.0 + i * PI / 4.0
		var d := rad if i % 2 == 0 else rad * 0.28
		pts.append(center + Vector2(cos(a), sin(a)) * d)
	ci.draw_colored_polygon(pts, c)


static func _ellipse(ci: CanvasItem, center: Vector2, radii: Vector2, c: Color) -> void:
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	ci.draw_colored_polygon(pts, c)


static func _ellipse_outline(ci: CanvasItem, center: Vector2, radii: Vector2, c: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for i in 25:
		var a := TAU * i / 24.0
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	ci.draw_polyline(pts, c, width, true)


## Иконка категории по слоту предмета.
static func for_slot(slot: String) -> String:
	return slot
