class_name CraftingService
extends RefCounted
## Выкройки и крафт. Списание ресурсов и выдача предмета — одна логическая операция.

signal recipes_changed

var grants: ItemGrantService
var resources: ResourceInventory
var errors: Array[String] = []
var _recipes: Dictionary = {}
var _order: Array[String] = []
var _unlocked: Dictionary = {}   # recipe_id -> true


func _init(p_grants: ItemGrantService, p_resources: ResourceInventory) -> void:
	grants = p_grants
	resources = p_resources


func load_recipes(entries: Array) -> void:
	for r in entries:
		var id := str(r.get("id", ""))
		if id == "" or _recipes.has(id):
			errors.append("Выкройка с пустым или повторяющимся id: '%s'" % id)
			continue
		if not grants.catalog.has_item(str(r.get("output_item_id", ""))):
			errors.append("[%s] неизвестный результат '%s'" % [id, r.get("output_item_id")])
			continue
		for res_id in r.get("costs", {}).keys():
			if not resources.is_known(res_id):
				errors.append("[%s] неизвестный ресурс '%s'" % [id, res_id])
		_recipes[id] = r
		_order.append(id)
		if r.get("unlocked_by_default", false):
			_unlocked[id] = true


func recipe_ids() -> Array[String]:
	return _order.duplicate()


func get_recipe(id: String) -> Dictionary:
	return _recipes.get(id, {})


func is_unlocked(id: String) -> bool:
	return _unlocked.has(id)


func unlock(id: String) -> bool:
	if not _recipes.has(id) or _unlocked.has(id):
		return false
	_unlocked[id] = true
	recipes_changed.emit()
	return true


## Проверка без изменения состояния. Возвращает "" или код ошибки.
func check(recipe_id: String) -> String:
	var r := get_recipe(recipe_id)
	if r.is_empty():
		return "craft.unknown_recipe"
	if not is_unlocked(recipe_id):
		return "craft.locked"
	if grants.inventory.owns(str(r.output_item_id)):
		# Уникальная одежда: крафт уже имеющейся вещи заблокирован, чтобы не тратить материалы впустую.
		return "craft.already_owned"
	if not resources.can_afford(r.get("costs", {})):
		return "craft.not_enough_resources"
	return ""


## Шаги 5–8 процесса из ТЗ. Повторная проверка выполняется здесь же перед списанием.
func craft(recipe_id: String) -> Dictionary:
	var err := check(recipe_id)
	if err != "":
		return {"ok": false, "error_key": err}
	var r := get_recipe(recipe_id)
	var plan := grants.plan_item(str(r.output_item_id))
	if plan.status == "error":
		return {"ok": false, "error_key": plan.error_key}
	var spend_err := resources.spend(r.get("costs", {}))
	if spend_err != "":
		return {"ok": false, "error_key": spend_err}
	var grant := grants.grant_item(str(r.output_item_id), "craft")
	return {"ok": true, "error_key": "", "item_id": r.output_item_id, "grant": grant}


func to_dict() -> Dictionary:
	return {"unlocked": _unlocked.keys()}


func load_dict(d: Dictionary) -> void:
	for id in d.get("unlocked", []):
		if _recipes.has(id):
			_unlocked[id] = true
	recipes_changed.emit()
