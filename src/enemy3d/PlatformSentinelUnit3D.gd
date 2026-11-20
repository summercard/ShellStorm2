class_name PlatformSentinelUnit3D
extends Node3D

const ARM_HP := 2200
const SLAM_RADIUS := 3.80
const SLAM_YAW_LIMIT := 0.94
const SLAM_MIN_REACH := 5.25
const SLAM_EXTENSION_CLEARANCE := 1.10

@export var grapple := false
@export var mount_tile: StringName

@onready var animation := find_child("AnimationPlayer", true, false) as AnimationPlayer
@onready var rig := find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
@onready var installed_transform := transform

var hit_body: PlatformSentinelWeakPoint3D
var armor: StaticBody3D
var ready_at := 0.0
var _sockets: Dictionary[StringName, Node3D] = {}
var _joint := -1
var _recoil := -1
var _fire_pose := Transform3D.IDENTITY
var _meshes: Array[Node] = []
var _camera_cutaway := 0.0
var _cutaway_surfaces: Array[Array] = []
var _standby_bones: Array[int] = []
var _standby_rest: Array[Quaternion] = []
var _standby_axes: Array[Vector3] = []
var _elbow := -1
var _wrist := -1
var _head := -1
var _impact_shoulder := Vector3.ZERO
var _impact_forward := Vector3.ZERO
var _impact_wrist := Basis.IDENTITY
var _impact_head := Basis.IDENTITY
var _wrist_to_head := Vector3.ZERO
var _head_to_contact := Vector3.ZERO
var _upper_length := 0.0
var _lower_length := 0.0
static var _cutaway_materials: Dictionary[ShaderMaterial, ShaderMaterial] = {}


func _ready() -> void:
	_joint = rig.find_bone("shoulder" if grapple else "gimbal_pitch")
	var joints := ["shoulder", "elbow", "wrist"] if grapple else ["gimbal_yaw", "gimbal_pitch", "lift", "forearm"]
	for joint: String in joints:
		_standby_bones.append(rig.find_bone(joint))
	if grapple:
		_elbow = rig.find_bone("elbow")
		_wrist = rig.find_bone("wrist")
		_head = rig.find_bone("head_yaw")
		_meshes = find_children("*", "MeshInstance3D", true, false)
		hit_body = PlatformSentinelWeakPoint3D.new()
		hit_body.name = "HitBody"
		add_child(hit_body)
		hit_body.configure(ARM_HP, rig)
	else:
		_recoil = rig.find_bone("recoil")
		var bearing := BoneAttachment3D.new()
		bearing.bone_name = "trunnion"
		rig.add_child(bearing)
		armor = StaticBody3D.new()
		armor.name = "SentryArmor"
		armor.collision_layer = 0
		armor.collision_mask = 0
		var shape := CollisionShape3D.new()
		var shell := SphereShape3D.new()
		shell.radius = 0.54
		shape.shape = shell
		armor.add_child(shape)
		bearing.add_child(armor)
	play("activate_grapple" if grapple else "activate_sentry", 0.0)


func play(clip: StringName, speed := 1.0, at := 0.0) -> void:
	if not animation.has_animation(clip):
		push_error("Platform Sentinel missing clip %s/%s" % [name, clip])
		return
	stop_standby()
	if str(clip).begins_with("idle_"):
		animation.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	animation.play(clip, 0.12 if speed > 0.0 else 0.0, speed)
	animation.seek(at, true)
	animation.advance(0.0)
	# A playing zero-speed clip still writes its tracks on the next frame.
	if is_zero_approx(speed):
		animation.pause()
	sync_rig()


func delay_motion(seconds: float) -> void:
	if seconds > 0.0:
		animation.speed_scale = 0.0
		create_tween().tween_property(animation, "speed_scale", 1.0, 0.0).set_delay(seconds)


func sync_rig() -> void:
	rig.force_update_all_bone_transforms()
	for attachment in rig.get_children():
		if attachment is BoneAttachment3D and attachment.bone_idx >= 0:
			attachment.transform = rig.get_bone_global_pose(attachment.bone_idx)


func socket(key: StringName) -> Node3D:
	if not _sockets.has(key):
		_sockets[key] = find_child("*__" + str(key), true, false) as Node3D
	return _sockets[key]


func set_fade(fade: float) -> void:
	if is_equal_approx(_camera_cutaway, fade):
		return
	_camera_cutaway = fade
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		for mesh: GeometryInstance3D in _meshes:
			mesh.transparency = fade
		return
	if _cutaway_surfaces.is_empty():
		for mesh: MeshInstance3D in _meshes:
			for i in range(mesh.mesh.get_surface_count()):
				var source := mesh.get_active_material(i) as ShaderMaterial
				if source != null:
					_cutaway_surfaces.append([mesh, i, source, mesh.get_surface_override_material(i)])
	for entry in _cutaway_surfaces:
		var mesh: MeshInstance3D = entry[0]
		var surface: int = entry[1]
		var source: ShaderMaterial = entry[2]
		if fade <= 0.0:
			mesh.set_surface_override_material(surface, entry[3])
			continue
		if not _cutaway_materials.has(source):
			_cutaway_materials[source] = source.duplicate() as ShaderMaterial
		var material := _cutaway_materials[source]
		material.set_shader_parameter("camera_cutaway", fade)
		material.set_shader_parameter("red_black", source.get_shader_parameter("red_black"))
		mesh.set_surface_override_material(surface, material)


func palm_position() -> Vector3:
	var sum := Vector3.ZERO
	for key in [&"palm_contact_ll", &"palm_contact_lr", &"palm_contact_ul", &"palm_contact_ur"]:
		sum += socket(key).global_position
	return sum * 0.25


func prepare_slam(at: float) -> void:
	play("attack_grapple_slam", 0.0, at)
	_impact_shoulder = rig.get_bone_global_pose(_joint).origin
	var elbow := rig.get_bone_global_pose(_elbow).origin
	var wrist := rig.get_bone_global_pose(_wrist)
	var head := rig.get_bone_global_pose(_head)
	var contact := rig.to_local(palm_position())
	_impact_forward = contact - _impact_shoulder
	_impact_wrist = wrist.basis
	_impact_head = head.basis
	_wrist_to_head = head.origin - wrist.origin
	_head_to_contact = contact - head.origin
	_upper_length = elbow.distance_to(_impact_shoulder)
	_lower_length = wrist.origin.distance_to(elbow)
	play("activate_grapple", 0.0)


func choose_slam(arena: Node3D, target: Vector3, now: float) -> Dictionary:
	if hit_body.current_hp <= 0 or ready_at > now:
		return {}
	var target_local := arena.to_local(target)
	var installed := arena.to_local(global_position)
	if (target_local.x >= 0.0) != (installed.x > 0.0) or (target_local.z >= 0.0) != (installed.z > 0.0):
		return {}
	var shoulder := rig.to_global(_impact_shoulder)
	var rest_forward := (rig.global_basis * _impact_forward).slide(Vector3.UP).normalized()
	var approach := (target - shoulder).slide(Vector3.UP)
	var yaw := clampf(rest_forward.signed_angle_to(approach, Vector3.UP), -SLAM_YAW_LIMIT, SLAM_YAW_LIMIT)
	var turn := Basis(Vector3.UP, yaw)
	var forward := turn * rest_forward
	# Extend the wrist joint toward the strike while keeping the impact pad flat.
	var wrist_to_head := (forward + Vector3.DOWN * 0.42).normalized() * _wrist_to_head.length()
	var turned_frame := turn * rig.global_basis
	var wrist_to_contact := wrist_to_head + turned_frame * _head_to_contact
	var pad_y := arena.global_position.y + 0.004
	var vertical := pad_y - wrist_to_contact.y - shoulder.y
	var chain_reach := _upper_length + _lower_length - SLAM_EXTENSION_CLEARANCE
	var max_reach := sqrt(maxf(0.0, chain_reach * chain_reach - vertical * vertical)) + wrist_to_contact.dot(forward)
	var contact := shoulder + forward * clampf(approach.dot(forward), SLAM_MIN_REACH, max_reach)
	contact.y = pad_y
	if (target - contact).slide(Vector3.UP).length() > SLAM_RADIUS - 0.12:
		return {}
	var tilt := Basis(Quaternion((turned_frame * _wrist_to_head).normalized(), wrist_to_head.normalized()))
	return {
		"yaw": yaw, "contact": contact,
		"wrist": Transform3D(tilt * turned_frame * _impact_wrist, contact - wrist_to_contact),
		"head_basis": turned_frame * _impact_head,
	}


func apply_slam_reach(plan: Dictionary, amount: float) -> void:
	if amount <= 0.0:
		return
	var shoulder := _world_bone(_joint)
	var elbow := _world_bone(_elbow)
	var wrist := _world_bone(_wrist)
	var head := _world_bone(_head)
	var head_offset := wrist.affine_inverse() * head.origin
	var wrist_goal: Transform3D = plan.wrist
	var hand_goal: Basis = plan.head_basis
	var reach := wrist.origin.lerp(wrist_goal.origin, amount) - shoulder.origin
	var axis := reach.normalized()
	var distance := clampf(reach.length(), absf(_upper_length - _lower_length) + 0.04, _upper_length + _lower_length - 0.04)
	var upper := elbow.origin - shoulder.origin
	var lower := wrist.origin - elbow.origin
	var bend_axis := upper.slide(axis).normalized()
	if bend_axis.is_zero_approx():
		bend_axis = Vector3.UP.slide(axis).normalized()
	var along := (distance * distance + _upper_length * _upper_length - _lower_length * _lower_length) / (2.0 * distance)
	var bend := sqrt(maxf(0.0, _upper_length * _upper_length - along * along))
	var upper_goal := axis * along + bend_axis * bend
	var lower_goal := axis * distance - upper_goal
	shoulder.basis = Basis(Quaternion(upper.normalized(), upper_goal.normalized())) * shoulder.basis
	elbow.basis = Basis(Quaternion(lower.normalized(), lower_goal.normalized())) * elbow.basis
	elbow.origin = shoulder.origin + upper_goal
	wrist.origin = elbow.origin + lower_goal
	wrist.basis = wrist.basis.slerp(wrist_goal.basis, amount)
	head.origin = wrist * head_offset
	head.basis = head.basis.slerp(hand_goal, amount)
	var inverse := rig.global_transform.affine_inverse()
	rig.set_bone_global_pose_override(_joint, inverse * shoulder, 1.0, true)
	rig.set_bone_global_pose_override(_elbow, inverse * elbow, 1.0, true)
	rig.set_bone_global_pose_override(_wrist, inverse * wrist, 1.0, true)
	rig.set_bone_global_pose_override(_head, inverse * head, 1.0, true)
	sync_rig()


func _world_bone(bone: int) -> Transform3D:
	return rig.global_transform * rig.get_bone_global_pose(bone)


func slew(yaw: float, pitch := 0.0) -> void:
	var pose := rig.get_bone_global_pose(_joint)
	var local_up := (rig.global_basis.inverse() * Vector3.UP).normalized()
	var local_right := (rig.global_basis.inverse() * global_basis.x).normalized()
	pose.basis = Basis(local_up, yaw) * Basis(local_right, pitch) * pose.basis
	rig.set_bone_global_pose_override(_joint, pose, 1.0, true)
	sync_rig()


func sample_standby(elapsed: float, slot: int, target: Vector3, arena_center: Vector3) -> void:
	if _standby_rest.is_empty():
		rig.clear_bones_global_pose_override()
		play("idle_grapple" if grapple else "idle_sentry", 0.0)
		for i in range(_standby_bones.size()):
			var bone := _standby_bones[i]
			var basis := rig.global_basis * rig.get_bone_global_pose(bone).basis
			var axis := Vector3.UP if i == 0 else global_basis.x
			_standby_rest.append(rig.get_bone_pose_rotation(bone))
			_standby_axes.append((basis.inverse() * axis).normalized())
	var bank := floorf(float(slot) / 4.0)
	var period := 2.15 + float(slot) * 0.11 if grapple else 1.8 + bank * 0.14
	var phase := fposmod(elapsed / period + float(slot % 4) * 0.25 + bank * 0.083 + (0.19 if grapple else 0.0), 1.0)
	var inward := (arena_center - global_position).slide(Vector3.UP).normalized()
	var sight := (target - global_position).slide(Vector3.UP).normalized()
	var limit := 0.29 if grapple else 0.43
	var track := clampf(inward.signed_angle_to(sight, Vector3.UP), -limit, limit)
	var follow := 0.88 * smoothstep(0.31, 0.57, phase) * (1.0 - smoothstep(0.68, 0.92, phase))
	var sweep := -limit * cos(TAU * smoothstep(0.0, 1.0, phase))
	_rotate_standby_bone(0, lerpf(sweep, track, follow))
	if grapple:
		_rotate_standby_bone(1, sin(TAU * (phase + 0.08)) * 0.22)
		_rotate_standby_bone(2, sin(TAU * (phase + 0.34)) * 0.14)
	else:
		var fold := smoothstep(0.05, 0.36, phase) * (1.0 - smoothstep(0.59, 0.88, phase))
		_rotate_standby_bone(1, lerpf(0.08, -0.16, fold) + sin(TAU * phase) * 0.12)
		_rotate_standby_bone(2, lerpf(0.03, 0.34, fold))
		_rotate_standby_bone(3, lerpf(0.35, -0.06, fold))
	sync_rig()


func _rotate_standby_bone(index: int, angle: float) -> void:
	rig.set_bone_pose_rotation(_standby_bones[index], _standby_rest[index] * Quaternion(_standby_axes[index], angle))


func stop_standby() -> void:
	for i in range(_standby_rest.size()):
		rig.set_bone_pose_rotation(_standby_bones[i], _standby_rest[i])
	_standby_rest.clear()
	_standby_axes.clear()


func aim_sentry(target: Vector3) -> void:
	var pose := rig.get_bone_global_pose(_joint)
	var pivot := rig.to_global(pose.origin)
	var axis := socket(&"muzzle_exit").global_position.direction_to(socket(&"muzzle_forward").global_position)
	var aim := (target - pivot).slide(Vector3.UP).normalized()
	var correction := Basis(Quaternion(axis, aim))
	pose.basis = rig.global_basis.inverse() * correction * rig.global_basis * pose.basis
	rig.set_bone_global_pose_override(_joint, pose, 1.0, true)
	sync_rig()
	_fire_pose = rig.get_bone_global_pose(_recoil)


func set_recoil(axis: Vector3, kick: float) -> void:
	var pose := _fire_pose
	pose.origin -= (rig.global_basis.inverse() * axis) * kick * 0.34
	rig.set_bone_global_pose_override(_recoil, pose, 1.0, true)
	sync_rig()
