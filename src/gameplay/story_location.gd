class_name StoryLocation
extends Node3D
## Локация сюжета: модель art/locations/<id>.glb (строится tools/art/build_locations.py), её точки
## (spawn*, npc_*, int_*, reach_*), свет по времени суток и уровень воды.
## Столкновения — меши с суффиксом «-col»/«-colonly» (их создаёт импорт glTF в Godot).

const DIR := "res://art/locations/"
const TOON := preload("res://art/shaders/toon.gdshader")
const OUTLINE := preload("res://art/shaders/outline.gdshader")
const WATER := preload("res://art/shaders/water.gdshader")

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
var _sky: ProceduralSkyMaterial
var _lamps: Array[OmniLight3D] = []
var _materials := {}
var _glow: Array[ShaderMaterial] = []
var _tween: Tween
var _water_tween: Tween
## Дождь (время «storm»): частицы-штрихи; StoryGame держит его над игроком.
var rain: CPUParticles3D


func _ready() -> void:
	_sky = ProceduralSkyMaterial.new()
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
	time_of_day = t
	if _tween:
		_tween.kill()
	rain.emitting = t == "storm"
	rain.visible = t == "storm"
	var lamps_on := t in ["night", "storm", "evening"]
	for l in _lamps:
		l.visible = lamps_on
	for g in _glow:
		_set_glow(g, t)
	var rot := Vector3(deg_to_rad(p.pitch), deg_to_rad(p.yaw), 0)
	if seconds <= 0.0:
		_sun.light_color = p.sun
		_sun.light_energy = p.energy
		_sun.rotation = rot
		_sky.sky_top_color = p.sky_top
		_sky.sky_horizon_color = p.sky_horizon
		_sky.ground_horizon_color = p.sky_horizon
		_sky.ground_bottom_color = p.ground
		_env.ambient_light_color = p.ambient
		_env.ambient_light_energy = p.ambient_energy
		_env.fog_light_color = p.fog
		_env.fog_density = p.fog_density
		return
	_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE)
	_tween.tween_property(_sun, "light_color", p.sun, seconds)
	_tween.tween_property(_sun, "light_energy", p.energy, seconds)
	_tween.tween_property(_sun, "rotation", rot, seconds)
	_tween.tween_property(_sky, "sky_top_color", p.sky_top, seconds)
	_tween.tween_property(_sky, "sky_horizon_color", p.sky_horizon, seconds)
	_tween.tween_property(_sky, "ground_horizon_color", p.sky_horizon, seconds)
	_tween.tween_property(_sky, "ground_bottom_color", p.ground, seconds)
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
		if nm.begins_with("lamp_") and not n is MeshInstance3D:
			var l := OmniLight3D.new()
			l.light_color = Color("ffd59a")
			l.light_energy = 0.7
			l.omni_range = 5.0
			n.add_child(l)
			_lamps.append(l)
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
			m.set_surface_override_material(i, _toon(m.mesh.surface_get_material(i), nm.begins_with("prop_"), vcol))


func _toon(src: Material, outline: bool, vcol: bool) -> ShaderMaterial:
	var key := (src.resource_name if src else "") + ("/o" if outline else "") + ("/v" if vcol else "")
	if _materials.has(key):
		return _materials[key]
	var m := ShaderMaterial.new()
	m.shader = TOON
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
		# сигнальные фонари переезда — свой цвет из вершин, светятся всегда
		m.set_shader_parameter("albedo", Color.WHITE)
		m.set_shader_parameter("emission_boost", 0.6)
	elif kind == "glow_lamp":
		m.set_shader_parameter("albedo", Color("fff0c8"))
		m.set_shader_parameter("emission_boost", 1.6 if lit else 0.0)
	else:
		m.set_shader_parameter("albedo", Color("ffd99a") if lit else Color("c4d9ea"))
		m.set_shader_parameter("emission_boost", (0.85 if dark else 0.45) if lit else 0.05)
