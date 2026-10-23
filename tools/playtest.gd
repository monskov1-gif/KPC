extends SceneTree
## Прохождение пролога «как игрок» — без автопилота и телепортов:
## • ходит физикой персонажа по проложенному пути (сетка проходимости, как в walk_check), бегом;
## • обучение выполняет настоящим вводом (ходьба, поворот камеры, зум, бег);
## • говорит и осматривает кнопкой «взаимодействие», только когда игра показала подсказку;
## • реплики и скетчбук листает кнопкой, катсцены не пропускает;
## • в гардеробе нажимает карточки вещей, «На подиум» и «Продолжить».
## KPC_PLAYTEST_OLD_SAVE=1 — начать со «старого» сохранения без одежды Кота-ребёнка.
## Код выхода 0 — пролог пройден; 1 — застрял (печатает, где и почему).
## Запуск: tools/playtest.sh

const CELL := 0.4
const STEP := 0.25
const STUCK_LIMIT := 150.0     # секунд без продвижения по сюжету
const PRESS := 0.35

var g: Node
var game_ap: Node
var _last_step := ""
var _idle := 0.0
var _press_t := 0.0
var _path: Array = []
var _goal = null
var _goal_id := ""
var _replan := 0.0
var _last_pos := Vector3.ZERO
var _still := 0.0
var _tut_t := 0.0
var _w_state := ""
var _w_t := 0.0
var _done := false
var _cap: CapsuleShape3D
var _log := []


func _initialize() -> void:
	_cap = CapsuleShape3D.new()
	_cap.radius = 0.22
	_cap.height = 0.9
	_start.call_deferred()


func _start() -> void:
	game_ap = root.get_node("Game")
	if game_ap.session == null:
		await game_ap.session_ready
	if OS.has_environment("KPC_PLAYTEST_OLD_SAVE"):
		# сохранение прошлой версии: без сюжетной одежды Кота-ребёнка
		var d: Dictionary = game_ap.session.to_save_dict()
		for id in (d.wardrobe.owned as Dictionary).keys():
			if str(id).begins_with("clothing_kotc_"):
				d.wardrobe.owned.erase(id)
		game_ap.session.load_save_dict(d)
		print("старое сохранение: одежда Кота-ребёнка — ", game_ap.session.inventory.owns("clothing_kotc_puffer_jacket_001"))
	g = (load("res://scenes/game/story.tscn") as PackedScene).instantiate()
	root.add_child(g)
	_hook.call_deferred()


func _hook() -> void:
	var d = g.get("director")
	d.step_done.connect(func(sid, i):
		_last_step = "%s:%d" % [sid, i]
		_idle = 0.0
		print("  шаг ", _last_step, " — ", d.story.scenes[d.current].steps[i].type))
	d.finished.connect(func():
		_done = true
		print("ПРОЙДЕНО ИГРОКОМ, prologue_complete = ", game_ap.session.flags.is_set("prologue_complete")))


func _process(delta: float) -> bool:
	if _done:
		quit(0)
		return true
	_idle += delta
	if _idle > STUCK_LIMIT:
		_report_stuck()
		quit(1)
		return true
	_press_t -= delta
	if g == null:
		return false
	var d = g.get("director")
	if d == null or d.current < 0:
		return false
	var ov = g.overlay
	# гардероб испытания
	var w := _find_wardrobe()
	if w:
		_wardrobe(w, delta)
		return false
	_w_state = ""
	# реплики и скетчбук — кнопкой
	if ov.dialogue.visible or ov.sketchbook.visible:
		_release_moves()
		if _press_t <= 0.0:
			_tap("ui_accept")
		return false
	var step: Dictionary = d.story.scenes[d.current].steps[clampi(_step_index(), 0, d.story.scenes[d.current].steps.size() - 1)]
	# обучение — настоящим вводом
	if str(g.tutorial._active) in ["move", "camera", "zoom", "run"]:
		_tutorial(str(g.tutorial._active), delta)
		# «бег» идёт вместе с шагом «дойти»: не прерывать путь
		if str(g.tutorial._active) != "run":
			return false
	_release_tutorial_input()
	match str(step.type):
		"reach":
			_go(g.location.marker("reach_" + str(step.target)).origin, "reach_" + str(step.target), delta)
		"explore":
			_explore(step, delta)
		_:
			_release_moves()
	return false


func _step_index() -> int:
	# шаг, который сейчас выполняется: следующий после последнего завершённого в этой сцене
	var d = g.get("director")
	var sid := str(d.story.scenes[d.current].id)
	if _last_step.begins_with(sid + ":"):
		return int(_last_step.get_slice(":", 1)) + 1
	return 0


# ---------- обучение ----------

func _tutorial(id: String, delta: float) -> void:
	_tut_t += delta
	match id:
		"move":
			Input.action_press("move_forward")
		"camera":
			Input.action_press("camera_right")
		"zoom":
			Input.action_press("zoom_in" if fmod(_tut_t, 2.0) < 1.0 else "zoom_out")
		"run":
			Input.action_press("run")
			Input.action_press("move_forward")
		_:
			pass   # «осмотреть» и «гардероб» выполняются по ходу сцены


func _release_tutorial_input() -> void:
	for a in ["camera_right", "zoom_in", "zoom_out"]:
		Input.action_release(a)
	_tut_t = 0.0


# ---------- ходьба по пути ----------

func _go(goal: Vector3, id: String, delta: float) -> bool:
	var p: Vector3 = g.player.global_position
	if Vector2(p.x - goal.x, p.z - goal.z).length() < 0.9:
		g.player.auto_target = null
		Input.action_release("run")
		return true
	if _goal_id != id or _path.is_empty():
		_goal_id = id
		_goal = goal
		_path = _plan(p, goal)
		if _path.is_empty():
			_log.append("нет пути к %s от %s" % [id, p])
			_path = [goal]
	var wp: Vector3 = _path[0]
	if Vector2(p.x - wp.x, p.z - wp.z).length() < 0.45:
		_path.pop_front()
		if _path.is_empty():
			_path = [goal]
		wp = _path[0]
	Input.action_press("run")
	g.player.auto_target = wp
	# застрял на месте — переложить путь
	_still = _still + delta if p.distance_to(_last_pos) < 0.02 else 0.0
	_last_pos = p
	if _still > 2.0:
		_still = 0.0
		_log.append("упёрся у %s по пути к %s" % [p.snapped(Vector3.ONE * 0.1), id])
		_path = _plan(p, goal)
	return false


func _release_moves() -> void:
	g.player.auto_target = null
	for a in ["move_forward", "run"]:
		Input.action_release(a)


func _plan(from: Vector3, goal: Vector3) -> Array:
	var space: PhysicsDirectSpaceState3D = g.get_world_3d().direct_space_state
	var start := Vector2i(roundi(from.x / CELL), roundi(from.z / CELL))
	var gc := Vector2i(roundi(goal.x / CELL), roundi(goal.z / CELL))
	var h0 := _floor(space, from.x, from.z, from.y)
	if is_nan(h0):
		h0 = from.y
	var height := {start: h0}
	var prev := {}
	var q := [start]
	var head := 0
	var best := start
	var best_d := INF
	while head < q.size() and q.size() < 40000:
		var c: Vector2i = q[head]
		head += 1
		var dd := Vector2(c - gc).length()
		if dd < best_d:
			best_d = dd
			best = c
		if dd * CELL < 0.8:
			break
		for dl in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + dl
			if height.has(n):
				continue
			var h := _floor(space, n.x * CELL, n.y * CELL, height[c])
			if is_nan(h) or absf(h - height[c]) > STEP + 0.05 or not _free(space, n.x * CELL, h, n.y * CELL):
				continue
			height[n] = h
			prev[n] = c
			q.append(n)
	var path := []
	var c := best
	while prev.has(c):
		path.push_front(Vector3(c.x * CELL, height[c], c.y * CELL))
		c = prev[c]
	# прореживание: каждая третья точка
	var out := []
	for i in path.size():
		if i % 3 == 2 or i == path.size() - 1:
			out.append(path[i])
	return out


func _floor(space: PhysicsDirectSpaceState3D, x: float, z: float, from_y: float) -> float:
	var r := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, from_y + 1.4, z), Vector3(x, from_y - 3.0, z), 1))
	if r.is_empty() or (r.normal as Vector3).y < 0.6:
		return NAN
	return (r.position as Vector3).y


func _free(space: PhysicsDirectSpaceState3D, x: float, y: float, z: float) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _cap
	q.collision_mask = 1 | 4
	q.transform = Transform3D(Basis.IDENTITY, Vector3(x, y + STEP + 0.02 + _cap.height * 0.5, z))
	return space.intersect_shape(q, 1).is_empty()


# ---------- осмотр ----------

func _explore(step: Dictionary, delta: float) -> void:
	var lines: Dictionary = step.interactions
	var need: Array = step.get("required", []).duplicate()
	for k in lines:
		if not k in need:
			need.append(k)
	var target := ""
	for k in need:
		if not g._seen.has(k):
			target = str(k)
			break
	if target == "":
		_release_moves()
		return
	var pos: Vector3 = g._interactables.get(target, g.location.marker("int_" + target).origin)
	# подсказка видна — нажать «взаимодействие»
	if g._focus == target:
		_release_moves()
		if _press_t <= 0.0:
			_tap("interact")
		return
	_go(pos, "int_" + target, delta)


# ---------- гардероб ----------

func _find_wardrobe() -> Node:
	for n in root.find_children("*", "WardrobeScreen", true, false):
		if n.is_inside_tree() and n.visible:
			return n
	return null


func _wardrobe(w: Node, delta: float) -> void:
	_release_moves()
	_w_t += delta
	if _w_t < 0.6:
		return
	_w_t = 0.0
	# окно результата: «Продолжить» или «Переодеться»
	for b in root.find_children("*", "Button", true, false):
		var btn := b as Button
		if btn.is_visible_in_tree() and not btn.disabled and (btn.text == "Продолжить" or btn.text == "Переодеться"):
			print("  гардероб: «%s»" % btn.text)
			btn.pressed.emit()
			_w_state = "" if btn.text == "Переодеться" else "done"
			return
	if _w_state == "":
		_dress(w)
		_w_state = "dressed"
		return
	if _w_state == "dressed":
		for b in root.find_children("*", "Button", true, false):
			var btn := b as Button
			if btn.is_visible_in_tree() and not btn.disabled and btn.text == Localization.t("ui.submit"):
				print("  гардероб: «%s»" % btn.text)
				btn.pressed.emit()
				_w_state = "submitted"
				return
		# узкая раскладка (телефон): испытание открывается кнопкой-кубком
		if w._trophy_btn and w._trophy_btn.is_visible_in_tree():
			print("  гардероб: кубок (испытание)")
			w._trophy_btn.pressed.emit()
			return
		var texts := []
		for b in root.find_children("*", "Button", true, false):
			if (b as Button).text != "":
				texts.append("%s[%s%s]" % [(b as Button).text, "v" if (b as Button).is_visible_in_tree() else "h", "d" if (b as Button).disabled else ""])
		_log.append("гардероб: нет кнопки «На подиум»; кнопки: " + ", ".join(texts))


## Как игрок: перебирает карточки в сетке и оставляет то, что повышает оценку испытания.
func _dress(w: Node) -> void:
	var cards := []
	for c in w._grid.get_children():
		if c is ItemCard:
			cards.append(c)
	print("  гардероб: в сумке карточек — ", cards.size())
	if cards.is_empty():
		_log.append("гардероб: в сумке нет ни одной вещи")
		return
	var s = game_ap.session
	var ch: Dictionary = w._challenge.challenge()
	for round in 2:
		for c in cards:
			var id: String = c.item.id
			var before: int = s.scoring.score(ch, s.items_for_outfit(w.draft)).final_score
			var worn: bool = w.draft.has_item(id)
			c.tapped.emit(id)
			var after: int = s.scoring.score(ch, s.items_for_outfit(w.draft)).final_score
			if after < before or (after == before and not worn):
				if w.draft.has_item(id) != worn:
					w.toggle_item(id)      # хуже — вернуть как было
	var r = s.scoring.score(ch, s.items_for_outfit(w.draft))
	print("  гардероб: образ ", w.draft.item_ids(), " → ", r.final_score, " ", r.rank)


func _tap(action: String) -> void:
	var e := InputEventAction.new()
	e.action = action
	e.pressed = true
	Input.parse_input_event(e)
	var u := InputEventAction.new()
	u.action = action
	u.pressed = false
	Input.parse_input_event(u)
	_press_t = PRESS


func _report_stuck() -> void:
	var d = g.get("director")
	print("ЗАСТРЯЛ ИГРОК после шага ", _last_step, " (сцена ", d.story.scenes[d.current].id if d.current >= 0 else "?", ")")
	print("  позиция ", g.player.global_position, ", подсказка: ", g._focus, ", катсцена: ", g._cutscene)
	print("  обучение: ", g.tutorial._active, ", диалог: ", g.overlay.dialogue.visible, ", гардероб: ", _find_wardrobe() != null)
	for l in _log.slice(-8):
		print("  ", l)
