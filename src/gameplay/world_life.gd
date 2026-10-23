class_name WorldLife
extends Node3D
## Живой мир локации по data/world/life.json: прохожие идут по маршрутам и уступают дорогу герою,
## птицы кружат стайками, через переезд ходит поезд (звонок, мигающие фонари, шлагбаумы), плывут облака,
## на склоне идёт снег. Что есть при каком времени суток — поле "times". Пересоздаётся при смене локации.

const DATA_PATH := "res://data/world/life.json"
const TOON := preload("res://art/shaders/toon_loc.gdshader")

var location: StoryLocation
var player: Node3D
var time_of_day := "day"
var _cfg: Dictionary = {}
var _walkers: Array[Dictionary] = []
var _birds: Array[Dictionary] = []
var _clouds: Array[Dictionary] = []
var _train := {}
var _snow: CPUParticles3D
var _rng := RandomNumberGenerator.new()
var _t := 0.0


## Собрать жизнь для локации (старое удаляется). Вызывать после загрузки локации и выбора времени суток.
func build(loc: StoryLocation, hero: Node3D, time: String) -> void:
	clear()
	location = loc
	player = hero
	time_of_day = time
	_rng.seed = hash(loc.location_id)
	_cfg = DataLoader.load_json(DATA_PATH).get(loc.location_id, {})
	for w in _cfg.get("walkers", []):
		if _when(w):
			_add_walker(w)
	for b in _cfg.get("birds", []):
		if _when(b):
			_add_flock(b)
	if _cfg.has("train") and _when(_cfg.train) and loc.has_marker("train_a"):
		_add_train(_cfg.train)
	if _cfg.has("clouds") and _when(_cfg.clouds):
		for i in int(_cfg.clouds.get("count", 6)):
			_add_cloud(i)
	if _cfg.has("snow") and _when(_cfg.snow):
		_add_snow()


func clear() -> void:
	for c in get_children():
		c.queue_free()
	_walkers.clear()
	_birds.clear()
	_clouds.clear()
	_train = {}
	_snow = null


## Время суток меняется в сцене — пересобрать (вечером нет третьего прохожего, ночью — птиц и облаков).
func set_time(time: String) -> void:
	if time != time_of_day and location:
		build(location, player, time)


func _when(e: Dictionary) -> bool:
	return time_of_day in e.get("times", ["day", "evening", "night", "storm"])


func _process(delta: float) -> void:
	_t += delta
	for w in _walkers:
		_walk(w, delta)
	for b in _birds:
		_fly(b, delta)
	for c in _clouds:
		var n: Node3D = c.node
		n.position.x += c.speed * delta
		if n.position.x > 220.0:
			n.position.x = -220.0
	if not _train.is_empty():
		_train_tick(delta)
	if _snow and player:
		_snow.global_position = player.global_position + Vector3(0, 8, 0)


# ---------- прохожие ----------

func _add_walker(e: Dictionary) -> void:
	var route := str(e.route)
	if not location.has_marker(route + "_a") or not location.has_marker(route + "_b"):
		return
	var body := AnimatableBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	body.sync_to_physics = false
	add_child(body)
	var m := CharacterModel.new()
	body.add_child(m)
	m.setup(str(e.model), Game.session.characters)
	if e.has("look"):
		m.apply_look(e.look)
	body.add_child(StoryGame.blob_shadow(0.38))
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.25
	cap.height = 1.6
	shape.shape = cap
	shape.position.y = 0.8
	body.add_child(shape)
	var a := location.marker(route + "_a").origin
	var b := location.marker(route + "_b").origin
	var w := {"body": body, "model": m, "a": a, "b": b, "speed": float(e.get("speed", 1.1)),
		"wait": float(e.get("delay", 0.0)), "p": 0.0, "dir": 1}
	body.visible = false
	_walkers.append(w)
	_place_walker(w)


func _place_walker(w: Dictionary) -> void:
	var from: Vector3 = w.a if w.dir > 0 else w.b
	var to: Vector3 = w.b if w.dir > 0 else w.a
	var pos := from.lerp(to, w.p)
	(w.body as Node3D).global_position = pos
	var d := to - from
	(w.model as CharacterModel).rotation.y = atan2(d.x, d.z)


func _walk(w: Dictionary, delta: float) -> void:
	var body := w.body as Node3D
	var m := w.model as CharacterModel
	if w.wait > 0.0:
		w.wait -= delta
		m.play_motion("idle")
		if w.wait <= 0.0:
			body.visible = true
		return
	var from: Vector3 = w.a if w.dir > 0 else w.b
	var to: Vector3 = w.b if w.dir > 0 else w.a
	var length := maxf(0.1, from.distance_to(to))
	# герой на пути — остановиться и посмотреть на него, пока не отойдёт
	var ahead := body.global_position + (to - from).normalized() * 0.9
	var blocked := player != null and ahead.distance_to(player.global_position) < 0.85
	if m.look:
		var near := player != null and body.global_position.distance_to(player.global_position) < 4.0
		m.look.target = player.global_position + Vector3(0, 1.0, 0) if near else null
	if blocked:
		m.play_motion("idle")
		return
	w.p += w.speed * delta / length
	m.play_motion("walk", w.speed)
	if w.p >= 1.0:
		# дошёл: исчезает за углом и через паузу идёт обратно
		w.p = 0.0
		w.dir = -w.dir
		w.wait = _rng.randf_range(4.0, 10.0)
		body.visible = false
	_place_walker(w)


# ---------- птицы ----------

func _bird_mesh() -> ArrayMesh:
	# силуэт «галочкой»: тело и два крыла; взмах — масштаб крыльев по Y в _fly
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Color("3a3440")
	var pts := [
		[Vector3(0, 0, 0.16), Vector3(-0.32, 0.05, -0.02), Vector3(0, 0, -0.08)],
		[Vector3(0, 0, 0.16), Vector3(0, 0, -0.08), Vector3(0.32, 0.05, -0.02)],
		[Vector3(0, 0, -0.08), Vector3(-0.06, 0, -0.2), Vector3(0.06, 0, -0.2)],
	]
	for tri in pts:
		for v in tri:
			st.set_color(c)
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
		for i in [2, 1, 0]:
			st.set_color(c)
			st.set_normal(Vector3.DOWN)
			st.add_vertex(tri[i])
	return st.commit()


func _add_flock(e: Dictionary) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh := _bird_mesh()
	var c: Array = e.get("center", [0, 0])
	# Blender X/Y → Godot X/−Z (как точки локации)
	var center := Vector3(float(c[0]), float(e.get("height", 9)), -float(c[1]))
	for i in int(e.get("count", 5)):
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.scale = Vector3.ONE * _rng.randf_range(0.8, 1.15)
		add_child(mi)
		_birds.append({"node": mi, "center": center, "r": float(e.get("radius", 12)) * _rng.randf_range(0.7, 1.1),
			"phase": _rng.randf() * TAU, "speed": _rng.randf_range(0.18, 0.28) * (1 if i % 3 else -1),
			"bob": _rng.randf() * TAU, "flap": _rng.randf_range(7.0, 10.0), "dy": _rng.randf_range(-1.5, 1.5)})


func _fly(b: Dictionary, delta: float) -> void:
	b.phase += b.speed * delta
	var n := b.node as Node3D
	var r: float = b.r * (1.0 + 0.15 * sin(b.phase * 2.3 + b.bob))
	var p: Vector3 = b.center + Vector3(cos(b.phase) * r, b.dy + sin(_t * 0.7 + b.bob) * 0.8, sin(b.phase) * r)
	var tangent := Vector3(-sin(b.phase), 0, cos(b.phase)) * signf(b.speed)
	n.position = p
	n.basis = Basis.looking_at(-tangent, Vector3.UP).scaled(n.scale) if tangent.length() > 0.01 else n.basis
	# взмахи с паузами-планированием
	var flap := sin(_t * b.flap + b.bob)
	var glide := 0.5 + 0.5 * sin(_t * 0.6 + b.bob)
	n.scale.y = (0.25 + 0.75 * absf(flap)) * (1.0 if glide > 0.35 else 0.3) + 0.1


# ---------- облака ----------

func _add_cloud(i: int) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(_rng.randf_range(40, 80), _rng.randf_range(14, 24))
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.75))
	g.set_color(1, Color(1, 1, 1, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = tex
	mat.albedo_color = Color("fff4ec") if time_of_day == "evening" else Color(1, 1, 1)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.no_depth_test = false
	mat.disable_fog = true
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var a := _rng.randf() * TAU
	mi.position = Vector3(_rng.randf_range(-200, 200), _rng.randf_range(55, 85), -sin(a) * 160 - 60)
	_clouds.append({"node": mi, "speed": _rng.randf_range(0.6, 1.4)})


# ---------- снег ----------

func _add_snow() -> void:
	_snow = CPUParticles3D.new()
	_snow.amount = 400
	_snow.lifetime = 7.0
	_snow.preprocess = 7.0
	_snow.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_snow.emission_box_extents = Vector3(14, 0.5, 14)
	_snow.direction = Vector3(0.2, -1, 0.1)
	_snow.spread = 12
	_snow.gravity = Vector3(0.15, -0.6, 0)
	_snow.initial_velocity_min = 0.4
	_snow.initial_velocity_max = 0.9
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(1, 1, 1, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	q.material = mat
	_snow.mesh = q
	add_child(_snow)


# ---------- поезд и переезд ----------

func _add_train(e: Dictionary) -> void:
	var a := location.marker("train_a").origin
	var b := location.marker("train_b").origin
	var lamps: Array[MeshInstance3D] = []
	var lamp_mat_on := _lamp_mat(true)
	var lamp_mat_off := _lamp_mat(false)
	for n in 2:
		for k in 2:
			var nm := "xing_lamp_%d_%d" % [n, k]
			if not location.has_marker(nm):
				continue
			var mi := MeshInstance3D.new()
			var s := SphereMesh.new()
			s.radius = 0.15
			s.height = 0.3
			mi.mesh = s
			mi.material_override = lamp_mat_off
			add_child(mi)
			mi.global_position = location.marker(nm).origin
			lamps.append(mi)
	var arms: Array[Node3D] = []
	for n in 2:
		var nm := "xing_arm_%d" % n
		if not location.has_marker(nm):
			continue
		var t := location.marker(nm)
		var pivot := Node3D.new()
		add_child(pivot)
		pivot.global_transform = t
		pivot.add_child(_barrier_arm(6.4))
		arms.append(pivot)
	var train := _train_mesh(int(e.get("cars", 3)))
	train.visible = false
	add_child(train)
	var center := location.marker("xing_center").origin if location.has_marker("xing_center") else (a + b) * 0.5
	_train = {"a": a, "b": b, "center": center, "lamps": lamps, "on": lamp_mat_on, "off": lamp_mat_off, "arms": arms,
		"node": train, "speed": float(e.get("speed", 12)), "interval": e.get("interval", [40, 60]),
		"next": float(e.get("first", 15)), "state": "idle", "clock": 0.0, "pos": 0.0, "dir": 1, "bell": null,
		"length": float(e.get("cars", 3)) * 15.5, "arm": 0.0}


## Для снимков: поезд прямо на переезде, шлагбаумы опущены, звонок идёт.
func debug_train_at_crossing() -> void:
	if _train.is_empty():
		return
	var t := _train
	t.state = "pass"
	t.dir = 1
	t.arm = 1.0
	t.bell = Audio.sfx_at("crossing_bell", self, t.center + Vector3(0, 2.5, 0), 45.0)
	(t.node as Node3D).visible = true
	var from: Vector3 = t.a
	t.pos = 30.0 + from.distance_to(t.center) + 10.0


func _lamp_mat(on: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color("ff6a4a") if on else Color("5a2a28")
	if on:
		m.emission_enabled = true
		m.emission = Color("ff5a3a")
		m.emission_energy_multiplier = 2.0
	return m


## Шлагбаум: полосатая жёлто-чёрная перекладина длиной length вдоль −Z узла (опущен — горизонтально).
func _barrier_arm(length: float) -> Node3D:
	var root := Node3D.new()
	var mat_y := _flat_mat(Color("f2c230"))
	var mat_k := _flat_mat(Color("1f1d1f"))
	var seg := 0.5
	for k in int(length / seg):
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.07, 0.07, seg)
		mi.mesh = bm
		mi.material_override = mat_y if k % 2 == 0 else mat_k
		mi.position = Vector3(0, 0, -(k + 0.5) * seg)
		root.add_child(mi)
	# поднят: перекладина вертикально вверх
	root.rotation.x = PI / 2
	return root


func _flat_mat(c: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TOON
	m.set_shader_parameter("albedo", c.srgb_to_linear())
	m.set_shader_parameter("use_vertex_color", false)
	m.set_shader_parameter("shade_color", Color(0.72, 0.68, 0.86))
	return m


## Электричка: вагоны (кремовый кузов, зелёная полоса, окна) тянутся за головой — вдоль +Z узла (едет по −Z).
func _train_mesh(cars: int) -> Node3D:
	var root := Node3D.new()
	var body_m := _flat_mat(Color("eeeae0"))
	var stripe_m := _flat_mat(Color("3f8f6a"))
	var glass_m := _flat_mat(Color("3a4a5c"))
	var roof_m := _flat_mat(Color("9a9ea4"))
	for i in cars:
		var z := i * 15.5 + 7.5
		for part in [[Vector3(2.8, 2.9, 15.0), Vector3(0, 1.75, z), body_m],
				[Vector3(2.84, 0.32, 15.02), Vector3(0, 1.05, z), stripe_m],
				[Vector3(2.86, 0.75, 13.0), Vector3(0, 2.25, z), glass_m],
				[Vector3(2.5, 0.25, 14.6), Vector3(0, 3.3, z), roof_m],
				[Vector3(2.2, 0.5, 13.0), Vector3(0, 0.4, z), glass_m]]:
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = part[0]
			mi.mesh = bm
			mi.material_override = part[2]
			mi.position = part[1]
			root.add_child(mi)
	return root


func _train_tick(delta: float) -> void:
	var t := _train
	t.clock += delta
	match t.state:
		"idle":
			t.next -= delta
			if t.next <= 0.0:
				# звонок и фонари за 5 с до поезда, шлагбаумы опускаются
				t.state = "warn"
				t.clock = 0.0
				t.dir = 1 if _rng.randf() < 0.5 else -1
				t.bell = Audio.sfx_at("crossing_bell", self, t.center + Vector3(0, 2.5, 0), 45.0)
		"warn":
			t.arm = minf(1.0, t.arm + delta / 3.0)
			if t.clock > 5.0:
				t.state = "pass"
				t.pos = 0.0
				(t.node as Node3D).visible = true
				Audio.sfx_at("train_pass", t.node, (t.node as Node3D).global_position, 70.0)
		"pass":
			var from: Vector3 = t.a if t.dir > 0 else t.b
			var to: Vector3 = t.b if t.dir > 0 else t.a
			var total: float = from.distance_to(to) + t.length + 30.0
			t.pos += t.speed * delta
			var dir := (to - from).normalized()
			var n := t.node as Node3D
			# голова поезда идёт от конца пути «from − 30 м» к «to + длина»
			var head: Vector3 = from - dir * 30.0 + dir * t.pos
			n.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), head)
			for p in n.get_children():
				if p is AudioStreamPlayer3D:
					(p as AudioStreamPlayer3D).global_position = head - dir * t.length * 0.5
			if t.pos > total:
				n.visible = false
				t.state = "clear"
				t.clock = 0.0
		"clear":
			if t.clock > 1.5:
				t.arm = maxf(0.0, t.arm - delta / 3.0)
				if t.bell and is_instance_valid(t.bell):
					(t.bell as Node).queue_free()
					t.bell = null
				if t.arm <= 0.0:
					t.state = "idle"
					var iv: Array = t.interval
					t.next = _rng.randf_range(float(iv[0]), float(iv[1]))
	# фонари: мигают попеременно, пока звонит
	var blinking: bool = t.state != "idle" and t.bell != null
	var phase := int(_t * 2.0) % 2
	for i in t.lamps.size():
		(t.lamps[i] as MeshInstance3D).material_override = t.on if blinking and (i % 2) == phase else t.off
	for arm in t.arms:
		(arm.get_child(0) as Node3D).rotation.x = PI / 2 * (1.0 - _ease(t.arm))


func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)
