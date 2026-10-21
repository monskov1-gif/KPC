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
	cam.position = m.position + Vector3(0, h * 0.82, 1.15)
	cam.rotation_degrees = Vector3(-6, 0, 0)
