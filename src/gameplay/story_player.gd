class_name StoryPlayer
extends CharacterBody3D
## Управляемый персонаж сюжета: ходьба относительно камеры, бег, гравитация, поворот модели по движению.
## Ввод — действия move_*/run (клавиатура и геймпад) и виртуальный стик (touch_move) на сенсорном экране.

## Скорости — от роста персонажа (ребёнок ходит медленнее взрослого): см. set_character.
var walk_speed := 1.6
var run_speed := 3.6
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
## Постановка: идти к точке без ввода игрока (StoryGame.auto_walk); null — обычное управление.
var auto_target = null
var _shape: CollisionShape3D
var _step_acc := 0.0
## Самый высокий уступ, на который герой шагает сам (бордюр, порог, настил переезда).
const STEP_UP := 0.25
var _height := 0.0


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
	_height = h
	walk_speed = clampf(h * 1.15, 1.25, 1.9)
	run_speed = clampf(h * 2.6, 3.0, 4.4)
	var cap := _shape.shape as CapsuleShape3D
	cap.height = h * 0.95
	cap.radius = clampf(h * 0.17, 0.2, 0.34)
	_shape.position.y = cap.height * 0.5


func place(t: Transform3D) -> void:
	global_position = t.origin
	velocity = Vector3.ZERO
	reset_physics_interpolation()     # телепорт без «пролёта» камеры
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
	if auto_target != null:
		var to: Vector3 = auto_target - global_position
		to.y = 0
		dir = to.normalized() if to.length() > 0.3 else Vector3.ZERO
		inp = Vector2(0, 0.7 if to.length() > 0.3 else 0.0)
	var running := input_enabled and (Input.is_action_pressed("run") or touch_run)
	var speed := (run_speed if running else walk_speed) * inp.length()
	if water_level - global_position.y > WADE_DEPTH:
		speed *= 0.6
	var target := dir.normalized() * speed if dir.length() > 0.05 else Vector3.ZERO
	# разгон и торможение плавные, не зависят от FPS
	velocity.x = move_toward(velocity.x, target.x, 12.0 * delta)
	velocity.z = move_toward(velocity.z, target.z, 12.0 * delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -0.5
	move_and_slide()
	# невысокий уступ (бордюр, настил, порог) — шагнуть на него, а не упереться, как в невидимую стену
	if is_on_floor() and target.length() > 0.3 and Vector2(velocity.x, velocity.z).length() < target.length() * 0.35 \
			and get_slide_collision_count() > 0:
		_try_step_up(target)
	var flat := Vector2(velocity.x, velocity.z)
	if flat.length() > 0.2:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(velocity.x, velocity.z), clampf(TURN * delta, 0.0, 1.0))
		var run := flat.length() > walk_speed + 0.3
		model.play_motion("run" if run else "walk", flat.length())
		if is_on_floor():
			_footsteps(flat.length() * delta, run)
		else:
			_step_acc = 0.0
	else:
		model.play_motion("idle")
		_step_acc = 0.0


## Подъём на ступеньку до STEP_UP: над головой свободно и на высоте ступеньки впереди нет стены —
## поднять героя и сдвинуть вперёд; на опору его вернёт прижатие к полу.
func _try_step_up(target: Vector3) -> void:
	var up := Vector3(0, STEP_UP, 0)
	var fwd := Vector3(target.x, 0, target.z).normalized() * 0.18
	if test_move(global_transform, up):
		return
	if test_move(global_transform.translated(up), fwd):
		return
	global_position += up + fwd
	var snap := floor_snap_length
	floor_snap_length = STEP_UP + 0.1
	velocity.y = 0.0
	apply_floor_snap()
	floor_snap_length = snap


## Шаги: звук на каждый шаг (полцикла клипа: шаг ≈ 0.39 роста, бег ≈ 0.75); поверхность — от локации,
## в воде — всплески. У ребёнка шаги выше и легче.
func _footsteps(dist: float, run: bool) -> void:
	if _height <= 0.0:
		_height = maxf(0.6, model.height())
	_step_acc += dist
	var stride := _height * (0.75 if run else 0.39)
	if _step_acc < stride:
		return
	_step_acc = fmod(_step_acc, stride)
	var pitch := clampf(1.6 / _height, 0.9, 1.3)
	if water_level - global_position.y > 0.05:
		Audio.sfx("splash", -8.0, pitch)
	else:
		Audio.sfx("step_" + Audio.surface(), 2.0 if run else 0.0, pitch)
