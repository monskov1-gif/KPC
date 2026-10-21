class_name RequirementEvaluator
extends RefCounted
## Проверка условий испытания по списку надетых предметов. Чистая функция.


static func is_met(req: Dictionary, items: Array[ClothingItem]) -> bool:
	var p: Dictionary = req.get("params", {})
	match str(req.get("type", "")):
		"required_slot":
			for it in items:
				if it.all_slots().has(str(p.get("slot"))):
					return true
			return false
		"required_category":
			for it in items:
				if it.category == str(p.get("category")):
					return true
			return false
		"tag_any":
			return _count(items, func(it: ClothingItem): return it.has_tag(str(p.get("tag")))) >= int(p.get("min_count", 1))
		"forbidden_tag":
			return _count(items, func(it: ClothingItem): return it.has_tag(str(p.get("tag")))) == 0
		"attribute_min":
			for it in items:
				if it.attr(str(p.get("attribute"))) >= float(p.get("min", 0)):
					return true
			return false
		"item_count_max":
			return items.size() <= int(p.get("max", 0))
		"item_count_min":
			return items.size() >= int(p.get("min", 0))
		"color_any":
			return _count(items, func(it: ClothingItem): return it.color_tags.has(str(p.get("color")))) > 0
		"material_any":
			return _count(items, func(it: ClothingItem): return it.material_tags.has(str(p.get("material")))) > 0
	push_warning("Неизвестный тип требования: %s" % req.get("type"))
	return false


static func _count(items: Array[ClothingItem], pred: Callable) -> int:
	var n := 0
	for it in items:
		if pred.call(it):
			n += 1
	return n
