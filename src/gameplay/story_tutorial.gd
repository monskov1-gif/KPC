class_name StoryTutorial
extends Node
## Обучение в прологе (data/story/tutorials.json): карточка подсказки с текстом под текущее устройство ввода
## (клавиатура и мышь / касание / геймпад); исчезает, когда игрок выполнил действие. Пройденное запоминается
## во флагах «tut_<id>» и не повторяется; список доступен в справке паузы.

signal completed(id: String)

const PATH := "res://data/story/tutorials.json"

var game: StoryGame
var data: Dictionary = {}
var device := "kb"
var _active := ""
var _need: Dictionary = {}
var _progress := 0.0
var _last_pos := Vector3.ZERO
var _last_yaw := 0.0
var _last_zoom := 0.0


func _ready() -> void:
	data = DataLoader.load_json(PATH).get("tutorials", {})
	device = "touch" if DisplayServer.is_touchscreen_available() or OS.has_environment("KPC_TOUCH") else "kb"


func _input(e: InputEvent) -> void:
	# подсказки меняются вместе с последним устройством ввода
	if e is InputEventJoypadButton or (e is InputEventJoypadMotion and absf(e.axis_value) > 0.4):
		_set_device("pad")
	elif e is InputEventScreenTouch:
		_set_device("touch")
	elif e is InputEventKey or (e is InputEventMouseButton and e.device != InputEvent.DEVICE_ID_EMULATION):
		_set_device("kb")


func _set_device(d: String) -> void:
	if d != device:
		device = d
		if _active != "":
			_show_card()


func text_for(id: String) -> String:
	var t: Dictionary = data.get(id, {})
	return str(t.get(device, t.get("kb", "")))


## Показать подсказку и дождаться выполнения (или сразу вернуться при async: true — подсказка висит до выполнения).
func run(id: String, st: Dictionary = {}) -> void:
	if not data.has(id) or Game.session.flags.is_set("tut_" + id):
		return
	_active = id
	_need = data[id].get("done", {})
	_progress = 0.0
	_last_pos = game.player.global_position
	_last_yaw = game.cam.yaw
	_last_zoom = game.cam.zoom
	_show_card()
	if st.get("async", false):
		return
	while _active == id and is_inside_tree():
		await get_tree().process_frame


## Отметить действие извне (взаимодействие, гардероб).
func notify(kind: String) -> void:
	if _active != "" and _need.has(kind):
		_progress += 1.0
		_check(kind)


func _process(delta: float) -> void:
	if _active == "" or game == null:
		return
	if _need.has("moved"):
		var p := game.player.global_position
		_progress += Vector2(p.x - _last_pos.x, p.z - _last_pos.z).length()
		_last_pos = p
		_check("moved")
	elif _need.has("turned"):
		_progress += absf(angle_difference(_last_yaw, game.cam.yaw))
		_last_yaw = game.cam.yaw
		_check("turned")
	elif _need.has("zoomed"):
		_progress += absf(game.cam.zoom - _last_zoom)
		_last_zoom = game.cam.zoom
		_check("zoomed")
	elif _need.has("ran"):
		var v := game.player.velocity
		if Vector2(v.x, v.z).length() > game.player.walk_speed + 0.3:
			_progress += delta
		_check("ran")


func _check(kind: String) -> void:
	if _progress >= float(_need.get(kind, 0.0)):
		finish()


func finish() -> void:
	if _active == "":
		return
	var id := _active
	_active = ""
	Game.session.flags.set_flag("tut_" + id, true)
	game.overlay.hide_hint(true)
	completed.emit(id)


func _show_card() -> void:
	var t: Dictionary = data.get(_active, {})
	game.overlay.show_hint(str(t.get("icon", "sparkle")), str(t.get("title", "")), text_for(_active))
