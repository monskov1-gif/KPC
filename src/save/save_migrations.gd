class_name SaveMigrations
extends RefCounted
## Явные миграции схемы сохранения. Каждая функция переводит данные с версии N на N+1.


static func migrate(data: Dictionary, from_version: int, to_version: int) -> Dictionary:
	var d := data.duplicate(true)
	var v := from_version
	while v < to_version:
		match v:
			0:
				d = _v0_to_v1(d)
		v += 1
	return d


## v0 — ранний прототип без версий: владение хранилось простым списком ID.
static func _v0_to_v1(d: Dictionary) -> Dictionary:
	if d.has("owned_items") and not d.has("wardrobe"):
		var owned := {}
		var i := 0
		for id in d.owned_items:
			i += 1
			owned[str(id)] = {"order": i, "source": "migrated", "is_new": false, "favorite": false}
		d["wardrobe"] = {"owned": owned, "counter": i}
		d.erase("owned_items")
	for key in ["resources", "equipment", "presets", "recipes", "shops", "challenge_results", "flags"]:
		if not d.has(key):
			d[key] = {}
	if not d.has("unlocked_characters"):
		d["unlocked_characters"] = []
	return d
