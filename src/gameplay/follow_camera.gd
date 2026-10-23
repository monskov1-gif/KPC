class_name FollowCamera
extends Node3D
## Камера от третьего лица: следует за целью, вращается действиями camera_*, мышью (с зажатой кнопкой)
## и свайпом по экрану; пружина не даёт уйти за стены. Камера чуть сбоку («через плечо»), чтобы собеседник был виден.

@export var distance := 4.2
@export var height := 1.25
var target: Node3D
var yaw := 0.0
var pitch := -0.32
var _arm: SpringArm3D
var camera: Camera3D
var _drag := false


func _ready() -> void:
	_arm = SpringArm3D.new()
	_arm.spring_length = distance
	_arm.collision_mask = 1
	_arm.margin = 0.2
	var probe := SphereShape3D.new()
	probe.radius = 0.2
	_arm.shape = probe
	add_child(_arm)
	camera = Camera3D.new()
	camera.fov = 52
	camera.h_offset = 0.45
	camera.current = true
	_arm.add_child(camera)


## Подогнать под рост персонажа (ребёнку камера ниже и ближе).
func fit_height(h: float) -> void:
	height = h * 0.78
	distance = clampf(h * 2.6, 2.8, 5.0)
	_arm.spring_length = distance


func rotate_by(d: Vector2) -> void:
	yaw -= d.x
	pitch = clampf(pitch - d.y, -1.1, 0.25)


## Мгновенно поставить камеру за спиной персонажа (смена локации).
func snap_behind(model_yaw: float) -> void:
	yaw = model_yaw + PI
	_update(1.0)


func _unhandled_input(e: InputEvent) -> void:
	# мышь, эмулированная из касаний, — не вращает камеру (палец на стике не должен крутить вид)
	if e is InputEventMouse and e.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if e is InputEventMouseButton and e.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		_drag = e.pressed
	elif e is InputEventMouseMotion and _drag:
		rotate_by(e.relative * 0.005)
	elif e is InputEventScreenDrag:
		rotate_by(e.relative * 0.006)


func _process(delta: float) -> void:
	var stick := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	if stick.length() > 0.0:
		rotate_by(stick * 2.2 * delta)
	_update(clampf(10.0 * delta, 0.0, 1.0))


func _update(k: float) -> void:
	if target == null:
		return
	global_position = global_position.lerp(target.global_position + Vector3(0, height, 0), k)
	rotation = Vector3(pitch, yaw, 0)
