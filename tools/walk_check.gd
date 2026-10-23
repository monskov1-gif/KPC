extends SceneTree
## Проверка проходимости локаций пролога (ловит «невидимые стены» и непроходимые ступеньки).
## Для каждой локации: сетка с шагом CELL от точки появления заливается «волной» — клетка проходима, если под ней
## есть пол (луч вниз), а капсула героя на высоте ступеньки ни во что не упирается; соседние клетки связаны, если
## перепад высоты не больше ступеньки (STEP). Каждая цель сюжета (reach_*, int_*) должна оказаться в пределах
## радиуса досягаемости от залитой клетки. Код выхода 1 — есть недостижимые цели.
## Запуск: godot --headless --path . -s tools/walk_check.gd   (входит в tools/run_tests.sh)

const CELL := 0.4
const STEP := 0.25            # = StoryPlayer.STEP_UP
const REACH := 1.3            # цель засчитывается с этого расстояния (подойти и осмотреть)
const MAX_CELLS := 60000

var _loc: StoryLocation
var _jobs := []
var _i := -1
var _wait := 0
var _fail := 0
var _space: PhysicsDirectSpaceState3D
var _cap: CapsuleShape3D


func _initialize() -> void:
	_cap = CapsuleShape3D.new()
	_cap.radius = 0.22
	_cap.height = 0.9
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/story/prologue.json"))
	var by_loc := {}
	for sc in d.scenes:
		var locs := [[str(sc.location), str(sc.get("spawn", "spawn"))]]
		for st in sc.steps:
			if st.type == "location":
				locs.append([str(st.id), str(st.get("spawn", "spawn"))])
		var cur: Array = locs[0]
		for st in sc.steps:
			if st.type == "location":
				cur = [str(st.id), str(st.get("spawn", "spawn"))]
			var tg := []
			if st.type == "reach":
				tg.append("reach_" + str(st.target))
			elif st.type == "explore":
				for k in st.interactions:
					tg.append("int_" + str(k))
			if tg.is_empty():
				continue
			var key: String = cur[0] + "|" + cur[1]
			if not by_loc.has(key):
				by_loc[key] = {"loc": cur[0], "spawn": cur[1], "targets": []}
			for t in tg:
				if not t in by_loc[key].targets:
					by_loc[key].targets.append(t)
	_jobs = by_loc.values()
	_loc = StoryLocation.new()
	root.add_child(_loc)


func _process(_delta: float) -> bool:
	if _wait > 0:
		_wait -= 1
		return false
	if _i >= 0:
		_check(_jobs[_i])
	_i += 1
	if _i >= _jobs.size():
		print("Проходимость: %s" % ("все цели достижимы" if _fail == 0 else "НЕДОСТИЖИМЫХ ЦЕЛЕЙ: %d" % _fail))
		quit(1 if _fail > 0 else 0)
		return true
	_loc.load_location(_jobs[_i].loc)
	_wait = 3          # коллизии регистрируются в физике через кадр
	return false


func _floor(x: float, z: float, from_y: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, from_y + 1.4, z), Vector3(x, from_y - 3.0, z), 1)
	var r := _space.intersect_ray(q)
	if r.is_empty() or (r.normal as Vector3).y < 0.6:
		return NAN
	return (r.position as Vector3).y


func _free(x: float, y: float, z: float) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _cap
	q.collision_mask = 1
	# низ капсулы на высоте ступеньки: на что можно шагнуть — не мешает
	q.transform = Transform3D(Basis.IDENTITY, Vector3(x, y + STEP + 0.02 + _cap.height * 0.5, z))
	return _space.intersect_shape(q, 1).is_empty()


func _check(job: Dictionary) -> void:
	_space = root.get_world_3d().direct_space_state
	var sp := _loc.marker(job.spawn).origin
	var start := Vector2i(roundi(sp.x / CELL), roundi(sp.z / CELL))
	var h0 := _floor(sp.x, sp.z, sp.y)
	if is_nan(h0):
		print("  %s: под точкой появления нет пола" % job.loc)
		_fail += 1
		return
	var height := {start: h0}
	var queue := [start]
	var head := 0
	while head < queue.size() and queue.size() < MAX_CELLS:
		var c: Vector2i = queue[head]
		head += 1
		var hc: float = height[c]
		for dlt in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + dlt
			if height.has(n):
				continue
			var x := n.x * CELL
			var z := n.y * CELL
			var h := _floor(x, z, hc)
			if is_nan(h) or absf(h - hc) > STEP + 0.05 or not _free(x, h, z):
				continue
			height[n] = h
			queue.append(n)
	var bad := []
	for t in job.targets:
		if not _loc.has_marker(t):
			bad.append(t + " (нет точки)")
			continue
		var p := _loc.marker(t).origin
		var ok := false
		var r := int(ceil(REACH / CELL))
		var tc := Vector2i(roundi(p.x / CELL), roundi(p.z / CELL))
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var cc := tc + Vector2i(dx, dz)
				if height.has(cc) and Vector2(cc.x * CELL - p.x, cc.y * CELL - p.z).length() <= REACH:
					ok = true
		if not ok:
			bad.append(t)
	print("  %s (от %s): клеток %d, %s" % [job.loc, job.spawn, height.size(), "ок" if bad.is_empty() else "НЕ ДОЙТИ: " + ", ".join(bad)])
	_fail += bad.size()
