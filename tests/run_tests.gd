extends SceneTree
## Запуск: godot --headless --path . -s tests/run_tests.gd
## Код выхода 0 — все тесты прошли, 1 — есть падения.


func _initialize() -> void:
	var total := 0
	var failed: Array[String] = []
	var dir := DirAccess.open("res://tests")
	var files := dir.get_files()
	files.sort()
	for f in files:
		if not (f.begins_with("test_") and f.ends_with(".gd")) or f == "test_case.gd":
			continue
		var script: GDScript = load("res://tests/" + f)
		for m in script.get_script_method_list():
			var name: String = m.name
			if not name.begins_with("test_"):
				continue
			var inst: TestCase = script.new()
			inst._current = "%s::%s" % [f.get_basename(), name]
			inst.before_each()
			inst.call(name)
			total += 1
			if inst.failures.is_empty():
				print("  ok   ", inst._current)
			else:
				print("  FAIL ", inst._current)
				for msg in inst.failures:
					print("       ", msg)
				failed.append(inst._current)
	print("\n%d тестов, %d упало" % [total, failed.size()])
	quit(0 if failed.is_empty() and total > 0 else 1)
