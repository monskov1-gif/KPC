class_name SynergyEvaluator
extends RefCounted
## Бонусы за сочетания. Число срабатываний ограничено max_triggers (по умолчанию 1).


## Возвращает {triggers, count, needed}. count/needed используются для подсказок «почти собрано».
static func evaluate(rule: Dictionary, items: Array[ClothingItem]) -> Dictionary:
	var p: Dictionary = rule.get("params", {})
	var max_triggers := int(rule.get("max_triggers", 1))
	var count := 0
	var needed := 1
	match str(rule.get("type", "")):
		"set_pieces":
			needed = int(p.get("min_count", 2))
			for it in items:
				if it.set_id == str(p.get("set_id")):
					count += 1
		"color_count":
			needed = int(p.get("min_count", 2))
			for it in items:
				if it.color_tags.has(str(p.get("color"))):
					count += 1
		"material_count":
			needed = int(p.get("min_count", 2))
			for it in items:
				if it.material_tags.has(str(p.get("material"))):
					count += 1
		"tags_all":
			var tags: Array = p.get("tags", [])
			needed = tags.size()
			for t in tags:
				for it in items:
					if it.has_tag(str(t)):
						count += 1
						break
			# Для tags_all одно срабатывание — когда все теги присутствуют.
			return {"triggers": 1 if count >= needed and needed > 0 else 0, "count": count, "needed": needed}
	var triggers := 0
	if needed > 0:
		triggers = mini(floori(float(count) / needed), max_triggers)
	return {"triggers": triggers, "count": count, "needed": needed}
