extends Node3D
## Кадры для рисунков скетчбука Кота (tools/art/sketchify.py превращает их в карандашные наброски).
## Снимок: tools/capture.sh res://scenes/dev/sketch_shots.tscn out.png 1200x780 30 debug_<кадр>. Не входит в игру.

var loc: StoryLocation
var cam: Camera3D


func _ready() -> void:
	loc = StoryLocation.new()
	add_child(loc)
	cam = Camera3D.new()
	cam.fov = 50
	add_child(cam)
	cam.current = true


func _people(ids: Array, x0: float, step: float, z := 0.0, yaw := 0.0) -> void:
	var looks := DataLoader.load_json(StoryGame.LOOKS_PATH)
	var x := x0
	for id in ids:
		var m := CharacterModel.new()
		add_child(m)
		m.position = Vector3(x, 0, z)
		m.rotation.y = yaw
		m.setup(id, Game.session.characters)
		if looks.has(id):
			m.apply_look(looks[id])
		else:
			if Game.session.outfit_items(id).is_empty():
				Game.session.equipment.equip_signature(id)
			m.apply_items(Game.session.outfit_items(id))
		x += step


func debug_street() -> void:
	loc.load_location("city_street")
	loc.apply_time("day")
	cam.position = Vector3(-24, 2.2, -1.6)
	cam.look_at(Vector3(-8, 2.4, 1.5))


func debug_city() -> void:
	loc.load_location("rooftop")
	loc.apply_time("day")
	cam.position = Vector3(6.4, 2.6, -2.0)
	cam.look_at(Vector3(30, -9, -6))


func debug_family() -> void:
	loc.load_location("family_home")
	loc.apply_time("day")
	_people(["mama", "papa", "sora_young", "gabi_child", "kot_child"], -1.9, 0.95, -1.6)
	cam.position = Vector3(0, 1.3, 3.3)
	cam.look_at(Vector3(0, 1.0, -1.6))
	cam.fov = 48


func debug_three() -> void:
	loc.load_location("rooftop")
	loc.apply_time("evening")
	_people(["sora", "gabi", "kot"], -0.9, 0.9, 0.0)
	cam.position = Vector3(0, 1.5, 4.2)
	cam.look_at(Vector3(0, 1.1, 0))
	cam.fov = 40
