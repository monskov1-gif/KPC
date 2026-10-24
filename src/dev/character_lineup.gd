extends Node3D
## Витрина 3D-прототипов персонажей (для проверки моделей и скриншотов). Не входит в игру.

const IDS := ["kot", "gabi", "sora", "hotto"]
## Персонажи пролога (образы — data/story/looks.json); снимок: debug_prologue.
const PROLOGUE_IDS := ["kot_child", "girl", "gabi_child", "sora_young", "mama", "papa", "passerby_a", "passerby_b",
	"doctor", "nurse", "resident_a", "resident_b"]
var focus := ""   # пусто — все трое; иначе крупный план одного


func _ready() -> void:
	var s := Game.session
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("e9d6d3")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("f3dcd8")
	env.environment.ambient_light_energy = 0.55
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, float(OS.get_environment("KPC_SUN_YAW")) if OS.has_environment("KPC_SUN_YAW") else 30.0, 0)
	key.light_energy = 0.7
	key.light_color = Color("fff1e6")
	add_child(key)
	var x := -1.8
	for id in IDS:
		var m := CharacterModel.new()
		add_child(m)
		m.position = Vector3(x, 0, 0)
		m.setup(id, s.characters)
		if s.outfit_items(id).is_empty():
			s.equipment.equip_signature(id)    # закрытый в гардеробе персонаж (Хотто) — витрина всё равно в образе
		m.apply_items(s.outfit_items(id))
		m.name = id
		x += 1.2
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.15, 4.6)
	cam.fov = 32
	add_child(cam)


func debug_focus_kot() -> void:
	_focus("kot")


func debug_focus_gabi() -> void:
	_focus("gabi")


func debug_focus_sora() -> void:
	_focus("sora")


func debug_focus_hotto() -> void:
	_focus("hotto")


## Хотто целиком: спереди, в 3/4 и сбоку (по очереди — через KPC_YAW), в образе.
func debug_full_hotto() -> void:
	var m: Node3D = get_node("hotto")
	for id in IDS:
		(get_node(id) as Node3D).visible = id == "hotto"
	m.position = Vector3.ZERO
	m.rotation_degrees.y = float(OS.get_environment("KPC_YAW")) if OS.has_environment("KPC_YAW") else 0.0
	var cam := get_viewport().get_camera_3d()
	cam.position = Vector3(0, 1.2, 5.0)
	cam.rotation_degrees = Vector3.ZERO
	_cam_override()


## Голова Хотто крупно (KPC_YAW — поворот).
func debug_head_hotto() -> void:
	debug_full_hotto()
	var cam := get_viewport().get_camera_3d()
	cam.position = Vector3(0, 2.05, 1.6)


func _focus(id: String) -> void:
	var cam := get_viewport().get_camera_3d()
	var m: Node3D = get_node(id)
	var h: float = {"kot": 1.63, "gabi": 1.6, "sora": 2.06, "hotto": 2.35}[id]
	cam.position = m.position + Vector3(0, h * 0.86, 0.85)
	cam.rotation_degrees = Vector3(-6, 0, 0)
	if OS.has_environment("KPC_YAW"):
		m.rotation_degrees.y = float(OS.get_environment("KPC_YAW"))


func debug_head_kot() -> void:
	var cam := get_viewport().get_camera_3d()
	var m: Node3D = get_node("kot")
	cam.position = m.position + Vector3(0, 1.6, 0.75)
	cam.rotation_degrees = Vector3(-2, 0, 0)
	_cam_override()


func debug_full_kot() -> void:
	_kot_turn(0.0)


## Разворот Кота как на референсе 16: спереди, три четверти, сбоку, сзади (только Кот в кадре).
func debug_kot_34() -> void:
	_kot_turn(-35.0)


func debug_kot_side() -> void:
	_kot_turn(-90.0)


func debug_kot_back() -> void:
	_kot_turn(180.0)


func _kot_turn(yaw: float) -> void:
	for id in IDS:
		(get_node(id) as Node3D).visible = id == "kot"
	var m: Node3D = get_node("kot")
	m.rotation_degrees.y = yaw
	var cam := get_viewport().get_camera_3d()
	cam.position = m.position + Vector3(0.0, 0.9, 3.5)
	cam.rotation_degrees = Vector3(-1, 0, 0)


func debug_hips_kot() -> void:
	var cam := get_viewport().get_camera_3d()
	var m: Node3D = get_node("kot")
	cam.position = m.position + Vector3(0.0, 0.9, 0.7)
	cam.rotation_degrees = Vector3(-2, 0, 0)


## Все без одежды: видно, что базовый слой белья остаётся всегда.
func debug_underwear() -> void:
	for id in IDS:
		(get_node(id) as CharacterModel).apply_items([] as Array[ClothingItem])


func debug_head_kot_bare() -> void:
	debug_underwear()
	debug_head_kot()


func debug_kot_back_hips() -> void:
	_kot_turn(180.0)
	var cam := get_viewport().get_camera_3d()
	cam.position = Vector3(get_node("kot").position.x, float(OS.get_environment("KPC_CAM_Y")) if OS.has_environment("KPC_CAM_Y") else 0.95, 0.8)


## Лицо Кота в три четверти и в профиль — проверка лепки головы (нос, губы, подбородок, скулы).
func debug_head_kot_34() -> void:
	_kot_head_turn(-32.0)


func debug_head_kot_side() -> void:
	_kot_head_turn(-90.0)


func _kot_head_turn(yaw: float) -> void:
	_kot_turn(yaw)
	var cam := get_viewport().get_camera_3d()
	cam.position = get_node("kot").position + Vector3(0, 1.64, 1.0)
	cam.rotation_degrees = Vector3(-2, 0, 0)


## Кадр «как портрет на реф. 16» для наложения: только Кот, поза покоя замерла, поворот головы KPC_YAW
## (градусы; −3 — подобрано по наложению: так ошибка черт лица минимальна). Экранные координаты ориентиров lm_*
## пишутся в JSON (путь KPC_LANDMARKS) — их читает tools/art/ref_overlay.py.
func debug_ref_portrait_kot() -> void:
	_ref_view("kot", Vector3(0, 1.5, 1.35), -3.0, 21.0)


## Кадр «во весь рост, спереди» для наложения на вид спереди реф. 16.
func debug_ref_front_kot() -> void:
	_ref_view("kot", Vector3(0, 0.86, 5.2), 0.0, 21.0)


func _ref_view(id: String, cam_pos: Vector3, default_yaw: float, fov: float) -> void:
	for other in IDS:
		(get_node(other) as Node3D).visible = other == id
	var m: Node3D = get_node(id)
	var yaw := float(OS.get_environment("KPC_YAW")) if OS.has_environment("KPC_YAW") else default_yaw
	m.rotation_degrees.y = yaw
	var anim := m.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim:
		anim.seek(0.0, true)
		anim.pause()
	var cam := get_viewport().get_camera_3d()
	cam.fov = fov
	cam.position = m.position + cam_pos
	cam.rotation_degrees = Vector3.ZERO
	await get_tree().process_frame
	var out := {}
	# unproject_position даёт координаты в пространстве вьюпорта (с учётом масштаба интерфейса) —
	# переводим в пиксели окна, т. е. снимка.
	var k := Vector2(DisplayServer.window_get_size()) / get_viewport().get_visible_rect().size
	for n in m.find_children("lm_*", "", true, false):
		var sp := cam.unproject_position((n as Node3D).global_position) * k
		out[String(n.name).trim_prefix("lm_")] = [sp.x, sp.y]
	var path := OS.get_environment("KPC_LANDMARKS") if OS.has_environment("KPC_LANDMARKS") else "user://landmarks.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out, "  "))
		f.close()


## Тело Кота без одежды крупно: плечи/руки и голени (проверка деформаций базовой модели).
func debug_kot_body_closeup() -> void:
	debug_underwear()
	_kot_turn(0.0)
	var cam := get_viewport().get_camera_3d()
	cam.position = get_node("kot").position + Vector3(0.0, 0.9, 3.4)


func debug_kot_body_side() -> void:
	debug_underwear()
	_kot_turn(-90.0)
	var cam := get_viewport().get_camera_3d()
	cam.position = get_node("kot").position + Vector3(0.0, 0.9, 3.4)


## Лицо без одежды и повязки: спереди, три четверти, профиль (для проверки лица критиком).
func debug_face_bare_front() -> void:
	debug_underwear()
	_kot_head_turn(0.0)


func debug_face_bare_34() -> void:
	debug_underwear()
	_kot_head_turn(-32.0)


func debug_face_bare_side() -> void:
	debug_underwear()
	_kot_head_turn(-90.0)


func debug_prologue() -> void:
	for id in IDS:
		get_node(id).visible = false
	var looks := DataLoader.load_json(StoryGame.LOOKS_PATH)
	var x := -0.75 * (PROLOGUE_IDS.size() - 1) / 2.0
	for id in PROLOGUE_IDS:
		var m := CharacterModel.new()
		add_child(m)
		m.position = Vector3(x, 0, 0)
		m.setup(id, Game.session.characters)
		m.apply_look(looks.get(id, {}))
		x += 0.75
	var cam := get_viewport().get_camera_3d()
	cam.position = Vector3(0, 1.0, 9.5)
	cam.fov = 32
	_cam_override()


## Шесть баз тела (build_characters.py base_*): спереди и сбоку (KPC_YAW), без одежды.
func debug_bases() -> void:
	for id in IDS:
		get_node(id).visible = false
	var kinds := ["child", "teen_f", "teen_m", "adult_f", "adult_m", "muscular_m"]
	var x := -2.5
	for k in kinds:
		var m := CharacterModel.new()
		add_child(m)
		m.position = Vector3(x, 0, 0)
		m.setup("bases/" + k, Game.session.characters)
		m.apply_look({})
		if OS.has_environment("KPC_YAW"):
			m.rotation_degrees.y = float(OS.get_environment("KPC_YAW"))
		x += 1.0
	var cam := get_viewport().get_camera_3d()
	cam.position = Vector3(0, 1.1, 8.6)
	cam.rotation_degrees = Vector3.ZERO
	cam.fov = 32
	_cam_override()


## Сменные лица: 4 копии героя (KPC_POSE_ID, по умолчанию kot) с разными стилями лица — головы крупно.
func debug_face_styles() -> void:
	for id in IDS:
		get_node(id).visible = false
	var id := OS.get_environment("KPC_POSE_ID") if OS.has_environment("KPC_POSE_ID") else "kot"
	var styles := [
		{},
		{"expression": "smile", "eye_shape": "round", "makeup": {"blush_amount": 0.75},
		 "iris": {"tint": 1.0, "top": "#7a3a8a", "bottom": "#f0a0d8", "pattern": "butterfly", "pattern_color": "#fff4fb"}},
		{"expression": "serious", "eye_shape": "sharp", "makeup": {"blush_amount": 0.1, "eyeshadow": "#8a6a7a", "eyeshadow_amount": 0.6}},
		{"expression": "happy", "iris": {"rainbow": 1.0}, "makeup": {"blush_amount": 0.8}},
	]
	if OS.has_environment("KPC_FACE_SET") and OS.get_environment("KPC_FACE_SET") == "2":
		styles = [
			{"expression": "surprised", "iris": {"pattern": "star", "pattern_color": "#fff6c0"}},
			{"expression": "cat", "eye_shape": "round", "iris": {"tint": 1.0, "top": "#2a6a5a", "bottom": "#a0f0d0", "pattern": "heart", "pattern_color": "#ff9ab8"}},
			{"expression": "smirk", "makeup": {"lips": "#c0303c", "lips_amount": 0.9, "eyeshadow": "#6a3050", "eyeshadow_amount": 0.8}},
			{"expression": "pout", "iris": {"pattern": "sparkles", "sparkle": 1.0, "tint": 1.0, "top": "#2a3a9a", "bottom": "#c0d0ff"}},
		]
	var models := []
	for i in styles.size():
		var m := CharacterModel.new()
		add_child(m)
		m.position = Vector3(-0.9 + i * 0.6, 0, 0)
		m.setup(id, Game.session.characters)
		if Game.session.outfit_items(id).is_empty():
			Game.session.equipment.equip_signature(id)
		m.apply_items(Game.session.outfit_items(id))
		if m.face:
			m.face.blinking = false
			m.face.apply_style(styles[i])
		models.append(m)
	await get_tree().process_frame
	var cam := get_viewport().get_camera_3d()
	var h: float = (models[0] as CharacterModel).height()
	cam.position = Vector3(0, h * 0.9, 2.6)
	cam.rotation_degrees = Vector3.ZERO
	cam.fov = 30
	if OS.has_environment("KPC_FACE_IDX"):    # крупно одну голову
		var mi: CharacterModel = models[int(OS.get_environment("KPC_FACE_IDX"))]
		cam.position = Vector3(mi.position.x, h * 0.89, 0.66)
		cam.fov = 32
	_cam_override()


## KPC_CAM=«x,y,z» — камера в эту точку (крупный план любого места витрины).
func _cam_override() -> void:
	if OS.has_environment("KPC_CAM"):
		var c := OS.get_environment("KPC_CAM").split_floats(",")
		get_viewport().get_camera_3d().position = Vector3(c[0], c[1], c[2])


## Кадры анимации: KPC_POSE_ID=<модель> KPC_ANIM=walk|run|idle; 4 копии в разных фазах цикла, вид сбоку и спереди.
func debug_anim() -> void:
	for id in IDS:
		get_node(id).visible = false
	var id := OS.get_environment("KPC_POSE_ID") if OS.has_environment("KPC_POSE_ID") else "kot_child"
	var anim := OS.get_environment("KPC_ANIM") if OS.has_environment("KPC_ANIM") else "walk"
	var looks := DataLoader.load_json(StoryGame.LOOKS_PATH)
	for i in 5:
		var m := CharacterModel.new()
		add_child(m)
		m.setup(id, Game.session.characters)
		m.apply_look(looks.get(id, {}))
		m.position = Vector3(-1.6 + i * 0.8, 0, 0)
		m.rotation.y = PI / 2 if i < 4 else 0.0
		var ap := m.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap and ap.has_animation(anim):
			ap.play(anim)
			ap.seek(ap.current_animation_length * (i % 4) / 4.0, true)
			ap.pause()
	var cam := get_viewport().get_camera_3d()
	cam.position = Vector3(0, 0.75, 5.2)
	cam.fov = 30


## Позы отдыха: сидит и спит (KPC_POSE_ID — модель).
func debug_rest() -> void:
	for id in IDS:
		get_node(id).visible = false
	var id := OS.get_environment("KPC_POSE_ID") if OS.has_environment("KPC_POSE_ID") else "kot_child"
	var looks := DataLoader.load_json(StoryGame.LOOKS_PATH)
	var kinds := ["sit", "sit", "sleep", "sleep"]
	for i in 4:
		var m := CharacterModel.new()
		add_child(m)
		m.setup(id, Game.session.characters)
		m.apply_look(looks.get(id, {}))
		m.position = Vector3(-1.5 + i * 1.0, 0, 0)
		m.rotation.y = PI / 2 if i % 2 == 0 else 0.0
		m.set_rest(kinds[i], 0.0)
	var cam := get_viewport().get_camera_3d()
	cam.position = Vector3(0, 0.9, 4.6)
	cam.fov = 32
