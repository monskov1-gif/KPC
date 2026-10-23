extends Node
## Автозагрузка Audio — звук игры по данным data/audio/audio.json.
## • Шины Master / Music / Ambient / SFX / Voice (создаются при запуске, если их нет); громкость шин хранится
##   в user://settings.cfg (раздел [audio]) и задаётся set_volume().
## • Музыка и окружение — по две дорожки с плавной сменой (crossfade); петли бесшовные.
## • Локация и время суток выбирают музыку и окружение (раздел «locations»); сцена сюжета может задать свою музыку.
## • Эффекты: sfx(id) — пул плееров, случайный вариант и высота; ui(id) звучит и на паузе.
## • Кнопки интерфейса озвучиваются автоматически (каждая новая BaseButton; отключить — meta "silent").
## • Пауза: окружение и игровые эффекты замирают, музыка приглушается.

const DATA_PATH := "res://data/audio/audio.json"
const SETTINGS_PATH := "user://settings.cfg"
const BUSES := ["Music", "Ambient", "SFX", "Voice"]
const POOL := 10

var data: Dictionary = {}
## Громкость шин 0…1 (Master тоже).
var volumes := {"Master": 0.9, "Music": 0.7, "Ambient": 0.8, "SFX": 0.85, "Voice": 0.8}
var location_id := ""
var time_of_day := "day"
## Музыка, заданная сценой сюжета, перекрывает музыку локации до сброса (override_music("")).
var music_override := ""
var current_music := ""
var current_ambient := ""

var _music: Array[AudioStreamPlayer] = []
var _amb: Array[AudioStreamPlayer] = []
var _mi := 0
var _ai := 0
var _pool: Array[AudioStreamPlayer] = []
var _ui_pool: Array[AudioStreamPlayer] = []
var _cache := {}
var _tweens := {}
var _paused := false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	data = DataLoader.load_json(DATA_PATH)
	_make_buses()
	_load_settings()
	for i in 2:
		_music.append(_player("Music", true))
		# окружение ставим на паузу сами (stream_paused): плеер на паузе дерева не даёт себя заглушить при смене сцены
		_amb.append(_player("Ambient", true))
	for i in POOL:
		_pool.append(_player("SFX", false))
	for i in 4:
		_ui_pool.append(_player("SFX", true))
	get_tree().node_added.connect(_on_node_added)


func _player(bus: String, always: bool) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.process_mode = Node.PROCESS_MODE_ALWAYS if always else Node.PROCESS_MODE_PAUSABLE
	add_child(p)
	return p


func _make_buses() -> void:
	for b in BUSES:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")


# ---------- громкость ----------

func set_volume(bus: String, v: float, save := true) -> void:
	volumes[bus] = clampf(v, 0.0, 1.0)
	_apply_bus(bus)
	if save:
		_save_settings()


## Громкость шины из настроек; музыка на паузе — на 8 дБ тише.
func _apply_bus(bus: String) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return
	var db := linear_to_db(maxf(volumes[bus], 0.0001)) - (8.0 if bus == "Music" and _paused else 0.0)
	AudioServer.set_bus_volume_db(i, db)
	AudioServer.set_bus_mute(i, volumes[bus] <= 0.001)


## Сохранить настройки (ползунок вызывает при отпускании, а не на каждый шаг).
func save_settings() -> void:
	_save_settings()


func get_volume(bus: String) -> float:
	return volumes.get(bus, 1.0)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		for b in volumes:
			volumes[b] = float(cfg.get_value("audio", b, volumes[b]))
	for b in volumes:
		set_volume(b, volumes[b], false)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	for b in volumes:
		cfg.set_value("audio", b, volumes[b])
	cfg.save(SETTINGS_PATH)


# ---------- музыка и окружение ----------

## Локация и время суток: подобрать музыку (если сцена не задала свою) и окружение.
func set_location(id: String, time := "day") -> void:
	location_id = id
	time_of_day = time
	_apply_location()


func set_time(time: String) -> void:
	time_of_day = time
	_apply_location()


func surface() -> String:
	return str(data.get("locations", {}).get(location_id, {}).get("surface", "asphalt"))


## Музыка сцены сюжета: id — перекрыть музыку локации, "" — вернуть музыку локации.
func override_music(id: String, fade := 2.0) -> void:
	music_override = id
	_apply_location(fade)


func _apply_location(fade := 2.0) -> void:
	var loc: Dictionary = data.get("locations", {}).get(location_id, {})
	var m := music_override if music_override != "" else _pick(loc.get("music", {}))
	play_music(m, fade)
	play_ambient(_pick(loc.get("ambient", {})), fade)


func _pick(by_time: Dictionary) -> String:
	return str(by_time.get(time_of_day, by_time.get("*", by_time.get("day", ""))))


func play_music(id: String, fade := 1.5) -> void:
	if id == current_music:
		return
	current_music = id
	_mi = _cross(_music, _mi, data.get("music", {}).get(id, {}), fade)


func play_ambient(id: String, fade := 2.0) -> void:
	if id == current_ambient:
		return
	current_ambient = id
	_ai = _cross(_amb, _ai, data.get("ambient", {}).get(id, {}), fade)


func stop_music(fade := 1.5) -> void:
	current_music = ""
	_mi = _cross(_music, _mi, {}, fade)


## Плавная смена: старая дорожка затихает, новая (если есть) нарастает. Возвращает индекс новой дорожки.
func _cross(pair: Array[AudioStreamPlayer], cur: int, entry: Dictionary, fade: float) -> int:
	var old := pair[cur]
	_fade(old, -60.0, fade, true)
	var nxt := 1 - cur
	var p := pair[nxt]
	var stream: AudioStream = _stream(str(entry.get("file", ""))) if not entry.is_empty() else null
	if stream == null:
		return nxt
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	p.stream = stream
	p.volume_db = -60.0
	p.play()
	_fade(p, float(entry.get("volume_db", 0.0)), fade, false)
	return nxt


func _fade(p: AudioStreamPlayer, to_db: float, seconds: float, stop_after: bool) -> void:
	if _tweens.has(p) and (_tweens[p] as Tween).is_valid():
		(_tweens[p] as Tween).kill()
	if not p.playing and not p.stream_paused:
		return
	if seconds <= 0.0 or (p.stream_paused and stop_after):
		p.volume_db = to_db
		if stop_after:
			p.stop()
		return
	var tw := create_tween()
	tw.tween_property(p, "volume_db", to_db, seconds).set_trans(Tween.TRANS_SINE)
	if stop_after:
		tw.tween_callback(p.stop)
	_tweens[p] = tw


# ---------- эффекты ----------

## Эффект по id из данных. pitch — множитель высоты (голос персонажа, шаги ребёнка). Возвращает плеер (для петель).
func sfx(id: String, volume_offset_db := 0.0, pitch := 1.0) -> AudioStreamPlayer:
	var e: Dictionary = data.get("sfx", {}).get(id, {})
	if e.is_empty():
		return null
	var files: Array = e.get("files", [])
	if files.is_empty():
		return null
	var stream := _stream(str(files[_rng.randi() % files.size()]))
	if stream == null:
		return null
	# петли — только через sfx_at (плеер живёт вместе с локацией); из пула всё звучит один раз
	if stream is AudioStreamOggVorbis and (stream as AudioStreamOggVorbis).loop:
		stream = stream.duplicate()
		(stream as AudioStreamOggVorbis).loop = false
	var ui_sound: bool = e.get("ui", false)
	var p := _free_player(_ui_pool if ui_sound else _pool)
	p.bus = str(e.get("bus", "SFX"))
	p.stream = stream
	p.volume_db = float(e.get("volume_db", 0.0)) + volume_offset_db
	var pr := float(e.get("pitch_rand", 0.0))
	p.pitch_scale = maxf(0.3, pitch * (1.0 + _rng.randf_range(-pr, pr)))
	p.play()
	return p


## Звук в мире: 3D-плеер в точке pos (под узлом parent), затухает с расстоянием. Петли (колокол переезда)
## играют, пока плеер не удалят или не остановят.
func sfx_at(id: String, parent: Node3D, pos: Vector3, max_distance := 40.0) -> AudioStreamPlayer3D:
	var e: Dictionary = data.get("sfx", {}).get(id, {})
	var files: Array = e.get("files", [])
	if files.is_empty() or parent == null or not parent.is_inside_tree():
		return null
	var stream := _stream(str(files[_rng.randi() % files.size()]))
	if stream == null:
		return null
	var loop: bool = e.get("loop", false)
	if stream is AudioStreamOggVorbis:
		stream = stream.duplicate()
		(stream as AudioStreamOggVorbis).loop = loop
	var p := AudioStreamPlayer3D.new()
	p.bus = str(e.get("bus", "SFX"))
	p.stream = stream
	p.volume_db = float(e.get("volume_db", 0.0))
	p.max_distance = max_distance
	p.unit_size = 6.0
	parent.add_child(p)
	p.global_position = pos
	p.play()
	if not loop:
		p.finished.connect(p.queue_free)
	return p


func ui(id: String) -> void:
	sfx(id)


func _free_player(pool: Array[AudioStreamPlayer]) -> AudioStreamPlayer:
	for p in pool:
		if not p.playing:
			return p
	# все заняты — перебиваем самый давний
	var p := pool.pop_front() as AudioStreamPlayer
	pool.append(p)
	return p


func _stream(path: String) -> AudioStream:
	if path == "":
		return null
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
		if _cache[path] == null:
			push_warning("Нет звука %s" % path)
	return _cache[path]


# ---------- пауза и интерфейс ----------

func _process(_delta: float) -> void:
	var paused := get_tree().paused
	if paused != _paused:
		_paused = paused
		# на паузе музыка тише, окружение замирает (игровые эффекты замирают сами — их плееры на паузе дерева)
		_apply_bus("Music")
		for p in _amb:
			if p.playing or p.stream_paused:
				p.stream_paused = paused


func _on_node_added(n: Node) -> void:
	if n is BaseButton and not n.has_meta("silent"):
		(n as BaseButton).pressed.connect(_on_button.bind(n))


func _on_button(b: BaseButton) -> void:
	if b.has_meta("silent"):
		return
	ui("ui_tap")
