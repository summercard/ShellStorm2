class_name PlatformSentinelUnit3D
extends Node3D

const ARM_HP := 2200
const SLAM_RADIUS := 3.05

@export var grapple := false
@export var mount_tile: StringName

@onready var animation := find_child("AnimationPlayer", true, false) as AnimationPlayer
@onready var rig := find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
@onready var installed_transform := transform

var hit_body: PlatformSentinelWeakPoint3D
var armor: StaticBody3D
var ready_at := 0.0
var slam_slots: Array[Dictionary] = []
var _sockets: Dictionary[StringName, Node3D] = {}
var _joint := -1
var _recoil := -1
var _fire_pose := Transform3D.IDENTITY
var _meshes: Array[Node] = []
var _camera_cutaway := 0.0
var _cutaway_surfaces: Array[Array] = []
static var _cutaway_materials: Dictionary[ShaderMaterial, ShaderMaterial] = {}


func _ready() -> void:
	_joint = rig.find_bone("shoulder" if grapple else "gimbal_pitch")
	if grapple:
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
	if str(clip).begins_with("idle_"):
		animation.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	animation.play(clip, 0.12 if speed > 0.0 else 0.0, speed)
	animation.seek(at, true)
	animation.advance(0.0)
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


func prepare_slam_slots(arena: Node3D, at: float) -> void:
	play("attack_grapple_slam", 0.0, at)
	var pivot := rig.to_global(rig.get_bone_global_pose(_joint).origin)
	var point := palm_position()
	slam_slots = [{"angle": 0.0, "point": arena.to_local(point), "pivot": arena.to_local(pivot)}]
	var best := arena.to_local(point).slide(Vector3.UP).length()
	for angle in [deg_to_rad(18.0), deg_to_rad(-18.0)]:
		var candidate := pivot + (point - pivot).rotated(Vector3.UP, angle)
		var local := arena.to_local(candidate)
		if local.slide(Vector3.UP).length() < best - 0.35 and maxf(absf(local.x), absf(local.z)) < 10.9:
			best = local.slide(Vector3.UP).length()
			if slam_slots.size() > 1:
				slam_slots.pop_back()
			slam_slots.append({"angle": angle, "point": local, "pivot": arena.to_local(pivot)})
	play("activate_grapple", 0.0)


func choose_slam(arena: Node3D, target: Vector3, now: float) -> Dictionary:
	if hit_body.current_hp <= 0 or ready_at > now:
		return {}
	var best := SLAM_RADIUS - 0.12
	var selected: Dictionary = {}
	for slot in slam_slots:
		var distance := (target - arena.to_global(slot.point)).slide(Vector3.UP).length()
		if distance <= best:
			best = distance
			selected = slot
	return selected


func slew(yaw: float, pitch := 0.0) -> void:
	var pose := rig.get_bone_global_pose(_joint)
	var local_up := (rig.global_basis.inverse() * Vector3.UP).normalized()
	var local_right := (rig.global_basis.inverse() * global_basis.x).normalized()
	pose.basis = Basis(local_up, yaw) * Basis(local_right, pitch) * pose.basis
	rig.set_bone_global_pose_override(_joint, pose, 1.0, true)
	sync_rig()


func sample_standby(progress: float, target: Vector3, arena_center: Vector3) -> void:
	var inward := (arena_center - global_position).slide(Vector3.UP).normalized()
	var sight := (target - global_position).slide(Vector3.UP).normalized()
	var limit := 0.27 if grapple else 0.42
	var track := clampf(inward.signed_angle_to(sight, Vector3.UP), -limit, limit)
	var blend := smoothstep(0.0, 0.25, progress) * (1.0 - smoothstep(0.76, 1.0, progress))
	var sweep := lerpf(-0.24, track, smoothstep(0.14, 0.69, progress))
	var flex := (0.18 if grapple else -0.20) * sin(progress * PI)
	rig.clear_bones_global_pose_override()
	slew(blend * sweep, flex)


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
	pose.origin -= (rig.global_basis.inverse() * axis) * kick * 0.23
	rig.set_bone_global_pose_override(_recoil, pose, 1.0, true)
	sync_rig()
