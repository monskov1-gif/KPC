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
## Живой мир локации: прохожие, птицы, поезд, облака (data/world/life.json).
var life: WorldLife
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
var _verbs: Dictionary = {}
var _pause: Sheet
var tutorial: StoryTutorial
var _npc_by_model: Dictionary = {}  # модель -> CharacterModel (для постановки «act»)


func _ready() -> void:
	story = StoryScript.load_file(SCRIPT_PATH)
	_looks = DataLoader.load_json(LOOKS_PATH)
	location = StoryLocation.new()
	add_child(location)
	life = WorldLife.new()
	add_child(life)
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
	overlay.menu_requested.connect(open_pause)
	overlay.skip_pressed.connect(func(): director.skip())
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS     # меню паузы работает при остановленной сцене
	_pause = Sheet.new()
	_pause.max_size = Vector2(560, 480)
	overlay.add_ui(_pause)
	_pause.closed.connect(func():
		get_tree().paused = false
		Audio.save_settings())
	_beacon = _make_beacon()
	add_child(_beacon)
	_beacon.visible = false
	tutorial = StoryTutorial.new()
	tutorial.game = self
	add_child(tutorial)
	director = StoryDirector.new()
	director.name = "Director"
	director.game = self
	director.story = story
	if OS.has_environment("KPC_STORY_FAST"):
		director.time_scale = 0.05
	add_child(director)
	director.scene_started.connect(_on_scene_started)
	director.finished.connect(_on_finished)
	if not story.errors.is_empty() or story.scenes.is_empty():
		# сломанный сценарий не запускаем: понятное сообщение вместо сцены не на своих местах
		for e in story.errors:
			push_error("Сценарий: " + e)
		overlay.set_black(true)
		overlay.caption("Сценарий не загрузился", "Ошибок: %d — подробности в журнале" % story.errors.size(), 600.0)
		return
	director.run.call_deferred(_first_scene())


func _first_scene() -> int:
	if OS.has_environment("KPC_STORY_SCENE"):
		var v := OS.get_environment("KPC_STORY_SCENE")
		return int(v) if v.is_valid_int() else maxi(0, story.scene_index(v))
	if start_scene >= 0:
		return start_scene
	return maxi(0, story.scene_index(saved_scene_id(story)))


## Сохранённая сцена — по id (вставка или перестановка сцен в данных не ломает старые сохранения).
## Старые сохранения хранили номер — переводим его в id.
static func saved_scene_id(s: StoryScript) -> String:
	var v = Game.session.flags.get_flag(PROGRESS_FLAG, "")
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		var i := int(v)
		return str(s.scenes[i].id) if i > 0 and i < s.scenes.size() else ""
	return str(v)


## Загрузить локацию, поставить игрока на точку, расставить NPC, выставить время суток.
func enter_location(loc_id: String, model_id: String, spawn: String, time: String, npcs: Dictionary) -> void:
	set_interactables([])
	set_beacon(null)
	for n in _npcs.values():
		n.get_parent().queue_free()
	_npcs.clear()
	_npc_by_model.clear()
	player.model.set_rest("", 0.0)
	cam.release(0.0)
	if loc_id != location.location_id:
		location.load_location(loc_id)
	location.apply_time(time)
	Audio.set_location(loc_id, time)
	life.build(location, player, time)
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


## Кот носит то, что надето в гардеробе; если там пусто (или персонаж закрыт) — фирменный образ,
## но только на модели: сохранённый гардероб сюжет не меняет.
func _outfit(model_id: String) -> Array[ClothingItem]:
	var s := Game.session
	if not s.characters.has_character(model_id):
		return []
	var items := s.outfit_items(model_id)
	if items.is_empty():
		var sig := s.characters.signature_outfit(model_id)
		for slot in sig:
			if s.catalog.has_item(str(sig[slot])):
				items.append(s.catalog.get_item(str(sig[slot])))
	return items


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
	_npc_by_model[model_id] = m


## Цели осмотра: точки int_<id> текущей локации; verbs — действие у цели из данных шага.
func npc_model(model_id: String) -> CharacterModel:
	return _npc_by_model.get(model_id)


## Постановка: персонаж сам идёт к точке (игрок — через контроллер, без ввода; NPC — по прямой).
func auto_walk(pos: Vector3, who := "player") -> void:
	if who == "player":
		player.auto_target = pos
		while is_inside_tree() and player_distance(pos) > 0.35:
			await get_tree().physics_frame
		player.auto_target = null
		return
	var m := npc_model(who)
	if m == null:
		return
	var body := m.get_parent() as Node3D
	var from := body.global_position
	var d := Vector2(pos.x - from.x, pos.z - from.z)
	m.rotation.y = atan2(d.x, d.y)
	var speed := 1.3
	m.play_motion("walk", speed)
	var tw := create_tween()
	tw.tween_property(body, "global_position", Vector3(pos.x, from.y, pos.z), d.length() / speed)
	await tw.finished
	m.play_motion("idle")


## Испытание-переодевание в гардеробе прямо посреди сцены (челлендж на склоне): открыть гардероб персонажа
## с темой испытания; после закрытия — образ на модели в мире. Возвращает true, если испытание пройдено.
func run_challenge(id: String, st: Dictionary) -> bool:
	var model_id := str(st.get("character", player_model))
	set_cutscene(true)
	overlay.set_skippable(false)
	tutorial.run("wardrobe", {"async": true})
	# в сумке персонажа — все его сюжетные вещи (старое сохранение могло их не содержать)
	if not Game.session.ensure_story_items(model_id).is_empty():
		Game.save_game()
	var music_before := Audio.music_override
	Audio.override_music("wardrobe", 1.0)
	var passed := false
	while not passed and is_inside_tree():
		var w: Control = load("res://scenes/ui/wardrobe.tscn").instantiate()
		w.set("start_character", model_id)
		w.set("start_challenge", id)
		w.set("story_mode", true)
		overlay.add_ui(w)
		await w.closed
		w.queue_free()
		passed = bool(Game.session.rewards.result(id).get("cleared", false))
		if not passed and st.has("retry"):
			await overlay.dialogue.play(st.retry, story)
	tutorial.finish()
	Audio.override_music(music_before, 1.5)
	player.set_character(model_id, Game.session.characters, _outfit(model_id))
	set_cutscene(false)
	return passed


## Автопилот испытания: надеть подходящие по теме вещи и сдать испытание (как сделал бы игрок).
func autopilot_challenge(id: String, st: Dictionary) -> void:
	var s := Game.session
	var model_id := str(st.get("character", player_model))
	var ch := s.challenges.get_challenge(id)
	var o := s.equipment.get_outfit(model_id).duplicate_outfit()
	for it in s.catalog.all_items():
		if model_id in it.compatible_character_ids and ("warm" in it.style_tags or "cold_weather" in it.style_tags):
			s.equipment.equip_into(o, model_id, it.id)
	s.equipment.set_outfit(model_id, o)
	var report := s.scoring.score(ch, s.outfit_items(model_id))
	s.rewards.submit(ch, report)
	player.set_character(model_id, s.characters, _outfit(model_id))


## Взаимодействие с целью без нажатия (автопилот и снимки).
func debug_interact(id: String) -> void:
	if not _interactables.has(id):
		return
	_focus = id
	_cutscene = false
	_try_interact()


func set_interactables(ids: Array, verbs: Dictionary = {}) -> void:
	_interactables.clear()
	_verbs = verbs
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
	overlay.set_skippable(on)
	if on:
		overlay.clear_fragments()
	if on and focus_id != "" and _interactables.has(focus_id):
		var p: Vector3 = _interactables[focus_id]
		player.face(p)
		var npc: CharacterModel = _npcs.get("int_" + focus_id)
		if npc:
			var d := player.global_position - npc.global_position
			npc.rotation.y = atan2(d.x, d.z)


func _process(_delta: float) -> void:
	player.water_level = location.water_level()
	if location.rain.visible:
		location.rain.global_position = player.global_position + Vector3(0, 9, 0)
	if overlay.stick:
		player.touch_move = overlay.stick.value
		player.touch_run = overlay.stick.value.length() > 0.92     # стик до упора — бег
	player.camera_yaw = cam.yaw
	if _beacon.visible:
		_beacon.rotation.y += _delta * 0.8
		var k := 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.004)
		_beacon.scale = Vector3(k, 1, k)
	_update_gazes()
	if _cutscene or _interactables.is_empty():
		return
	var best := ""
	var best_d := INTERACT_RADIUS
	for id in _interactables:
		var d := player_distance(_interactables[id])
		if d < best_d and _visible_from_player(_interactables[id]):
			best_d = d
			best = id
	if best != _focus:
		_focus = best
		if best == "":
			overlay.set_prompt("")
		else:
			overlay.set_prompt(_verb(best) + ("  ✓" if _seen.has(best) else ""))


## Для снимков: поезд через переезд — сразу.
func debug_train() -> void:
	if not life._train.is_empty():
		life.debug_train_at_crossing()
		# герой у переезда, лицом к путям (снимок поезда)
		var c: Vector3 = life._train.center
		player.place(Transform3D(Basis.looking_at(Vector3(-1, 0, 0.35).normalized(), Vector3.UP), c + Vector3(7.5, 0, -0.8)))
		cam.snap_behind(player.model.rotation.y)


## Взгляды: NPC поворачивают голову к герою, когда он рядом; герой смотрит на ближайшего собеседника.
func _update_gazes() -> void:
	var head := player.global_position + Vector3(0, player.model.eye_height(), 0) if player.model else player.global_position
	var nearest: CharacterModel = null
	var nearest_d := 3.2
	for m in _npcs.values():
		var npc := m as CharacterModel
		if npc == null or npc.look == null or not npc.is_inside_tree():
			continue
		var d := npc.global_position.distance_to(player.global_position)
		npc.look.target = head if d < 4.5 else null
		if d < nearest_d:
			nearest_d = d
			nearest = npc
	if player.model and player.model.look:
		player.model.look.target = nearest.global_position + Vector3(0, nearest.eye_height(), 0) if nearest else null


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("interact"):
		_try_interact()
	elif e.is_action_pressed("pause"):
		open_pause()


func _try_interact() -> void:
	if _cutscene or _focus == "":
		return
	overlay.set_prompt("")
	var id := _focus
	_focus = ""
	tutorial.notify("interacted")
	interacted.emit(id)


func _on_scene_started(i: int) -> void:
	_seen.clear()
	# первую сцену не запоминаем: «Продолжить» появляется, когда есть что продолжать
	Game.session.flags.set_flag(PROGRESS_FLAG, str(story.scenes[i].id) if i > 0 else "")
	Game.save_game()


func _on_finished() -> void:
	Game.session.flags.set_flag(PROGRESS_FLAG, "")
	Game.session.flags.set_flag(DONE_FLAG, true)
	Game.save_game()
	await overlay.fade(true, 1.0)
	to_title()


func to_title() -> void:
	get_tree().paused = false
	Game.save_game()
	start_scene = -1
	get_tree().change_scene_to_file("res://scenes/main.tscn")


## Пауза: продолжить или выйти в главное меню (прогресс — с начала текущей сцены).
func open_pause() -> void:
	if _pause.visible:
		_pause.close()
		return
	get_tree().paused = true
	_pause.clear()
	_pause.content.add_child(UiTheme.label("Прогресс сохранён с начала текущей сцены.", 18, UiTheme.TEXT_DIM))
	_pause.content.add_child(UiTheme.title("Звук", 22))
	for row in [["Music", "Музыка", "note"], ["Ambient", "Окружение", "wind"], ["SFX", "Эффекты", "speaker"], ["Voice", "Голоса", "voice"]]:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		h.add_child(UiTheme.icon(row[2], 26, UiTheme.GOLD_DEEP))
		var l := UiTheme.label(row[1], 18)
		l.custom_minimum_size.x = 120
		h.add_child(l)
		var bus: String = row[0]
		var sl := UiTheme.slider(Audio.get_volume(bus), func(v: float): Audio.set_volume(bus, v, false))
		sl.drag_ended.connect(func(_changed: bool): Audio.save_settings())
		h.add_child(sl)
		_pause.content.add_child(h)
	_pause.add_footer(UiTheme.secondary(UiTheme.button("В главное меню", to_title)))
	_pause.add_footer(UiTheme.primary(UiTheme.button("Продолжить", _pause.close)))
	_pause.open("Пауза", "menu")


## Глагол подсказки: из данных шага («verbs»: {"цель": "talk"|"look"}), иначе — по тому, говорящий ли это.
func _verb(id: String) -> String:
	var v: String = _verbs.get(id, "talk" if story.speakers.has(id) else "look")
	return "Поговорить" if v == "talk" else "Осмотреть"


## Цель видна, если между головой игрока и точкой нет стены (подсказка не светится сквозь стены).
func _visible_from_player(p: Vector3) -> bool:
	var from := player.global_position + Vector3(0, 1.0, 0)
	var q := PhysicsRayQueryParameters3D.create(from, p + Vector3(0, 1.0, 0), 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


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
