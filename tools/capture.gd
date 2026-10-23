extends SceneTree
## Снимок сцены для отслеживания прогресса.
## godot --path . --rendering-driver opengl3 --resolution WxH -s tools/capture.gd -- <scene.tscn> <out.png> [frames] [method]
## method — необязательный метод корневого узла сцены, вызываемый перед съёмкой (например, открыть нужную панель).

var _out := ""
var _frames := 30
var _method := ""
var _scene: Node
var _reached := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("Использование: -- <scene.tscn> <out.png> [frames] [method]")
		quit(2)
		return
	_out = args[1]
	if args.size() > 2:
		_frames = int(args[2])
	if args.size() > 3:
		_method = args[3]
	var packed: PackedScene = load(args[0])
	if packed == null:
		printerr("Не удалось загрузить сцену ", args[0])
		quit(2)
		return
	_scene = packed.instantiate()
	root.add_child(_scene)
	_run.call_deferred()


func _run() -> void:
	for i in 3:
		await process_frame
	if _method != "" and _scene.has_method(_method):
		_scene.call(_method)
	# KPC_STOP_AT / KPC_SHOT_AT: снимать, когда режиссёр сюжета прошёл нужный шаг (frames — кадров после него).
	# STOP_AT ещё и останавливает сюжет на этом шаге, SHOT_AT — нет (снимок следующего шага, например гардероба).
	# Режиссёр создаётся сценой сам — ищем его каждый кадр и подписываемся сразу, как появится.
	var want := OS.get_environment("KPC_SHOT_AT") if OS.has_environment("KPC_SHOT_AT") else OS.get_environment("KPC_STOP_AT")
	if want != "":
		var director: Node = null
		for i in 20000:
			if director == null:
				director = _scene.find_child("Director", true, false)
				if director and director.has_signal("step_done"):
					director.step_done.connect(func(sc, k):
						if "%s:%d" % [sc, k] == want:
							_reached = true)
			if _reached:
				print("capture: шаг ", want, " пройден")
				break
			await process_frame
	for i in _frames:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
	var err := img.save_png(_out)
	print("Снимок: ", _out, " (", img.get_width(), "x", img.get_height(), ") err=", err)
	quit(0 if err == OK else 1)
