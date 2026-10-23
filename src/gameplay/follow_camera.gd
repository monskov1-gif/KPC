class_name FollowCamera
extends Node3D
## Камера от третьего лица.
## • Плавность: поворот, высота и дистанция сглаживаются экспоненциально (не зависят от FPS); цель берётся
##   с интерполяцией физики — при одновременной ходьбе и повороте камера не дёргается.
## • Зум: колесо мыши, щипок на сенсорном экране, клавиши zoom_in / zoom_out; пределы MIN_DIST…MAX_DIST.
## • Препятствия: сферический луч от героя к камере; к стене камера подходит быстро, отходит медленно.
## • Кат-сцены: shot(pos, look, seconds) — постановочный кадр; release() — плавный возврат за спину героя.
## Чувствительность и инверсия берутся из настроек (Settings), если они есть.

const MIN_DIST := 1.4
const MAX_DIST := 7.0
const ROT_SHARP := 14.0      # скорость догона поворота
const FOLLOW_SHARP := 12.0   # скорость догона героя
const PITCH_MIN := -1.15
const PITCH_MAX := 0.35

@export var height := 1.25
var target: Node3D
var yaw := 0.0
var pitch := -0.3
var zoom := 4.0              # желаемая дистанция (зум игрока)
var camera: Camera3D
var sens_x := 1.0
var sens_y := 1.0
var invert_y := false
var _yaw_t := 0.0
var _pitch_t := -0.3
var _dist := 4.0
var _pivot := Vector3.ZERO
var _drag := false
var _touches := {}           # индекс пальца → позиция (щипок двумя пальцами)
var _pinch := 0.0
var _shot: Transform3D
var _shot_active := false
var _shot_tween: Tween
var _shot_w := 0.0           # 1 — полностью постановочный кадр, 0 — игровая камера


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 52
	camera.current = true
	add_child(camera)


## Подогнать под рост персонажа (ребёнку камера ниже и ближе).
func fit_height(h: float) -> void:
	height = h * 0.8
	zoom = clampf(h * 2.7, 2.6, 5.0)
	_dist = zoom


func rotate_by(d: Vector2) -> void:
	_yaw_t -= d.x * sens_x
	_pitch_t = clampf(_pitch_t - d.y * sens_y * (-1.0 if invert_y else 1.0), PITCH_MIN, PITCH_MAX)


func zoom_by(k: float) -> void:
	zoom = clampf(zoom * k, MIN_DIST, MAX_DIST)


## Мгновенно поставить камеру за спиной персонажа (смена локации — без «полёта» из прошлой).
func snap_behind(model_yaw: float) -> void:
	yaw = model_yaw + PI
	_yaw_t = yaw
	pitch = _pitch_t
	if target:
		_pivot = _target_pos()
	_dist = zoom
	_place()


## Постановочный кадр кат-сцены: камера плавно уходит в точку pos и смотрит на look.
func shot(pos: Vector3, look: Vector3, seconds := 1.2) -> void:
	_shot = Transform3D(Basis.IDENTITY, pos).looking_at(look, Vector3.UP)
	_shot_active = true
	_tween_w(1.0, seconds)


## Вернуть игровую камеру (плавно).
func release(seconds := 0.9) -> void:
	_shot_active = false
	_tween_w(0.0, seconds)


func _tween_w(to: float, seconds: float) -> void:
	if _shot_tween and _shot_tween.is_valid():
		_shot_tween.kill()
	if seconds <= 0.0:
		_shot_w = to
		return
	_shot_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_shot_tween.tween_property(self, "_shot_w", to, seconds)


func _unhandled_input(e: InputEvent) -> void:
	# мышь, эмулированная из касаний, — не вращает камеру (палец на стике не должен крутить вид)
	if e is InputEventMouse and e.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if e is InputEventMouseButton:
		if e.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			_drag = e.pressed
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by(0.88)
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(1.13)
	elif e is InputEventMouseMotion and _drag:
		rotate_by(e.relative * 0.005)
	elif e is InputEventMagnifyGesture:
		zoom_by(1.0 / e.factor)
	elif e is InputEventScreenTouch:
		if e.pressed:
			_touches[e.index] = e.position
		else:
			_touches.erase(e.index)
		_pinch = _pinch_dist()
	elif e is InputEventScreenDrag:
		_touches[e.index] = e.position
		if _touches.size() >= 2:
			var d := _pinch_dist()
			if _pinch > 0.0 and d > 0.0:
				zoom_by(_pinch / d)
			_pinch = d
		else:
			rotate_by(e.relative * 0.006)


func _pinch_dist() -> float:
	if _touches.size() < 2:
		return 0.0
	var v: Array = _touches.values()
	return (v[0] as Vector2).distance_to(v[1])


func _process(delta: float) -> void:
	var stick := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	if stick.length() > 0.0:
		rotate_by(stick * 2.4 * delta)
	if InputMap.has_action("zoom_in") and Input.is_action_pressed("zoom_in"):
		zoom_by(1.0 - 1.2 * delta)
	if InputMap.has_action("zoom_out") and Input.is_action_pressed("zoom_out"):
		zoom_by(1.0 + 1.2 * delta)
	var kr := 1.0 - exp(-ROT_SHARP * delta)
	yaw = lerp_angle(yaw, _yaw_t, kr)
	pitch = lerpf(pitch, _pitch_t, kr)
	if target:
		_pivot = _pivot.lerp(_target_pos(), 1.0 - exp(-FOLLOW_SHARP * delta))
	# препятствия: сфера от героя к желаемой точке камеры
	var allowed := _clear_distance(zoom)
	var sharp := 22.0 if allowed < _dist else 4.0
	_dist = lerpf(_dist, minf(zoom, allowed), 1.0 - exp(-sharp * delta))
	_place()


func _target_pos() -> Vector3:
	var t: Vector3 = target.get_global_transform_interpolated().origin if target.is_inside_tree() else target.global_position
	return t + Vector3(0, height, 0)


func _dir() -> Vector3:
	return Basis.from_euler(Vector3(pitch, yaw, 0)) * Vector3(0, 0, 1)


func _place() -> void:
	var game_t := Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0)), _pivot + _dir() * _dist)
	# лёгкий сдвиг «через плечо»: собеседник в кадре, герой не закрывает цель
	game_t.origin += game_t.basis.x * 0.35 * clampf(_dist / 4.0, 0.3, 1.0)
	if _shot_w > 0.001:
		game_t = game_t.interpolate_with(_shot, _shot_w)
	global_transform = game_t


func _clear_distance(want: float) -> float:
	if not is_inside_tree() or target == null:
		return want
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.22
	q.shape = sph
	q.collision_mask = 1
	q.transform = Transform3D(Basis.IDENTITY, _pivot)
	q.motion = _dir() * want
	var r := space.cast_motion(q)
	return maxf(MIN_DIST * 0.6, want * r[0] - 0.05) if r[0] < 1.0 else want
