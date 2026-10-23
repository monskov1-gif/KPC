class_name StoryPlayer
extends CharacterBody3D
## Управляемый персонаж сюжета: ходьба относительно камеры, бег, гравитация, поворот модели по движению.
## Ввод — действия move_*/run (клавиатура и геймпад) и виртуальный стик (touch_move) на сенсорном экране.

const WALK := 2.0
const RUN := 4.2
const TURN := 10.0
const GRAVITY := 18.0
## Глубина воды (м), с которой шаг замедляется.
const WADE_DEPTH := 0.25

var model: CharacterModel
var input_enabled := true
## Направление камеры (рад) — движение «вперёд» идёт от камеры.
var camera_yaw := 0.0
## Ввод с экранного стика: x — вправо, y — вперёд (длина 0..1).
var touch_move := Vector2.ZERO
var touch_run := false
## Уровень воды локации (м); −INF — воды нет.
var water_level := -INF
var _shape: CollisionShape3D


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4
	_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = 1.6
	_shape.shape = cap
	_shape.position.y = 0.8
	add_child(_shape)
	model = CharacterModel.new()
	add_child(model)


## Смена модели (Кот-ребёнок → Кот) с подгонкой капсулы под рост.
func set_character(model_id: String, characters: CharacterCatalog, items: Array[ClothingItem] = []) -> void:
	model.setup(model_id, characters)
	model.apply_items(items)
	var h := clampf(model.height(), 0.8, 2.6)
	var cap := _shape.shape as CapsuleShape3D
	cap.height = h * 0.95
	cap.radius = clampf(h * 0.17, 0.2, 0.34)
	_shape.position.y = cap.height * 0.5


func place(t: Transform3D) -> void:
	global_position = t.origin
	velocity = Vector3.ZERO
	var f := -t.basis.z
	if f.length() > 0.01:
		model.rotation.y = atan2(f.x, f.z)


## Повернуться лицом к точке (для разговоров).
func face(point: Vector3) -> void:
	var d := point - global_position
	if Vector2(d.x, d.z).length() > 0.05:
		model.rotation.y = atan2(d.x, d.z)


func move_input() -> Vector2:
	if not input_enabled:
		return Vector2.ZERO
	var v := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	if touch_move.length() > v.length():
		v = touch_move
	return v.limit_length(1.0)


func _physics_process(delta: float) -> void:
	var inp := move_input()
	var fwd := Vector3(-sin(camera_yaw), 0, -cos(camera_yaw))
	var right := Vector3(cos(camera_yaw), 0, -sin(camera_yaw))
	var dir := fwd * inp.y + right * inp.x
	var running := input_enabled and (Input.is_action_pressed("run") or touch_run)
	var speed := (RUN if running else WALK) * inp.length()
	if water_level - global_position.y > WADE_DEPTH:
		speed *= 0.6
	var target := dir.normalized() * speed if dir.length() > 0.05 else Vector3.ZERO
	velocity.x = move_toward(velocity.x, target.x, 20.0 * delta)
	velocity.z = move_toward(velocity.z, target.z, 20.0 * delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -0.5
	move_and_slide()
	var flat := Vector2(velocity.x, velocity.z)
	if flat.length() > 0.2:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(velocity.x, velocity.z), clampf(TURN * delta, 0.0, 1.0))
		model.play_motion("run" if speed > WALK + 0.1 else "walk", flat.length() / WALK)
	else:
		model.play_motion("idle")
