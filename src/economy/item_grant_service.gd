class_name ItemGrantService
extends RefCounted
## Единая точка выдачи одежды и ресурсов для всех источников (магазин, крафт, награды, задания).
## Повторная выдача предмета обрабатывается одним правилом из config.duplicate_policy.

signal item_granted(item_id: String, source: String)

var catalog: ItemCatalog
var inventory: WardrobeInventory
var resources: ResourceInventory
var config: WardrobeConfig


func _init(p_catalog: ItemCatalog, p_inventory: WardrobeInventory, p_resources: ResourceInventory, p_config: WardrobeConfig) -> void:
	catalog = p_catalog
	inventory = p_inventory
	resources = p_resources
	config = p_config


## Что произойдёт при выдаче (без изменения состояния). Используется для атомарных операций.
func plan_item(item_id: String) -> Dictionary:
	var item := catalog.get_item(item_id)
	if item == null:
		return {"status": "error", "error_key": "grant.unknown_item", "item_id": item_id}
	if not inventory.owns(item_id):
		return {"status": "added", "item_id": item_id}
	var policy := config.duplicate_policy
	var res_id := str(policy.get("resource_id", ""))
	var amount := int((policy.get("amount_by_rarity", {}) as Dictionary).get(item.rarity, 0))
	if policy.get("mode", "") == "convert_to_resource" and resources.can_receive(res_id, amount) and amount > 0:
		return {"status": "duplicate_converted", "item_id": item_id, "resource_id": res_id, "amount": amount}
	return {"status": "duplicate_ignored", "item_id": item_id}


func grant_item(item_id: String, source: String) -> Dictionary:
	var plan := plan_item(item_id)
	match plan.status:
		"added":
			inventory.add(item_id, source)
			item_granted.emit(item_id, source)
		"duplicate_converted":
			resources.apply_deltas({plan.resource_id: plan.amount})
	return plan
