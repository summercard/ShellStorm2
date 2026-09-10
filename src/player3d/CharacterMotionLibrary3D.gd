class_name CharacterMotionLibrary3D
extends RefCounted
## Read-only Blender bone clips mapped to existing presentation nodes.
## Never writes Player3D, weapons, physics, animation events, or save data.

const LIBRARY_PATH := "res://assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/production/v009/exports/anim_bunny01_library_v009.json"
static var _libraries: Dictionary = {}
var _cache: Dictionary = {}
var _fallback: Dictionary = {}
var _version := "v009"
var _last_pose: Dictionary = {}
var _transition_pose: Dictionary = {}
var _transition_time := 1.0
var _time := 0.0
var _state := ""
var _nodes: Dictionary = {}
var _weapon_socket_rest := Transform3D.IDENTITY
var active_clip := ""

func bind(avatar: Node3D) -> void:
	_version = str(avatar.get_meta("assembly_version", "v009"))
	var path := LIBRARY_PATH.replace("v009", _version)
	_cache = _load_library(path)
	var cache_clips: Dictionary = _cache.get("clips", {})
	_fallback = _load_library(LIBRARY_PATH) if not cache_clips.has("dead") else _cache
	_nodes = {"root": avatar.visual_root, "body": avatar.body, "head": avatar.head, "feet": avatar.feet,
		"hand_l": avatar.bunny_hand_l, "hand_r": avatar.bunny_hand_r,
		"foot_l": avatar.foot_l, "foot_r": avatar.foot_r,
		"ear_l": avatar.ear_socket_l, "ear_r": avatar.ear_socket_r}
	_weapon_socket_rest = avatar.weapon_socket.transform

static func _load_library(path: String) -> Dictionary:
	if not _libraries.has(path) and FileAccess.file_exists(path):
		var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if decoded is Dictionary and int(decoded.get("schema", 0)) in [1, 2]:
			_libraries[path] = decoded
	return _libraries.get(path, {})

func apply(avatar: Node3D, delta: float) -> void:
	var state: String = avatar.get("_state")
	var armed := bool(avatar.get("_weapon_grip_pose_active")) and str(avatar.get("_weapon_class")) in ["sidearm", "longgun"]
	var clips: Dictionary = _cache.get("clips", {})
	var locomotion_name := state
	var planar_speed := 0.0
	if state == "moving" and avatar.get("_player") != null:
		var velocity: Variant = avatar.get("_player").get("velocity")
		if velocity is Vector3:
			planar_speed = Vector2(velocity.x, velocity.z).length()
			if planar_speed > 0.05 and planar_speed < 3.2 and clips.has("walking"):
				locomotion_name = "walking"
	var armed_name := "armed_" + locomotion_name
	var clip_name := armed_name if armed and locomotion_name in ["idle", "moving", "walking"] and clips.has(armed_name) else locomotion_name
	var authored_anatomical := int(_cache.get("schema", 0)) == 2 and clips.has(clip_name)
	if not clips.has(clip_name):
		clips = _fallback.get("clips", {})
		authored_anatomical = false
	if not clips.has(clip_name):
		return
	if _state != clip_name:
		_time = 0.0
		_state = clip_name
		_transition_pose = _last_pose.duplicate(true)
		_transition_time = 0.0
	_transition_time += delta
	var clip: Dictionary = clips[clip_name]
	var duration: float = clip.duration
	var rate := 1.0
	if state == "moving" and avatar.get("_player") != null:
		rate = clampf(planar_speed / (2.4 if locomotion_name == "walking" else 5.0), 0.72, 1.18)
	_time += delta * rate
	var phase := _time / duration
	match state:
		"dashing": phase = avatar.get("_dash_animation_progress")
		"hurt": phase = avatar.get("_hurt_animation_progress")
		"landing": phase = avatar.get("_landing_animation_progress")
		"dead":
			var player: Node = avatar.get("_player")
			if player != null and player.has_method("get_death_animation_progress"):
				phase = player.get_death_animation_progress()
	phase = fposmod(phase, 1.0) if bool(clip.loop) else clampf(phase, 0.0, 1.0)
	var frames: Array = clip.frames
	var cursor := phase * (frames.size() - 1)
	var first := mini(int(cursor), frames.size() - 1)
	var second := mini(first + 1, frames.size() - 1)
	var blend := cursor - first
	var live_grip_active := bool(avatar.get("_weapon_grip_pose_active"))
	var legacy_grip_override := live_grip_active and _version != "v021"
	var live_hand_l_global: Transform3D = avatar.bunny_hand_l.global_transform
	var live_hand_r_global: Transform3D = avatar.bunny_hand_r.global_transform
	if authored_anatomical and (armed or not bool(avatar.get("_weapon_grip_pose_active"))):
		avatar.hand.transform = Transform3D.IDENTITY
	for bone: String in _nodes:
		var target: Node3D = _nodes[bone]
		if target == null: continue
		var a: Dictionary = frames[first][bone]
		var b: Dictionary = frames[second][bone]
		var aim_yaw := target.rotation.y
		var position := _vector(a.p).lerp(_vector(b.p), blend)
		var rotation := _quaternion(a.q).slerp(_quaternion(b.q), blend)
		var scaling := _vector(a.s).lerp(_vector(b.s), blend)
		if authored_anatomical and _transition_pose.has(bone):
			var weight := smoothstep(0.0, 1.0, minf(_transition_time / 0.18, 1.0))
			var previous: Dictionary = _transition_pose[bone]
			position = (previous.p as Vector3).lerp(position, weight)
			rotation = (previous.q as Quaternion).slerp(rotation, weight)
			scaling = (previous.s as Vector3).lerp(scaling, weight)
		_last_pose[bone] = {"p": position, "q": rotation, "s": scaling}
		# v021 由 Blender 唯一拥有角色姿势。旧版本仍保留原实时握持覆盖，
		# 以便回滚；正式玩家不再让程序约束反向覆盖手部关键帧。
		if bone in ["hand_l", "hand_r"] and legacy_grip_override:
			continue
		target.position = position
		target.quaternion = rotation
		target.scale = scaling
		if bone == "root": target.rotation.y = aim_yaw
	# Parent/body motion can move skipped hand nodes indirectly. Restore the complete
	# live global grip after sampling so GripSocket and support-hand constraints remain exact.
	if legacy_grip_override:
		avatar.bunny_hand_l.global_transform = live_hand_l_global
		avatar.bunny_hand_r.global_transform = live_hand_r_global
		if str(avatar.get("_weapon_class")) in ["sidearm", "longgun"]:
			avatar.bunny_hand_r.global_position = avatar.weapon_socket.global_position
	elif _version == "v021":
		# 武器是角色动画的从属物：保持枪口局部朝向契约，只把握点平移到
		# Blender 右手掌心。长枪双手动作缺失时也明确复用同一单手动作。
		avatar.weapon_socket.transform = _weapon_socket_rest
		if live_grip_active:
			avatar.weapon_socket.global_position = avatar.bunny_hand_r.global_position
	# Root yaw and weapon poses stay with the existing aim/grip constraints.
	# Dynamic shot/charge/knockback feedback remains an overlay, not a state transition.
	if _version == "v021":
		active_clip = clip_name
		return
	var fire: float = sin(float(avatar.get("_fire_progress")) * PI) * float(avatar.get("_fire_intensity")) if avatar.get("_firing_animation_active") else 0.0
	var charge: float = float(avatar.get("_charge_progress")) if avatar.get("_charging_animation_active") else 0.0
	avatar.body.position.y -= (fire * 0.016 + charge * 0.018) * avatar.BUNNY_LINEAR_SCALE
	avatar.body.scale *= Vector3(1.0 + fire * 0.045, 1.0 - fire * 0.08, 1.0 - fire * 0.025)
	avatar.head.rotation.x += fire * 0.035
	avatar.visual_root.position += Vector3(0.0, -fire * 0.018 - charge * 0.026, fire * 0.045) * avatar.BUNNY_LINEAR_SCALE
	avatar.visual_root.scale *= Vector3(1.0 + fire * 0.055 - charge * 0.035, 1.0 - fire * 0.075 - charge * 0.055, 1.0 - fire * 0.035 - charge * 0.035)
	if bool(avatar.get("_knockback_animation_active")):
		var impulse: Vector3 = avatar.get("_knockback_direction")
		var pulse := sin(float(avatar.get("_knockback_progress")) * PI)
		impulse = impulse.rotated(Vector3.UP, -avatar.visual_root.rotation.y)
		impulse.y = 0.0
		avatar.visual_root.position += (impulse.normalized() * pulse * 0.16 + Vector3.UP * pulse * 0.045) * avatar.BUNNY_LINEAR_SCALE
		avatar.visual_root.scale *= Vector3(1.0 + pulse * 0.10, 1.0 - pulse * 0.13, 1.0 + pulse * 0.07)
	if bool(avatar.get("_melee_animation_active")):
		var pulse := sin(float(avatar.get("_melee_progress")) * PI)
		var side := -1.0 if int(avatar.get("_melee_combo_step")) == 1 else 1.0
		avatar.visual_root.position += Vector3(-side * pulse * 0.08, -pulse * 0.03, 0.04) * avatar.BUNNY_LINEAR_SCALE
		avatar.visual_root.rotation.z += side * pulse * 0.16
	active_clip = clip_name

static func _vector(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])

static func _quaternion(value: Array) -> Quaternion:
	return Quaternion(value[0], value[1], value[2], value[3]).normalized()
