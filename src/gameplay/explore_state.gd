class_name ExploreState
extends RefCounted
## Прогресс шага «осмотр»: сцена идёт дальше, когда пройдены все обязательные цели
## и не меньше optional_min необязательных. Повторный осмотр не считается дважды.

var required: Array = []
var optional_min := 0
var targets: Array = []
var _done := {}


static func from_step(st: Dictionary) -> ExploreState:
	var e := ExploreState.new()
	e.required = st.get("required", [])
	e.optional_min = int(st.get("optional_min", 0))
	e.targets = st.get("interactions", {}).keys()
	return e


func mark(target: String) -> void:
	if target in targets:
		_done[target] = true


func is_done(target: String) -> bool:
	return _done.has(target)


func optional_done() -> int:
	var n := 0
	for t in _done:
		if not t in required:
			n += 1
	return n


func complete() -> bool:
	for r in required:
		if not _done.has(r):
			return false
	return optional_done() >= optional_min


## Сколько ещё осталось (для подсказки в цели): обязательные + недостающие необязательные.
func remaining() -> int:
	var n := 0
	for r in required:
		if not _done.has(r):
			n += 1
	return n + maxi(0, optional_min - optional_done())
