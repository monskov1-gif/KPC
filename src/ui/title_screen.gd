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
	add_child(SoftBackground.new())
	(get_child(0) as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu = Control.new()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_menu)
	_menu.add_child(_hero())
	_menu.add_child(_panel())
	resized.connect(_layout)
	_layout()


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
	var cam := Camera3D.new()
	cam.fov = 30
	cam.position = Vector3(0, h * 0.55, h * 2.35)
	cam.rotation.x = deg_to_rad(-4)
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
	var t := UiTheme.title("KPC", 72)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(t)
	var sub := UiTheme.label("История Кота: город под водой, дом-отель родителей и жилой комплекс на горе", 18, UiTheme.TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	v.add_child(UiTheme.divider())
	var flags := Game.session.flags
	var progress := int(flags.get_flag(StoryGame.PROGRESS_FLAG, 0))
	if progress > 0:
		v.add_child(UiTheme.primary(UiTheme.button("Продолжить пролог", func(): _start(-1))))
		v.add_child(UiTheme.secondary(UiTheme.button("Пролог сначала", func(): _start(0))))
	else:
		v.add_child(UiTheme.primary(UiTheme.button("Пролог" if not flags.is_set(StoryGame.DONE_FLAG) else "Пролог ещё раз", func(): _start(0))))
	v.add_child(UiTheme.secondary(UiTheme.button("Гардероб", _open_wardrobe)))
	var note := UiTheme.label("Реплики пролога — черновые, ждут утверждения.", 14, UiTheme.TEXT_DIM)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(note)
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
		panel.position = Vector2((size.x - panel.size.x) * 0.5, size.y * 0.5)
	else:
		hero.position = Vector2(size.x * 0.06, 0)
		hero.size = Vector2(size.x * 0.42, size.y)
		panel.size = Vector2(minf(size.x * 0.4, 560), 0)
		panel.position = Vector2(size.x * 0.52, (size.y - panel.get_combined_minimum_size().y) * 0.5)


func _start(scene: int) -> void:
	StoryGame.start_scene = scene
	get_tree().change_scene_to_file(STORY_SCENE)


func _open_wardrobe() -> void:
	_menu.visible = false
	_wardrobe = WARDROBE.instantiate()
	add_child(_wardrobe)
	_wardrobe.closed.connect(func():
		_wardrobe.queue_free()
		_wardrobe = null
		_hero_model.apply_items(Game.session.outfit_items("kot"))   # образ из гардероба
		_menu.visible = true)


## Для снимка гардероба через титульный экран.
func debug_wardrobe() -> void:
	_open_wardrobe()
