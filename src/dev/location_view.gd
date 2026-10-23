extends Node3D
## Просмотр локации для снимков и критиков (не входит в игру):
## KPC_LOC=<id> KPC_TIME=day|evening|night|storm KPC_CAM="x,y,z" KPC_LOOK="x,y,z" (координаты Blender: z — вверх)
## KPC_CAST="model@x,y,rz;…" — расставить персонажей (по образам data/story/looks.json).

var loc: StoryLocation


func _ready() -> void:
	loc = StoryLocation.new()
	add_child(loc)
	loc.load_location(OS.get_environment("KPC_LOC") if OS.has_environment("KPC_LOC") else "family_home")
	loc.apply_time(OS.get_environment("KPC_TIME") if OS.has_environment("KPC_TIME") else "day")
	var cam := Camera3D.new()
	cam.fov = float(OS.get_environment("KPC_FOV")) if OS.has_environment("KPC_FOV") else 55.0
	add_child(cam)
	cam.current = true
	cam.position = _v(OS.get_environment("KPC_CAM"), Vector3(0, 1.6, 4))
	cam.look_at(_v(OS.get_environment("KPC_LOOK"), Vector3.ZERO))
	if OS.has_environment("KPC_CAST"):
		var looks := DataLoader.load_json(StoryGame.LOOKS_PATH)
		for part in OS.get_environment("KPC_CAST").split(";", false):
			var id := part.get_slice("@", 0)
			var p := part.get_slice("@", 1).split(",")
			var m := CharacterModel.new()
			add_child(m)
			m.setup(id, Game.session.characters)
			m.apply_look(looks.get(id, {}))
			m.position = Vector3(float(p[0]), 0, -float(p[1]))
			m.rotation.y = float(p[2]) if p.size() > 2 else 0.0


## «x,y,z» в координатах Blender → Godot.
func _v(s: String, d: Vector3) -> Vector3:
	var p := s.split(",")
	if p.size() < 3:
		return d
	return Vector3(float(p[0]), float(p[2]), -float(p[1]))
