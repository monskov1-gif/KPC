extends SceneTree
## Иконки вещей из самих 3D-мешей одежды (а не нарисованные силуэты): для каждой вещи берётся модель
## подходящего персонажа, показывается только её меш-шаблон в цвете вещи, кадр по габаритам → art/items/<id>.png.
## Запуск: tools/render_icons.sh (Xvfb + OpenGL, как capture.sh).

const SIZE := 256
const OUT_DIR := "res://art/items/"

var _vp: SubViewport
var _cam: Camera3D
var _models := {}


func _initialize() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.own_world_3d = true
	root.add_child(_vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.9, 0.88, 0.92)
	env.environment.ambient_light_energy = 0.6
	_vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -30, 0)
	sun.light_energy = 1.1
	_vp.add_child(sun)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_vp.add_child(_cam)
	_run.call_deferred()


func _run() -> void:
	var items: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/wardrobe/items.json"))["items"]
	var chars: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/characters/characters.json"))["characters"]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var done := 0
	for d in items:
		var it := ClothingItem.from_dict(d)
		var cid := _owner_for(it, chars)
		var model := _model(cid)
		for m in _models.values():
			(m as CharacterModel).visible = m == model
		model.apply_items([it] as Array[ClothingItem])
		# Тело, голова и бельё скрыты — на иконке только вещь.
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var n := String(mi.name)
			if not n.begins_with("garment__"):
				(mi as MeshInstance3D).visible = false
		var box := AABB()
		var first := true
		for mi in model.find_children("garment__*", "MeshInstance3D", true, false):
			if not (mi as MeshInstance3D).visible:
				continue
			var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
			box = b if first else box.merge(b)
			first = false
		if first:
			push_warning("нет меша для " + it.id)
			continue
		var c := box.get_center()
		var w := box.size.x
		if it.slot in ["footwear", "socks", "gloves"]:
			# парная вещь: на иконке — одна (левая для зрителя), крупно
			w = box.size.x * 0.42
			c.x = box.position.x + w * 0.5
		_cam.size = maxf(box.size.y, w) * 1.12
		_cam.position = c + Vector3(0.35, 0.15, 3.0)
		_cam.look_at(c, Vector3.UP)
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := _vp.get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path(OUT_DIR + it.id + ".png"))
		done += 1
	print("Иконок: ", done)
	quit(0)


func _owner_for(it: ClothingItem, chars: Array) -> String:
	# Сначала персонаж, в чьём фирменном образе вещь; иначе первый подходящий по типу фигуры.
	for c in chars:
		if it.id in (c.get("signature_outfit", {}) as Dictionary).values():
			return c["id"]
	for c in chars:
		if c.get("body_type", "") in it.compatible_body_types:
			return c["id"]
	return "kot"


func _model(cid: String) -> CharacterModel:
	if not _models.has(cid):
		var m := CharacterModel.new()
		_vp.add_child(m)
		m.setup(cid, null)
		var anim := m.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if anim:
			anim.stop()
		_models[cid] = m
	return _models[cid]
