class_name HeadLook
extends SkeletonModifier3D
## Поворот головы к точке поверх анимации (NPC смотрят на героя, герой — на собеседника).
## Голова поворачивается не больше чем на MAX_YAW / MAX_PITCH, шея берёт часть поворота; влияние плавно
## нарастает и спадает, поэтому взгляд не «щёлкает». target = null — смотреть прямо.

const MAX_YAW := 1.05
const MAX_PITCH := 0.4
const NECK_SHARE := 0.35

var target = null                 # Vector3 в мире или null
var _w := 0.0                     # текущее влияние 0…1
var _yaw := 0.0
var _pitch := 0.0
var _head := -1
var _neck := -1


func _ready() -> void:
	var sk := get_skeleton()
	if sk:
		_head = sk.find_bone("head")
		_neck = sk.find_bone("neck")


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or _head < 0:
		return
	var dt := get_process_delta_time()
	var want := 0.0
	var yaw := _yaw
	var pitch := _pitch
	if target != null:
		var head_pose := sk.get_bone_global_pose(_head)
		var local: Vector3 = sk.global_transform.affine_inverse() * (target as Vector3)
		var d := local - head_pose.origin
		var y := atan2(d.x, d.z)
		# цель за спиной — не выворачивать голову
		if absf(y) < 1.9:
			want = 1.0
			yaw = clampf(y, -MAX_YAW, MAX_YAW)
			pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -MAX_PITCH, MAX_PITCH)
	var k := 1.0 - exp(-5.0 * dt)
	_w = lerpf(_w, want, k)
	_yaw = lerp_angle(_yaw, yaw, k)
	_pitch = lerpf(_pitch, pitch, k)
	if _w < 0.01:
		return
	if _neck >= 0:
		_turn(sk, _neck, _yaw * NECK_SHARE * _w, _pitch * NECK_SHARE * _w)
	_turn(sk, _head, _yaw * (1.0 - NECK_SHARE) * _w, _pitch * (1.0 - NECK_SHARE) * _w)


## Поворот кости в пространстве скелета вокруг её же начала: сначала наклон (вокруг X), затем поворот (вокруг Y).
func _turn(sk: Skeleton3D, bone: int, yaw: float, pitch: float) -> void:
	var g := sk.get_bone_global_pose(bone)
	var r := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -pitch)
	sk.set_bone_global_pose(bone, Transform3D(r * g.basis, g.origin))
