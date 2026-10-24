class_name GachaService
extends RefCounted
## Молитвы (гача): баннеры персонажей и образов из data/gacha/banners.json.
## Шансы по звёздам (5★/4★, остальное 3★) с мягким и жёстким гарантом 5★ и гарантом 4★ каждые pity_4 молитв.
## Выпадение: персонаж (открывается; повтор — звёздная пыль), вещь (через ItemGrantService — повтор по общему
## правилу), ресурс. Списание билетов и выдача — атомарно: при нехватке билетов не меняется ничего.
## Случайность — свой генератор с сохраняемым состоянием: результат не зависит от посторонних вызовов randf().

var errors: Array[String] = []
var currency := "wish_ticket"
var dust_resource := "star_dust"
var dust_for_duplicate_character := 60
var dust_per_ticket := 20

var _grants: ItemGrantService
var _resources: ResourceInventory
var _banners: Array[Dictionary] = []
var _state: Dictionary = {}             # banner_id -> {"pity5": int, "pity4": int, "pulls": int}
var _history: Array = []                # последние выпадения (для окна «История»), не больше HISTORY_MAX
var _rng := RandomNumberGenerator.new()

const HISTORY_MAX := 60


func _init(grants: ItemGrantService, resources: ResourceInventory) -> void:
	_grants = grants
	_resources = resources
	_rng.seed = 0x6b7063


func load_data(d: Dictionary, catalog: ItemCatalog, characters: CharacterCatalog) -> void:
	currency = str(d.get("currency", currency))
	dust_resource = str(d.get("dust_resource", dust_resource))
	dust_for_duplicate_character = int(d.get("dust_for_duplicate_character", dust_for_duplicate_character))
	dust_per_ticket = int(d.get("dust_per_ticket", dust_per_ticket))
	for r in [currency, dust_resource]:
		if not _resources.is_known(r):
			errors.append("молитвы: неизвестный ресурс '%s'" % r)
	for b in d.get("banners", []):
		if typeof(b) != TYPE_DICTIONARY or str(b.get("id", "")) == "":
			errors.append("молитвы: баннер без id")
			continue
		for tier in ["pool_5", "pool_4", "pool_3"]:
			var pool: Array = b.get(tier, [])
			if pool.is_empty():
				errors.append("баннер %s: пустой %s" % [b.id, tier])
			for e in pool:
				var t := str(e.get("type", ""))
				var id := str(e.get("id", ""))
				if t == "character" and not characters.has_character(id):
					errors.append("баннер %s: неизвестный персонаж '%s'" % [b.id, id])
				elif t == "item" and not catalog.has_item(id):
					errors.append("баннер %s: неизвестная вещь '%s'" % [b.id, id])
				elif t == "resource" and not _resources.is_known(id):
					errors.append("баннер %s: неизвестный ресурс '%s'" % [b.id, id])
				elif not t in ["character", "item", "resource"]:
					errors.append("баннер %s: неизвестный тип награды '%s'" % [b.id, t])
		var rates: Dictionary = b.get("rates", {})
		if float(rates.get("5", 0)) + float(rates.get("4", 0)) >= 1.0:
			errors.append("баннер %s: шансы 5★ и 4★ в сумме ≥ 1" % b.id)
		_banners.append(b)


func banners() -> Array[Dictionary]:
	return _banners


func banner(id: String) -> Dictionary:
	for b in _banners:
		if str(b.id) == id:
			return b
	return {}


func state(banner_id: String) -> Dictionary:
	if not _state.has(banner_id):
		_state[banner_id] = {"pity5": 0, "pity4": 0, "pulls": 0}
	return _state[banner_id]


func total_pulls() -> int:
	var n := 0
	for k in _state:
		n += int(_state[k].get("pulls", 0))
	return n


func history() -> Array:
	return _history


## Шанс 5★ на следующей молитве (с учётом мягкого гаранта) — для окна «Шансы».
func chance_5(b: Dictionary, pity5: int) -> float:
	var n := pity5 + 1
	if n >= int(b.get("hard_pity", 90)):
		return 1.0
	var base := float(b.get("rates", {}).get("5", 0.006))
	var soft := int(b.get("soft_pity", 74))
	if n >= soft:
		base += float(b.get("soft_step", 0.06)) * (n - soft + 1)
	return minf(base, 1.0)


## Молитвы: count штук на баннере banner_id. unlocked — список открытых персонажей (дополняется новыми).
## Возвращает {"ok", "error_key", "results": [{"tier", "type", "id", "amount", "new", "converted"}]}.
func pull(banner_id: String, count: int, unlocked: Array[String]) -> Dictionary:
	var b := banner(banner_id)
	if b.is_empty():
		return {"ok": false, "error_key": "gacha.unknown_banner", "results": []}
	var cost := int(b.get("cost", 1)) * count
	if _resources.amount(currency) < cost:
		return {"ok": false, "error_key": "gacha.not_enough_tickets", "results": []}
	_resources.apply_deltas({currency: -cost})
	var st := state(banner_id)
	var results: Array = []
	for i in count:
		var tier := _roll_tier(b, st)
		var pool: Array = b.get("pool_%d" % tier, [])
		var e: Dictionary = pool[_rng.randi_range(0, pool.size() - 1)]
		results.append(_grant(e, tier, unlocked))
		st.pulls = int(st.pulls) + 1
	for r in results:
		_history.push_front({"banner": banner_id, "tier": r.tier, "type": r.type, "id": r.id})
	while _history.size() > HISTORY_MAX:
		_history.pop_back()
	return {"ok": true, "error_key": "", "results": results}


## Обмен звёздной пыли на билет (повторы персонажей не пропадают).
func exchange_dust(tickets: int) -> String:
	var need := dust_per_ticket * tickets
	if _resources.amount(dust_resource) < need:
		return "gacha.not_enough_dust"
	return _resources.apply_deltas({dust_resource: -need, currency: tickets})


func _roll_tier(b: Dictionary, st: Dictionary) -> int:
	var p5 := chance_5(b, int(st.pity5))
	var x := _rng.randf()
	if x < p5:
		st.pity5 = 0
		st.pity4 = 0
		return 5
	st.pity5 = int(st.pity5) + 1
	var p4 := float(b.get("rates", {}).get("4", 0.051))
	if int(st.pity4) + 1 >= int(b.get("pity_4", 10)) or x < p5 + p4:
		st.pity4 = 0
		return 4
	st.pity4 = int(st.pity4) + 1
	return 3


func _grant(e: Dictionary, tier: int, unlocked: Array[String]) -> Dictionary:
	var t := str(e.get("type", ""))
	var id := str(e.get("id", ""))
	var out := {"tier": tier, "type": t, "id": id, "amount": int(e.get("amount", 1)), "new": false, "converted": {}}
	match t:
		"character":
			if unlocked.has(id):
				_resources.apply_deltas({dust_resource: dust_for_duplicate_character})
				out.converted = {dust_resource: dust_for_duplicate_character}
			else:
				unlocked.append(id)
				out.new = true
		"item":
			var res := _grants.grant_item(id, "gacha")
			out.new = res.get("status", "") == "added"
			if res.get("status", "") == "duplicate_converted":
				out.converted = {str(res.resource_id): int(res.amount)}
		"resource":
			_resources.apply_deltas({id: int(e.get("amount", 1))})
	return out


func reset() -> void:
	_state.clear()
	_history.clear()
	_rng.seed = 0x6b7063


func to_dict() -> Dictionary:
	return {"state": _state.duplicate(true), "history": _history.duplicate(true), "rng_state": str(_rng.state)}


func load_dict(d: Dictionary) -> void:
	reset()
	var st = d.get("state", {})
	if typeof(st) == TYPE_DICTIONARY:
		for k in st:
			if typeof(st[k]) == TYPE_DICTIONARY:
				_state[str(k)] = {"pity5": int(st[k].get("pity5", 0)), "pity4": int(st[k].get("pity4", 0)),
					"pulls": int(st[k].get("pulls", 0))}
	var h = d.get("history", [])
	if typeof(h) == TYPE_ARRAY:
		_history = h.slice(0, HISTORY_MAX)
	var rs := str(d.get("rng_state", ""))
	if rs.is_valid_int():
		_rng.state = rs.to_int()
