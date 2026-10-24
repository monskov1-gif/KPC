class_name PhotoAlbum
extends RefCounted
## Альбом снимков (кнопка «Снимок» в игре): PNG в user://photos, список путей — в профиле игрока (сохраняется).
## Не больше MAX снимков: самый старый удаляется. Снимки экрана и тесты пишут в отдельную папку.

const MAX := 60


static func dir() -> String:
	return "user://test_photos/" if OS.has_environment("KPC_SAVE_PATH") else "user://photos/"


## Сохранить снимок и записать в профиль. Возвращает путь или "" при ошибке.
static func add(img: Image, profile: PlayerProfile) -> String:
	if img == null or img.is_empty():
		return ""
	DirAccess.make_dir_recursive_absolute(dir())
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	var path := dir() + "kpc_%s.png" % stamp
	var k := 1
	while FileAccess.file_exists(path):
		k += 1
		path = dir() + "kpc_%s_%d.png" % [stamp, k]
	if img.save_png(path) != OK:
		return ""
	profile.photos.append(path)
	while profile.photos.size() > MAX:
		DirAccess.remove_absolute(profile.photos.pop_front())
	return path


## Миниатюра снимка (ширина w); null — файла нет (удалён вне игры).
static func thumbnail(path: String, w := 240) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	img.resize(w, maxi(1, int(w * float(img.get_height()) / img.get_width())), Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(img)
