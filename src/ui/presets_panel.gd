class_name PresetsPanel
extends ScrollContainer
## Сохранённые комплекты текущего персонажа. Применение загружает совместимую часть в черновик примерки.

var screen: WardrobeScreen
var _box: VBoxContainer
var _name_edit: LineEdit
var _list: VBoxContainer
var _msg: Label


func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_box)
	var row := HBoxContainer.new()
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Название комплекта"
	_name_edit.custom_minimum_size.y = UiTheme.TOUCH_MIN
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_name_edit)
	row.add_child(UiTheme.button(tr("ui.save_preset"), _save))
	_box.add_child(row)
	_msg = UiTheme.label("", UiTheme.FONT_SIZE_SMALL, UiTheme.WARN)
	_box.add_child(_msg)
	_list = VBoxContainer.new()
	_box.add_child(_list)
	refresh()


func refresh() -> void:
	if _list == null or screen == null or screen.character_id == "":
		return
	WardrobeScreen._clear(_list)
	var presets := screen.session.presets.presets_for(screen.character_id)
	if presets.is_empty():
		_list.add_child(UiTheme.label("Сохранённых комплектов пока нет.", UiTheme.FONT_SIZE_SMALL, UiTheme.TEXT_DIM))
	for p in presets:
		var row := HBoxContainer.new()
		var l := UiTheme.label("%s (%d)" % [p.name, (p.slots as Dictionary).size()])
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(UiTheme.button(tr("ui.apply"), _apply.bind(p.id)))
		row.add_child(UiTheme.button(tr("ui.delete"), _delete.bind(p.id)))
		_list.add_child(row)


func _save() -> void:
	var n := _name_edit.text.strip_edges()
	if n == "":
		n = "Комплект %d" % (screen.session.presets.presets_for(screen.character_id).size() + 1)
	screen.session.presets.create_from_outfit(screen.character_id, n, screen.draft)
	_name_edit.text = ""
	_msg.text = ""
	Game.save_game()
	refresh()


func _apply(preset_id: String) -> void:
	var built := screen.session.presets.build_outfit(preset_id)
	screen.set_draft(built.outfit)
	var problems: Array = built.problems
	_msg.text = "" if problems.is_empty() else "Не применено: " + ", ".join(
		problems.map(func(p): return "%s (%s)" % [screen.item_name(p.item_id), tr(p.error_key)]))


func _delete(preset_id: String) -> void:
	screen.session.presets.delete(preset_id)
	Game.save_game()
	refresh()
