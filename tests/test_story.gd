extends TestCase
## Сюжетные данные: сценарий пролога проходит проверку, локации и модели на месте, логика осмотра.

const PROLOGUE := "res://data/story/prologue.json"


func test_prologue_valid() -> void:
	var s := StoryScript.load_file(PROLOGUE)
	eq(s.errors.size(), 0, "ошибки сценария: %s" % [s.errors])
	eq(s.scenes.size(), 9, "в прологе 9 сцен по сценарию")
	eq(s.scenes[0].get("id"), "p1_city", "первая сцена")
	eq(s.scenes[8].get("id"), "p9_inheritance", "последняя сцена")


func test_validator_catches_errors() -> void:
	var bad := {"speakers": {"kot": "Кот"}, "scenes": [
		{"id": "a", "location": "x", "player": "kot", "steps": [
			{"type": "say", "lines": [{"who": "nobody", "text": "?"}]},
			{"type": "warp"},
			{"type": "fade", "to": "grey", "seconds": 1},
			{"type": "explore", "required": ["z"], "optional_min": 3, "interactions": {"y": [{"who": "kot", "text": "."}]}},
		]},
		{"id": "a", "location": "", "player": "kot", "steps": []},
	]}
	var errs := StoryScript.validate(bad)
	var text := "\n".join(errs)
	check("nobody" in text, "неизвестный говорящий")
	check("warp" in text, "неизвестный тип шага")
	check("fade.to" in text, "неверный fade")
	check("'z'" in text, "обязательная цель без реплик")
	check("optional_min" in text, "optional_min больше целей")
	check("повтором" in text, "повтор id сцены")
	check("нет локации" in text, "сцена без локации")


func test_locations_have_markers() -> void:
	var s := StoryScript.load_file(PROLOGUE)
	var need := s.required_markers()
	for loc in s.locations():
		var path := StoryLocation.DIR + loc + ".glb"
		if not ResourceLoader.exists(path):
			check(false, "нет локации %s" % path)
			continue
		var inst: Node = (load(path) as PackedScene).instantiate()
		for m in need.get(loc, []):
			check(inst.find_child(m, true, false) != null, "%s: нет точки %s" % [loc, m])
		inst.free()


func test_character_models_exist() -> void:
	var s := StoryScript.load_file(PROLOGUE)
	for m in s.character_models():
		check(ResourceLoader.exists(CharacterModel.MODEL_DIR + m + ".glb"), "нет модели персонажа %s" % m)


func test_sketch_pages_exist() -> void:
	var s := StoryScript.load_file(PROLOGUE)
	for sc in s.scenes:
		for st in sc.steps:
			if st.type == "sketchbook":
				for p in st.pages:
					check(ResourceLoader.exists(StoryOverlay.SKETCH_DIR + str(p.image) + ".png"), "нет рисунка %s" % p.image)


func test_explore_state() -> void:
	var e := ExploreState.from_step({"required": ["girl"], "optional_min": 2,
		"interactions": {"girl": [], "a": [], "b": [], "c": []}})
	check(not e.complete(), "в начале не завершён")
	eq(e.remaining(), 3, "осталось: девочка + 2 необязательных")
	e.mark("girl")
	e.mark("a")
	e.mark("a")
	check(not e.complete(), "повторный осмотр не считается")
	e.mark("zzz")
	eq(e.optional_done(), 1, "чужая цель не считается")
	e.mark("c")
	check(e.complete(), "обязательная + 2 необязательных — готово")
	eq(e.remaining(), 0, "ничего не осталось")


func test_validator_types_and_empty() -> void:
	var bad := {"speakers": {"kot": "Кот"}, "scenes": [
		"не сцена",
		{"id": "b", "location": "x", "player": "kot", "time": "noon", "npcs": {"a": "p1", "b": "p1"}, "steps": [
			7,
			{"type": "sketchbook", "pages": []},
			{"type": "montage", "frames": [], "seconds_each": 1},
			{"type": "say", "lines": ["строка"]},
		]},
	]}
	var text := "\n".join(StoryScript.validate(bad))
	check("не объект" in text, "сцена/шаг/реплика не того типа")
	check("без страниц" in text, "пустой скетчбук")
	check("без кадров" in text, "пустой монтаж")
	check("два NPC" in text, "два NPC на одной точке")
	check("noon" in text, "неизвестное время суток")


func test_time_presets_match_script() -> void:
	for t in StoryScript.TIMES:
		check(StoryLocation.TIME_PRESETS.has(t), "нет пресета света для %s" % t)
	eq(StoryLocation.TIME_PRESETS.size(), StoryScript.TIMES.size(), "списки времени суток совпадают")


## Образы NPC (looks.json) ссылаются только на шаблоны одежды, которые есть в их моделях.
func test_looks_match_garments() -> void:
	var looks := DataLoader.load_json("res://data/story/looks.json")
	for id in looks:
		if str(id).begins_with("_"):
			continue
		var path := CharacterModel.MODEL_DIR + str(id) + ".glb"
		if not ResourceLoader.exists(path):
			check(false, "нет модели %s" % id)
			continue
		var inst: Node = (load(path) as PackedScene).instantiate()
		for key in looks[id]:
			check(inst.find_child("garment__" + str(key), true, false) != null, "%s: нет шаблона %s" % [id, key])
		inst.free()


## Стоящие NPC — на вертикальных точках, лежащие (кровать) — на повёрнутых.
func test_npc_markers_upright() -> void:
	var s := StoryScript.load_file(PROLOGUE)
	for sc in s.scenes:
		var path := StoryLocation.DIR + str(sc.location) + ".glb"
		var inst: Node = (load(path) as PackedScene).instantiate()
		for m in sc.get("npcs", {}).values():
			var n := inst.find_child(str(m), true, false) as Node3D
			if n == null:
				continue
			var up := n.transform.basis.y.normalized().dot(Vector3.UP) > 0.9
			check(up == not str(m).ends_with("_bed"), "%s: точка %s ориентирована неверно" % [sc.id, m])
		inst.free()
