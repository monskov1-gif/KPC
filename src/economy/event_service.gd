class_name EventService
extends RefCounted
## События (data/events/events.json): конкурсы-испытания по расписанию и ежедневный подарок.
## Расписание — по номеру дня (UTC): событие идёт days дней из каждого цикла длиной cycle, начиная с offset.
## Награда события выдаётся один раз за его период (за конкурс — после прохождения испытания, за подарок — раз в
## день; каждый every-й день подряд — бонус). День передаётся снаружи (today()) — тесты задают его сами.

var errors: Array[String] = []
var _events: Array[Dictionary] = []
var _resources: ResourceInventory
var _claimed: Dictionary = {}          # event_id -> номер периода, за который награда уже получена
var _streak := 0
var _last_gift_day := -1
var _total := 0                        # сколько наград событий получено за всю игру (профиль)


func _init(resources: ResourceInventory) -> void:
	_resources = resources


static func today() -> int:
	return int(Time.get_unix_time_from_system() / 86400.0)


func load_data(entries: Array, challenges: FashionChallengeCatalog) -> void:
	for e in entries:
		if typeof(e) != TYPE_DICTIONARY or str(e.get("id", "")) == "":
			errors.append("события: запись без id")
			continue
		if e.get("kind", "") == "challenge" and challenges.get_challenge(str(e.get("challenge_id", ""))) == null:
			errors.append("событие %s: неизвестное испытание '%s'" % [e.id, e.get("challenge_id")])
		for r in _rewards_of(e):
			if not _resources.is_known(r):
				errors.append("событие %s: неизвестный ресурс '%s'" % [e.id, r])
		if int(e.get("cycle", 1)) < 1 or int(e.get("days", 1)) < 1:
			errors.append("событие %s: cycle и days должны быть ≥ 1" % e.id)
		_events.append(e)


static func _rewards_of(e: Dictionary) -> Array:
	var out: Array = (e.get("reward", {}) as Dictionary).keys()
	out.append_array((e.get("streak_bonus", {}).get("reward", {}) as Dictionary).keys())
	return out


func all_events() -> Array[Dictionary]:
	return _events


func get_event(id: String) -> Dictionary:
	for e in _events:
		if str(e.id) == id:
			return e
	return {}


## Номер текущего периода события (−1 — сейчас не идёт).
func period(e: Dictionary, day: int) -> int:
	var cycle := maxi(1, int(e.get("cycle", 1)))
	var k := posmod(day - int(e.get("offset", 0)), cycle)
	if k >= int(e.get("days", 1)):
		return -1
	return floori(float(day - int(e.get("offset", 0))) / cycle)


func is_active(e: Dictionary, day: int) -> bool:
	return period(e, day) >= 0


## Сколько дней осталось (включая сегодня); для неактивного — через сколько дней начнётся (отрицательное число).
func days_left(e: Dictionary, day: int) -> int:
	var cycle := maxi(1, int(e.get("cycle", 1)))
	var k := posmod(day - int(e.get("offset", 0)), cycle)
	var days := int(e.get("days", 1))
	return days - k if k < days else -(cycle - k)


func claimed(e: Dictionary, day: int) -> bool:
	var p := period(e, day)
	return p >= 0 and int(_claimed.get(str(e.id), -999999)) == p


## Можно ли забрать награду: событие идёт, награда за этот период ещё не получена, условие выполнено
## (для конкурса — испытание пройдено: cleared передаёт вызывающий из ChallengeRewardService).
func can_claim(e: Dictionary, day: int, cleared := false) -> bool:
	if not is_active(e, day) or claimed(e, day):
		return false
	return e.get("kind", "") == "daily" or cleared


## Забрать награду. Возвращает {"ok", "error_key", "reward": {ресурс: число}}.
func claim(id: String, day: int, cleared := false) -> Dictionary:
	var e := get_event(id)
	if e.is_empty():
		return {"ok": false, "error_key": "event.unknown", "reward": {}}
	if not can_claim(e, day, cleared):
		return {"ok": false, "error_key": "event.not_available", "reward": {}}
	var reward: Dictionary = (e.get("reward", {}) as Dictionary).duplicate()
	if e.get("kind", "") == "daily":
		_streak = _streak + 1 if _last_gift_day == day - 1 else 1
		_last_gift_day = day
		var bonus: Dictionary = e.get("streak_bonus", {})
		if not bonus.is_empty() and _streak % maxi(1, int(bonus.get("every", 7))) == 0:
			for r in bonus.get("reward", {}):
				reward[r] = int(reward.get(r, 0)) + int(bonus.reward[r])
	var err := _resources.apply_deltas(reward)
	if err != "":
		return {"ok": false, "error_key": err, "reward": {}}
	_claimed[str(e.id)] = period(e, day)
	_total += 1
	return {"ok": true, "error_key": "", "reward": reward}


func streak() -> int:
	return _streak


func claims_total() -> int:
	return _total


func reset() -> void:
	_claimed.clear()
	_streak = 0
	_last_gift_day = -1
	_total = 0


func to_dict() -> Dictionary:
	return {"claimed": _claimed.duplicate(), "streak": _streak, "last_gift_day": _last_gift_day, "total": _total}


func load_dict(d: Dictionary) -> void:
	reset()
	var c = d.get("claimed", {})
	if typeof(c) == TYPE_DICTIONARY:
		for k in c:
			_claimed[str(k)] = int(c[k])
	_streak = int(d.get("streak", 0))
	_last_gift_day = int(d.get("last_gift_day", -1))
	_total = int(d.get("total", _claimed.size()))
