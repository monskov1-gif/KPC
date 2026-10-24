class_name StoryLocation
extends Node3D
## Локация сюжета: модель art/locations/<id>.glb (строится tools/art/build_locations.py), её точки
## (spawn*, npc_*, int_*, reach_*), свет по времени суток и уровень воды.
## Столкновения — меши с суффиксом «-col»/«-colonly» (их создаёт импорт glTF в Godot).

const DIR := "res://art/locations/"
const TOON := preload("res://art/shaders/toon_loc.gdshader")
const ADDITIVE := preload("res://art/shaders/loc_additive.gdshader")
const VIEW := preload("res://art/shaders/loc_view.gdshader")
## Состояния света для объектов с суффиксом «__day» / «__evening» / «__night» (location-kit: statePool, brightWindow).
const STATE_OF_TIME := {"day": "day", "evening": "evening", "night": "night", "storm": "evening"}
const OUTLINE := preload("res://art/shaders/outline.gdshader")
const WATER := preload("res://art/shaders/water.gdshader")
const SKY := preload("res://art/shaders/sky_anime.gdshader")
## Нарисованное небо по времени суток (art/shaders/sky_anime): градиент, облака, ночью — звёзды.
const SKY_PRESETS := {
	"day": {"zenith": Color("5c8fdc"), "upper": Color("9ec4ee"), "lilac": Color("dcd6f0"), "horizon": Color("fbe6da"),
		"below": Color("d9c8c4"), "cloud_light": Color("ffffff"), "cloud_shadow": Color("e8d2e2"), "cloud_cover": 0.5,
		"stars": 0.0, "sun_glow": 0.35},
	"evening": {"zenith": Color("5a5fae"), "upper": Color("8a86c8"), "lilac": Color("e4a6c0"), "horizon": Color("ffbd8e"),
		"below": Color("8a6c78"), "cloud_light": Color("ffe2c8"), "cloud_shadow": Color("e08a9a"), "cloud_cover": 0.54,
		"stars": 0.0, "sun_glow": 0.6},
	"night": {"zenith": Color("0f1638"), "upper": Color("1d2550"), "lilac": Color("343a76"), "horizon": Color("4a4f86"),
		"below": Color("232744"), "cloud_light": Color("5a6496"), "cloud_shadow": Color("2a3060"), "cloud_cover": 0.6,
		"stars": 1.0, "sun_glow": 0.1},
	"storm": {"zenith": Color("4a5262"), "upper": Color("5b6474"), "lilac": Color("6e7684"), "horizon": Color("8f97a2"),
		"below": Color("4a505a"), "cloud_light": Color("a2aab6"), "cloud_shadow": Color("5a6270"), "cloud_cover": 0.22,
		"stars": 0.0, "sun_glow": 0.0},
}

## Свет и небо по времени суток (мягкая «облачная» палитра; ночь — синяя, не чёрная).
const TIME_PRESETS := {
	"day": {"sun": Color("fff3e2"), "energy": 0.78, "pitch": -48.0, "yaw": -35.0,
		"sky_top": Color("9cc6ec"), "sky_horizon": Color("f6e2dc"), "ground": Color("d9c8c4"),
		"ambient": Color("f2e6e6"), "ambient_energy": 0.32, "fog": Color("dfe6ee"), "fog_density": 0.0022},
	"evening": {"sun": Color("ffb07a"), "energy": 0.72, "pitch": -14.0, "yaw": -70.0,
		"sky_top": Color("7f86c8"), "sky_horizon": Color("ffbc94"), "ground": Color("8a6c78"),
		"ambient": Color("e8c4c4"), "ambient_energy": 0.3, "fog": Color("f0b8a8"), "fog_density": 0.006},
	"night": {"sun": Color("aebef0"), "energy": 0.32, "pitch": -40.0, "yaw": 20.0,
		"sky_top": Color("1d2550"), "sky_horizon": Color("4a4f86"), "ground": Color("232744"),
		"ambient": Color("6f78b4"), "ambient_energy": 0.24, "fog": Color("343a6a"), "fog_density": 0.01},
	"storm": {"sun": Color("c4ccd8"), "energy": 0.35, "pitch": -60.0, "yaw": 0.0,
		"sky_top": Color("5b6474"), "sky_horizon": Color("8f97a2"), "ground": Color("4a505a"),
		"ambient": Color("a8b0bc"), "ambient_energy": 0.36, "fog": Color("8a929c"), "fog_density": 0.03},
}

var location_id := ""
var time_of_day := "day"
var water: MeshInstance3D
var _model: Node3D
var _env: Environment
var _sun: DirectionalLight3D
var _sky: ShaderMaterial
var _lamps: Array[OmniLight3D] = []
var _materials := {}
var _glow: Array[ShaderMaterial] = []
var _state_nodes: Array[Node3D] = []     # видимы только в своём состоянии света
var _fills: Array[OmniLight3D] = []      # дневная подсветка интерьера (fill_*)
var _moons: Array[OmniLight3D] = []      # лунный свет из окон (moon_*)
var _tween: Tween
var _water_tween: Tween
## Дождь (время «storm»): частицы-штрихи; StoryGame держит его над игроком.
var rain: CPUParticles3D


func _ready() -> void:
	_sky = ShaderMaterial.new()
	_sky.shader = SKY
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.006
	noise.fractal_octaves = 5
	var nt := NoiseTexture2D.new()
	nt.width = 512
	nt.height = 512
	nt.seamless = true
	nt.generate_mipmaps = true
	nt.noise = noise
	_sky.set_shader_parameter("cloud_noise", nt)
	var sky := Sky.new()
	sky.sky_material = _sky
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# Отражения неба выключены: на аниме-шейдере они «выбеливали» освещённые стороны.
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	_env.fog_enabled = true
	# мягкое свечение фонарей и окон, чуть сочнее цвет (видео 2AM: блум и цветокоррекция как в ZZZ)
	_env.glow_enabled = true
	_env.glow_intensity = 0.45
	_env.glow_bloom = 0.06
	_env.glow_hdr_threshold = 1.0
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 1.08
	_env.adjustment_contrast = 1.03
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	# В рендерере Compatibility (веб) тени солнца на аниме-шейдере пересвечивают освещённые стороны —
	# там теней от солнца нет, под персонажами — мягкие пятна (StoryGame.blob_shadow).
	_sun.shadow_enabled = not compat()
	_sun.directional_shadow_max_distance = 40.0
	add_child(_sun)
	rain = CPUParticles3D.new()
	rain.amount = 900
	rain.lifetime = 0.9
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(14, 0.5, 14)
	rain.direction = Vector3(0.15, -1, 0.05)
	rain.spread = 2.0
	rain.gravity = Vector3(0, -6, 0)
	rain.initial_velocity_min = 14.0
	rain.initial_velocity_max = 18.0
	var streak := QuadMesh.new()
	streak.size = Vector2(0.025, 0.55)
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	rm.albedo_color = Color(0.85, 0.9, 1.0, 0.45)
	streak.material = rm
	rain.mesh = streak
	rain.emitting = false
	rain.visible = false
	add_child(rain)


static func compat() -> bool:
	return RenderingServer.get_current_rendering_method() == "gl_compatibility"


func load_location(id: String) -> bool:
	if _model:
		_model.queue_free()
		_model = null
	water = null
	_lamps.clear()
	_glow.clear()
	_materials.clear()
	_state_nodes.clear()
	_fills.clear()
	_moons.clear()
	location_id = id
	var path := DIR + id + ".glb"
	if not ResourceLoader.exists(path):
		push_error("Нет локации %s" % path)
		return false
	_model = (load(path) as PackedScene).instantiate()
	add_child(_model)
	if not OS.has_environment("KPC_DBG_PLAIN"):
		_stylize(_model)
	return true


func has_marker(marker_name: String) -> bool:
	return _model != null and _model.find_child(marker_name, true, false) != null


## Положение точки локации; если точки нет — начало координат (и предупреждение).
func marker(marker_name: String) -> Transform3D:
	var n := _model.find_child(marker_name, true, false) as Node3D if _model else null
	if n == null:
		push_warning("%s: нет точки %s" % [location_id, marker_name])
		return Transform3D.IDENTITY
	return n.global_transform


## Время суток: мгновенно (seconds = 0) или плавным переходом.
func apply_time(t: String, seconds := 0.0) -> void:
	var p: Dictionary = TIME_PRESETS.get(t, TIME_PRESETS.day)
	var sp: Dictionary = SKY_PRESETS.get(t, SKY_PRESETS.day)
	time_of_day = t
	if _tween:
		_tween.kill()
	rain.emitting = t == "storm"
	rain.visible = t == "storm"
	var lamps_on := t in ["night", "storm", "evening"]
	for l in _lamps:
		l.visible = lamps_on
	for l in _fills:
		l.visible = t == "day"
	for l in _moons:
		l.visible = t == "night"
	var st: String = STATE_OF_TIME.get(t, "day")
	for n in _state_nodes:
		n.visible = (String(n.name).get_slice("__", 1)).split("_").has(st)
	for g in _glow:
		_set_glow(g, t)
	var rot := Vector3(deg_to_rad(p.pitch), deg_to_rad(p.yaw), 0)
	if seconds <= 0.0:
		_sun.light_color = p.sun
		_sun.light_energy = p.energy
		_sun.rotation = rot
		for k in sp:
			_sky.set_shader_parameter(k, sp[k])
		_env.ambient_light_color = p.ambient
		_env.ambient_light_energy = p.ambient_energy
		_env.fog_light_color = p.fog
		_env.fog_density = p.fog_density
		return
	_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE)
	_tween.tween_property(_sun, "light_color", p.sun, seconds)
	_tween.tween_property(_sun, "light_energy", p.energy, seconds)
	_tween.tween_property(_sun, "rotation", rot, seconds)
	for k in sp:
		_tween.tween_property(_sky, "shader_parameter/" + k, sp[k], seconds)
	_tween.tween_property(_env, "ambient_light_color", p.ambient, seconds)
	_tween.tween_property(_env, "ambient_light_energy", p.ambient_energy, seconds)
	_tween.tween_property(_env, "fog_light_color", p.fog, seconds)
	_tween.tween_property(_env, "fog_density", p.fog_density, seconds)


## Высота воды над уровнем улицы (м). Возвращает твин, чтобы режиссёр мог дождаться подъёма.
func set_water(level: float, seconds: float) -> Tween:
	if water == null:
		push_warning("%s: в локации нет воды" % location_id)
		return null
	if _water_tween and _water_tween.is_valid():
		_water_tween.kill()
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(water, "position:y", level, seconds)
	_water_tween = tw
	return tw


## Пропуск катсцены: свет и вода сразу в итоговом состоянии.
func finish_tweens() -> void:
	for t in [_tween, _water_tween]:
		if t and t.is_valid() and t.is_running():
			t.custom_step(1000.0)


func water_level() -> float:
	return water.global_position.y if water else -INF


## Материалы Blender → аниме-шейдер; «water» — анимированная вода; «lamp_*» — источники света.
func _stylize(root: Node) -> void:
	for n in root.find_children("*", "Node3D", true, false):
		var nm := String(n.name)
		if "__" in nm:
			_state_nodes.append(n)
		if n is MeshInstance3D:
			continue
		if nm.begins_with("lamp_"):
			_lamps.append(_omni(n, Color("ffd59a"), 0.7, 5.0))
		elif nm.begins_with("fill_"):
			_fills.append(_omni(n, Color("e6eef6"), 0.45, 7.0))
		elif nm.begins_with("moon_"):
			_moons.append(_omni(n, Color("7f96d6"), 0.5, 6.0))
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var nm := String(m.name)
		if nm.begins_with("water"):
			if nm == "water":
				water = m
			var wm := ShaderMaterial.new()
			wm.shader = WATER
			m.material_override = wm
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			continue
		if nm.begins_with("far_") or nm.ends_with("_far") or nm.begins_with("ceiling"):
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in m.mesh.get_surface_count():
			var vcol: bool = (m.mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_COLOR) != 0
			var src := m.mesh.surface_get_material(i)
			var sname := src.resource_name if src else ""
			if sname.begins_with("add_") or sname.begins_with("view_"):
				m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var mat := _toon(src, nm.begins_with("prop_"), vcol)
			var w := _wind_for(nm, m)
			if w.x > 0.0:
				mat = _windy(mat, w)
			m.set_surface_override_material(i, mat)


## Ветер по имени меша: листва деревьев, изгороди, бельё на верёвке, шторы.
## Возвращает (размах, высота крепления или 1e6, длина подвеса).
func _wind_for(mesh_name: String, m: MeshInstance3D) -> Vector3:
	if mesh_name.begins_with("prop_trees"):
		return Vector3(0.05, 1e6, 1.0)
	if mesh_name.begins_with("prop_hedges"):
		return Vector3(0.012, 1e6, 1.0)
	if mesh_name.begins_with("prop_clothes") or mesh_name.begins_with("prop_curtains"):
		var top := (m.global_transform * m.get_aabb()).end.y if m.is_inside_tree() else m.get_aabb().end.y
		return Vector3(0.09 if mesh_name.begins_with("prop_clothes") else 0.015, top - 0.03, 0.6)
	return Vector3.ZERO


## Копия материала с ветром (и контур — тоже с ветром, иначе он отстаёт от листвы).
func _windy(mat: ShaderMaterial, w: Vector3) -> ShaderMaterial:
	var key := "%d/wind/%.3f/%.2f" % [mat.get_instance_id(), w.x, w.y]
	if _materials.has(key):
		return _materials[key]
	var m := mat.duplicate() as ShaderMaterial
	if mat.next_pass:
		m.next_pass = mat.next_pass.duplicate()
	for p in [m, m.next_pass]:
		if p is ShaderMaterial:
			p.set_shader_parameter("wind", w.x)
			p.set_shader_parameter("wind_pin_top", w.y)
			p.set_shader_parameter("wind_span", w.z)
	_materials[key] = m
	return m


func _toon(src: Material, outline: bool, vcol: bool) -> ShaderMaterial:
	var key := (src.resource_name if src else "") + ("/o" if outline else "") + ("/v" if vcol else "")
	if _materials.has(key):
		return _materials[key]
	var m := ShaderMaterial.new()
	var sname := src.resource_name if src else ""
	var tex: Texture2D = (src as BaseMaterial3D).albedo_texture if src is BaseMaterial3D else null
	if sname.begins_with("add_"):
		# лучи и пятна света: аддитивно; без текстуры (блик на стекле) — сплошная заливка
		m.shader = ADDITIVE
		m.set_shader_parameter("tex", tex)
		_materials[key] = m
		return m
	if sname.begins_with("view_"):
		m.shader = VIEW
		m.set_shader_parameter("tex", tex)
		_materials[key] = m
		return m
	m.shader = TOON
	if sname.begins_with("alpha_"):
		m.set_shader_parameter("use_alpha_scissor", true)
	if src is BaseMaterial3D:
		var b := src as BaseMaterial3D
		m.set_shader_parameter("albedo", b.albedo_color.srgb_to_linear())
		if b.albedo_texture:
			m.set_shader_parameter("albedo_tex", b.albedo_texture)
	m.set_shader_parameter("use_vertex_color", vcol)
	m.set_shader_parameter("shade_color", Color(0.72, 0.68, 0.86))
	m.set_shader_parameter("shade_softness", 0.12)
	m.set_shader_parameter("rim_strength", 0.12)
	if src and src.resource_name.begins_with("glow"):
		# окна и фонари: днём — стекло, вечером и ночью — тёплый свет (apply_time)
		m.set_shader_parameter("rim_strength", 0.0)
		m.set_meta("kind", src.resource_name)
		_glow.append(m)
		_set_glow(m, time_of_day)
	if outline:
		var o := ShaderMaterial.new()
		o.shader = OUTLINE
		o.set_shader_parameter("thickness", 0.012)
		o.set_shader_parameter("outline_color", Color(0.36, 0.28, 0.34))
		m.next_pass = o
	_materials[key] = m
	return m


## Окна: днём голубоватое стекло, вечером и ночью — тёплый свет; фонари светятся только в темноте.
func _set_glow(m: ShaderMaterial, t: String) -> void:
	var kind: String = m.get_meta("kind", "")
	var dark := t in ["night", "storm"]
	var lit := dark or t == "evening"
	if kind == "glow_signal":
		# стёкла фонарей переезда — тёмно-красные; мигают отдельные огни поверх (WorldLife, при подходе поезда)
		m.set_shader_parameter("albedo", Color(0.55, 0.5, 0.5))
		m.set_shader_parameter("emission_boost", 0.0)
	elif kind == "glow_lamp":
		m.set_shader_parameter("albedo", Color("fff0c8"))
		m.set_shader_parameter("emission_boost", 1.6 if lit else 0.0)
	else:
		m.set_shader_parameter("albedo", Color("ffd99a") if lit else Color("c4d9ea"))
		m.set_shader_parameter("emission_boost", (0.85 if dark else 0.45) if lit else 0.05)


func _omni(parent: Node3D, color: Color, energy: float, rng: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = false
	parent.add_child(l)
	return l
