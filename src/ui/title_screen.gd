class_name TitleScreen
extends Control
## Титульный экран (просьба пользователя 24.10): дом-отель плывёт по океану, Кот в окне-куполе смотрит вдаль
## (TitleWorld). Снизу — просто «Начать», без крупных кнопок; по бокам — неброские «⋯»: слева язык и
## настройки, справа гардероб, пролог сначала и «об игре».

const STORY_SCENE := "res://scenes/game/story.tscn"
const WARDROBE := preload("res://scenes/ui/wardrobe.tscn")
const VIGNETTE := preload("res://art/shaders/vignette.gdshader")

var world: TitleWorld
var _view: SubViewportContainer
var _ui: Control
var _start: Button
var _popup: PanelContainer
var _sheet: Sheet
var _wardrobe: Control
var _t := 0.0


func _ready() -> void:
	theme = UiTheme.build()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if Game.session == null:
		await Game.session_ready
	Audio.set_location("", "day")
	Audio.override_music("title", 1.0)
	_view = SubViewportContainer.new()
	_view.stretch = true
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	_view.add_child(vp)
	world = TitleWorld.new()
	vp.add_child(world)
	var vig := ColorRect.new()
	vig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vm := ShaderMaterial.new()
	vm.shader = VIGNETTE
	vig.material = vm
	add_child(vig)
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui)
	_build_ui()
	_sheet = Sheet.new()
	add_child(_sheet)
	_sheet.closed.connect(func(): _start.grab_focus())
	resized.connect(_layout)
	_layout.call_deferred()
	_start.grab_focus.call_deferred()


func _build_ui() -> void:
	# название — маленькое, в углу, не спорит с картинкой
	var logo := VBoxContainer.new()
	logo.name = "Logo"
	logo.add_theme_constant_override("separation", 0)
	logo.add_child(_soft_label("KPC", 40, 0.95))
	logo.add_child(_soft_label("Kot's photo collection", 16, 0.8))
	logo.position = Vector2(28, 22)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(logo)
	# «Начать» — просто текст с мягким свечением
	_start = Button.new()
	_start.name = "Start"
	_start.text = "Начать"
	_start.flat = true
	_start.focus_mode = Control.FOCUS_ALL
	_start.add_theme_font_override("font", UiTheme.title_font())
	_start.add_theme_font_size_override("font_size", 38)
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		_start.add_theme_color_override(st, Color(1, 0.98, 0.95))
	_start.add_theme_color_override("font_outline_color", Color(0.45, 0.28, 0.36, 0.55))
	_start.add_theme_constant_override("outline_size", 6)
	_start.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_start.pressed.connect(_on_start)
	_ui.add_child(_start)
	_ui.add_child(_dots("DotsLeft", _left_menu))
	_ui.add_child(_dots("DotsRight", _right_menu))


func _soft_label(text: String, size: int, alpha: float) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UiTheme.title_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1, 0.98, 0.95, alpha))
	l.add_theme_color_override("font_outline_color", Color(0.45, 0.28, 0.36, 0.45))
	l.add_theme_constant_override("outline_size", 5)
	return l


## Неброская кнопка «⋯»: полупрозрачный кружок.
func _dots(node_name: String, cb: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.custom_minimum_size = Vector2(54, 54)
	var st := UiTheme.pill(Color(1, 1, 1, 0.22), 0)
	var st_h := UiTheme.pill(Color(1, 1, 1, 0.38), 0)
	b.add_theme_stylebox_override("normal", st)
	b.add_theme_stylebox_override("hover", st_h)
	b.add_theme_stylebox_override("pressed", st_h)
	b.add_theme_stylebox_override("focus", st_h)
	var iv := IconView.new()
	iv.icon = "dots"
	iv.color = Color(1, 1, 1, 0.92)
	iv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(iv)
	iv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	iv.offset_left = 14; iv.offset_right = -14; iv.offset_top = 14; iv.offset_bottom = -14
	b.pressed.connect(func():
		Audio.ui("tap")
		cb.call(b))
	return b


func _process(delta: float) -> void:
	_t += delta
	if _start:
		# «Начать» мягко дышит (с настройкой «меньше движения» — не мерцает)
		var k := 0.0 if bool(Settings.get_value("reduce_motion")) else 1.0
		_start.modulate.a = 1.0 - k * 0.22 * (0.5 - 0.5 * sin(_t * 1.8))


func _layout() -> void:
	if _start == null:
		return
	var portrait := size.y > size.x
	if world:
		world.set_portrait(portrait)
	_start.size = _start.get_combined_minimum_size()
	_start.position = Vector2((size.x - _start.size.x) * 0.5, size.y - _start.size.y - (64.0 if portrait else 44.0))
	var dl := _ui.get_node("DotsLeft") as Control
	var dr := _ui.get_node("DotsRight") as Control
	dl.size = dl.custom_minimum_size
	dr.size = dr.custom_minimum_size
	var y := _start.position.y + (_start.size.y - dl.size.y) * 0.5
	dl.position = Vector2(26, y)
	dr.position = Vector2(size.x - dr.size.x - 26, y)


func _on_start() -> void:
	Audio.ui("tap")
	var saved := StoryGame.saved_scene_id(StoryScript.load_file(StoryGame.SCRIPT_PATH)) != ""
	_go(-1 if saved else 0)


func _go(scene: int) -> void:
	StoryGame.start_scene = scene
	get_tree().change_scene_to_file(STORY_SCENE)


## Маленькое меню над «⋯»: пункты — простой текст.
func _menu(anchor: Control, items: Array) -> void:
	_close_popup()
	_popup = PanelContainer.new()
	_popup.add_theme_stylebox_override("panel", UiTheme.cloud(Color(1, 0.99, 0.98, 0.92), 18, 14))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	_popup.add_child(v)
	for it in items:
		var b := Button.new()
		b.flat = true
		b.text = it[0]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_color_override("font_color", UiTheme.TEXT)
		b.add_theme_color_override("font_hover_color", UiTheme.GOLD_DEEP)
		b.add_theme_color_override("font_focus_color", UiTheme.GOLD_DEEP)
		b.add_theme_font_size_override("font_size", 19)
		var cb: Callable = it[1]
		if not cb.is_valid():
			b.disabled = true                 # пункт «скоро» (язык без перевода)
			b.add_theme_color_override("font_disabled_color", UiTheme.TEXT_DIM)
		b.pressed.connect(func():
			Audio.ui("tap")
			_close_popup()
			cb.call())
		v.add_child(b)
	_ui.add_child(_popup)
	_popup.size = _popup.get_combined_minimum_size()
	var x := clampf(anchor.position.x + anchor.size.x * 0.5 - _popup.size.x * 0.5, 12.0, size.x - _popup.size.x - 12.0)
	_popup.position = Vector2(x, anchor.position.y - _popup.size.y - 10)
	for b in v.get_children():
		if not (b as Button).disabled:
			(b as Button).grab_focus()
			break


func _close_popup() -> void:
	if _popup:
		_popup.queue_free()
		_popup = null


func _unhandled_input(e: InputEvent) -> void:
	if _popup and ((e is InputEventMouseButton and e.pressed) or e.is_action_pressed("ui_cancel")):
		_close_popup()
		_start.grab_focus()


func _left_menu(anchor: Control) -> void:
	var items: Array = []
	var have := Settings.languages()
	for code in SettingsSheet.LANG_NAMES:
		var mark := "• " if Settings.get_value("language") == code else "   "
		if have.has(code):
			items.append([mark + SettingsSheet.LANG_NAMES[code], func(): Settings.set_value("language", code)])
		else:
			items.append([mark + SettingsSheet.LANG_NAMES[code] + " — скоро", Callable()])
	items.append(["Настройки", func(): SettingsSheet.open(_sheet)])
	_menu(anchor, items)


func _right_menu(anchor: Control) -> void:
	var items: Array = [["Гардероб", _open_wardrobe]]
	if StoryGame.saved_scene_id(StoryScript.load_file(StoryGame.SCRIPT_PATH)) != "":
		items.append(["Пролог сначала", func(): _go(0)])
	items.append(["Об игре", _about])
	_menu(anchor, items)


func _about() -> void:
	_sheet.clear()
	for line in ["KPC — история Кота: затопленный город, дом-отель родителей и жилой комплекс на горе.",
			"Пролог: реплики, которых нет в сценарии, — черновые (ждут утверждения).",
			"Сторонние ресурсы и их авторы — art/characters/src/CREDITS.md."]:
		var l := UiTheme.label(line, 18, UiTheme.TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_sheet.content.add_child(l)
	_sheet.open("Об игре", "sparkle")


func _open_wardrobe() -> void:
	_ui.visible = false
	world.process_mode = Node.PROCESS_MODE_DISABLED
	_wardrobe = WARDROBE.instantiate()
	add_child(_wardrobe)
	Audio.override_music("wardrobe", 1.0)
	_wardrobe.closed.connect(func():
		Audio.override_music("title", 1.0)
		_wardrobe.queue_free()
		_wardrobe = null
		world.process_mode = Node.PROCESS_MODE_INHERIT
		if world.kot:
			world.kot.apply_items(Game.session.outfit_items("kot"))   # образ из гардероба
		_ui.visible = true
		_start.grab_focus())


## Для снимка гардероба через титульный экран.
func debug_wardrobe() -> void:
	_open_wardrobe()


## Для снимка настроек.
func debug_settings() -> void:
	SettingsSheet.open(_sheet)
