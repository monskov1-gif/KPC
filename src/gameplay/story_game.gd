class_name StoryGame
extends Node3D
## Сюжетный режим: локация, игрок, камера, NPC, точки осмотра и цели, интерфейс; сцены ведёт StoryDirector.
## Прогресс (номер сцены) хранится во флагах сессии и сохраняется в начале каждой сцены.

signal interacted(id: String)

const SCRIPT_PATH := "res://data/story/prologue.json"
const INTERACT_RADIUS := 1.9
const REACH_RADIUS := 1.5
const PROGRESS_FLAG := "prologue_scene"
const DONE_FLAG := "prologue_complete"
const LOOKS_PATH := "res://data/story/looks.json"

## С какой сцены начать (задаёт титульный экран); −1 — продолжить с сохранённой.
static var start_scene := -1

var story: StoryScript
var location: StoryLocation
var player: StoryPlayer
var cam: FollowCamera
var overlay: StoryOverlay
var director: StoryDirector
var player_model := ""
var _npcs: Dictionary = {}          # имя точки -> CharacterModel
var _interactables: Dictionary = {} # id цели -> Vector3
var _seen: Dictionary = {}
var _focus := ""
var _beacon: Node3D
var _cutscene := false
var _looks: Dictionary = {}


func _ready() -> void:
	story = StoryScript.load_file(SCRIPT_PATH)
	_looks = DataLoader.load_json(LOOKS_PATH)
	for e in story.errors:
		push_error("Сценарий: " + e)
	location = StoryLocation.new()
	add_child(location)
	player = StoryPlayer.new()
	add_child(player)
	player.add_child(blob_shadow(0.42))
	cam = FollowCamera.new()
	add_child(cam)
	cam.target = player
	overlay = StoryOverlay.new()
	add_child(overlay)
	overlay.set_black(true)
	overlay.interact_pressed.connect(_try_interact)
	overlay.menu_requested.connect(to_title)
	_beacon = _make_beacon()
	add_child(_beacon)
	_beacon.visible = false
	director = StoryDirector.new()
	director.game = self
	director.story = story
	if OS.has_environment("KPC_STORY_FAST"):
		director.time_scale = 0.05
	add_child(director)
	director.scene_started.connect(_on_scene_started)
	director.finished.connect(_on_finished)
	if story.scenes.is_empty():
		return
	director.run.call_deferred(_first_scene())


func _first_scene() -> int:
	if OS.has_environment("KPC_STORY_SCENE"):
		var v := OS.get_environment("KPC_STORY_SCENE")
		return int(v) if v.is_valid_int() else maxi(0, story.scene_index(v))
	if start_scene >= 0:
		return start_scene
	return clampi(int(Game.session.flags.get_flag(PROGRESS_FLAG, 0)), 0, story.scenes.size() - 1)


## Загрузить локацию, поставить игрока на точку, расставить NPC, выставить время суток.
func enter_location(loc_id: String, model_id: String, spawn: String, time: String, npcs: Dictionary) -> void:
	set_interactables([])
	set_beacon(null)
	for n in _npcs.values():
		n.get_parent().queue_free()
	_npcs.clear()
	if loc_id != location.location_id:
		location.load_location(loc_id)
	location.apply_time(time)
	if model_id != player_model:
		player_model = model_id
		player.set_character(model_id, Game.session.characters, _outfit(model_id))
		if _looks.has(model_id):
			player.model.apply_look(_looks[model_id])
		cam.fit_height(player.model.height())
	player.place(location.marker(spawn))
	cam.snap_behind(player.model.rotation.y)
	for model in npcs:
		_spawn_npc(str(model), str(npcs[model]))


## Кот носит то, что надето в гардеробе; остальные персонажи из каталога — фирменный образ.
func _outfit(model_id: String) -> Array[ClothingItem]:
	var s := Game.session
	if not s.characters.has_character(model_id):
		return []
	if s.outfit_items(model_id).is_empty():
		s.equipment.equip_signature(model_id)
	return s.outfit_items(model_id)


func _spawn_npc(model_id: String, marker_name: String) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 4      # NPC: игрок упирается, камера (маска 1) проходит сквозь
	add_child(body)
	var t := location.marker(marker_name)
	var m := CharacterModel.new()
	body.add_child(m)
	m.setup(model_id, Game.session.characters)
	m.apply_items(_outfit(model_id))
	if _looks.has(model_id):
		m.apply_look(_looks[model_id])
	var upright := t.basis.y.normalized().dot(Vector3.UP) > 0.9
	if upright:
		body.global_position = t.origin
		var f := -t.basis.z
		m.rotation.y = atan2(f.x, f.z)
		body.add_child(blob_shadow(0.4))
		var shape := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		var h := clampf(m.height(), 0.8, 2.6)
		cap.radius = 0.26
		cap.height = h
		shape.shape = cap
		shape.position.y = h * 0.5
		body.add_child(shape)
	else:
		# лежит (кровать): вся ориентация точки; модель смотрит по +Z, точка — по −Z
		body.global_transform = Transform3D(t.basis.orthonormalized(), t.origin)
		m.rotation.y = PI
		m.play_motion("idle", 0.4)
	_npcs[marker_name] = m


## Цели осмотра: точки int_<id> текущей локации.
func set_interactables(ids: Array) -> void:
	_interactables.clear()
	for id in ids:
		_interactables[str(id)] = location.marker("int_" + str(id)).origin
	_focus = ""
	overlay.set_prompt("")


func mark_seen(id: String) -> void:
	_seen[id] = true


func set_beacon(pos) -> void:
	_beacon.visible = pos != null
	if pos != null:
		_beacon.global_position = pos


func player_distance(pos: Vector3) -> float:
	return Vector2(player.global_position.x - pos.x, player.global_position.z - pos.z).length()


## Катсцена: игрок не управляется, игровые подсказки скрыты. focus_id — с кем разговор (повернуться друг к другу).
func set_cutscene(on: bool, focus_id := "") -> void:
	_cutscene = on
	player.input_enabled = not on
	overlay.set_gameplay_ui(not on)
	if on and focus_id != "" and _interactables.has(focus_id):
		var p: Vector3 = _interactables[focus_id]
		player.face(p)
		var npc: CharacterModel = _npcs.get("int_" + focus_id)
		if npc:
			var d := player.global_position - npc.global_position
			npc.rotation.y = atan2(d.x, d.z)


func _process(_delta: float) -> void:
	player.water_level = location.water_level()
	if overlay.stick:
		player.touch_move = overlay.stick.value
	player.camera_yaw = cam.yaw
	if _beacon.visible:
		_beacon.rotation.y += _delta * 0.8
		var k := 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.004)
		_beacon.scale = Vector3(k, 1, k)
	if _cutscene or _interactables.is_empty():
		return
	var best := ""
	var best_d := INTERACT_RADIUS
	for id in _interactables:
		var d := player_distance(_interactables[id])
		if d < best_d:
			best_d = d
			best = id
	if best != _focus:
		_focus = best
		if best == "":
			overlay.set_prompt("")
		else:
			overlay.set_prompt(("Поговорить" if story.speakers.has(best) else "Осмотреть") + ("  ✓" if _seen.has(best) else ""))


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("interact"):
		_try_interact()
	elif e.is_action_pressed("pause"):
		to_title()


func _try_interact() -> void:
	if _cutscene or _focus == "":
		return
	overlay.set_prompt("")
	var id := _focus
	_focus = ""
	interacted.emit(id)


func _on_scene_started(i: int) -> void:
	_seen.clear()
	Game.session.flags.set_flag(PROGRESS_FLAG, i)
	Game.save_game()


func _on_finished() -> void:
	Game.session.flags.set_flag(PROGRESS_FLAG, 0)
	Game.session.flags.set_flag(DONE_FLAG, true)
	Game.save_game()
	await overlay.fade(true, 1.0)
	to_title()


func to_title() -> void:
	Game.save_game()
	start_scene = -1
	get_tree().change_scene_to_file("res://scenes/main.tscn")


## Мягкое пятно тени под персонажем (вместо теней солнца в рендерере Compatibility, и для «приземления»).
static func blob_shadow(radius: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(radius * 2, radius * 2)
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	mi.position.y = 0.03
	var g := Gradient.new()
	g.set_color(0, Color(0.25, 0.18, 0.3, 0.42))
	g.set_color(1, Color(0.25, 0.18, 0.3, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = t
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Мягкий световой столб над целью «дойти до…».
func _make_beacon() -> Node3D:
	var root := Node3D.new()
	var col := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.55
	cyl.bottom_radius = 0.7
	cyl.height = 3.0
	cyl.cap_top = false
	cyl.cap_bottom = false
	col.mesh = cyl
	col.position.y = 1.5
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(1.0, 0.86, 0.55, 0.22)
	col.material_override = m
	root.add_child(col)
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.62
	tor.outer_radius = 0.74
	ring.mesh = tor
	ring.position.y = 0.05
	var rm := m.duplicate() as StandardMaterial3D
	rm.albedo_color = Color(1.0, 0.9, 0.62, 0.8)
	ring.material_override = rm
	root.add_child(ring)
	return root


# ---------- отладка и снимки (tools/capture.sh … debug_*) ----------

## Подойти к цели осмотра и начать разговор.
func debug_talk_girl() -> void:
	_debug_talk("girl")


func debug_talk_family() -> void:
	_debug_talk("family_table")


func _debug_talk(id: String) -> void:
	await get_tree().create_timer(0.8).timeout
	if not _interactables.has(id):
		return
	var p: Vector3 = _interactables[id]
	player.global_position = p + (player.global_position - p).normalized() * 1.3
	_focus = id
	_try_interact()


## Дойти до текущей цели (световой столб) — для снимков следующих шагов сцены.
func debug_reach() -> void:
	await get_tree().create_timer(0.8).timeout
	if _beacon.visible:
		player.global_position = _beacon.global_position + Vector3(0, 0.1, 0)


func debug_talk_hotel() -> void:
	_debug_talk("hotel_sign")


func debug_walk() -> void:
	player.touch_move = Vector2(0, 1)
	overlay.stick = null
