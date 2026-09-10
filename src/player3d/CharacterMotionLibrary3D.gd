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
var active_clip := ""

func bind(avatar: Node3D) -> void:
	_version = str(avatar.get_meta("assembly_version", "v009"))
	var path := LIBRARY_PATH.replace("v009", _version)
	_cache = _load_library(path)
	_fallback = _load_library(LIBRARY_PATH) if _version in ["v010", "v011"] else _cache
	_nodes = {"root": avatar.visual_root, "body": avatar.body, "head": avatar.head, "feet": avatar.feet,
		"hand_l": avatar.bunny_hand_l, "hand_r": avatar.bunny_hand_r,
		"foot_l": avatar.foot_l, "foot_r": avatar.foot_r,
		"ear_l": avatar.ear_socket_l, "ear_r": avatar.ear_socket_r}

static func _load_library(path: String) -> Dictionary:
	if not _libraries.has(path) and FileAccess.file_exists(path):
		var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if decoded is Dictionary and int(decoded.get("schema", 0)) in [1, 2]:
			_libraries[path] = decoded
	return _libraries.get(path, {})

func apply(avatar: Node3D, delta: float) -> void:
	var state: String = avatar.get("_state")
	var armed := bool(avatar.get("_weapon_grip_pose_active")) and str(avatar.get("_weapon_class")) in ["sidearm", "longgun"]
	var clip_name := "armed_" + state if armed and state in ["idle", "moving"] and _version in ["v010", "v011"] else state
	var clips: Dictionary = _cache.get("clips", {})
	var authored_v010 := _version in ["v010", "v011"] and clips.has(clip_name)
	if not clips.has(clip_name):
		clips = _fallback.get("clips", {})
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
		var velocity: Variant = avatar.get("_player").get("velocity")
		if velocity is Vector3:
			rate = lerpf(7.8, 11.2, clampf(Vector2(velocity.x, velocity.z).length() / 7.0, 0.0, 1.0)) / 11.2
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
	var support_offset: Vector3 = avatar.bunny_hand_l.global_position - avatar.weapon_socket.global_position
	if authored_v010 and (armed or not bool(avatar.get("_weapon_grip_pose_active"))):
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
		if _version in ["v010", "v011"] and _transition_pose.has(bone) and (authored_v010 or _version == "v010"):
			var weight := smoothstep(0.0, 1.0, minf(_transition_time / 0.18, 1.0))
			var previous: Dictionary = _transition_pose[bone]
			position = (previous.p as Vector3).lerp(position, weight)
			rotation = (previous.q as Quaternion).slerp(rotation, weight)
			scaling = (previous.s as Vector3).lerp(scaling, weight)
		_last_pose[bone] = {"p": position, "q": rotation, "s": scaling}
		if bone in ["hand_l", "hand_r"] and bool(avatar.get("_weapon_grip_pose_active")) and (not authored_v010 or not armed):
			continue
		target.position = position
		target.quaternion = rotation
		target.scale = scaling
		if bone == "root": target.rotation.y = aim_yaw
	if authored_v010 and armed:
		# Authored ready-hand trajectory owns the presentation socket translation.
		# Actual weapon aim, recoil and reload remain the existing live constraints.
		avatar.weapon_socket.position = avatar.bunny_hand_r.position + (avatar.get("_reload_offset") as Vector3) + (avatar.get("_action_offset") as Vector3)
		avatar.bunny_hand_r.global_position = avatar.weapon_socket.global_position
		avatar.bunny_hand_r.rotation += (avatar.get("_reload_rotation") as Vector3) + (avatar.get("_action_rotation") as Vector3)
		if str(avatar.get("_weapon_class")) == "longgun" or bool(avatar.get("_reload_animation_active")):
			avatar.bunny_hand_l.global_position = avatar.weapon_socket.global_position + support_offset
	# Root yaw and weapon poses stay with the existing aim/grip constraints.
	# Dynamic shot/charge/knockback feedback remains an overlay, not a state transition.
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
