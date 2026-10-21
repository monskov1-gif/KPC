class_name Localization
extends RefCounted
## Загрузка строк из data/localization/<locale>.json в TranslationServer.
## Отсутствующий ключ показывается как есть — это видно при проверке и не роняет игру.


static func load_all(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("Нет папки локализации: %s" % dir_path)
		return
	for file in dir.get_files():
		if not file.ends_with(".json"):
			continue
		var locale := file.get_basename()
		var errs: Array = []
		var strings := DataLoader.load_json(dir_path.path_join(file), errs)
		for e in errs:
			push_error(e)
		var t := Translation.new()
		t.locale = locale
		for key in strings.keys():
			if not key.begins_with("_"):
				t.add_message(key, str(strings[key]))
		TranslationServer.add_translation(t)
	# Стартовый набор языков не согласован (docs/OPEN_QUESTIONS.md); пока доступен только русский.
	TranslationServer.set_locale("ru")


## tr() с подстановкой параметров {name}.
static func text(key: String, params: Dictionary = {}) -> String:
	var s := TranslationServer.translate(key)
	for k in params.keys():
		s = s.replace("{%s}" % k, str(params[k]))
	return s
