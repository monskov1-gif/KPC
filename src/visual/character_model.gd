class_name CharacterModel
extends Node3D
## 3D-прототип персонажа из art/characters/<id>.glb (строится tools/art/build_characters.py).
## Аниме-шейдер + контур, анимация покоя, одежда — меши-шаблоны «garment__<слот>__<шаблон>»:
## показываются по надетым вещам и окрашиваются в цвет вещи. Если модели нет — показывает манекен-заглушку.

const TOON := preload("res://art/shaders/toon.gdshader")
const OUTLINE := preload("res://art/shaders/outline.gdshader")
const HAIR := preload("res://art/shaders/toon_hair.gdshader")
const MODEL_DIR := "res://art/characters/"

var character_id := ""
var _root: Node3D
var _garments: Dictionary = {}     # "слот__шаблон" -> MeshInstance3D
var _underwear: Dictionary = {}    # "briefs"/"panties"/"bra" -> MeshInstance3D

## Какие слоты одежды закрывают какую часть белья. Бельё скрывается только под вещью,
## поэтому полностью раздеть персонажа нельзя (без вещей бельё всегда видно).
const UNDERWEAR_COVERED_BY := {
	"bra": ["upper_body", "outerwear", "full_body"],
	"briefs": ["lower_body", "full_body"],
	"panties": ["lower_body", "full_body"],
}
var _materials: Dictionary = {}    # кэш материалов по ключу
var _fallback: PlaceholderAppearance


func setup(p_character_id: String, characters: CharacterCatalog) -> void:
	character_id = p_character_id
	if _root:
		_root.queue_free()
		_root = null
	_garments.clear()
	_underwear.clear()
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
	var slots := {}
	for it in items:
		slots[it.slot] = true
	for part in _underwear:
		var covered := false
		for slot in UNDERWEAR_COVERED_BY.get(part, []):
			covered = covered or slots.has(slot)
		(_underwear[part] as MeshInstance3D).visible = not covered
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
		# underwear__* — базовый слой: всегда виден, раздеть полностью нельзя.
		if name.begins_with("garment__"):
			_garments[name.trim_prefix("garment__")] = m
			m.visible = false
		elif name.begins_with("underwear__"):
			_underwear[name.trim_prefix("underwear__")] = m
		for i in m.mesh.get_surface_count():
			m.set_surface_override_material(i, _toon_for(m.mesh.surface_get_material(i), name))


func _toon_for(src: Material, mesh_name: String) -> ShaderMaterial:
	var src_name := src.resource_name if src else ""
	var key := mesh_name + "/" + src_name if mesh_name.begins_with("garment__") else src_name
	if _materials.has(key):
		return _materials[key]
	var tex: Texture2D = (src as BaseMaterial3D).albedo_texture if src is BaseMaterial3D else null
	# glTF хранит цвет в линейном пространстве, импорт переводит его в sRGB; тун-шейдер берёт цвет как есть,
	# поэтому возвращаем исходное значение из Blender — иначе тёмные цвета (ремень, бельё) выходят блёклыми.
	var color: Color = (src as BaseMaterial3D).albedo_color.srgb_to_linear() if src is BaseMaterial3D else Color.WHITE
	var m := ShaderMaterial.new()
	if src_name == "hair":
		# Карты прядей: отдельный шейдер, без контура (контур на полупрозрачных картах даёт «проволоку»).
		m.shader = HAIR
		m.set_shader_parameter("strands", tex)
		_materials[key] = m
		return m
	m.shader = TOON
	if tex:
		m.set_shader_parameter("albedo_tex", tex)
	m.set_shader_parameter("albedo", color)
	var thickness := 0.0032
	match src_name:
		"hair_cap":
			m.set_shader_parameter("use_vertex_color", true)
			m.set_shader_parameter("shade_color", Color(0.58, 0.64, 0.86))
			thickness = 0.0
		"hair_solid":
			# Объёмные пряди-клоки: тун-свет + тонкий контур, чтобы читались завитки.
			m.set_shader_parameter("use_vertex_color", true)
			m.set_shader_parameter("shade_color", Color(0.62, 0.68, 0.9))
			thickness = 0.0012
		"skin":
			m.set_shader_parameter("shade_color", Color(0.94, 0.76, 0.76))
		_:
			if src_name.begins_with("face"):
				m.set_shader_parameter("shade_color", Color(0.95, 0.8, 0.8))
				m.set_shader_parameter("use_alpha_scissor", true)
				thickness = 0.0022
			elif src_name.begins_with("eye"):
				m.set_shader_parameter("shade_color", Color(0.85, 0.85, 0.95))
				m.set_shader_parameter("rim_strength", 0.0)
				thickness = 0.0
	if thickness > 0.0:
		var outline := ShaderMaterial.new()
		outline.shader = OUTLINE
		outline.set_shader_parameter("thickness", thickness)
		if src_name.begins_with("face") and tex:
			outline.set_shader_parameter("mask_tex", tex)
			outline.set_shader_parameter("use_mask", true)
		m.next_pass = outline
	_materials[key] = m
	return m


## Цвет вещи: основная ткань шаблона («garment_*») окрашивается; детали (цветы, пряжка, ремень) остаются своими.
func _tint(mi: MeshInstance3D, c: Color) -> void:
	for i in mi.mesh.get_surface_count():
		var mat := mi.get_surface_override_material(i) as ShaderMaterial
		var src := mi.mesh.surface_get_material(i)
		if mat and src and src.resource_name.begins_with("garment_"):
			mat.set_shader_parameter("albedo", c)
