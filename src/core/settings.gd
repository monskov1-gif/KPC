extends Node
## Настройки игры (громкость — в Audio): язык, графика, управление, доступность. Хранятся в user://settings.cfg
## и применяются сразу: язык — TranslationServer, масштаб отрисовки и ограничение кадров — движок,
## тени и свечение — у каждого нового света и окружения сцены, контуры — в CharacterModel, камера — FollowCamera.

signal changed(key: String)

const PATH := "user://settings.cfg"
const SECTION := "settings"
const DEFAULTS := {
	"language": "ru",
	"quality": "high",          # low | medium | high
	"render_scale": 1.0,        # 0.5…1.0 (доля разрешения 3D)
	"shadows": true,
	"outlines": true,
	"bloom": true,
	"fps_limit": 60,            # 30 | 60 | 0 (без ограничения)
	"camera_sensitivity": 1.0,  # 0.3…2.0
	"invert_y": false,
	"vibration": true,
	"ui_scale": 1.0,            # 0.9…1.3 — размер интерфейса и текста
	"reduce_motion": false,     # меньше покачиваний камеры и фона
	"show_fps": false,
}
## Пресеты качества: что меняется вместе с ним.
const QUALITY := {
	"low": {"render_scale": 0.7, "shadows": false, "bloom": false},
	"medium": {"render_scale": 0.85, "shadows": true, "bloom": true},
	"high": {"render_scale": 1.0, "shadows": true, "bloom": true},
}

var values: Dictionary = {}
var _fps_label: Label


func _ready() -> void:
	values = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(_path()) == OK:
		for k in DEFAULTS:
			values[k] = cfg.get_value(SECTION, k, DEFAULTS[k])
	get_tree().node_added.connect(_on_node_added)
	for k in values:
		_apply(k)


func _path() -> String:
	# снимки и тесты не трогают настройки игрока
	return "user://test_settings.cfg" if OS.has_environment("KPC_SAVE_PATH") else PATH


func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))


func set_value(key: String, v: Variant, save := true) -> void:
	values[key] = v
	if key == "quality" and QUALITY.has(v):
		for k in QUALITY[v]:
			values[k] = QUALITY[v][k]
			_apply(k)
			changed.emit(k)
	_apply(key)
	changed.emit(key)
	if save:
		save_settings()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for k in values:
		cfg.set_value(SECTION, k, values[k])
	cfg.save(_path())


## Языки, для которых есть файл строк (data/localization/<код>.json).
func languages() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open("res://data/localization")
	if dir:
		for f in dir.get_files():
			if f.ends_with(".json"):
				out.append(f.get_basename())
	out.sort()
	return out


func _apply(key: String) -> void:
	var v = values[key]
	match key:
		"language":
			if languages().has(str(v)):
				TranslationServer.set_locale(str(v))
		"render_scale":
			get_tree().root.scaling_3d_scale = clampf(float(v), 0.5, 1.0)
		"fps_limit":
			Engine.max_fps = int(v)
		"ui_scale":
			Game.ui_scale = float(v)          # множитель поверх масштаба по размеру экрана (Game._update_ui_scale)
		"shadows":
			for n in get_tree().root.find_children("*", "Light3D", true, false):
				_light(n as Light3D)
		"bloom":
			for n in get_tree().root.find_children("*", "WorldEnvironment", true, false):
				_env(n as WorldEnvironment)
		"show_fps":
			_show_fps(bool(v))


func _on_node_added(n: Node) -> void:
	if n is Light3D:
		_light(n)
	elif n is WorldEnvironment:
		_env.call_deferred(n)
	elif n is FollowCamera:
		_camera.call_deferred(n)


func _light(l: Light3D) -> void:
	if not bool(values["shadows"]):
		l.shadow_enabled = false


func _env(we: WorldEnvironment) -> void:
	if is_instance_valid(we) and we.environment and not bool(values["bloom"]):
		we.environment.glow_enabled = false


func _camera(c: FollowCamera) -> void:
	if is_instance_valid(c):
		c.sens_x = float(values["camera_sensitivity"])
		c.sens_y = float(values["camera_sensitivity"])
		c.invert_y = bool(values["invert_y"])


func _show_fps(on: bool) -> void:
	if on and _fps_label == null:
		var layer := CanvasLayer.new()
		layer.layer = 100
		add_child(layer)
		_fps_label = Label.new()
		_fps_label.position = Vector2(8, 4)
		_fps_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
		_fps_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
		_fps_label.add_theme_constant_override("outline_size", 3)
		layer.add_child(_fps_label)
	if _fps_label:
		_fps_label.get_parent().visible = on


func _process(_delta: float) -> void:
	if _fps_label and _fps_label.get_parent().visible:
		_fps_label.text = "%d FPS" % Engine.get_frames_per_second()


## Вибрация на телефоне (если не выключена в настройках).
func vibrate(ms: int) -> void:
	if bool(values["vibration"]):
		Input.vibrate_handheld(ms)
