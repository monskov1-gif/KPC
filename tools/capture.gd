extends SceneTree
## Снимок сцены для отслеживания прогресса.
## godot --path . --rendering-driver opengl3 --resolution WxH -s tools/capture.gd -- <scene.tscn> <out.png> [frames] [method]
## method — необязательный метод корневого узла сцены, вызываемый перед съёмкой (например, открыть нужную панель).

var _out := ""
var _frames := 30
var _method := ""
var _scene: Node


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
	for i in _frames:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
	var err := img.save_png(_out)
	print("Снимок: ", _out, " (", img.get_width(), "x", img.get_height(), ") err=", err)
	quit(0 if err == OK else 1)
