class_name CharacterModel
extends Node3D
## 3D-прототип персонажа из art/characters/<id>.glb (строится tools/art/build_characters.py).
## Аниме-шейдер + контур, анимация покоя, одежда — меши-шаблоны «garment__<слот>__<шаблон>»:
## показываются по надетым вещам и окрашиваются в цвет вещи. Если модели нет — показывает манекен-заглушку.

const TOON := preload("res://art/shaders/toon.gdshader")
const EYE_SHADE := preload("res://art/shaders/eye_shade.gdshader")
const OUTLINE := preload("res://art/shaders/outline.gdshader")
const HAIR_LOCK := preload("res://art/shaders/toon_hair_lock.gdshader")
const FACE := preload("res://art/shaders/toon_face.gdshader")
const FACE_SDF := preload("res://art/characters/textures/face_sdf.png")
const HAIR := preload("res://art/shaders/toon_hair.gdshader")
const MODEL_DIR := "res://art/characters/"

var character_id := ""
var _root: Node3D
var _garments: Dictionary = {}     # "слот__шаблон" -> MeshInstance3D
var _underwear: Dictionary = {}    # "briefs"/"panties"/"bra" -> MeshInstance3D

## Какие слоты одежды закрывают какую часть белья. Бельё скрывается только под вещью,
## поэтому полностью раздеть персонажа нельзя (без вещей бельё всегда видно).
const UNDERWEAR_COVERED_BY := {
	"bra": ["upper_body", "outerwear", "full_body"],
	"briefs": ["lower_body", "full_body"],
	"panties": ["lower_body", "full_body"],
}
## Какие области тела закрывает шаблон одежды (ключ или его начало): закрытые области кожа не рисует —
## тело не просвечивает сквозь ткань (области — альфа цвета вершин, tools/art/build_characters.py REGIONS).
const REGION_BITS := {"torso": 19, "hips": 18, "upper_arm": 17, "forearm": 16, "hand": 15, "thigh": 14, "knee": 13,
	"shin": 12, "ankle": 11, "foot": 10, "shoulder": 9, "wrist": 8, "collar": 7}
## Запасная таблица (если у модели нет <id>.covers.json — сборка старее покрытия).
const COVERS := {
	"upper_body__tshirt": ["torso"],
	"upper_body__": ["torso", "shoulder", "upper_arm", "forearm"],
	"outerwear__": ["torso", "shoulder", "upper_arm", "forearm"],
	"lower_body__skirt": ["hips"],
	"lower_body__": ["hips", "thigh", "knee", "shin"],
	"full_body__dress": ["torso", "hips"],
	"footwear__": ["foot"],
	"socks__knee": ["foot", "ankle"],
	"gloves__": ["hand", "wrist"],
}
var _skin_mats: Array[ShaderMaterial] = []
var _covers: Dictionary = {}
var _materials: Dictionary = {}    # кэш материалов по ключу
var _fallback: PlaceholderAppearance
var _anim: AnimationPlayer
var _height_cache := 0.0
## Поворот головы поверх анимации: look.target = точка в мире или null (см. HeadLook).
var look: HeadLook
var _hair_lock_mats: Array[ShaderMaterial] = []
var _face_mats: Array[ShaderMaterial] = []
## Текущая поза отдыха ("sit", "sleep") или "" — обычное движение.
var _rest := ""
var _rest_tween: Tween


func setup(p_character_id: String, characters: CharacterCatalog) -> void:
	character_id = p_character_id
	if _root:
		_root.queue_free()
		_root = null
	_anim = null
	_height_cache = 0.0
	_rest = ""
	_garments.clear()
	_underwear.clear()
	_materials.clear()   # ключи материалов — по имени: у другого персонажа те же имена, но другие цвета
	var path := MODEL_DIR + character_id + ".glb"
	if not ResourceLoader.exists(path):
		push_warning("Нет 3D-модели %s — используется заглушка" % path)
		if _fallback == null:
			_fallback = PlaceholderAppearance.new()
			add_child(_fallback)
		_fallback.visible = true
		_fallback.setup(character_id, characters)
		return
	if _fallback:
		_fallback.visible = false
	_root = (load(path) as PackedScene).instantiate()
	var cov_path := MODEL_DIR + character_id + ".covers.json"
	_covers = DataLoader.load_json(cov_path) if FileAccess.file_exists(cov_path) else {}
	add_child(_root)
	_hair_lock_mats.clear()
	_face_mats.clear()
	_skin_mats.clear()
	_prepare(_root)
	# «нимб» на волосах — чуть ниже макушки (по росту модели)
	if not _hair_lock_mats.is_empty():
		var top := _root_top()
		for hm in _hair_lock_mats:
			hm.set_shader_parameter("ring_y", top - 0.045)
	_anim = _root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var found := _root.find_children("*", "Skeleton3D", true, false)
	var sk := found[0] as Skeleton3D if not found.is_empty() else null
	look = null
	if sk:
		look = HeadLook.new()
		sk.add_child(look)
	if _anim:
		for a in ["idle", "walk", "run", "sit", "sleep"]:
			if _anim.has_animation(a):
				_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
		play_motion("idle")


func _process(_delta: float) -> void:
	# лицо: направления головы для карты теней (модель смотрит по +Z, правая сторона героя — −X)
	if _face_mats.is_empty() or not is_inside_tree():
		return
	var b := global_transform.basis.orthonormalized()
	for fm in _face_mats:
		fm.set_shader_parameter("head_forward", b.z)
		fm.set_shader_parameter("head_right", -b.x)


## Анимация движения: «idle», «walk», «run». speed — скорость персонажа (м/с): клип ускоряется так, чтобы
## ступни не скользили (длина цикла шага ≈ 0.78 роста, бега ≈ 1.5 роста; клипы — 0.75 и 1.2 цикла в секунду).
## Если клипа нет — ближайший имеющийся (бег → шаг → покой).
func play_motion(motion: String, speed := 0.0) -> void:
	# в позе отдыха (сидит, спит) движение не перебивает позу — её снимает set_rest("")
	if _anim == null or _rest != "":
		return
	var clip := motion
	if clip == "run" and not _anim.has_animation("run"):
		clip = "walk"
	if not _anim.has_animation(clip):
		clip = "idle"
	if not _anim.has_animation(clip):
		return
	var rate := 1.0
	if clip != "idle" and speed > 0.0:
		var h := maxf(0.6, _height_cache if _height_cache > 0.0 else height())
		_height_cache = h
		var cycle := h * (1.5 if clip == "run" else 0.78)
		rate = clampf(speed / cycle / (1.2 if clip == "run" else 0.75), 0.4, 3.0)
	_anim.speed_scale = rate
	if _anim.current_animation != clip:
		_anim.play(clip, 0.25)


## Поза отдыха для постановки: "sit" — сидит на полу, "sleep" — спит на боку (модель укладывается на бок
## поворотом вокруг направления взгляда), "" — встать. seconds — плавный переход.
func set_rest(kind: String, seconds := 0.8) -> void:
	if _root == null:
		return
	if look and kind != "":
		look.target = null
	var h := maxf(0.6, _height_cache if _height_cache > 0.0 else height())
	_height_cache = h
	_rest = kind
	var rot := Vector3.ZERO
	var pos := Vector3.ZERO
	if kind == "sleep":
		rot = Vector3(0, 0, PI / 2)             # на правый бок, лицом по-прежнему вперёд
		pos = Vector3(0.0, h * 0.11, 0.0)
	if _anim:
		var clip := kind if kind != "" and _anim.has_animation(kind) else "idle"
		_anim.speed_scale = 1.0
		_anim.play(clip, seconds * 0.8)
	if _rest_tween and _rest_tween.is_valid():
		_rest_tween.kill()
	if seconds <= 0.0:
		_root.rotation = rot
		_root.position = pos
		return
	_rest_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_rest_tween.tween_property(_root, "rotation", rot, seconds)
	_rest_tween.tween_property(_root, "position", pos, seconds)


## Верх модели в её координатах (до масштаба узла) — для «нимба» на волосах.
func _root_top() -> float:
	var top := 0.0
	for mi in _root.find_children("*", "MeshInstance3D", true, false):
		if String(mi.name).begins_with("hair_cap"):
			top = maxf(top, ((mi as MeshInstance3D).transform * (mi as MeshInstance3D).get_aabb()).end.y)
	return top if top > 0.0 else 1.6


## Высота глаз (кэш роста): для взглядов, без пересчёта габаритов каждый кадр.
func eye_height() -> float:
	if _height_cache <= 0.0:
		_height_cache = maxf(0.6, height())
	return _height_cache * 0.92


## Высота модели в метрах (для кадрирования камеры).
func height() -> float:
	if _root == null:
		return _fallback.scale.y * 1.6 if _fallback else 1.6
	# в координатах самой модели: рост не зависит от того, где модель стоит в мире
	var aabb := AABB()
	var first := true
	var to_local := global_transform.affine_inverse() if is_inside_tree() else Transform3D.IDENTITY
	for mi in _root.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).get_aabb()
		b = (to_local * (mi as MeshInstance3D).global_transform) * b if mi.is_inside_tree() else b
		aabb = b if first else aabb.merge(b)
		first = false
	return aabb.end.y


func apply_items(items: Array[ClothingItem]) -> void:
	if _root == null:
		if _fallback:
			_fallback.apply_items(items)
		return
	for g in _garments.values():
		g.visible = false
	# Слоты считаем только по реально показанным мешам: вещь без шаблона не должна «снимать» бельё.
	var slots := {}
	var shown: Array[String] = []
	for it in items:
		var key := _template_for(it)
		if key == "" or not _garments.has(key):
			continue
		var mi: MeshInstance3D = _garments[key]
		mi.visible = true
		slots[it.slot] = true
		shown.append(key)
		_tint(mi, it.placeholder_color)
	_hide_covered(shown)
	for part in _underwear:
		var covered := false
		for slot in UNDERWEAR_COVERED_BY.get(part, []):
			covered = covered or slots.has(slot)
		(_underwear[part] as MeshInstance3D).visible = not covered


## Неизменный образ персонажа без гардероба (NPC сюжета): {"слот__шаблон": "#цвет"} из data/story/looks.json.
func apply_look(look: Dictionary) -> void:
	if _root == null:
		return
	for g in _garments.values():
		g.visible = false
	var slots := {}
	var shown: Array[String] = []
	for key in look:
		if not _garments.has(key):
			push_warning("%s: нет шаблона одежды %s" % [character_id, key])
			continue
		var mi: MeshInstance3D = _garments[key]
		mi.visible = true
		slots[str(key).get_slice("__", 0)] = true
		shown.append(str(key))
		_tint(mi, Color(str(look[key])))
	_hide_covered(shown)
	for part in _underwear:
		var covered := false
		for slot in UNDERWEAR_COVERED_BY.get(part, []):
			covered = covered or slots.has(slot)
		(_underwear[part] as MeshInstance3D).visible = not covered


## Маска скрытых областей кожи по показанной одежде (первое совпадение в COVERS — от частного к общему).
func _hide_covered(shown: Array[String]) -> void:
	var mask := 0
	for key in shown:
		# точные данные сборки: какие области закрывает именно эта вещь (art/characters/<id>.covers.json)
		if _covers.has(key):
			for r in _covers[key]:
				if REGION_BITS.has(r):
					mask |= 1 << int(REGION_BITS[r])
			continue
		for prefix in COVERS:
			if key.begins_with(prefix):
				for r in COVERS[prefix]:
					mask |= 1 << int(REGION_BITS[r])
				break
	for m in _skin_mats:
		m.set_shader_parameter("hide_regions", mask)
		if m.next_pass:
			(m.next_pass as ShaderMaterial).set_shader_parameter("hide_regions", mask)


func _template_for(it: ClothingItem) -> String:
	if it.model_template != "" and _garments.has(it.model_template):
		return it.model_template
	# Шаблон по умолчанию — первый подходящий по слоту.
	for k in _garments.keys():
		if str(k).begins_with(it.slot + "__"):
			return k
	return ""


func _prepare(node: Node) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var name := String(m.name)
		# underwear__* — базовый слой: всегда виден, раздеть полностью нельзя.
		if name.begins_with("garment__"):
			_garments[name.trim_prefix("garment__")] = m
			m.visible = false
		elif name.begins_with("underwear__"):
			_underwear[name.trim_prefix("underwear__")] = m
		for i in m.mesh.get_surface_count():
			m.set_surface_override_material(i, _toon_for(m.mesh.surface_get_material(i), name))


func _toon_for(src: Material, mesh_name: String) -> ShaderMaterial:
	var src_name := src.resource_name if src else ""
	var key := mesh_name + "/" + src_name if mesh_name.begins_with("garment__") else src_name
	if _materials.has(key):
		return _materials[key]
	var tex: Texture2D = (src as BaseMaterial3D).albedo_texture if src is BaseMaterial3D else null
	# Цвета в build_characters.py задуманы как экранные (sRGB), как и цвета вещей в items.json.
	# glTF хранит их как линейные, импорт переводит в sRGB (0.1 → 0.35, блёкло) — возвращаем исходное число;
	# uniform albedo (source_color) затем выводится на экран ровно этим цветом.
	var color: Color = (src as BaseMaterial3D).albedo_color.srgb_to_linear() if src is BaseMaterial3D else Color.WHITE
	var m := ShaderMaterial.new()
	if src_name == "hair_lock":
		# пряди-оболочки: свой шейдер с бликом; контур — толщина по вершинам, постоянная на экране
		m.shader = HAIR_LOCK
		_hair_lock_mats.append(m)
		var ol := ShaderMaterial.new()
		ol.shader = OUTLINE
		ol.set_shader_parameter("thickness", 0.0022)
		ol.set_shader_parameter("use_vertex_width", true)
		ol.set_shader_parameter("screen_scale", 2.5)
		ol.set_shader_parameter("outline_color", Color(0.16, 0.26, 0.4))
		m.next_pass = ol
		_materials[key] = m
		return m
	if src_name == "eye_shade":
		# тень века — полупрозрачная лента поверх радужки, без контура
		m.shader = EYE_SHADE
		m.set_shader_parameter("albedo", color)
		_materials[key] = m
		return m
	if src_name == "hair":
		# Карты прядей: отдельный шейдер, без контура (контур на полупрозрачных картах даёт «проволоку»).
		m.shader = HAIR
		m.set_shader_parameter("strands", tex)
		_materials[key] = m
		return m
	m.shader = TOON
	if tex:
		m.set_shader_parameter("albedo_tex", tex)
	m.set_shader_parameter("albedo", color)
	var thickness := 0.0032
	match src_name:
		"hair_cap", "hair_cap_lock":
			m.set_shader_parameter("use_vertex_color", true)
			m.set_shader_parameter("shade_color", Color(0.58, 0.64, 0.86))
			thickness = 0.0013
		"hair_solid", "hair_solid_light":
			# Объёмные пряди-клоки: тун-свет + тонкий контур, чтобы читались завитки.
			m.set_shader_parameter("use_vertex_color", true)
			m.set_shader_parameter("shade_color", Color(0.62, 0.68, 0.9) if src_name == "hair_solid" else Color(0.86, 0.78, 0.7))
			# Тонкий контур: читаются отдельные пряди (толстый превращал причёску в «клубок линий»).
			thickness = 0.0013
		"ear", "ear_inner", "ear_fur":
			thickness = 0.0012    # тонкий контур — ухо не «вырезано» толстой линией
			m.set_shader_parameter("shade_color", Color(0.7, 0.75, 0.8))   # нейтральная тень: середина уха угольная, не сливовая
		"skin":
			# Цвет кожи с «отрисовкой» анатомии (впадины, румянец) — в цвете вершин (paint_skin).
			m.set_shader_parameter("use_vertex_color", true)
			m.set_shader_parameter("use_regions", true)
			_skin_mats.append(m)
			m.set_shader_parameter("shade_color", Color(0.94, 0.76, 0.76))
			# Мягкая светотень кожи: видна форма тела (рёбра, ключицы, колени), а не плоская заливка.
			m.set_shader_parameter("shade_softness", 0.22)
			m.set_shader_parameter("shade_threshold", 0.5)
		_:
			if src_name.begins_with("face"):
				# лицо — тень по карте порогов (SDF), а не по геометрии (docs/MODEL_STUDY.md, «Видео»)
				m.shader = FACE
				if tex:
					m.set_shader_parameter("albedo_tex", tex)
				m.set_shader_parameter("albedo", color)
				m.set_shader_parameter("sdf_tex", FACE_SDF)
				m.set_shader_parameter("shade_color", Color(0.95, 0.8, 0.8))
				_face_mats.append(m)
				thickness = 0.0016
			elif src_name in ["lash", "lash_hi", "lash_glint", "brow", "crease", "strap", "patch", "skin_line", "nipple", "nipple_tip", "lid_warm"]:
				# Объёмные ресницы, брови, складка века, повязка и шнурок, «наклейки» на коже (соски, линии рельефа):
				# ровный цвет, без контура (с контуром повязка читается как дыра, а ресницы — как каракули).
				m.set_shader_parameter("shade_color", Color(0.85, 0.85, 0.9))
				m.set_shader_parameter("rim_strength", 0.0)
				if src_name == "brow":
					m.set_shader_parameter("view_bias", 0.035)    # бровь видна сквозь чёлку
				thickness = 0.0
			elif src_name.begins_with("eye"):
				m.set_shader_parameter("shade_color", Color(0.85, 0.85, 0.95))
				m.set_shader_parameter("rim_strength", 0.0)
				thickness = 0.0
	if thickness > 0.0:
		var outline := ShaderMaterial.new()
		outline.shader = OUTLINE
		outline.set_shader_parameter("thickness", thickness)
		if src_name == "hair_cap_lock":
			outline.set_shader_parameter("use_vertex_width", true)   # у шлема под прядями (альфа 0) контура нет
		if src_name in ["hair_solid", "hair_cap", "hair_cap_lock"]:
			# контур прядей — тёмно-бирюзовый, а не бордовый: в просветах между прядями он не читается дырой
			outline.set_shader_parameter("outline_color", Color(0.2, 0.32, 0.42))
		elif src_name == "hair_solid_light":
			# светлая грива (Хотто): тёплый коричневатый контур — бирюзовый на ней читался синими пятнами
			outline.set_shader_parameter("outline_color", Color(0.55, 0.45, 0.36))
		if src_name == "skin":
			outline.set_shader_parameter("use_regions", true)
		if src_name == "garment_cloth":
			# у ткани толщина контура по вершинам: в подмышках и сгибах тоньше (build_characters.outline_width)
			outline.set_shader_parameter("use_vertex_width", true)
		if src_name.begins_with("face") and tex:
			outline.set_shader_parameter("mask_tex", tex)
			outline.set_shader_parameter("use_mask", true)
		m.next_pass = outline
	_materials[key] = m
	return m


## Цвет вещи: основная ткань шаблона («garment_*») окрашивается; детали (цветы, пряжка, ремень) остаются своими.
func _tint(mi: MeshInstance3D, c: Color) -> void:
	for i in mi.mesh.get_surface_count():
		var mat := mi.get_surface_override_material(i) as ShaderMaterial
		var src := mi.mesh.surface_get_material(i)
		if mat and src and src.resource_name.begins_with("garment_"):
			mat.set_shader_parameter("albedo", c)
