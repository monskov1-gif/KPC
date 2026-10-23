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
	game.enter_location(str(sc.location), str(sc.player), str(sc.get("spawn", "spawn")), str(sc.get("time", "day")), sc.get("npcs", {}))
	for st in sc.steps:
		await _step(st)
		if not is_inside_tree():
			return


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
			await _wait(st.seconds)
			game.set_cutscene(false)
		"montage":
			game.set_cutscene(true)
			for fr in st.frames:
				game.location.apply_time(str(fr.time), _t(0.8))
				await o.caption("", str(fr.get("caption", "")), _t(st.seconds_each))
			game.set_cutscene(false)
		"water":
			var tw := game.location.set_water(float(st.level), _t(st.seconds))
			if tw and not st.get("async", false):
				await tw.finished
		"flag":
			Game.session.flags.set_flag(str(st.name), st.get("value", true))
		"say":
			game.set_cutscene(true)
			await o.dialogue.play(st.lines, story)
			game.set_cutscene(false)
			o.dialogue.skipping = _skipping
		"sketchbook":
			if not _skipping:
				game.set_cutscene(true)
				await o.sketchbook.open(st.pages)
				game.set_cutscene(false)
		"reach":
			_end_skip()
			await _reach(st)
		"explore":
			_end_skip()
			await _explore(st)


func _explore(st: Dictionary) -> void:
	var state := ExploreState.from_step(st)
	var lines: Dictionary = st.interactions
	game.set_interactables(lines.keys(), st.get("verbs", {}))
	_update_objective(state)
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
