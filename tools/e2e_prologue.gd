extends SceneTree
## Сквозная проверка пролога: игра сама проходит все сцены на автопилоте (StoryDirector.autopilot).
## Печатает каждый шаг; код выхода 0 — пролог пройден до конца, 1 — застрял или упал (по таймауту).
## Запуск: tools/e2e_prologue.sh

var _scene: Node
var _last := ""
var _t := 0.0
var _done := false


func _initialize() -> void:
	_scene = (load("res://scenes/game/story.tscn") as PackedScene).instantiate()
	root.add_child(_scene)
	_hook.call_deferred()


func _hook() -> void:
	var d = _scene.get("director")
	d.step_done.connect(func(sid, i):
		_last = "%s:%d" % [sid, i]
		_t = 0.0
		print("  шаг ", _last, " — ", d.story.scenes[d.current].steps[i].type))
	d.finished.connect(func():
		_done = true
		print("ПРОЛОГ ПРОЙДЕН, флаг prologue_complete = ", root.get_node("Game").session.flags.is_set("prologue_complete")))


func _process(delta: float) -> bool:
	_t += delta
	if _done:
		quit(0)
		return true
	if _t > 40.0:
		printerr("ЗАСТРЯЛ после шага ", _last)
		quit(1)
		return true
	return false
