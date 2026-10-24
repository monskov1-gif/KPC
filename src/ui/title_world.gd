class_name TitleWorld
extends Node3D
## 3D-сцена титульного экрана (просьба пользователя 24.10): дом-отель плывёт по океану, Кот сидит в окне-
## куполе и смотрит вдаль; цветы на подоконнике, стекло с бликами, волны бегут навстречу, дом покачивается.
## Всё строится кодом (примитивы + шейдеры art/shaders/ocean, sky_anime, glass_dome) — без отдельных моделей.

const OCEAN := preload("res://art/shaders/ocean.gdshader")
const SKY := preload("res://art/shaders/sky_anime.gdshader")
const GLASS := preload("res://art/shaders/glass_dome.gdshader")
const TOON := preload("res://art/shaders/toon.gdshader")

const WALL := Color("dcb8a8")
const WALL_SHADE := Color("cfa898")
const WOOD := Color("8a5a46")
const ROOF := Color("5f8f96")
const TRIM := Color("fffaf4")
const WINDOW_GLOW := Color("ffd9a0")
const DOME_CENTER := Vector3(0.9, 0.85, 2.85)   # центр купола на кромке основания (выступает из фасада z = 2.4)
const DOME_R := 1.45
const KOT_YAW := 12.0                            # Кот повёрнут к открытому океану (вправо в кадре)
const LOOK_FAR := Vector3(30, 3, 22)

var house: Node3D           # покачивается целиком (дом на воде)
var kot: CharacterModel
var camera: Camera3D
var _t := 0.0
var _cam_base := Vector3.ZERO
var _look := Vector3.ZERO
var _cam_fixed := false      # кадр задан KPC_TITLE_CAM (подбор кадра) — не трогать при смене ориентации


func _ready() -> void:
	_environment()
	_ocean()
	house = Node3D.new()
	house.name = "House"
	add_child(house)
	_build_house()
	_build_dome()
	_seat_kot()
	_flowers()
	_camera()


func _process(delta: float) -> void:
	_t += delta
	# дом на воде: медленная качка с креном и подъёмом на волне (настройка «меньше движения» — едва заметно)
	var k := 0.25 if bool(Settings.get_value("reduce_motion")) else 1.0
	house.rotation = Vector3(deg_to_rad(sin(_t * 0.47 + 1.0) * 0.9 * k), 0.0, deg_to_rad(sin(_t * 0.61) * 1.4 * k))
	house.position.y = (sin(_t * 0.8) * 0.06 + 0.05) * k
	# камера чуть «дышит» вместе с домом (снимает с лодки рядом)
	if camera:
		camera.look_at_from_position(_cam_base + Vector3(sin(_t * 0.31) * 0.05, sin(_t * 0.5) * 0.04, 0.0) * k, _look)


func _environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = SKY
	sm.set_shader_parameter("cloud_noise", _noise_tex(512, 0.006, 5, 11))
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("f2dcd6")
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.82
	env.glow_enabled = not OS.has_environment("KPC_NO_GLOW")
	env.glow_intensity = 0.3
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.6
	env.fog_enabled = true
	env.fog_light_color = Color("f6d6c8")
	env.fog_density = 0.0012
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	# тёплое низкое солнце «золотого часа» спереди-слева: дом и Кот освещены, на волнах — искры
	sun.rotation_degrees = Vector3(-24, -38, 0)
	sun.light_color = Color("ffe4c8")
	sun.light_energy = 0.62
	sun.shadow_enabled = true
	add_child(sun)


func _noise_tex(size: int, freq: float, octaves: int, seed_v: int) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = octaves
	n.seed = seed_v
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.noise = n
	t.generate_mipmaps = true
	return t


func _ocean() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Ocean"
	var pm := PlaneMesh.new()
	pm.size = Vector2(260, 260)
	pm.subdivide_width = 220
	pm.subdivide_depth = 220
	mi.mesh = pm
	var m := ShaderMaterial.new()
	m.shader = OCEAN
	m.set_shader_parameter("foam_noise", _noise_tex(256, 0.03, 3, 4))
	m.set_shader_parameter("hull_center", Vector3(0, 0, 0))
	m.set_shader_parameter("hull_half", Vector2(3.4, 4.4))
	mi.material_override = m
	mi.position = Vector3(0, 0, -40)
	add_child(mi)


## Материал дома — тот же аниме-шейдер, что у персонажей: две зоны света, цветная тень (не «пересвеченный» PBR).
func _mat(c: Color, _rough := 0.85, emit := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TOON
	m.set_shader_parameter("albedo", c)
	m.set_shader_parameter("shade_color", Color(0.78, 0.68, 0.8))
	m.set_shader_parameter("shade_threshold", 0.45)
	m.set_shader_parameter("rim_strength", 0.12)
	if emit > 0.0:
		m.set_shader_parameter("emission_boost", emit * 0.6)
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.rotation_degrees = rot
	mi.material_override = mat
	parent.add_child(mi)
	return mi


## Дом-отель на плавучем основании: два этажа, двускатная крыша, окна светятся, ящики с цветами.
func _build_house() -> void:
	var wall := _mat(WALL)
	var shade := _mat(WALL_SHADE)
	var wood := _mat(WOOD, 0.7)
	var roof := _mat(ROOF, 0.6)
	var trim := _mat(TRIM)
	var glow := _mat(WINDOW_GLOW, 0.4, 0.5)
	# понтон-корпус: тёмное дерево, борт с белой полосой
	_box(house, Vector3(6.8, 1.1, 8.8), Vector3(0, -0.15, 0), wood)
	_box(house, Vector3(6.9, 0.12, 8.9), Vector3(0, 0.36, 0), trim)
	# веранда (палуба)
	_box(house, Vector3(6.6, 0.1, 8.6), Vector3(0, 0.45, 0), _mat(Color("c79a72"), 0.8))
	# этажи
	_box(house, Vector3(5.2, 2.6, 6.0), Vector3(0, 1.8, -0.6), wall)
	_box(house, Vector3(5.0, 2.2, 5.6), Vector3(0, 4.2, -0.7), shade)
	_box(house, Vector3(5.3, 0.14, 6.1), Vector3(0, 3.12, -0.6), trim)
	# крыша: два ската
	for sx in [-1, 1]:
		_box(house, Vector3(3.3, 0.16, 6.6), Vector3(sx * 1.38, 6.05, -0.7), roof, Vector3(0, 0, -sx * 34))
	_box(house, Vector3(0.3, 0.3, 6.7), Vector3(0, 6.95, -0.7), trim)
	_box(house, Vector3(0.6, 1.2, 0.6), Vector3(1.4, 6.9, -2.0), wall)          # труба
	# окна (тёплый свет внутри) и ставни
	for z in [-2.6, -0.4]:
		for y in [1.9, 4.3]:
			_box(house, Vector3(0.06, 0.9, 0.7), Vector3(2.61, y, z), glow)
			_box(house, Vector3(0.08, 1.02, 0.08), Vector3(2.63, y, z - 0.39), wood)
			_box(house, Vector3(0.08, 1.02, 0.08), Vector3(2.63, y, z + 0.39), wood)
			_box(house, Vector3(0.3, 0.12, 0.9), Vector3(2.7, y - 0.55, z), _mat(Color("b07a5a")))   # ящик с цветами
			for k in 4:
				_flower(house, Vector3(2.75, y - 0.45, z - 0.3 + k * 0.2), [Color("ff9eb8"), Color("fff0a8"), Color("c8a8ff"), Color("ffffff")][k % 4], 0.07)
	# фасад к камере (z = 2.4): круглое окошко второго этажа, окно и дверь первого, вывеска, вьюнок с цветами
	for wp in [Vector3(-1.95, 1.95, 2.42), Vector3(-1.2, 4.3, 2.32)]:
		_box(house, Vector3(0.8, 0.9, 0.06), wp, glow)
		_box(house, Vector3(0.96, 0.08, 0.1), wp + Vector3(0, 0.49, 0.02), trim)
		_box(house, Vector3(0.96, 0.08, 0.1), wp + Vector3(0, -0.49, 0.02), trim)
		_box(house, Vector3(0.08, 1.0, 0.1), wp + Vector3(0, 0, 0.02), trim)
		_box(house, Vector3(1.0, 0.16, 0.3), wp + Vector3(0, -0.6, 0.12), _mat(Color("b07a5a")))
		for k in 5:
			_flower(house, wp + Vector3(-0.4 + k * 0.2, -0.48, 0.16), [Color("ff9eb8"), Color("fff0a8"), Color("c8a8ff"), Color("ffffff"), Color("ffc8a0")][k], 0.07)
	_box(house, Vector3(0.8, 1.7, 0.08), Vector3(-0.85, 1.35, 2.43), wood)         # дверь
	_box(house, Vector3(0.12, 0.12, 0.06), Vector3(-0.6, 1.3, 2.48), _mat(Color("e8c46a"), 0.3, 0.6))
	var sign := Label3D.new()                                                       # вывеска «Отель» (дом-отель)
	sign.text = "Отель"
	sign.font_size = 64
	sign.outline_size = 10
	sign.modulate = Color("fff6e8")
	sign.outline_modulate = Color("8a5a46")
	sign.position = Vector3(-0.85, 2.62, 2.5)
	sign.pixel_size = 0.004
	house.add_child(sign)
	_box(house, Vector3(1.1, 0.34, 0.06), Vector3(-0.85, 2.62, 2.45), wood)
	var leaf_mat := _mat(Color("86b47c"))
	var leaf_dark := _mat(Color("6a9a66"))
	for k in 26:                                                                   # вьюнок по углу дома
		var y := 0.6 + k * 0.15
		var x := -2.5 + 0.12 * sin(k * 0.9) + 0.05 * sin(k * 2.3)
		var leaf := MeshInstance3D.new()
		var lm := SphereMesh.new()
		lm.radius = 0.07 + 0.03 * (k % 3); lm.height = lm.radius * 2.0
		leaf.mesh = lm
		leaf.scale = Vector3(1.0, 0.8, 0.35)                   # лист прижат к стене, а не «тарелка»
		leaf.position = Vector3(x + 0.06 * ((k % 2) * 2 - 1), y, 2.46 + 0.02 * (k % 2))
		leaf.material_override = leaf_mat if k % 3 else leaf_dark
		house.add_child(leaf)
		if k % 4 == 1:
			_flower(house, Vector3(x + 0.1, y + 0.04, 2.58), Color("ffb3c6") if k % 8 == 1 else Color("fff1a8"), 0.05)
	# фонарики на палубе
	for p in [Vector3(3.0, 0.9, 3.6), Vector3(-3.0, 0.9, 3.6), Vector3(3.0, 0.9, -4.0)]:
		_box(house, Vector3(0.06, 0.8, 0.06), p - Vector3(0, 0.4, 0), wood)
		var lamp := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 0.13; sp.height = 0.26
		lamp.mesh = sp
		lamp.material_override = _mat(Color("ffe0a8"), 0.3, 2.2)
		lamp.position = p + Vector3(0, 0.05, 0)
		house.add_child(lamp)
		var ol := OmniLight3D.new()
		ol.light_color = Color("ffcf90")
		ol.light_energy = 0.25
		ol.omni_range = 1.8
		ol.position = p + Vector3(0, 0.1, 0)
		house.add_child(ol)


## Окно-купол у фасада: круглое основание-подоконник, на нём стеклянный купол с тонкими белыми рёбрами
## (задняя часть купола уходит в стену — эркер). Внутри уютная ниша: подушка, тёплый свет, цветы в горшках.
func _build_dome() -> void:
	var c := DOME_CENTER                    # центр купола — на верхней кромке основания
	var r := DOME_R
	var base := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = r + 0.1; cy.bottom_radius = r + 0.04; cy.height = c.y - 0.5
	cy.radial_segments = 48
	base.mesh = cy
	base.position = Vector3(c.x, 0.5 + cy.height * 0.5, c.z)
	base.material_override = _mat(Color("c98f6e"))           # тёплое дерево, как ящики с цветами
	house.add_child(base)
	var white := _mat(TRIM, 0.4)
	var rim := MeshInstance3D.new()                         # кромка основания
	var tm := TorusMesh.new()
	tm.inner_radius = r - 0.02; tm.outer_radius = r + 0.13
	tm.rings = 64
	rim.mesh = tm
	rim.position = c
	rim.material_override = white
	house.add_child(rim)
	var cushion := MeshInstance3D.new()
	cushion.name = "Cushion"
	var cm := CylinderMesh.new()
	cm.top_radius = r * 0.62; cm.bottom_radius = r * 0.66; cm.height = 0.14
	cushion.mesh = cm
	cushion.position = c + Vector3(0.05, 0.07, 0.15)
	cushion.material_override = _mat(Color("f2a7b5"), 0.9)
	house.add_child(cushion)
	var nook := OmniLight3D.new()
	nook.light_color = Color("ffd7b0")
	nook.light_energy = 0.25
	nook.omni_range = 1.6
	nook.position = c + Vector3(0, 0.9, -0.2)
	house.add_child(nook)
	# стекло: полусфера вверх
	var glass := MeshInstance3D.new()
	glass.name = "DomeGlass"
	var sm := SphereMesh.new()
	sm.radius = r; sm.height = r                # у полусферы высота = радиус, иначе купол вытянут
	sm.is_hemisphere = true
	sm.radial_segments = 64; sm.rings = 32
	glass.mesh = sm
	glass.position = c
	var gm := ShaderMaterial.new()
	gm.shader = GLASS
	gm.render_priority = 1
	glass.material_override = gm
	house.add_child(glass)
	# рёбра: меридианы (нижняя половина тора прячется в основании, задняя — в стене) и пояс на середине
	var rib_mat := _mat(Color("fbf3ea"), 0.4)
	for phi in [-60.0, 0.0, 60.0]:
		var mer := MeshInstance3D.new()
		var t3 := TorusMesh.new()
		t3.inner_radius = r - 0.008; t3.outer_radius = r + 0.014
		t3.rings = 96
		mer.mesh = t3
		mer.rotation_degrees = Vector3(90, phi, 0)
		mer.position = c
		mer.material_override = rib_mat
		house.add_child(mer)
	var a := deg_to_rad(60.0)                   # пояс выше головы Кота, не перечёркивает лицо
	var belt := MeshInstance3D.new()
	var t2 := TorusMesh.new()
	t2.inner_radius = r * cos(a) - 0.008; t2.outer_radius = r * cos(a) + 0.014
	t2.rings = 96
	belt.mesh = t2
	belt.position = c + Vector3(0, r * sin(a), 0)
	belt.material_override = rib_mat
	house.add_child(belt)
	var top := MeshInstance3D.new()                          # шпиль-навершие
	var ts := SphereMesh.new()
	ts.radius = 0.06; ts.height = 0.12
	top.mesh = ts
	top.position = c + Vector3(0, r + 0.04, 0)
	top.material_override = _mat(Color("e8c46a"), 0.3, 0.4)
	house.add_child(top)


func _seat_kot() -> void:
	kot = CharacterModel.new()
	kot.name = "Kot"
	house.add_child(kot)
	var s := Game.session
	kot.setup("kot", s.characters)
	if s.outfit_items("kot").is_empty():
		s.equipment.equip_signature("kot")
	kot.apply_items(s.outfit_items("kot"))
	# сидит на подушке, обняв колени (поза sit сажает таз на уровень узла), и смотрит вдаль — на открытый океан
	kot.position = DOME_CENTER + Vector3(0.05, 0.14, 0.15)
	kot.rotation_degrees = Vector3(0, KOT_YAW, 0)
	kot.set_rest("sit", 0.0)
	if kot.face:
		kot.face.set_expression("neutral")
	await get_tree().process_frame
	kot.hold_pose({"forearm.L": 0.6, "forearm.R": 0.6, "upper_arm.L": 1.15, "upper_arm.R": 1.15})
	if kot.look:
		kot.look.target = LOOK_FAR


## Цветы в горшках по кромке основания (внутри купола) и пара горшков снаружи у подножия.
func _flowers() -> void:
	var c := DOME_CENTER
	var cols := [Color("ffb3c6"), Color("fff1a8"), Color("cdb4ff"), Color("ffd0a8"), Color("ffffff")]
	for k in 7:
		var ang := deg_to_rad(-80.0 + k * 26.0)
		var p := c + Vector3(sin(ang) * (DOME_R - 0.12), 0.07, cos(ang) * (DOME_R - 0.12))
		var pot := MeshInstance3D.new()
		var cy := CylinderMesh.new()
		cy.top_radius = 0.08; cy.bottom_radius = 0.06; cy.height = 0.13
		pot.mesh = cy
		pot.position = p
		pot.material_override = _mat(Color("e8a07a") if k % 2 else Color("f4f0ea"))
		house.add_child(pot)
		for j in 3:
			_flower(house, p + Vector3(-0.05 + j * 0.05, 0.12 + 0.06 * (j % 2), 0.02 * j), cols[(k + j) % cols.size()], 0.055)
	for k in 6:                                             # цветы у подножия основания
		var ang := deg_to_rad(-70.0 + k * 28.0)
		var p := Vector3(c.x + sin(ang) * (DOME_R + 0.28), 0.62, c.z + cos(ang) * (DOME_R + 0.28))
		_flower(house, p, cols[k % cols.size()], 0.07)
		_flower(house, p + Vector3(0.08, 0.06, 0.05), cols[(k + 2) % cols.size()], 0.06)


func _flower(parent: Node3D, pos: Vector3, col: Color, size: float) -> void:
	var stem := MeshInstance3D.new()
	var sc := CylinderMesh.new()
	sc.top_radius = size * 0.08; sc.bottom_radius = size * 0.1; sc.height = size * 2.0
	stem.mesh = sc
	stem.position = pos - Vector3(0, size * 0.9, 0)
	stem.material_override = _mat(Color("6aa36a"))
	parent.add_child(stem)
	var pm := _mat(col, 0.8, 0.15)
	for k in 5:
		var a := TAU * k / 5.0
		var petal := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = size * 0.45; sp.height = size * 0.5
		petal.mesh = sp
		petal.position = pos + Vector3(cos(a) * size * 0.5, size * 0.1, sin(a) * size * 0.5)
		petal.material_override = pm
		parent.add_child(petal)
	var core := MeshInstance3D.new()
	var cs := SphereMesh.new()
	cs.radius = size * 0.28; cs.height = size * 0.5
	core.mesh = cs
	core.position = pos + Vector3(0, size * 0.18, 0)
	core.material_override = _mat(Color("ffc860"), 0.6, 0.3)
	parent.add_child(core)


const CAM_WIDE := Vector3(-1.0, 1.8, 8.6)
const CAM_TALL := Vector3(0.4, 1.9, 9.6)
const LOOK_AT := Vector3(1.6, 1.6, 2.6)
const LOOK_TALL := Vector3(0.9, 1.75, 2.6)


func _camera() -> void:
	camera = Camera3D.new()
	camera.fov = 40
	# снаружи, с воды: купол с Котом справа, слева — открытый океан и горизонт
	_cam_base = CAM_WIDE
	camera.position = _cam_base
	add_child(camera)
	_look = LOOK_AT
	if OS.has_environment("KPC_TITLE_CAM"):          # подбор кадра: «x,y,z;lx,ly,lz;fov»
		var parts := OS.get_environment("KPC_TITLE_CAM").split(";")
		var a := parts[0].split_floats(",")
		var b := parts[1].split_floats(",")
		_cam_base = Vector3(a[0], a[1], a[2])
		_look = Vector3(b[0], b[1], b[2])
		if parts.size() > 2:
			camera.fov = float(parts[2])
		_cam_fixed = true
	camera.look_at_from_position(_cam_base, _look)
	camera.current = true


## Портретный экран: купол по центру, камера дальше.
func set_portrait(on: bool) -> void:
	if camera == null or _cam_fixed:
		return
	_cam_base = CAM_TALL if on else CAM_WIDE
	_look = LOOK_TALL if on else LOOK_AT
	camera.look_at_from_position(_cam_base, _look)
	camera.fov = 56 if on else 40
