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
const HORIZONTAL_HIT_EXPANSION_M := 0.65
const ORIGINAL_RADII := [1.40, 1.24, 1.32]
## One tile plus a 0.75 m margin on either side; vertical band centered on player bullet height.
const DECK_HIT_SIZE := Vector3(6.5, 1.2, 6.5)
const DECK_HIT_INSET_M := 0.5

var _links: Array[Array] = []
var _bones: Array[int] = []
var aim_height := NAN
var _deck_aim := Vector3.INF
var _deck_hit: CollisionShape3D
var _deck_hit_frame: Node3D
var _deck_out: Vector3
var _deck_half_width := 0.0

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
	for radius in ORIGINAL_RADII:
		var capsule := CapsuleShape3D.new()
		capsule.radius = radius
		_add_lateral_shapes(capsule)
	var palm_shape := SphereShape3D.new()
	palm_shape.radius = 1.60
	_add_lateral_shapes(palm_shape)
	add_to_group("damageable_3d")
	add_to_group("aim_assist_target_3d")


func configure_deck_hit(frame: Node3D, side_out: Vector3, half_width: float) -> void:
	_deck_hit_frame = frame
	_deck_out = side_out
	_deck_half_width = half_width
	_deck_hit = CollisionShape3D.new()
	_deck_hit.name = "DeckHeightHit"
	var box := BoxShape3D.new()
	box.size = DECK_HIT_SIZE
	_deck_hit.shape = box
	add_child(_deck_hit)


func sync_pose() -> void:
	var joints: Array[Vector3] = []
	for index in _bones:
		joints.append(_rig.to_global(_rig.get_bone_global_pose(index).origin))
	global_position = (joints[2] + joints[3]) * 0.5
	_deck_aim = Vector3.INF
	if is_finite(aim_height):
		var low := joints[0]
		if not is_equal_approx(joints[0].y, joints[1].y):
			low = low.lerp(joints[1], clampf(inverse_lerp(joints[0].y, joints[1].y, aim_height), 0.0, 1.0))
		if absf(low.y - aim_height) < 0.8:
			_deck_aim = Vector3(low.x, aim_height, low.z)
	for i in range(ORIGINAL_RADII.size()):
		var axis := joints[i + 1] - joints[i]
		var y := axis.normalized() if not axis.is_zero_approx() else Vector3.UP
		var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.95 else Vector3.RIGHT).normalized()
		var capsule := (_links[i][0] as CollisionShape3D).shape as CapsuleShape3D
		capsule.height = axis.length() + 2.0 * capsule.radius
		_place_link(i, Basis(x, y, x.cross(y)), (joints[i] + joints[i + 1]) * 0.5)
	_place_link(3, Basis.IDENTITY, joints[3])
	if _deck_hit != null:
		# Follow the arm along its own edge without overlapping the fighting space or adjacent arms.
		var tangent := _deck_out.cross(Vector3.UP)
		var support := _deck_hit_frame.to_local((joints[0] + joints[1]) * 0.5)
		var along := clampf(support.dot(tangent), -_deck_half_width + DECK_HIT_SIZE.x * 0.5, _deck_half_width - DECK_HIT_SIZE.x * 0.5)
		var center := tangent * along + _deck_out * (_deck_half_width + DECK_HIT_SIZE.x * 0.5 - DECK_HIT_INSET_M)
		var world := _deck_hit_frame.to_global(center)
		world.y = aim_height
		_deck_hit.global_transform = Transform3D(_deck_hit_frame.global_basis.orthonormalized(), world)


func _add_lateral_shapes(shape: Shape3D) -> void:
	var shapes: Array[CollisionShape3D] = []
	for i in range(3):
		var part := CollisionShape3D.new()
		part.shape = shape
		add_child(part)
		shapes.append(part)
	_links.append(shapes)


func _place_link(index: int, frame: Basis, center: Vector3) -> void:
	# Offset identical volumes in world XZ: no extra height, no scale, one damage owner.
	var lateral := _rig.global_basis.x.slide(Vector3.UP).normalized() * HORIZONTAL_HIT_EXPANSION_M
	for slot in range(3):
		var part: CollisionShape3D = _links[index][slot]
		var side := 0 if slot == 0 else -1 if slot == 1 else 1
		part.global_transform = Transform3D(frame, center + lateral * side)


func set_open(enabled: bool) -> void:
	_enabled = enabled and current_hp > 0
	ai_state = "idle" if _enabled else "dead"
	set_deferred("collision_layer", 4 if _enabled else 0)


func get_melee_hit_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	if _enabled:
		for link in _links:
			for part: CollisionShape3D in link:
				points.append(part.global_position)
	return points


func get_aim_assist_points() -> Array[Vector3]:
	var points := get_melee_hit_points()
	if _enabled and _deck_aim.is_finite():
		points.append(_deck_aim)
	return points


func take_damage(amount: int, _critical := false, _direction := Vector3.ZERO, _knockback := 0.0) -> void:
	_apply_damage(amount, global_position)


func take_projectile_damage(amount: int, _critical: bool, direction: Vector3, _tags: Array, _fate: Dictionary, attacker: Node3D, _knockback: float) -> void:
	var point := global_position
	if is_instance_valid(attacker):
		var nearest := INF
		for sample in get_aim_assist_points():
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
