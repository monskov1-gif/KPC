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
