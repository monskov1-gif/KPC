class_name TestCase
extends RefCounted
## Минимальная база для автотестов. Методы test_* запускает tests/run_tests.gd.

var failures: Array[String] = []
var _current := ""


func before_each() -> void:
	pass


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append("%s: %s" % [_current, msg])


func eq(actual, expected, msg: String = "") -> void:
	if typeof(actual) != typeof(expected) and not (_is_num(actual) and _is_num(expected)):
		failures.append("%s: %s ожидалось %s, получено %s" % [_current, msg, var_to_str(expected), var_to_str(actual)])
	elif actual != expected:
		failures.append("%s: %s ожидалось %s, получено %s" % [_current, msg, var_to_str(expected), var_to_str(actual)])


func near(actual: float, expected: float, msg: String = "", eps: float = 0.001) -> void:
	if absf(actual - expected) > eps:
		failures.append("%s: %s ожидалось ≈%s, получено %s" % [_current, msg, expected, actual])


func _is_num(v) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


## Свежая сессия на реальных данных проекта с новой игрой.
func fresh_session() -> GameSession:
	var s := GameSession.create()
	s.new_game()
	return s
