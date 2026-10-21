class_name DataLoader
extends RefCounted
## Чтение JSON-данных проекта. Ошибки не роняют игру: возвращается пустой словарь и сообщение в errors.


static func load_json(path: String, errors: Array = []) -> Dictionary:
	if not FileAccess.file_exists(path):
		errors.append("Файл данных не найден: %s" % path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		errors.append("Ошибка JSON в %s, строка %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	if typeof(json.data) != TYPE_DICTIONARY:
		errors.append("Корень %s должен быть объектом" % path)
		return {}
	return json.data


static func to_string_array(value) -> Array[String]:
	var out: Array[String] = []
	if value is Array:
		for v in value:
			out.append(str(v))
	return out
