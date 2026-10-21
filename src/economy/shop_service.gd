class_name ShopService
extends RefCounted
## Магазины: покупка одежды и материалов с атомарным списанием.

var grants: ItemGrantService
var resources: ResourceInventory
var errors: Array[String] = []
var _shops: Dictionary = {}
var _purchases: Dictionary = {}   # "shop_id/item_id" -> количество покупок


func _init(p_grants: ItemGrantService, p_resources: ResourceInventory) -> void:
	grants = p_grants
	resources = p_resources


func load_shops(entries: Array) -> void:
	for s in entries:
		var id := str(s.get("id", ""))
		if id == "" or _shops.has(id):
			errors.append("Магазин с пустым или повторяющимся id: '%s'" % id)
			continue
		var valid: Array = []
		for e in s.get("entries", []):
			var target := str(e.get("item_id", ""))
			var ok: bool = resources.is_known(target) if e.get("resource", false) else grants.catalog.has_item(target)
			if ok:
				valid.append(e)
			else:
				errors.append("[%s] неизвестный товар '%s'" % [id, target])
		s["entries"] = valid
		_shops[id] = s


func shop_ids() -> Array:
	return _shops.keys()


func entries(shop_id: String) -> Array:
	return _shops.get(shop_id, {}).get("entries", [])


func _find(shop_id: String, item_id: String) -> Dictionary:
	for e in entries(shop_id):
		if e.item_id == item_id:
			return e
	return {}


func check(shop_id: String, item_id: String) -> String:
	var e := _find(shop_id, item_id)
	if e.is_empty():
		return "shop.unavailable"
	var limit := int(e.get("purchase_limit", 0))
	if limit > 0 and int(_purchases.get("%s/%s" % [shop_id, item_id], 0)) >= limit:
		return "shop.limit_reached"
	if not e.get("resource", false) and grants.inventory.owns(item_id):
		return "shop.already_owned"
	if not resources.can_afford(e.get("price", {})):
		return "shop.not_enough_currency"
	if e.get("resource", false) and not resources.can_receive(item_id, 1):
		return "resource.cap_reached"
	return ""


func buy(shop_id: String, item_id: String) -> Dictionary:
	var err := check(shop_id, item_id)
	if err != "":
		return {"ok": false, "error_key": err}
	var e := _find(shop_id, item_id)
	if e.get("resource", false):
		var deltas := {item_id: 1}
		for k in e.price.keys():
			deltas[k] = int(deltas.get(k, 0)) - int(e.price[k])
		var res_err := resources.apply_deltas(deltas)
		if res_err != "":
			return {"ok": false, "error_key": res_err}
	else:
		var spend_err := resources.spend(e.get("price", {}))
		if spend_err != "":
			return {"ok": false, "error_key": spend_err}
		grants.grant_item(item_id, "shop")
	var key := "%s/%s" % [shop_id, item_id]
	_purchases[key] = int(_purchases.get(key, 0)) + 1
	return {"ok": true, "error_key": ""}


func to_dict() -> Dictionary:
	return {"purchases": _purchases.duplicate()}


func reset() -> void:
	_purchases.clear()


func load_dict(d: Dictionary) -> void:
	var p = d.get("purchases", {})
	_purchases = p.duplicate() if typeof(p) == TYPE_DICTIONARY else {}
