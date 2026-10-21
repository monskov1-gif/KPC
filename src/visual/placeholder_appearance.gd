class_name PlaceholderAppearance
extends Node3D
## PLACEHOLDER-визуализация персонажа и одежды из примитивов, пока нет моделей.
## Не является финальной визуальной системой: показывает слоты, цвета и рост, чтобы проверять логику примерки.
## Узлы частей создаются один раз и переиспользуются — смена одежды не плодит объекты.

const DEFAULT_HEIGHT_CM := 160.0

var _parts: Dictionary = {}      # имя части -> MeshInstance3D
var _materials: Dictionary = {}  # Color.to_html() -> StandardMaterial3D
var _height_scale := 1.0


func setup(character_id: String, characters: CharacterCatalog) -> void:
	var h = characters.get_data(character_id).get("height_cm")
	var height_cm: float = float(h) if h != null else DEFAULT_HEIGHT_CM
	_height_scale = height_cm / DEFAULT_HEIGHT_CM
	scale = Vector3.ONE * _height_scale
	_ensure_parts()
	var skin := Color(0.96, 0.86, 0.80)
	_paint("body", skin)
	_paint("head", skin)
	_paint("hair", characters.placeholder_color(character_id))
	_paint("ear_l", characters.placeholder_color(character_id))
	_paint("ear_r", characters.placeholder_color(character_id))
	# Кошачьи уши — особенность Кота по референсу; у других персонажей скрыты.
	_parts.ear_l.visible = character_id == "kot"
	_parts.ear_r.visible = character_id == "kot"


## Обновляет видимые части по списку надетых предметов.
func apply_items(items: Array[ClothingItem]) -> void:
	_ensure_parts()
	for p in ["top", "outer", "skirt", "legs", "shoe_l", "shoe_r", "sock_l", "sock_r", "hat", "patch", "neck", "glove_l", "glove_r", "bag"]:
		_parts[p].visible = false
	for it in items:
		var c := it.placeholder_color
		for s in it.all_slots():
			match s:
				"upper_body":
					_show("top", c)
				"lower_body":
					_show("legs", c)
				"full_body":
					_show("top", c)
					_show("skirt", c)
				"outerwear":
					_show("outer", c)
				"footwear":
					_show("shoe_l", c); _show("shoe_r", c)
				"socks":
					_show("sock_l", c); _show("sock_r", c)
				"headwear":
					_show("hat", c)
				"face_accessory":
					_show("patch", c)
				"neck_accessory":
					_show("neck", c)
				"gloves":
					_show("glove_l", c); _show("glove_r", c)
				"bag":
					_show("bag", c)


func _show(part: String, c: Color) -> void:
	_parts[part].visible = true
	_paint(part, c)


func _paint(part: String, c: Color) -> void:
	var key := c.to_html()
	if not _materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.75
		_materials[key] = m
	(_parts[part] as MeshInstance3D).material_override = _materials[key]


func _ensure_parts() -> void:
	if not _parts.is_empty():
		return
	# Пропорции условные: рост 1.6 м при масштабе 1.
	_add("body", _capsule(0.17, 0.95), Vector3(0, 0.95, 0))
	_add("head", _sphere(0.15), Vector3(0, 1.48, 0))
	_add("hair", _sphere(0.165, 0.6), Vector3(0, 1.53, -0.01))
	_add("ear_l", _cone(0.05, 0.12), Vector3(-0.09, 1.66, 0), Vector3(0, 0, 20))
	_add("ear_r", _cone(0.05, 0.12), Vector3(0.09, 1.66, 0), Vector3(0, 0, -20))
	_add("top", _cylinder(0.2, 0.18, 0.5), Vector3(0, 1.1, 0))
	_add("outer", _cylinder(0.23, 0.21, 0.56), Vector3(0, 1.08, 0))
	_add("skirt", _cylinder(0.19, 0.32, 0.55), Vector3(0, 0.62, 0))
	_add("legs", _cylinder(0.17, 0.14, 0.78), Vector3(0, 0.47, 0))
	_add("sock_l", _cylinder(0.055, 0.05, 0.3), Vector3(-0.08, 0.2, 0))
	_add("sock_r", _cylinder(0.055, 0.05, 0.3), Vector3(0.08, 0.2, 0))
	_add("shoe_l", _box(Vector3(0.1, 0.07, 0.2)), Vector3(-0.08, 0.035, 0.03))
	_add("shoe_r", _box(Vector3(0.1, 0.07, 0.2)), Vector3(0.08, 0.035, 0.03))
	_add("hat", _box(Vector3(0.12, 0.05, 0.05)), Vector3(0.1, 1.6, 0.08))
	_add("patch", _box(Vector3(0.07, 0.06, 0.02)), Vector3(-0.055, 1.5, 0.145))
	_add("neck", _torus(0.08, 0.1), Vector3(0, 1.33, 0))
	_add("glove_l", _sphere(0.055), Vector3(-0.26, 0.82, 0))
	_add("glove_r", _sphere(0.055), Vector3(0.26, 0.82, 0))
	_add("bag", _box(Vector3(0.18, 0.2, 0.08)), Vector3(0.3, 0.85, 0))


func _add(part: String, mesh: Mesh, pos: Vector3, rot_deg := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	mi.name = part
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = rot_deg
	add_child(mi)
	_parts[part] = mi


func _capsule(r: float, h: float) -> Mesh:
	var m := CapsuleMesh.new(); m.radius = r; m.height = h; return m


func _sphere(r: float, h_frac := 1.0) -> Mesh:
	var m := SphereMesh.new(); m.radius = r; m.height = r * 2.0 * h_frac; return m


func _cylinder(top: float, bottom: float, h: float) -> Mesh:
	var m := CylinderMesh.new(); m.top_radius = top; m.bottom_radius = bottom; m.height = h; return m


func _cone(r: float, h: float) -> Mesh:
	return _cylinder(0.0, r, h)


func _box(s: Vector3) -> Mesh:
	var m := BoxMesh.new(); m.size = s; return m


func _torus(inner: float, outer: float) -> Mesh:
	var m := TorusMesh.new(); m.inner_radius = inner; m.outer_radius = outer; return m
