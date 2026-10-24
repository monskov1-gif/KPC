class_name PlayerProfile
extends RefCounted
## Профиль игрока: имя, номер, время в игре, альбом снимков. Уровень считается из прогресса (вещи, испытания,
## молитвы, события, снимки) — не хранится отдельно и не расходится с сохранением. Формула — стартовый баланс.

const NAME_MAX := 16
const XP_PER := {"item": 10, "challenge": 150, "pull": 5, "event": 50, "photo": 20}

var player_name := ""
var uid := 0
var play_seconds := 0.0
var photos: Array[String] = []         # пути снимков в user://photos (альбом)


func reset() -> void:
	player_name = ""
	uid = 0
	play_seconds = 0.0
	photos.clear()


## Номер игрока — один раз на сохранение (9 цифр).
func ensure_uid(seed_value: int) -> void:
	if uid == 0:
		var r := RandomNumberGenerator.new()
		r.seed = seed_value
		uid = r.randi_range(100000000, 999999999)


func display_name() -> String:
	return player_name if player_name != "" else "Гость отеля"


func set_player_name(v: String) -> void:
	player_name = v.strip_edges().left(NAME_MAX)


static func xp_from(stats: Dictionary) -> int:
	var xp := 0
	for k in XP_PER:
		xp += int(stats.get(k, 0)) * int(XP_PER[k])
	return xp


## Уровень и прогресс к следующему: уровень n начинается с 40·(n−1)² опыта.
static func level_of(xp: int) -> Dictionary:
	var lv := int(floor(sqrt(xp / 40.0))) + 1
	var cur := 40 * (lv - 1) * (lv - 1)
	var nxt := 40 * lv * lv
	return {"level": lv, "xp": xp, "from": cur, "to": nxt, "progress": float(xp - cur) / float(nxt - cur)}


func to_dict() -> Dictionary:
	return {"name": player_name, "uid": uid, "play_seconds": snappedf(play_seconds, 1.0), "photos": photos.duplicate()}


func load_dict(d: Dictionary) -> void:
	reset()
	player_name = str(d.get("name", "")).left(NAME_MAX)
	uid = int(d.get("uid", 0))
	play_seconds = maxf(0.0, float(d.get("play_seconds", 0.0)))
	photos = DataLoader.to_string_array(d.get("photos", []))
