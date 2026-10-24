class_name FaceRig
extends Node
## Сменное лицо персонажа (просьба пользователя 24.10): выражение, форма глаз, макияж, цвет и узор глаз.
## Лицо собирается из слоёв (tools/art/gen_faces.py, раздел «сменные лица»): кожа с прорезями глаз нужной
## формы, маски макияжа, атлас ртов, радужка с узором; брови двигаются ключами формы (build_characters.py),
## для каждой формы глаз в модели свой набор ресниц, складки и тени века (имена «…__round», «…__sharp»).
## Стиль лица — словарь (вещь слота face_style в data/wardrobe/items.json или стиль героя по умолчанию):
##   {"expression": "smile", "eye_shape": "round",
##    "makeup": {"blush": "#f29aa4", "blush_amount": 0.5, "eyeshadow": "#d08a8a", "eyeshadow_amount": 0.4,
##               "lips": "#e07a86", "lips_amount": 0.6},
##    "iris": {"tint": 1.0, "top": "#3a4a8a", "bottom": "#9ab4f0", "pattern": "butterfly",
##             "pattern_color": "#ffffff", "rainbow": 0.0, "sparkle": 0.0}}

const FACES_DIR := "res://art/characters/faces/"
## Выражение: клетка атласа ртов, ключи формы бровей, закрытые глаза (^^).
const EXPRESSIONS := {
	"neutral": {"mouth": 0, "brows": {}},
	"smile": {"mouth": 1, "brows": {"brow_up": 0.25}},
	"surprised": {"mouth": 2, "brows": {"brow_up": 1.0}},
	"serious": {"mouth": 3, "brows": {"brow_angry": 0.45, "brow_down": 0.3}},
	"happy": {"mouth": 4, "brows": {"brow_up": 0.4}, "eyes": "closed"},
	"smirk": {"mouth": 5, "brows": {"brow_angry": 0.15}},
	"pout": {"mouth": 6, "brows": {"brow_sad": 0.6}},
	"cat": {"mouth": 7, "brows": {"brow_up": 0.3}},
}
const EYE_SHAPES := ["default", "round", "sharp"]
const PATTERNS := ["none", "butterfly", "heart", "star", "flower", "sparkles", "moon", "swirl"]
const SHARED_EYE := ["eye_sclera", "eye_iris", "eye_hl"]
const VARIANT_PARTS := ["lash_", "lid_warm", "crease", "eye_shade"]

var character_id := ""
var info: Dictionary = {}              # faces/<id>.json: прямоугольник рта, стиль по умолчанию
var style: Dictionary = {}             # текущий стиль (уже слитый со стилем по умолчанию)
var blinking := not OS.has_environment("KPC_CAPTURE")   # на снимках (tools/capture.sh) не моргают

var _face_mats: Array[ShaderMaterial] = []
var _default_tex: Dictionary = {}      # материал → исходная текстура кожи (форма default)
var _variant_tex: Dictionary = {}      # форма → Texture2D
var _sets: Dictionary = {}             # форма → [MeshInstance3D]
var _shared: Array[MeshInstance3D] = []
var _brows: Array[MeshInstance3D] = []
var _iris_mats: Array[ShaderMaterial] = []
var _eye_shape := "default"
var _closed := false
var _expression_override := ""
var _blink_wait := 3.0
var _blink_left := 0.0
var _rng := RandomNumberGenerator.new()


static func info_path(cid: String) -> String:
	return FACES_DIR + cid + ".json"


func setup(root: Node, cid: String, face_mats: Array[ShaderMaterial], iris_mats: Array[ShaderMaterial]) -> void:
	character_id = cid
	info = DataLoader.load_json(info_path(cid))
	_face_mats = face_mats
	_iris_mats = iris_mats
	_rng.seed = hash(cid)
	for m in _face_mats:
		_default_tex[m] = m.get_shader_parameter("albedo_tex")
		var mk := _load_tex("makeup_%s.png" % cid)
		if mk:
			m.set_shader_parameter("makeup_tex", mk)
			m.set_shader_parameter("use_makeup", true)
		var mouths := _load_tex("mouths.png")
		if mouths and info.has("mouth_rect"):
			var r: Array = info["mouth_rect"]
			m.set_shader_parameter("mouth_tex", mouths)
			m.set_shader_parameter("mouth_rect", Vector4(r[0], r[1], r[2], r[3]))
			m.set_shader_parameter("use_mouth", true)
	var patterns := _load_tex("iris_patterns.png")
	for im in _iris_mats:
		if patterns:
			im.set_shader_parameter("pattern_tex", patterns)
	for shape in EYE_SHAPES:
		_sets[shape] = []
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var n := String(mi.name)
		if n.begins_with("brow") and mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).get_blend_shape_count() > 0:
			_brows.append(mi)
			continue
		var shared := false
		for p in SHARED_EYE:
			shared = shared or n.begins_with(p)
		if shared:
			_shared.append(mi)
			continue
		var part := false
		for p in VARIANT_PARTS:
			part = part or n.begins_with(p)
		if not part:
			continue
		var shape := "default"
		for s in EYE_SHAPES:
			if n.contains("__" + s):
				shape = s
		_sets[shape].append(mi)
	apply_style({})


func _load_tex(file: String) -> Texture2D:
	var path := FACES_DIR + file
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## Стиль лица (пустой — стиль героя по умолчанию). Поля, которых нет в style, берутся из стиля по умолчанию.
func apply_style(p_style: Dictionary) -> void:
	style = _merged(info.get("default", {}), p_style)
	var mk: Dictionary = style.get("makeup", {})
	for m in _face_mats:
		m.set_shader_parameter("blush_color", Color(str(mk.get("blush", "#f296a0"))))
		m.set_shader_parameter("blush_amount", float(mk.get("blush_amount", 0.3)))
		m.set_shader_parameter("eyeshadow_color", Color(str(mk.get("eyeshadow", "#d48c8c"))))
		m.set_shader_parameter("eyeshadow_amount", float(mk.get("eyeshadow_amount", 0.3)))
		m.set_shader_parameter("lip_color", Color(str(mk.get("lips", "#e8909a"))))
		m.set_shader_parameter("lip_amount", float(mk.get("lips_amount", 0.5)))
	var ir: Dictionary = style.get("iris", {})
	for im in _iris_mats:
		im.set_shader_parameter("tint_amount", float(ir.get("tint", 0.0)))
		im.set_shader_parameter("color_top", Color(str(ir.get("top", "#3a4a8a"))))
		im.set_shader_parameter("color_bottom", Color(str(ir.get("bottom", "#9ab4f0"))))
		im.set_shader_parameter("rainbow", float(ir.get("rainbow", 0.0)))
		im.set_shader_parameter("sparkle", float(ir.get("sparkle", 0.0)))
		im.set_shader_parameter("pattern_cell", maxi(0, PATTERNS.find(str(ir.get("pattern", "none")))))
		im.set_shader_parameter("pattern_color", Color(str(ir.get("pattern_color", "#ffffff"))))
	var shape := str(style.get("eye_shape", "default"))
	_eye_shape = shape if EYE_SHAPES.has(shape) else "default"
	_apply_expression()


## Выражение поверх стиля (реплика, кат-сцена); пустое — выражение стиля.
func set_expression(expr: String) -> void:
	_expression_override = expr if EXPRESSIONS.has(expr) else ""
	_apply_expression()


func current_expression() -> String:
	if _expression_override != "":
		return _expression_override
	var e := str(style.get("expression", "neutral"))
	return e if EXPRESSIONS.has(e) else "neutral"


func _apply_expression() -> void:
	var ex: Dictionary = EXPRESSIONS[current_expression()]
	for m in _face_mats:
		m.set_shader_parameter("mouth_cell", int(ex["mouth"]))
	var brows: Dictionary = ex.get("brows", {})
	for mi in _brows:
		var am := mi.mesh as ArrayMesh
		for i in am.get_blend_shape_count():
			mi.set_blend_shape_value(i, float(brows.get(String(am.get_blend_shape_name(i)), 0.0)))
	_closed = ex.get("eyes", "") == "closed"
	_show_eyes(_closed, "closed")


## Глаза: открытые формы _eye_shape либо закрытые (closed — «^^», blink — моргание).
func _show_eyes(closed: bool, closed_kind: String) -> void:
	var tex_shape := closed_kind if closed else _eye_shape
	for m in _face_mats:
		m.set_shader_parameter("albedo_tex", _default_tex[m] if tex_shape == "default" else _variant(tex_shape, m))
	for mi in _shared:
		mi.visible = not closed
	for shape in _sets:
		for mi in _sets[shape]:
			(mi as MeshInstance3D).visible = not closed and shape == _eye_shape


func _variant(shape: String, m: ShaderMaterial) -> Texture2D:
	if not _variant_tex.has(shape):
		_variant_tex[shape] = _load_tex("face_%s__%s.png" % [character_id, shape])
	return _variant_tex[shape] if _variant_tex[shape] else _default_tex[m]


func _process(delta: float) -> void:
	if not blinking or _closed or _face_mats.is_empty():
		return
	if _blink_left > 0.0:
		_blink_left -= delta
		if _blink_left <= 0.0:
			_show_eyes(false, "")
		return
	_blink_wait -= delta
	if _blink_wait <= 0.0:
		_blink_wait = _rng.randf_range(2.4, 5.6)
		_blink_left = 0.11
		_show_eyes(true, "blink")


static func _merged(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for k in over:
		if over[k] is Dictionary and out.get(k) is Dictionary:
			out[k] = _merged(out[k], over[k])
		else:
			out[k] = over[k]
	return out
