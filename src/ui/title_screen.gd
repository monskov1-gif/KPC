class_name TitleScreen
extends Control
## Титульный экран: мягкий фон, Кот в 3D, название и меню — пролог (начать / продолжить) и гардероб.

const STORY_SCENE := "res://scenes/game/story.tscn"
const WARDROBE := preload("res://scenes/ui/wardrobe.tscn")

var _menu: Control
var _wardrobe: Control
var _hero_model: CharacterModel


func _ready() -> void:
	theme = UiTheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if Game.session == null:
		await Game.session_ready
	Audio.set_location("", "day")
	Audio.override_music("title", 1.0)
	add_child(SoftBackground.new())
	(get_child(0) as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu = Control.new()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_menu)
	_menu.add_child(_hero())
	_menu.add_child(_panel())
	# пометка о черновых репликах — маленькая плашка в углу, не в меню
	var note := PanelContainer.new()
	note.add_theme_stylebox_override("panel", UiTheme.chip())
	note.add_child(UiTheme.tag("Пролог: реплики черновые", 13, UiTheme.TEXT_DIM))
	note.anchor_left = 1.0; note.anchor_right = 1.0; note.anchor_top = 1.0; note.anchor_bottom = 1.0
	note.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	note.grow_vertical = Control.GROW_DIRECTION_BEGIN
	note.offset_right = -18; note.offset_bottom = -14
	_menu.add_child(note)
	resized.connect(_layout)
	# раскладка после первого кадра: переносимые строки к этому времени знают свою высоту
	_layout.call_deferred()
	_focus_first.call_deferred()


## Кот в 3D (тот же образ, что в гардеробе).
func _hero() -> Control:
	var box := SubViewportContainer.new()
	box.name = "Hero"
	box.stretch = true
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	box.add_child(vp)
	var m := CharacterModel.new()
	_hero_model = m
	vp.add_child(m)
	var s := Game.session
	m.setup("kot", s.characters)
	if s.outfit_items("kot").is_empty():
		s.equipment.equip_signature("kot")
	m.apply_items(s.outfit_items("kot"))
	m.rotation.y = deg_to_rad(-18)
	var h := m.height()
	# подиум со свечением под ногами (как в гардеробе-референсе)
	var pod := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.55; cyl.bottom_radius = 0.6; cyl.height = 0.06
	pod.mesh = cyl
	pod.position.y = -0.03
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color("fbefe6")
	pm.emission_enabled = true
	pm.emission = Color("f6dcc0")
	pm.emission_energy_multiplier = 0.25
	pod.material_override = pm
	vp.add_child(pod)
	var cam := Camera3D.new()
	cam.fov = 30
	cam.position = Vector3(0, h * 0.5, h * 2.75)
	cam.rotation.x = deg_to_rad(-3)
	vp.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-35), deg_to_rad(-30), 0)
	sun.light_color = Color("fff1e6")
	vp.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("f4e4e4")
	env.environment.ambient_light_energy = 0.7
	vp.add_child(env)
	return box


func _panel() -> Control:
	var p := PanelContainer.new()
	p.name = "Panel"
	p.add_theme_stylebox_override("panel", UiTheme.panel_light())
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	# логотип: картуш-лента со звёздами
	var logo := HBoxContainer.new()
	logo.alignment = BoxContainer.ALIGNMENT_CENTER
	logo.add_child(UiTheme.icon("star", 26, UiTheme.STAR))
	logo.add_child(UiTheme.ribbon_title("KPC", 56))
	logo.add_child(UiTheme.icon("star", 26, UiTheme.STAR))
	v.add_child(logo)
	var sub := UiTheme.label("История Кота: затопленный город, дом-отель родителей и жилой комплекс на горе", 18, UiTheme.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	v.add_child(UiTheme.divider())
	var flags := Game.session.flags
	if StoryGame.saved_scene_id(StoryScript.load_file(StoryGame.SCRIPT_PATH)) != "":
		v.add_child(UiTheme.primary(UiTheme.button("Продолжить пролог", func(): _start(-1))))
		v.add_child(UiTheme.secondary(UiTheme.button("Пролог сначала", func(): _start(0))))
	else:
		v.add_child(UiTheme.primary(UiTheme.button("Пролог" if not flags.is_set(StoryGame.DONE_FLAG) else "Пролог ещё раз", func(): _start(0))))
	v.add_child(UiTheme.secondary(UiTheme.button("Гардероб", _open_wardrobe)))
	return p


func _layout() -> void:
	if _menu == null:
		return
	var hero := _menu.get_node("Hero") as Control
	var panel := _menu.get_node("Panel") as Control
	var portrait := size.y > size.x
	if portrait:
		hero.position = Vector2(0, 0)
		hero.size = Vector2(size.x, size.y * 0.5)
		panel.size = Vector2(minf(size.x - 32, 520), 0)
		panel.size.y = panel.get_combined_minimum_size().y
		panel.position = Vector2((size.x - panel.size.x) * 0.5, size.y * 0.5)
	else:
		hero.position = Vector2(size.x * 0.06, 0)
		hero.size = Vector2(size.x * 0.42, size.y)
		panel.size = Vector2(minf(size.x * 0.4, 560), 0)
		panel.size.y = panel.get_combined_minimum_size().y
		panel.position = Vector2(size.x * 0.52, (size.y - panel.size.y) * 0.5)


func _start(scene: int) -> void:
	StoryGame.start_scene = scene
	get_tree().change_scene_to_file(STORY_SCENE)


func _open_wardrobe() -> void:
	_menu.visible = false
	_wardrobe = WARDROBE.instantiate()
	add_child(_wardrobe)
	Audio.override_music("wardrobe", 1.0)
	_wardrobe.closed.connect(func():
		Audio.override_music("title", 1.0)
		_wardrobe.queue_free()
		_wardrobe = null
		_hero_model.apply_items(Game.session.outfit_items("kot"))   # образ из гардероба
		_menu.visible = true
		_focus_first())


## Для снимка гардероба через титульный экран.
func debug_wardrobe() -> void:
	_open_wardrobe()


## Фокус на первой кнопке — меню доступно с геймпада и клавиатуры.
func _focus_first() -> void:
	var btns := _menu.find_children("*", "Button", true, false)
	if not btns.is_empty():
		(btns[0] as Button).grab_focus()
