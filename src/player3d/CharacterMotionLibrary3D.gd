class_name CharacterMotionLibrary3D
extends RefCounted
## Read-only Blender bone clips mapped to existing presentation nodes.
## Never writes Player3D, weapons, physics, animation events, or save data.

const LIBRARY_PATH := "res://assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/production/v009/exports/anim_bunny01_library_v009.json"
const CURRENT_LIBRARY_PATH := "res://assets/art/characters/player/chr_player_capsule01_3d/variants/bunny01/components/chr_bunny01_motion/anim_bunny01_library.json"
## 跑步剪辑（moving / armed_moving）的播放倍率。只缩放采样相位的推进速度，
## 不写玩家状态、不改移动速度、不改剪辑数据。走路剪辑（walking）保持 1.0。
const RUN_CLIP_RATE_SCALE := 1.3
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
var movement_direction := "forward"
var speed_role := "idle"
var fallback_reason := "none"
var playback_rate := 1.0
var reference_speed_mps := 0.0
var library_version := ""
var _fire_hold_remaining := 0.0
var _fire_weapon_id := ""
var _transition_duration := 0.18
var _switch_was_active := false
var _reload_was_active := false
var active_overlay := ""
var overlay_progress := 0.0
## 叙事姿态锁：剧情演出期间把采样相位钉在某个值（倒地 / 起身的落脚点）。
## 只影响采样相位，不改剪辑数据、不写玩家状态、不参与任何玩法判定。
var pose_lock_enabled := false
var pose_lock_phase := 0.0

func bind(avatar: Node3D) -> void:
	_version = str(avatar.get_meta("assembly_version", "v009"))
	var path := LIBRARY_PATH.replace("v009", _version)
	if _version == "v021":
		path = CURRENT_LIBRARY_PATH
	_cache = _load_library(path)
	library_version = str(_cache.get("version", _version))
	var cache_clips: Dictionary = _cache.get("clips", {})
	_fallback = _load_library(LIBRARY_PATH) if not cache_clips.has("dead") else _cache
	_nodes = {"root": avatar.visual_root, "body": avatar.body, "head": avatar.head, "feet": avatar.feet,
		"hand_l": avatar.bunny_hand_l, "hand_r": avatar.bunny_hand_r,
		"foot_l": avatar.foot_l, "foot_r": avatar.foot_r,
		"ear_l": avatar.ear_socket_l, "ear_r": avatar.ear_socket_r,
		"weapon_socket": avatar.weapon_socket}
	_weapon_socket_rest = avatar.weapon_socket.transform

static func _load_library(path: String) -> Dictionary:
	if not _libraries.has(path) and FileAccess.file_exists(path):
		var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if decoded is Dictionary and int(decoded.get("schema", 0)) in [1, 2]:
			_libraries[path] = decoded
	return _libraries.get(path, {})

func apply(avatar: Node3D, delta: float) -> void:
	var state: String = avatar.get("_state")
	var family := str(avatar.get("_weapon_class"))
	var armed := bool(avatar.get("_weapon_grip_pose_active")) and family in ["sidearm", "longgun", "machinegun"]
	var clips: Dictionary = _cache.get("clips", {})
	var locomotion_name := state
	var planar_speed := 0.0
	var world_velocity := Vector3.ZERO
	if state == "moving" and avatar.get("_player") != null:
		var owner: Node = avatar.get("_player")
		var parameters: Dictionary = owner.call("get_locomotion_presentation_snapshot") if owner.has_method("get_locomotion_presentation_snapshot") else {}
		var velocity: Variant = parameters.get("world_velocity", owner.get("velocity"))
		if velocity is Vector3:
			world_velocity = velocity
			planar_speed = Vector2(velocity.x, velocity.z).length()
			if planar_speed > 0.05 and planar_speed < 3.2 and clips.has("walking"):
				locomotion_name = "walking"
	var armed_name := "armed_" + locomotion_name
	var clip_name := armed_name if armed and locomotion_name in ["idle", "moving", "walking"] and clips.has(armed_name) else locomotion_name
	speed_role = locomotion_name
	fallback_reason = "none"
	var firing := armed and bool(avatar.get("_firing_animation_active"))
	var weapon_id := str(avatar.get("_equipped_gun_id"))
	if not armed or state not in ["idle", "moving"] or bool(avatar.get("_reload_animation_active")) or weapon_id != _fire_weapon_id:
		_fire_hold_remaining = 0.0
	_fire_weapon_id = weapon_id
	if armed and state in ["idle", "moving"] and not bool(avatar.get("_reload_animation_active")):
		_fire_hold_remaining = 0.16 if firing else maxf(0.0, _fire_hold_remaining - delta)
	if clips.has("sidearm_moving_forward") and state in ["idle", "moving"]:
		var pose_family := family if armed else "unarmed"
		if state == "moving":
			var local_velocity: Vector3 = avatar.visual_root.global_basis.orthonormalized().inverse() * world_velocity
			movement_direction = select_direction(local_velocity, movement_direction)
			clip_name = "%s_%s_%s" % [pose_family, locomotion_name, movement_direction]
		else:
			clip_name = "%s_idle" % family if armed else "idle"
		if armed and _fire_hold_remaining > 0.0:
			var fire_clip := "%s_fire_%s_%s" % [family, locomotion_name, movement_direction] if state == "moving" else family + "_fire_idle"
			if clips.has(fire_clip):
				clip_name = fire_clip
			else:
				fallback_reason = "missing_" + fire_clip
		if not clips.has(clip_name):
			fallback_reason = "missing_" + clip_name
			clip_name = locomotion_name
	if family == "heavy_melee":
		fallback_reason = "single_hand_attachment_only"
	var authored_anatomical := int(_cache.get("schema", 0)) == 2 and clips.has(clip_name)
	var reload_now := armed and bool(avatar.get("_reload_animation_active")) and state in ["idle", "moving", "seated"]
	var switch_now := false
	if avatar.get("_player") != null and avatar.get("_player").has_method("get_weapon_transition_snapshot"):
		switch_now = bool(avatar.get("_player").call("get_weapon_transition_snapshot").get("active", false))
	if (_switch_was_active and not switch_now) or (_reload_was_active and not reload_now):
		_transition_pose = _last_pose.duplicate(true)
		_transition_time = 0.0
		_transition_duration = 0.12
	_switch_was_active = switch_now
	_reload_was_active = reload_now
	if not clips.has(clip_name):
		clips = _fallback.get("clips", {})
		authored_anatomical = false
	if not clips.has(clip_name):
		return
	if _state != clip_name:
		var previous_clip: Dictionary = clips.get(_state, {})
		var old_phase := fposmod(_time / maxf(float(previous_clip.get("duration", 1.0)), 0.001), 1.0)
		var preserve_phase := state == "moving" and ("_walking_" in _state or "_moving_" in _state)
		_time = old_phase * float(clips[clip_name].duration) if preserve_phase else 0.0
		_state = clip_name
		_transition_pose = _last_pose.duplicate(true)
		_transition_time = 0.0
		_transition_duration = 0.06 if "_fire_" in clip_name else 0.18
	_transition_time += delta
	var clip: Dictionary = clips[clip_name]
	var duration: float = clip.duration
	var rate := 1.0
	if state == "moving" and avatar.get("_player") != null:
		var walking_clip := locomotion_name == "walking"
		rate = clampf(planar_speed / (2.4 if walking_clip else 5.0), 0.72, 1.18)
		if not walking_clip:
			rate *= RUN_CLIP_RATE_SCALE
	_time += delta * rate
	playback_rate = rate
	reference_speed_mps = float(clip.get("reference_speed_mps", 0.0))
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
	if pose_lock_enabled:
		phase = clampf(pose_lock_phase, 0.0, 1.0)
	var frames: Array = clip.frames
	var switch_snapshot: Dictionary = {}
	var switch_frames: Array = []
	var switch_cursor := 0.0
	active_overlay = ""
	overlay_progress = 0.0
	if reload_now and not switch_now:
		var reload_name := family + "_reload"
		if clips.has(reload_name):
			switch_frames = clips[reload_name].frames
			overlay_progress = clampf(float(avatar.get("_reload_progress")), 0.0, 1.0)
			switch_cursor = overlay_progress * (switch_frames.size() - 1)
			active_overlay = reload_name
		else:
			fallback_reason = "missing_" + reload_name
	if avatar.get("_player") != null and avatar.get("_player").has_method("get_weapon_transition_snapshot"):
		switch_snapshot = avatar.get("_player").call("get_weapon_transition_snapshot")
		if bool(switch_snapshot.get("active", false)) and state in ["idle", "moving", "seated"]:
			var switch_name := "%s_%s_slot%d" % [switch_snapshot.family, switch_snapshot.phase, switch_snapshot.slot]
			if clips.has(switch_name):
				switch_frames = clips[switch_name].frames
				switch_cursor = float(switch_snapshot.progress) * (switch_frames.size() - 1)
				active_overlay = switch_name
				overlay_progress = float(switch_snapshot.progress)
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
		var switching_track := not switch_frames.is_empty() and bone in ["hand_l", "hand_r", "weapon_socket"]
		if not frames[first].has(bone) and not switching_track: continue
		var a: Dictionary = frames[first].get(bone, {})
		var b: Dictionary = frames[second].get(bone, {})
		var track_blend := blend
		if switching_track:
			var switch_first := mini(int(switch_cursor), switch_frames.size() - 1)
			var switch_second := mini(switch_first + 1, switch_frames.size() - 1)
			a = switch_frames[switch_first][bone]
			b = switch_frames[switch_second][bone]
			track_blend = switch_cursor - switch_first
		var aim_yaw := target.rotation.y
		var position := _vector(a.p).lerp(_vector(b.p), track_blend)
		var rotation := _quaternion(a.q).slerp(_quaternion(b.q), track_blend)
		var scaling := _vector(a.s).lerp(_vector(b.s), track_blend)
		if authored_anatomical and _transition_pose.has(bone) and not switching_track:
			var weight := smoothstep(0.0, 1.0, minf(_transition_time / _transition_duration, 1.0))
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
		# Carry socket orientation is exported from Blender; no hand overrides.
		if (frames[first].has("weapon_socket") or not switch_frames.is_empty()) and live_grip_active:
			# Keep the sampled palm fixed through quaternion transition blending.
			avatar.weapon_socket.global_position = palm_global(avatar, "r")
		else:
			avatar.weapon_socket.transform = _weapon_socket_rest
			if live_grip_active:
				avatar.weapon_socket.global_position = avatar.bunny_hand_r.global_position
		_last_pose["weapon_socket"] = {"p": avatar.weapon_socket.position, "q": avatar.weapon_socket.quaternion, "s": avatar.weapon_socket.scale}
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

func palm_global(avatar: Node3D, side: String) -> Vector3:
	var node: Node3D = avatar.bunny_hand_l if side == "l" else avatar.bunny_hand_r
	var offsets: Dictionary = _cache.get("palm_offsets", {})
	return node.to_global(_vector(offsets[side])) if offsets.has(side) else node.global_position

func has_palm_offsets() -> bool:
	return not (_cache.get("palm_offsets", {}) as Dictionary).is_empty()

static func _quaternion(value: Array) -> Quaternion:
	return Quaternion(value[0], value[1], value[2], value[3]).normalized()

static func select_direction(local_velocity: Vector3, previous := "forward") -> String:
	var flat := Vector2(local_velocity.x, local_velocity.z)
	if flat.length() < 0.05:
		return previous
	var scores := {"forward": -flat.y, "backward": flat.y, "strafe_left": -flat.x, "strafe_right": flat.x}
	var selected := "forward"
	for direction: String in scores:
		if float(scores[direction]) > float(scores[selected]):
			selected = direction
	if scores.has(previous) and float(scores[previous]) > 0.0 and float(scores[selected]) - float(scores[previous]) < flat.length() * 0.10:
		return previous
	return selected
