class_name StoryDirector
extends Node
## Исполняет сцены StoryScript по шагам (типы шагов — StoryScript.STEP_FIELDS).
## Всё, что видно и слышно, берётся из данных; режиссёр только ведёт порядок и ждёт игрока.

signal scene_started(index: int)
signal finished

## Ускорение пауз и переходов (снимки экрана, отладка): 1 — обычная скорость.
var time_scale := 1.0
var game: StoryGame
var story: StoryScript
var current := -1
var _objective := ""
## Пропуск катсцены: паузы и переходы мгновенны, реплики не ждут; сбрасывается на игровом шаге.
var _skipping := false
## Поколение обрывков фраз: новый шаг «дойти» отменяет недоигранные обрывки прошлого.
var _frag_gen := 0
## Автопилот (KPC_AUTOPILOT): сам листает реплики, подходит к целям, проходит подсказки и испытания —
## для сквозной проверки пролога и снимков. Остановка KPC_STOP_AT="<сцена>:<шаг>" — после этого шага.
var autopilot := OS.has_environment("KPC_AUTOPILOT")
var _stop_at := OS.get_environment("KPC_STOP_AT") if OS.has_environment("KPC_STOP_AT") else ""
signal step_done(scene_id: String, index: int)


func run(from_index: int) -> void:
	for i in range(clampi(from_index, 0, story.scenes.size() - 1), story.scenes.size()):
		current = i
		scene_started.emit(i)
		await _scene(story.scenes[i])
		if not is_inside_tree():
			return
	finished.emit()


func _scene(sc: Dictionary) -> void:
	_end_skip()
	_objective = ""
	game.overlay.set_objective("")
	# музыка сцены (если задана) перекрывает музыку локации до конца сцены
	Audio.music_override = str(sc.get("music", ""))
	game.enter_location(str(sc.location), str(sc.player), str(sc.get("spawn", "spawn")), str(sc.get("time", "day")), sc.get("npcs", {}))
	if sc.has("rest"):
		# сцена начинается с героем в позе (спит на пледе) — управление вернёт шаг act «stand»
		game.player.model.set_rest(str(sc.rest), 0.0)
		game.set_cutscene(true)
	if autopilot:
		game.overlay.dialogue.auto_advance = 0.25 * time_scale + 0.05
	for i in sc.steps.size():
		await _step(sc.steps[i])
		if not is_inside_tree():
			return
		step_done.emit(str(sc.id), i)
		if _stop_at == "%s:%d" % [sc.id, i]:
			await get_tree().create_timer(3600.0).timeout


func _step(st: Dictionary) -> void:
	var o := game.overlay
	match st.type:
		"caption":
			game.set_cutscene(true)
			await o.caption(str(st.get("text", "")), str(st.get("sub", "")), _t(st.seconds))
			game.set_cutscene(false)
		"objective":
			_objective = str(st.text)
			o.set_objective(_objective)
		"fade":
			# во время затемнения игрок не ходит
			game.set_cutscene(true)
			await o.fade(st.to == "black", _t(st.seconds))
			game.set_cutscene(st.to == "black")
		"location":
			game.enter_location(str(st.id), str(st.get("player", game.player_model)), str(st.get("spawn", "spawn")),
				str(st.get("time", game.location.time_of_day)), st.get("npcs", {}))
		"time":
			game.set_cutscene(true)
			game.location.apply_time(str(st.to), _t(st.seconds))
			Audio.set_time(str(st.to))
			game.life.set_time(str(st.to))
			await _wait(st.seconds)
			game.set_cutscene(false)
		"montage":
			game.set_cutscene(true)
			for fr in st.frames:
				game.location.apply_time(str(fr.time), _t(0.8))
				Audio.set_time(str(fr.time))
				await o.caption("", str(fr.get("caption", "")), _t(st.seconds_each))
			game.set_cutscene(false)
		"water":
			var tw := game.location.set_water(float(st.level), _t(st.seconds))
			if tw and not st.get("async", false):
				await tw.finished
		"music":
			# "id": "" — вернуть музыку локации
			Audio.override_music(str(st.get("id", "")), _t(st.get("seconds", 2.0)))
		"sfx":
			Audio.sfx(str(st.id), float(st.get("volume_db", 0.0)))
		"flag":
			Game.session.flags.set_flag(str(st.name), st.get("value", true))
		"say":
			game.set_cutscene(true)
			await o.dialogue.play(st.lines, story)
			game.set_cutscene(false)
			o.dialogue.skipping = _skipping
		"sketchbook":
			if autopilot:
				get_tree().create_timer(maxf(0.3, 1.5 * time_scale)).timeout.connect(o.sketchbook.close)
			if not _skipping:
				game.set_cutscene(true)
				await o.sketchbook.open(st.pages)
				game.set_cutscene(false)
		"act":
			await _act(st)
		"camera":
			if st.get("release", false):
				game.cam.release(_t(st.get("seconds", 0.9)))
			else:
				var look: Vector3 = game.player.global_position + Vector3(0, game.player.model.height() * 0.6, 0) \
					if str(st.get("look", "player")) == "player" else game.location.marker(str(st.look)).origin
				game.cam.shot(game.location.marker(str(st.at)).origin, look, _t(st.get("seconds", 1.2)))
				if not st.get("async", true):
					await _wait(st.get("seconds", 1.2))
		"wait":
			await _wait(st.seconds)
		"tutorial":
			if autopilot:
				game.tutorial.run(str(st.id), {"async": true})
				game.tutorial.finish()
			else:
				await game.tutorial.run(str(st.id), st)
		"challenge":
			# KPC_SHOW_CHALLENGE: автопилот открывает настоящий гардероб (для снимков испытания)
			if autopilot and not OS.has_environment("KPC_SHOW_CHALLENGE"):
				game.autopilot_challenge(str(st.id), st)
			else:
				await game.run_challenge(str(st.id), st)
		"reach":
			_end_skip()
			await _reach(st)
		"explore":
			_end_skip()
			await _explore(st)


## Постановка: персонаж садится, засыпает, встаёт, подходит к точке, поворачивается.
func _act(st: Dictionary) -> void:
	var who := str(st.get("who", "player"))
	var secs := _t(st.get("seconds", 1.0))
	var model: CharacterModel = game.player.model if who == "player" else game.npc_model(who)
	if model == null:
		push_warning("act: нет персонажа %s" % who)
		return
	game.set_cutscene(true)
	match str(st.do):
		"walk_to":
			await game.auto_walk(game.location.marker(str(st.at)).origin, who)
		"face":
			var p := game.location.marker(str(st.at)).origin if st.has("at") else game.player.global_position
			model.rotation.y = atan2(p.x - model.global_position.x, p.z - model.global_position.z)
		"sit", "sleep":
			if st.has("at") and who == "player":
				game.player.place(game.location.marker(str(st.at)))
			model.set_rest(str(st.do), secs)
			await _wait(st.get("seconds", 1.0))
		"stand":
			model.set_rest("", secs)
			await _wait(st.get("seconds", 1.0))
	if not st.get("hold", false):
		game.set_cutscene(false)


func _explore(st: Dictionary) -> void:
	var state := ExploreState.from_step(st)
	var lines: Dictionary = st.interactions
	game.set_interactables(lines.keys(), st.get("verbs", {}))
	_update_objective(state)
	if autopilot:
		_autopilot_explore(st, state)
	while not state.complete():
		var id: String = await game.interacted
		if not lines.has(id):
			continue
		game.set_cutscene(true, id)
		await game.overlay.dialogue.play(lines[id], story)
		_end_skip()
		game.set_cutscene(false)
		state.mark(id)
		game.mark_seen(id)
		_update_objective(state)
	game.set_interactables([])


## Автопилот осмотра: подойти и поговорить с обязательными целями и нужным числом необязательных.
func _autopilot_explore(st: Dictionary, state: ExploreState) -> void:
	var order: Array = st.get("required", []).duplicate()
	for k in st.interactions:
		if not k in order and order.size() < state.required.size() + state.optional_min:
			order.append(k)
	for id in order:
		await get_tree().create_timer(0.2).timeout
		var p := game.location.marker("int_" + str(id)).origin
		# автопилот переносит героя к цели (прямая ходьба застряла бы у изгородей)
		game.player.place(Transform3D(Basis.IDENTITY, p + Vector3(0.9, 0.05, 0.6)))
		await get_tree().physics_frame
		game.debug_interact(str(id))
		while game._cutscene and is_inside_tree():
			await get_tree().process_frame


func _update_objective(state: ExploreState) -> void:
	if _objective == "":
		return
	var left := state.remaining()
	game.overlay.set_objective(_objective + ("  ·  ещё %d" % left if left > 0 else ""))


func _reach(st: Dictionary) -> void:
	var target := "reach_" + str(st.target)
	var pos := game.location.marker(target).origin
	game.set_beacon(pos)
	var frags: Array = st.get("fragments", [])
	if not frags.is_empty():
		_play_fragments(frags)
	if autopilot:
		game.player.place(Transform3D(Basis.IDENTITY, pos + Vector3(0, 0.1, 0)))
	while is_inside_tree() and game.player_distance(pos) > StoryGame.REACH_RADIUS:
		await get_tree().process_frame
	game.set_beacon(null)


func _play_fragments(frags: Array) -> void:
	_frag_gen += 1
	var gen := _frag_gen
	for f in frags:
		if not is_inside_tree() or gen != _frag_gen or game.player.input_enabled == false:
			return
		game.overlay.fragment(story.speaker_name(str(f.who)), str(f.text), _t(3.2))
		await _wait(3.6)


## Пропустить текущую катсцену до ближайшего игрового шага (осмотр или «дойти до…»).
## Итог сцены тот же: время суток, вода, флаги применяются, только без ожидания.
func skip() -> void:
	_skipping = true
	game.overlay.dialogue.skip()
	game.overlay.sketchbook.close()
	game.overlay.finish_tweens()
	game.location.finish_tweens()


func _end_skip() -> void:
	_skipping = false
	game.overlay.dialogue.skipping = false


func _t(seconds) -> float:
	return 0.01 if _skipping else float(seconds) * time_scale


func _wait(seconds) -> void:
	# таймер останавливается вместе с паузой игры
	await get_tree().create_timer(maxf(0.01, _t(seconds)), false).timeout
