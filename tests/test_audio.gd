extends TestCase
## Звук: файлы из data/audio/audio.json на месте, у каждой локации пролога есть музыка и окружение,
## шаги сюжета ссылаются на существующие дорожки и эффекты.

const AUDIO := "res://data/audio/audio.json"
const PROLOGUE := "res://data/story/prologue.json"


func _data() -> Dictionary:
	return DataLoader.load_json(AUDIO)


func test_audio_files_exist() -> void:
	var d := _data()
	for group in ["music", "ambient"]:
		for id in d.get(group, {}):
			var f: String = d[group][id].file
			check(ResourceLoader.exists(f), "%s.%s: нет файла %s" % [group, id, f])
	for id in d.get("sfx", {}):
		for f in d.sfx[id].files:
			check(ResourceLoader.exists(f), "sfx.%s: нет файла %s" % [id, f])


func test_locations_have_music_and_ambient() -> void:
	var d := _data()
	var s := StoryScript.load_file(PROLOGUE)
	for sc in s.scenes:
		var locs := [str(sc.location)]
		for st in sc.steps:
			if st.type == "location":
				locs.append(str(st.id))
		for loc in locs:
			var e: Dictionary = d.locations.get(loc, {})
			check(not e.is_empty(), "нет звука для локации %s" % loc)
			for key in ["music", "ambient"]:
				for t in e.get(key, {}):
					var id: String = e[key][t]
					check(d[key].has(id), "%s.%s.%s: нет дорожки %s" % [loc, key, t, id])
			check(d.sfx.has("step_" + str(e.get("surface", ""))), "%s: нет шагов для поверхности" % loc)


func test_story_audio_refs() -> void:
	var d := _data()
	var s := StoryScript.load_file(PROLOGUE)
	for sc in s.scenes:
		if sc.has("music"):
			check(d.music.has(str(sc.music)), "%s: нет музыки %s" % [sc.id, sc.music])
		for st in sc.steps:
			if st.type == "music" and str(st.get("id", "")) != "":
				check(d.music.has(str(st.id)), "%s: нет музыки %s" % [sc.id, st.id])
			if st.type == "sfx":
				check(d.sfx.has(str(st.id)), "%s: нет эффекта %s" % [sc.id, st.id])


func test_audio_buses_created() -> void:
	for b in ["Music", "Ambient", "SFX", "Voice"]:
		check(AudioServer.get_bus_index(b) >= 0, "нет шины %s" % b)
