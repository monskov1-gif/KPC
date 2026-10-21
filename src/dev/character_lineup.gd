extends Node3D
## Витрина 3D-прототипов персонажей (для проверки моделей и скриншотов). Не входит в игру.

const IDS := ["kot", "gabi", "sora"]
var focus := ""   # пусто — все трое; иначе крупный план одного


func _ready() -> void:
	var s := Game.session
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("e9d6d3")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("f3dcd8")
	env.environment.ambient_light_energy = 0.55
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 30, 0)
	key.light_energy = 0.7
	key.light_color = Color("fff1e6")
	add_child(key)
	var x := -1.2
	for id in IDS:
		var m := CharacterModel.new()
		add_child(m)
		m.position = Vector3(x, 0, 0)
		m.setup(id, s.characters)
		m.apply_items(s.outfit_items(id))
		m.name = id
		x += 1.2
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.15, 4.6)
	cam.fov = 32
	add_child(cam)


func debug_focus_kot() -> void:
	_focus("kot")


func debug_focus_gabi() -> void:
	_focus("gabi")


func debug_focus_sora() -> void:
	_focus("sora")


func _focus(id: String) -> void:
	var cam := get_viewport().get_camera_3d()
	var m: Node3D = get_node(id)
	var h: float = {"kot": 1.63, "gabi": 1.6, "sora": 2.06}[id]
	cam.position = m.position + Vector3(0, h * 0.86, 0.85)
	cam.rotation_degrees = Vector3(-6, 0, 0)


func debug_head_kot() -> void:
	var cam := get_viewport().get_camera_3d()
	var m: Node3D = get_node("kot")
	cam.position = m.position + Vector3(0, 1.55, 0.62)
	cam.rotation_degrees = Vector3(-2, 0, 0)


func debug_full_kot() -> void:
	_kot_turn(0.0)


## Разворот Кота как на референсе 16: спереди, три четверти, сбоку, сзади (только Кот в кадре).
func debug_kot_34() -> void:
	_kot_turn(-35.0)


func debug_kot_side() -> void:
	_kot_turn(-90.0)


func debug_kot_back() -> void:
	_kot_turn(180.0)


func _kot_turn(yaw: float) -> void:
	for id in IDS:
		(get_node(id) as Node3D).visible = id == "kot"
	var m: Node3D = get_node("kot")
	m.rotation_degrees.y = yaw
	var cam := get_viewport().get_camera_3d()
	cam.position = m.position + Vector3(0.0, 0.84, 3.3)
	cam.rotation_degrees = Vector3(-1, 0, 0)


func debug_hips_kot() -> void:
	var cam := get_viewport().get_camera_3d()
	var m: Node3D = get_node("kot")
	cam.position = m.position + Vector3(0.0, 0.9, 0.7)
	cam.rotation_degrees = Vector3(-2, 0, 0)


## Все без одежды: видно, что базовый слой белья остаётся всегда.
func debug_underwear() -> void:
	for id in IDS:
		(get_node(id) as CharacterModel).apply_items([] as Array[ClothingItem])


func debug_head_kot_bare() -> void:
	debug_underwear()
	debug_head_kot()


func debug_kot_back_hips() -> void:
	_kot_turn(180.0)
	var cam := get_viewport().get_camera_3d()
	cam.position = Vector3(get_node("kot").position.x, 0.95, 0.8)


## Лицо Кота в три четверти и в профиль — проверка лепки головы (нос, губы, подбородок, скулы).
func debug_head_kot_34() -> void:
	_kot_head_turn(-32.0)


func debug_head_kot_side() -> void:
	_kot_head_turn(-90.0)


func _kot_head_turn(yaw: float) -> void:
	_kot_turn(yaw)
	var cam := get_viewport().get_camera_3d()
	cam.position = get_node("kot").position + Vector3(0, 1.55, 0.62)
	cam.rotation_degrees = Vector3(-2, 0, 0)
