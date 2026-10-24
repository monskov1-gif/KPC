class_name MiniMap
extends Control
## Мини-карта в углу экрана. Карта локации — проходимые клетки: заливка от точки появления, как в проверке
## проходимости (tools/walk_check.gd): клетка есть, если под ней пол, а соседние связаны, если перепад не больше
## ступеньки. Строится по кадрам при входе в локацию (не задерживает загрузку). Рисуется мягко: светлая «суша»
## с тоном по высоте, тёмная кромка, вода голубым. Карта поворачивается вместе с камерой; в центре — стрелка
## героя, точки осмотра — кружки, цель «дойти до…» — звезда (за краем — на ободке, в её сторону).
## Нажатие — ближе/дальше.

const SHADER := preload("res://art/shaders/minimap.gdshader")
const CELL := 0.5
const STEP := 0.3
const MAX_CELLS := 30000
const PER_FRAME := 600
const ZOOMS := [22.0, 12.0]          # радиус обзора (м)

var player: StoryPlayer
var heading := 0.0                  # поворот камеры (рад)
var target = null                   # Vector3 цели или null
var points: Array = []              # точки осмотра (Vector3)

var _rect: ColorRect
var _marks: Control
var _mat: ShaderMaterial
var _origin := Vector2i.ZERO
var _cells := Vector2i.ONE
var _build_id := 0
var _ready_map := false
var _zoom := 0
var _cap: CapsuleShape3D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("ready", 0.0)
	_rect.material = _mat
	add_child(_rect)
	_marks = Control.new()
	_marks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marks.draw.connect(_draw_marks)
	add_child(_marks)
	_cap = CapsuleShape3D.new()
	_cap.radius = 0.22
	_cap.height = 0.9


func _gui_input(e: InputEvent) -> void:
	if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or \
			(e is InputEventScreenTouch and e.pressed):
		_zoom = (_zoom + 1) % ZOOMS.size()
		Audio.ui("tap")
		accept_event()


## Построить карту локации от точки start (обычно точка появления). Прерывается новым вызовом.
func build(start: Vector3, water_level := -INF) -> void:
	_build_id += 1
	var my := _build_id
	_ready_map = false
	_mat.set_shader_parameter("ready", 0.0)
	# коллизии новой локации регистрируются в физике через кадр
	for i in 2:
		await get_tree().physics_frame
	if my != _build_id or player == null or not player.is_inside_tree():
		return
	var space := player.get_world_3d().direct_space_state
	var c0 := Vector2i(roundi(start.x / CELL), roundi(start.z / CELL))
	var h0 := _floor(space, start.x, start.z, start.y)
	if is_nan(h0):
		return
	var height := {c0: h0}
	var queue: Array[Vector2i] = [c0]
	var head := 0
	var budget := PER_FRAME
	while head < queue.size() and queue.size() < MAX_CELLS:
		var c: Vector2i = queue[head]
		head += 1
		var hc: float = height[c]
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if height.has(n):
				continue
			var x := n.x * CELL
			var z := n.y * CELL
			var h := _floor(space, x, z, hc)
			if is_nan(h) or absf(h - hc) > STEP or not _free(space, x, h, z):
				continue
			height[n] = h
			queue.append(n)
		budget -= 1
		if budget <= 0:
			budget = PER_FRAME
			await get_tree().process_frame
			if my != _build_id or not is_inside_tree():
				return
	_bake(height, water_level)


func _floor(space: PhysicsDirectSpaceState3D, x: float, z: float, from_y: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, from_y + 1.4, z), Vector3(x, from_y - 3.0, z), 1)
	var r := space.intersect_ray(q)
	if r.is_empty() or (r.normal as Vector3).y < 0.6:
		return NAN
	return (r.position as Vector3).y


func _free(space: PhysicsDirectSpaceState3D, x: float, y: float, z: float) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _cap
	q.collision_mask = 1
	q.transform = Transform3D(Basis.IDENTITY, Vector3(x, y + STEP + 0.02 + _cap.height * 0.5, z))
	return space.intersect_shape(q, 1).is_empty()


## Клетки → текстура: суша с тоном по высоте, кромка темнее, вода голубая; поле с запасом в 2 клетки.
func _bake(height: Dictionary, water_level: float) -> void:
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	var hmin := INF
	var hmax := -INF
	for c in height:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
		hmin = minf(hmin, height[c])
		hmax = maxf(hmax, height[c])
	lo -= Vector2i(2, 2)
	hi += Vector2i(2, 2)
	_origin = lo
	_cells = hi - lo + Vector2i.ONE
	var img := Image.create(_cells.x, _cells.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var land := Color("f7ecdf")
	var high := Color("fffaf3")
	var edge := Color("d9b9a6")
	var water := Color("a9d4e6")
	for c in height:
		var h: float = height[c]
		var t := 0.0 if hmax - hmin < 0.01 else (h - hmin) / (hmax - hmin)
		var col := land.lerp(high, t)
		if h < water_level - 0.05:
			col = water
		var border := false
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if not height.has(c + d):
				border = true
		if border:
			col = col.lerp(edge, 0.75)
		img.set_pixel(c.x - lo.x, c.y - lo.y, col)
	_mat.set_shader_parameter("map_tex", ImageTexture.create_from_image(img))
	_mat.set_shader_parameter("ready", 1.0)
	_ready_map = true


func is_built() -> bool:
	return _ready_map


func _process(_delta: float) -> void:
	if not visible or player == null:
		return
	var view: float = ZOOMS[_zoom]
	var p := player.global_position
	_mat.set_shader_parameter("center_uv", Vector2((p.x / CELL - _origin.x + 0.5) / _cells.x,
		(p.z / CELL - _origin.y + 0.5) / _cells.y))
	_mat.set_shader_parameter("span", Vector2(view / CELL / _cells.x, view / CELL / _cells.y))
	_mat.set_shader_parameter("yaw", heading)
	_marks.queue_redraw()


## Мир (смещение x, z от героя) → точка на круге (−1…1).
func _to_screen(wx: float, wz: float) -> Vector2:
	var c := cos(heading)
	var s := sin(heading)
	return Vector2(c * wx - s * wz, s * wx + c * wz) / float(ZOOMS[_zoom])


func _draw_marks() -> void:
	if player == null:
		return
	var center := size * 0.5
	var rad := minf(size.x, size.y) * 0.5
	var p := player.global_position
	for q in points:
		var v := _to_screen((q as Vector3).x - p.x, (q as Vector3).z - p.z)
		if v.length() < 0.88:
			_marks.draw_circle(center + v * rad, rad * 0.055, UiTheme.MINT.darkened(0.15))
			_marks.draw_circle(center + v * rad, rad * 0.03, Color.WHITE)
	if target != null:
		var v := _to_screen((target as Vector3).x - p.x, (target as Vector3).z - p.z)
		var at := v.limit_length(0.8)
		var pos := center + at * rad
		var star := PackedVector2Array()
		for k in 10:
			var a := -PI / 2 + k * PI / 5
			var rr := rad * (0.11 if k % 2 == 0 else 0.05)
			star.append(pos + Vector2(cos(a), sin(a)) * rr)
		_marks.draw_colored_polygon(star, UiTheme.GOLD)
		_marks.draw_polyline(star + PackedVector2Array([star[0]]), Color.WHITE, 1.5, true)
	# стрелка героя: куда смотрит модель
	var my := player.model.rotation.y if player.model else 0.0
	var dir := _to_screen(sin(my), cos(my)).normalized()
	var side := Vector2(-dir.y, dir.x)
	var tip := center + dir * rad * 0.13
	var arrow := PackedVector2Array([tip, center - dir * rad * 0.07 + side * rad * 0.08, center - dir * rad * 0.02,
		center - dir * rad * 0.07 - side * rad * 0.08])
	_marks.draw_colored_polygon(arrow, UiTheme.GOLD_DEEP)
	_marks.draw_polyline(arrow + PackedVector2Array([arrow[0]]), Color.WHITE, 2.0, true)
	# «С» — север (−Z мира) на ободке
	var n := _to_screen(0.0, -1.0).normalized() * rad * 0.8
	var font := UiTheme.body_font()
	_marks.draw_circle(center + n, rad * 0.1, Color(1, 1, 1, 0.85))
	_marks.draw_string(font, center + n + Vector2(-5, 5), "С", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiTheme.TEXT)
