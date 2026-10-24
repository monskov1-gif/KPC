class_name StoryPlayer
extends CharacterBody3D
## Управляемый персонаж сюжета: ходьба относительно камеры, бег, гравитация, поворот модели по движению,
## прыжок, рывок-уклонение и удар (комбо из трёх взмахов).
## Ввод — действия move_*/run/jump/dodge/attack (клавиатура и геймпад), на сенсорном экране — стик и кнопки HUD.
## Удар задевает узлы группы «hittable» перед героем (метод take_hit(урон, откуда)); врагов в прологе нет —
## система боя готова для зон с противниками (docs/UI_STYLE.md, «Игровой интерфейс»).

signal acted(kind: String)             # jump, land, dodge, attack — для HUD (перезарядка) и подсказок

const SWING := preload("res://art/shaders/swing_arc.gdshader")
const DODGE_TIME := 0.28
const DODGE_COOLDOWN := 0.8
const ATTACK_COOLDOWN := 0.3
const COMBO_WINDOW := 0.9
const ATTACK_REACH := 1.5
const ATTACK_DAMAGE := [10, 12, 20]     # урон взмахов комбо

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
var _jump_v := 0.0
var _air := false
var _dodge_left := 0.0
var _dodge_vel := Vector3.ZERO
var _dodge_cd := 0.0
var _attack_cd := 0.0
var _combo := 0
var _combo_left := 0.0
## Неуязвимость во время рывка (для будущих врагов).
var invulnerable := false


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
	_dodge_cd = maxf(0.0, _dodge_cd - delta)
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_combo_left = maxf(0.0, _combo_left - delta)
	var running := input_enabled and (Input.is_action_pressed("run") or touch_run)
	var speed := (run_speed if running else walk_speed) * inp.length()
	if water_level - global_position.y > WADE_DEPTH:
		speed *= 0.6
	var target := dir.normalized() * speed if dir.length() > 0.05 else Vector3.ZERO
	# разгон и торможение плавные, не зависят от FPS; во время рывка — скорость рывка
	if _dodge_left > 0.0:
		_dodge_left -= delta
		velocity.x = _dodge_vel.x
		velocity.z = _dodge_vel.z
		invulnerable = _dodge_left > 0.0
	else:
		var accel := 12.0 if is_on_floor() else 5.0       # в воздухе управление мягче
		velocity.x = move_toward(velocity.x, target.x, accel * delta)
		velocity.z = move_toward(velocity.z, target.z, accel * delta)
	if _jump_v > 0.0:
		velocity.y = _jump_v
		_jump_v = 0.0
		_air = true
	elif not is_on_floor():
		velocity.y -= GRAVITY * delta
		_air = _air or velocity.y < -2.0                    # сошёл с уступа — тоже приземлится
	else:
		velocity.y = -0.5
	move_and_slide()
	if _air and is_on_floor() and velocity.y <= 0.0:
		_air = false
		Audio.sfx("land", 0.0, clampf(1.6 / maxf(_height, 0.6), 0.9, 1.3))
		_squash(Vector3(1.1, 0.88, 1.1))
		acted.emit("land")
	# невысокий уступ (бордюр, настил, порог) — шагнуть на него, а не упереться, как в невидимую стену
	if is_on_floor() and target.length() > 0.3 and Vector2(velocity.x, velocity.z).length() < target.length() * 0.35 \
			and get_slide_collision_count() > 0:
		_try_step_up(target)
	var flat := Vector2(velocity.x, velocity.z)
	if _dodge_left > 0.0:
		pass                                                  # рывок: модель держит текущую позу
	elif flat.length() > 0.2:
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


## Прыжок: высота — около трети роста (ребёнок прыгает ниже взрослого). Только с земли.
func jump() -> bool:
	if not input_enabled or auto_target != null or not is_on_floor() or _air:
		return false
	var h := clampf(_height * 0.3, 0.35, 0.8) if _height > 0.0 else 0.5
	_jump_v = sqrt(2.0 * GRAVITY * h)
	Audio.sfx("jump", 0.0, clampf(1.6 / maxf(_height, 0.6), 0.9, 1.3))
	_squash(Vector3(0.9, 1.12, 0.9))
	acted.emit("jump")
	return true


## Рывок-уклонение: ~2.6 м за DODGE_TIME по направлению ввода (без ввода — вперёд по взгляду), с перезарядкой.
func dodge() -> bool:
	if not input_enabled or auto_target != null or _dodge_cd > 0.0:
		return false
	var inp := move_input()
	var dir := Vector3(sin(model.rotation.y), 0, cos(model.rotation.y))
	if inp.length() > 0.2:
		var fwd := Vector3(-sin(camera_yaw), 0, -cos(camera_yaw))
		var right := Vector3(cos(camera_yaw), 0, -sin(camera_yaw))
		dir = (fwd * inp.y + right * inp.x).normalized()
		model.rotation.y = atan2(dir.x, dir.z)
	var dist := clampf(_height * 1.6, 1.8, 3.0) if _height > 0.0 else 2.6
	_dodge_vel = dir * dist / DODGE_TIME
	_dodge_left = DODGE_TIME
	_dodge_cd = DODGE_COOLDOWN
	invulnerable = true
	Audio.sfx("dodge")
	_squash(Vector3(1.08, 0.94, 1.08))
	acted.emit("dodge")
	return true


## Удар: взмах перед героем (комбо из трёх: справа, слева, сверху — третий сильнее). Задевает узлы группы
## «hittable» в секторе 110° на расстоянии ATTACK_REACH; возвращает число задетых.
func attack() -> int:
	if not input_enabled or auto_target != null or _attack_cd > 0.0:
		return -1
	_combo = _combo % 3 + 1 if _combo_left > 0.0 else 1
	_combo_left = COMBO_WINDOW
	_attack_cd = ATTACK_COOLDOWN
	var face := Vector3(sin(model.rotation.y), 0, cos(model.rotation.y))
	if is_on_floor():
		velocity += face * 1.2                                # шаг вперёд вместе с ударом
	_swing_fx(face)
	Audio.sfx("swing", 0.0, 1.0 + 0.08 * _combo)
	var hits := 0
	for n in get_tree().get_nodes_in_group("hittable"):
		var t := n as Node3D
		if t == null or not t.is_inside_tree():
			continue
		var d := t.global_position - global_position
		d.y = 0.0
		if d.length() <= ATTACK_REACH and (d.length() < 0.3 or face.dot(d.normalized()) > cos(deg_to_rad(55))):
			if t.has_method("take_hit"):
				t.call("take_hit", ATTACK_DAMAGE[_combo - 1], global_position)
				hits += 1
	acted.emit("attack")
	return hits


## Доля перезарядки (1 — только что, 0 — готово) — для кольца на кнопке HUD.
func cooldown(kind: String) -> float:
	match kind:
		"dodge":
			return _dodge_cd / DODGE_COOLDOWN
		"attack":
			return _attack_cd / ATTACK_COOLDOWN
	return 0.0


func combo() -> int:
	return _combo if _combo_left > 0.0 else 0


## Мягкое сжатие-растяжение модели (прыжок, приземление, рывок) — «аниме-пружинка» без отдельного клипа.
func _squash(k: Vector3) -> void:
	if model == null or bool(Settings.get_value("reduce_motion")):
		return
	var tw := model.create_tween().set_trans(Tween.TRANS_SINE)
	tw.tween_property(model, "scale", k, 0.07)
	tw.tween_property(model, "scale", Vector3.ONE, 0.16)


## Дуга взмаха: полупрозрачный серп перед героем, гаснет за 0.25 с (шейдер swing_arc).
func _swing_fx(face: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	var r := clampf(_height * 0.75, 0.8, 1.5) if _height > 0.0 else 1.1
	q.size = Vector2(r * 2.0, r * 2.0)
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = SWING
	m.set_shader_parameter("tint", [Color("fff3c4"), Color("ffd0e4"), Color("c9f2ff")][_combo - 1])
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var h := (_height if _height > 0.0 else 1.6) * 0.55
	mi.position = Vector3(0, h, 0) + face * 0.15
	mi.rotation.y = atan2(face.x, face.z)
	mi.rotation.z = [0.25, -0.25, 0.0][_combo - 1]
	mi.rotation.x = [0.0, 0.0, -1.2][_combo - 1]
	if _combo == 2:
		mi.scale.x = -1.0                                     # взмах в обратную сторону
	var tw := mi.create_tween()
	tw.tween_method(func(v: float): m.set_shader_parameter("progress", v), 0.0, 1.0, 0.25)
	tw.tween_callback(mi.queue_free)


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
