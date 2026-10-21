class_name CharacterModel
extends Node3D
## 3D-прототип персонажа из art/characters/<id>.glb (строится tools/art/build_characters.py).
## Аниме-шейдер + контур, анимация покоя, одежда — меши-шаблоны «garment__<слот>__<шаблон>»:
## показываются по надетым вещам и окрашиваются в цвет вещи. Если модели нет — показывает манекен-заглушку.

const TOON := preload("res://art/shaders/toon.gdshader")
const OUTLINE := preload("res://art/shaders/outline.gdshader")
const MODEL_DIR := "res://art/characters/"

var character_id := ""
var _root: Node3D
var _garments: Dictionary = {}     # "слот__шаблон" -> MeshInstance3D
var _materials: Dictionary = {}    # кэш материалов по ключу
var _fallback: PlaceholderAppearance


func setup(p_character_id: String, characters: CharacterCatalog) -> void:
	character_id = p_character_id
	if _root:
		_root.queue_free()
		_root = null
	_garments.clear()
	var path := MODEL_DIR + character_id + ".glb"
	if not ResourceLoader.exists(path):
		push_warning("Нет 3D-модели %s — используется заглушка" % path)
		if _fallback == null:
			_fallback = PlaceholderAppearance.new()
			add_child(_fallback)
		_fallback.visible = true
		_fallback.setup(character_id, characters)
		return
	if _fallback:
		_fallback.visible = false
	_root = (load(path) as PackedScene).instantiate()
	add_child(_root)
	_prepare(_root)
	var anim := _root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim and anim.has_animation("idle"):
		anim.get_animation("idle").loop_mode = Animation.LOOP_LINEAR
		anim.play("idle")


## Высота модели в метрах (для кадрирования камеры).
func height() -> float:
	if _root == null:
		return _fallback.scale.y * 1.6 if _fallback else 1.6
	var aabb := AABB()
	var first := true
	for mi in _root.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).get_aabb()
		b = (mi as MeshInstance3D).global_transform * b if mi.is_inside_tree() else b
		aabb = b if first else aabb.merge(b)
		first = false
	return aabb.end.y


func apply_items(items: Array[ClothingItem]) -> void:
	if _root == null:
		if _fallback:
			_fallback.apply_items(items)
		return
	for g in _garments.values():
		g.visible = false
	for it in items:
		var key := _template_for(it)
		if key == "" or not _garments.has(key):
			continue
		var mi: MeshInstance3D = _garments[key]
		mi.visible = true
		_tint(mi, it.placeholder_color)


func _template_for(it: ClothingItem) -> String:
	if it.model_template != "" and _garments.has(it.model_template):
		return it.model_template
	# Шаблон по умолчанию — первый подходящий по слоту.
	for k in _garments.keys():
		if str(k).begins_with(it.slot + "__"):
			return k
	return ""


func _prepare(node: Node) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var name := String(m.name)
		if name.begins_with("garment__"):
			_garments[name.trim_prefix("garment__")] = m
			m.visible = false
		for i in m.mesh.get_surface_count():
			m.set_surface_override_material(i, _toon_for(m.mesh.surface_get_material(i), name))


func _toon_for(src: Material, mesh_name: String) -> ShaderMaterial:
	var src_name := src.resource_name if src else ""
	var key := mesh_name + "/" + src_name if mesh_name.begins_with("garment__") else src_name
	if _materials.has(key):
		return _materials[key]
	var m := ShaderMaterial.new()
	m.shader = TOON
	var color := Color.WHITE
	if src is BaseMaterial3D:
		color = (src as BaseMaterial3D).albedo_color
		var t := (src as BaseMaterial3D).albedo_texture
		if t:
			m.set_shader_parameter("albedo_tex", t)
	m.set_shader_parameter("albedo", color)
	if src_name == "hair":
		m.set_shader_parameter("use_vertex_color", true)
		m.set_shader_parameter("shade_color", Color(0.62, 0.68, 0.86))
		m.set_shader_parameter("rim_strength", 0.45)
	elif src_name.begins_with("face") or src_name == "skin":
		m.set_shader_parameter("shade_color", Color(0.93, 0.76, 0.76))
	var outline := ShaderMaterial.new()
	outline.shader = OUTLINE
	# Волосам — тонкий контур: на прядях толстый контур выглядит как проволока.
	outline.set_shader_parameter("thickness", 0.0012 if src_name == "hair" else (0.0025 if src_name.begins_with("face") else 0.0035))
	m.next_pass = outline
	_materials[key] = m
	return m


## Цвет вещи: основной материал шаблона («garment_white») окрашивается, детали (цветы) остаются своими.
func _tint(mi: MeshInstance3D, c: Color) -> void:
	for i in mi.mesh.get_surface_count():
		var mat := mi.get_surface_override_material(i) as ShaderMaterial
		var src := mi.mesh.surface_get_material(i)
		if mat and src and src.resource_name == "garment_white":
			mat.set_shader_parameter("albedo", c)
