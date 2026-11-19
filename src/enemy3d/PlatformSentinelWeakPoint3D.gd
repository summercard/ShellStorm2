class_name PlatformSentinelWeakPoint3D
extends StaticBody3D

signal damaged(current: int)
signal destroyed

var max_hp := 1
var current_hp := 1
var ai_state := "dead"
var last_hit_position := Vector3.ZERO
var _enabled := false
var _rig: Skeleton3D
var _segments: Array[CollisionShape3D] = []
var _bones: Array[int] = []

func configure(hp: int, rig: Skeleton3D) -> void:
	max_hp = hp
	current_hp = hp
	collision_layer = 0
	collision_mask = 0
	_rig = rig
	for bone in ["shoulder", "elbow", "wrist", "palm"]:
		var index := rig.find_bone(bone)
		assert(index >= 0, "Missing Platform Sentinel arm bone: " + bone)
		_bones.append(index)
	for radius in [0.72, 0.68, 0.72]:
		var segment := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = radius
		segment.shape = capsule
		_segments.append(segment)
		add_child(segment)
	add_to_group("damageable_3d")
	add_to_group("aim_assist_target_3d")


func sync_pose() -> void:
	var joints: Array[Vector3] = []
	for index in _bones:
		joints.append(_rig.to_global(_rig.get_bone_global_pose(index).origin))
	global_position = (joints[2] + joints[3]) * 0.5
	for i in range(_segments.size()):
		var axis := joints[i + 1] - joints[i]
		var capsule := _segments[i].shape as CapsuleShape3D
		capsule.height = axis.length() + 2.0 * capsule.radius
		var y := axis.normalized() if not axis.is_zero_approx() else Vector3.UP
		var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.95 else Vector3.RIGHT).normalized()
		_segments[i].global_transform = Transform3D(Basis(x, y, x.cross(y)), (joints[i] + joints[i + 1]) * 0.5)


func set_open(enabled: bool) -> void:
	_enabled = enabled and current_hp > 0
	ai_state = "idle" if _enabled else "dead"
	set_deferred("collision_layer", 4 if _enabled else 0)


func get_melee_hit_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	if _enabled:
		for segment in _segments:
			points.append(segment.global_position)
		points.append(_rig.to_global(_rig.get_bone_global_pose(_bones[3]).origin))
	return points


func get_aim_assist_points() -> Array[Vector3]:
	return get_melee_hit_points()


func take_damage(amount: int, _critical := false, _direction := Vector3.ZERO, _knockback := 0.0) -> void:
	_apply_damage(amount, global_position)


func take_projectile_damage(amount: int, _critical: bool, direction: Vector3, _tags: Array, _fate: Dictionary, attacker: Node3D, _knockback: float) -> void:
	var point := global_position
	if is_instance_valid(attacker):
		var nearest := INF
		for sample in get_melee_hit_points():
			var offset := sample - attacker.global_position
			var distance := offset.cross(direction).length_squared()
			if offset.dot(direction) > 0.0 and distance < nearest:
				nearest = distance
				point = sample
	_apply_damage(amount, point)


func _apply_damage(amount: int, point: Vector3) -> void:
	if not _enabled or amount <= 0:
		return
	last_hit_position = point
	current_hp = maxi(0, current_hp - amount)
	damaged.emit(current_hp)
	if current_hp == 0:
		set_open(false)
		destroyed.emit()
