class_name StoryScript
extends RefCounted
## Сюжетный сценарий из data/story/<id>.json: сцены и шаги, которые исполняет StoryDirector.
## Здесь только загрузка и проверка данных — никакого сюжета в коде.

const TIMES := ["day", "evening", "night", "storm"]
## Обязательные поля каждого типа шага.
const STEP_FIELDS := {
	"caption": ["seconds"],
	"objective": ["text"],
	"explore": ["interactions"],
	"fade": ["to", "seconds"],
	"location": ["id"],
	"reach": ["target"],
	"say": ["lines"],
	"sketchbook": ["pages"],
	"time": ["to", "seconds"],
	"montage": ["frames", "seconds_each"],
	"water": ["level", "seconds"],
	"flag": ["name"],
}

var id := ""
var speakers: Dictionary = {}
var scenes: Array = []
var errors: Array[String] = []


static func load_file(path: String) -> StoryScript:
	var s := StoryScript.new()
	var load_errors: Array = []
	var d := DataLoader.load_json(path, load_errors)
	for e in load_errors:
		s.errors.append(str(e))
	if d.is_empty():
		if s.errors.is_empty():
			s.errors.append("%s: пустой файл" % path)
		return s
	s.id = str(d.get("id", ""))
	s.speakers = d.get("speakers", {})
	s.scenes = d.get("scenes", [])
	s.errors.append_array(validate(d))
	return s


func scene_index(scene_id: String) -> int:
	for i in scenes.size():
		if scenes[i].get("id") == scene_id:
			return i
	return -1


func speaker_name(who: String) -> String:
	return str(speakers.get(who, who))


## Все локации, которые нужны сценарию (сцены и шаги «location»).
func locations() -> Array[String]:
	var out: Array[String] = []
	for sc in scenes:
		_add_unique(out, str(sc.get("location", "")))
		for st in sc.get("steps", []):
			if st.get("type") == "location":
				_add_unique(out, str(st.get("id", "")))
	return out


## Имена точек, которые сцены ищут в каждой локации: {локация: [имя узла, ...]}.
func required_markers() -> Dictionary:
	var out := {}
	for sc in scenes:
		var loc := str(sc.get("location", ""))
		_need(out, loc, str(sc.get("spawn", "spawn")))
		for p in sc.get("npcs", {}).values():
			_need(out, loc, str(p))
		for st in sc.get("steps", []):
			match st.get("type"):
				"location":
					loc = str(st.get("id", ""))
					_need(out, loc, str(st.get("spawn", "spawn")))
					for p in st.get("npcs", {}).values():
						_need(out, loc, str(p))
				"explore":
					for k in st.get("interactions", {}):
						_need(out, loc, "int_" + str(k))
				"reach":
					_need(out, loc, "reach_" + str(st.get("target", "")))
	return out


## Все модели персонажей, которые появляются в сценарии (игрок и NPC).
func character_models() -> Array[String]:
	var out: Array[String] = []
	for sc in scenes:
		_add_unique(out, str(sc.get("player", "")))
		for m in sc.get("npcs", {}):
			_add_unique(out, str(m))
		for st in sc.get("steps", []):
			if st.get("type") == "location":
				_add_unique(out, str(st.get("player", "")))
				for m in st.get("npcs", {}):
					_add_unique(out, str(m))
	return out


## Проверка структуры: типы шагов, обязательные поля, говорящие, цели осмотра.
static func validate(d: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	var spk: Dictionary = d.get("speakers", {})
	var sc_list = d.get("scenes")
	if typeof(sc_list) != TYPE_ARRAY or sc_list.is_empty():
		errs.append("нет сцен")
		return errs
	var ids := {}
	for sc in sc_list:
		var sid := str(sc.get("id", ""))
		if sid == "" or ids.has(sid):
			errs.append("сцена без id или с повтором: '%s'" % sid)
		ids[sid] = true
		if str(sc.get("location", "")) == "":
			errs.append("%s: нет локации" % sid)
		if str(sc.get("player", "")) == "":
			errs.append("%s: нет модели игрока" % sid)
		if sc.has("time") and not sc.time in TIMES:
			errs.append("%s: неизвестное время суток %s" % [sid, sc.time])
		var steps = sc.get("steps")
		if typeof(steps) != TYPE_ARRAY or steps.is_empty():
			errs.append("%s: нет шагов" % sid)
			continue
		for i in steps.size():
			_check_step(steps[i], "%s#%d" % [sid, i], spk, errs)
	return errs


static func _check_step(st: Dictionary, where: String, spk: Dictionary, errs: Array[String]) -> void:
	var t := str(st.get("type", ""))
	if not STEP_FIELDS.has(t):
		errs.append("%s: неизвестный тип шага '%s'" % [where, t])
		return
	for f in STEP_FIELDS[t]:
		if not st.has(f):
			errs.append("%s (%s): нет поля %s" % [where, t, f])
	match t:
		"fade":
			if not st.get("to") in ["black", "clear"]:
				errs.append("%s: fade.to должно быть black или clear" % where)
		"time":
			if not st.get("to") in TIMES:
				errs.append("%s: неизвестное время суток %s" % [where, st.get("to")])
		"location":
			if st.has("time") and not st.time in TIMES:
				errs.append("%s: неизвестное время суток %s" % [where, st.time])
		"say":
			_check_lines(st.get("lines", []), where, spk, errs)
		"reach":
			if st.has("fragments"):
				_check_lines(st.fragments, where, spk, errs)
		"explore":
			var inter: Dictionary = st.get("interactions", {})
			for k in inter:
				_check_lines(inter[k], "%s/%s" % [where, k], spk, errs)
			var req: Array = st.get("required", [])
			for r in req:
				if not inter.has(r):
					errs.append("%s: обязательная цель '%s' без реплик" % [where, r])
			var optional := inter.size() - req.size()
			if int(st.get("optional_min", 0)) > optional:
				errs.append("%s: optional_min больше числа необязательных целей" % where)
			if inter.is_empty():
				errs.append("%s: осмотр без целей" % where)
		"sketchbook":
			for p in st.get("pages", []):
				if str(p.get("image", "")) == "":
					errs.append("%s: страница скетчбука без картинки" % where)
		"montage":
			for fr in st.get("frames", []):
				if not fr.get("time") in TIMES:
					errs.append("%s: кадр монтажа с неизвестным временем" % where)


static func _check_lines(lines, where: String, spk: Dictionary, errs: Array[String]) -> void:
	if typeof(lines) != TYPE_ARRAY or lines.is_empty():
		errs.append("%s: нет реплик" % where)
		return
	for l in lines:
		if not spk.has(str(l.get("who", ""))):
			errs.append("%s: неизвестный говорящий '%s'" % [where, l.get("who")])
		if not l.has("text"):
			errs.append("%s: реплика без текста" % where)


static func _add_unique(arr: Array[String], v: String) -> void:
	if v != "" and not v in arr:
		arr.append(v)


static func _need(out: Dictionary, loc: String, marker: String) -> void:
	if loc == "":
		return
	if not out.has(loc):
		out[loc] = []
	if not marker in out[loc]:
		out[loc].append(marker)
