class_name PlatformSentinelEncounter3D
extends Node3D

signal health_changed(current: int, maximum: int, phase: int)
signal defeated
signal checkpoint(reason: String)

const TAKEOVER := "nar_main_032_platform_takeover"
const ARM_HP := 2200
const TOTAL_HP := ARM_HP * 4
const SLAM_RADIUS := 3.05
const SLAM_CLIP_END := 80.0 / 30.0
const SLAM_HOLD_POSE := 47.0 / 30.0
const SLAM_RESPONSE := 1.2
const SLAM_END := 3.12
const ARM_COOLDOWN := 6.5
const RACKS_PER_SIDE := 4
const GUN_RANGE := 33.0
const BULLET_SPEED := 8.4
const PELLET_SPEED := 7.4
const BURST_TIMES := [0.90, 1.30, 1.70, 2.25]
const CROSS_TIMES := [1.05, 2.55]
const VOLLEY_TIMES := [1.10, 2.60, 4.10]
const CROSS_COOLDOWN := 14.0
const VOLLEY_COOLDOWN := 24.0
const SPREAD := [-7.0, -3.5, 0.0, 3.5, 7.0]
const CROSS_SPREAD := [-5.0, 0.0, 5.0]
const GUN_YAW_LIMIT := 0.48
const GUN_COOLDOWN := 5.0
const AUTHORED_FIRE := 20.0 / 30.0
const PORT_OFFLINE := 5.0
const PORT_REARM := 7.0
const SHUTDOWN_TIME := 0.6
const SIDE_LABELS := ["入口", "东", "后", "西"]
const MONITOR_VISUAL := preload("res://assets/art/enemies/bosses/enm_boss_monitor002/runtime/enm_boss_monitor002/enm_boss_monitor002_root_top3d.tscn")
const IMPACT := 35.0 / 30.0
const REAR := 2
const FULL_DEPLOY := 3.15

enum Stage { DORMANT, TAKEOVER, DEPLOY, COMBAT, COLLAPSE, CORE, WON }
enum Barrage { NONE, BURST, CROSS, VOLLEY }

@onready var deck: PlatformSentinelDeck3D = $Deck
var stage := Stage.DORMANT
var _player: Player3D
var _director: Node
var _arm_targets: Array[PlatformSentinelWeakPoint3D] = []
var _core: MeshInstance3D
var _ports: Array[PlatformSentinelWeakPoint3D] = []
var _side_lamps: Array[Node3D] = []
var _arm_slots: Array[Array] = []
var _gun_rest_lanes: Array[Array] = []
var _arm_ready: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _gun_ready: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _armor: Array[StaticBody3D] = []
var _screen_wake_at := -1.0
var _port_ready: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _route_markers: Array[Node3D] = []
var _barrage := Barrage.NONE
var _barrage_lanes: Dictionary = {}
var _recoil_poses: Dictionary = {}
var _rounds: Array[Projectile3D] = []
var _cross_at := 12.0
var _volley_at := 22.0
var _cross_side := 0
var _next_cross_side := 0
var _gun_markers: Array[MeshInstance3D] = []
var _projectiles: ProjectilePool3D
var _grapple_meshes: Array[Array] = []
var _bridges_releasing := false
var _slam_angle := 0.0
var _next_attack_at := 0.0
var _next_scan_at := 0.0
var _prefer_palm := true
var _shutdown_clock := -1.0
var _bridge_wait := -1.0
var _outer_start := PlatformSentinelDeck3D.OUTER_START
var _inner_start := PlatformSentinelDeck3D.INNER_START
var _clock := 0.0
var _arm_clock := 0.0
var _gun_clock := 0.0
var _active_arm := -1
var _active_gun := -1
var _slam_point := Vector3.ZERO
var _slam_marker: MeshInstance3D
var _shot_index := 0
var _returning_visit := false
var _takeover_requested := false
var _rear_started := false
var _stairs_broken := false
var _sent_racks := false
var _proxy: Node3D
var _proxy_attached := false
var _voice: Node
var _last_broken := 0

func _ready() -> void:
	set_physics_process(false)
	for i in range(deck.grapples.size()):
		var arm := deck.grapples[i]
		var target := _new_target(ARM_HP, 0.98)
		var arm_local := deck.to_local(arm.global_position)
		var radial := Basis(Vector3.UP, arm.rotation.y) * Vector3.FORWARD
		var point := arm_local + radial * 7.1
		target.position = Vector3(clampf(point.x, -10.25, 10.25), 1.02, clampf(point.z, -10.25, 10.25))
		target.name = "GrappleRelay_%02d" % (i + 1)
		target.damaged.connect(_on_target_damaged.bind(target))
		target.destroyed.connect(_on_arm_destroyed.bind(i))
		target.add_wrist()
		_arm_targets.append(target)
		_add_side_controls(i, target, radial)
	_prepare_attack_poses()
	var switch_mesh := BoxMesh.new()
	switch_mesh.size = Vector3(0.62, 0.96, 0.42)
	_core = MeshInstance3D.new()
	_core.name = "CentralCutoff"
	_core.mesh = PlatformSentinelDeck3D.palette_mesh(switch_mesh, Vector2(0.45, 0.25))
	_core.material_override = PlatformSentinelDeck3D.BRIDGE_LAMP
	_core.position = Vector3(0, 0.52, -0.55)
	add_child(_core)
	_core.hide()
	add_to_group("interaction_provider_3d")

func bind(player: Player3D, director: Node, rematch: bool) -> void:
	_player = player
	_projectiles = get_tree().get_first_node_in_group("projectile_pool_3d") as ProjectilePool3D
	_returning_visit = rematch
	if is_instance_valid(director) and _director != director:
		_director = director
		_director.narrative_finished.connect(_on_narrative_finished)
	set_physics_process(true)

func is_pending() -> bool:
	return stage > Stage.DORMANT and stage < Stage.WON or (stage == Stage.DORMANT and _returning_visit)

func monitor_defeated(enemy: Enemy3D) -> void:
	if stage != Stage.DORMANT:
		return
	var pose := enemy.avatar.global_transform
	_proxy = enemy.avatar.duplicate(0) as Node3D
	add_child(_proxy)
	_proxy.global_transform = pose
	stage = Stage.TAKEOVER
	_clock = 0.0
	_takeover_requested = false
	_takeover_safe_position()
	checkpoint.emit("platform_takeover_pending")

func run_cue(cue: String, params: Dictionary) -> bool:
	if stage != Stage.TAKEOVER:
		return false
	match cue:
		"voice":
			_stop_voice()
			var id := str(params.get("event_id", ""))
			var source := _proxy if id.contains(".monitor_") and is_instance_valid(_proxy) else self
			var point := source.global_position if source == _proxy else to_global(Vector3(0.0, 1.0, -9.0))
			_voice = AudioManager.emit_event(id, {
				"source_node": source, "source_position": point, "spatial_mode": "world_3d",
				"max_distance": 48.0, "unit_size": 14.0, "volume_db": -1.5,
			})
		"rear":
			_start_rear()
		"reach":
			_start_rear()
			AudioManager.play_sfx("door_open", -8.0, 0.71)
			var rear := deck.grapples[REAR]
			deck.play(rear, "attack_grapple_slam", 0.0, IMPACT)
			var contact := _palm_world(REAR)
			deck.play(rear, "attack_grapple_slam")
			if is_instance_valid(_proxy):
				var tween := create_tween()
				tween.tween_property(_proxy, "global_position", contact, IMPACT).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		"grab":
			AudioManager.play_sfx("melee_impact", -9.0, 0.78)
			_proxy_attached = true
			deck.play(deck.grapples[REAR], "attack_grapple_slam", -0.95, IMPACT + 0.36)
		"throw":
			_throw_monitor()
		"ignite":
			_screen_wake_at = _clock
			deck.wake_screens(0.0)
		_:
			return false
	return true

func _start_rear() -> void:
	if _rear_started:
		return
	_rear_started = true
	deck.play(deck.grapples[REAR], "activate_grapple")
	_fx(VfxPool3D.FX01_METAL_SPARK_HIT, deck.grapples[REAR].global_position + Vector3.UP * 5.0, 2.5)

func _throw_monitor() -> void:
	_proxy_attached = false
	if not is_instance_valid(_proxy):
		return
	if _proxy.is_queued_for_deletion() or _proxy.has_meta("falling"):
		return
	_proxy.set_meta("falling", true)
	var tween := create_tween().set_parallel()
	var out := deck.to_global(Vector3(-5.5, -15.0, -24.0))
	tween.tween_property(_proxy, "global_position", out, 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_proxy, "rotation", _proxy.rotation + Vector3(2.4, 1.2, 2.8), 0.85)
	tween.chain().tween_callback(_proxy.queue_free)

func _on_narrative_finished(id: String, reason: String) -> void:
	if id != TAKEOVER or stage != Stage.TAKEOVER:
		return
	_stop_voice()
	if reason in ["flow.end", "duration", "skip"]:
		_throw_monitor()
		_deploy()
	else:
		_takeover_requested = false
		_screen_wake_at = -1.0
		deck.set_screens(0.0, 0.0)
		_clock = 0.0

func _stop_voice() -> void:
	if is_instance_valid(_voice):
		_voice.queue_free()
	_voice = null


func _exit_tree() -> void:
	_cancel_rounds()
	_stop_voice()


func _takeover_safe_position() -> void:
	if not is_instance_valid(_player):
		return
	var local := to_local(_player.global_position)
	if absf(local.x) > 10.0 or absf(local.z) > 10.0 or local.y > 2.0:
		_player.global_position = to_global(Vector3(0.0, 0.08, 4.0))
		_player.velocity = Vector3.ZERO

func _deploy() -> void:
	_takeover_safe_position()
	stage = Stage.DEPLOY
	_clock = 0.0
	if _screen_wake_at < 0.0:
		deck.wake_screens(0.0)
	else:
		deck.set_screens(0.0)
	for i in range(deck.grapples.size()):
		var clip := "idle_grapple" if i == REAR and _rear_started else "activate_grapple"
		deck.play(deck.grapples[i], clip)
	_rear_started = true
	for i in range(deck.sentries.size()):
		var rack := deck.sentries[i]
		deck.play(rack, "activate_sentry")
		deck.delay_animation(rack, floori(float(i) / RACKS_PER_SIDE) * 0.14)
	_emit_health()
	checkpoint.emit("platform_deploy")

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player) or _player.current_hp <= 0:
		return
	var here := to_local(_player.global_position)
	if stage == Stage.DORMANT:
		if _returning_visit and absf(here.x) < 11.0 and absf(here.z) < 11.0 and absf(here.y) < 1.6:
			_deploy()
		return
	if here.y < -8.5 and absf(here.x) < 39.5 and absf(here.z) < 72.0:
		_player.notify_attacked_by(self)
		if stage != Stage.DORMANT:
			_player.take_damage(_player.max_hp * 4, false, Vector3.ZERO, false, 0.0, true)
		return
	if stage == Stage.WON:
		return
	_clock += delta
	match stage:
		Stage.TAKEOVER:
			if _screen_wake_at >= 0.0:
				deck.wake_screens(_clock - _screen_wake_at)
			if _proxy_attached and is_instance_valid(_proxy):
				_proxy.global_position = _palm_world(REAR) + Vector3.DOWN * 0.25
			if not _takeover_requested and _clock > 0.25:
				if is_instance_valid(_director):
					_takeover_requested = _director.play(TAKEOVER, {"priority": 32})
					if not _takeover_requested and _clock > 8.0:
						push_warning("Platform Sentinel takeover could not start; continuing encounter.")
						_throw_monitor()
						_deploy()
				elif _clock > 1.0:
					_throw_monitor()
					_deploy()
		Stage.DEPLOY:
			if _screen_wake_at < 0.0:
				deck.wake_screens(_clock)
			if _clock >= 0.72:
				_deck_link_release()
			if not _stairs_broken and _clock > 1.75:
				_break_stairs(true)
			if _clock >= FULL_DEPLOY:
				_arm_combat()
		Stage.COMBAT:
			_tick_combat(delta, here)
		Stage.COLLAPSE:
			_tick_collapse()
		Stage.CORE:
			_tick_core(delta)


func _break_stairs(animate: bool) -> void:
	if _stairs_broken:
		return
	_stairs_broken = true
	deck.break_stairs(animate)
	if animate:
		_fx(VfxPool3D.FX01_EXPLOSION, to_global(Vector3(0, 0.45, 14.5)), 2.9)


func _deck_link_release() -> void:
	if not _bridges_releasing:
		_bridges_releasing = true
		for side in [-1.0, 1.0]:
			_fx(VfxPool3D.FX01_METAL_SPARK_HIT, to_global(Vector3(side * 12.54, 0.38, 0.0)), 1.25)
		AudioManager.play_sfx("door_open", -7.0, 0.68)
	var motion := smoothstep(0.95, 2.65, _clock)
	deck.set_bridge_retraction(motion, motion)


func _arm_combat() -> void:
	deck.set_bridge_retraction(1.0, 1.0)
	stage = Stage.COMBAT
	_clock = 0.0
	_next_attack_at = 1.15
	_next_scan_at = 0.0
	_active_arm = -1
	_active_gun = -1
	_cross_at = 12.0
	_volley_at = 22.0
	_next_cross_side = 0
	_prefer_palm = true
	_arm_ready.fill(0.0)
	_gun_ready.fill(0.0)
	_port_ready.fill(0.0)
	for i in range(deck.grapples.size()):
		var alive := _arm_targets[i].current_hp > 0
		deck.play(deck.grapples[i], "idle_grapple" if alive else "death_grapple", 1.0 if alive else 0.0, 0.0 if alive else 2.16)
		_arm_targets[i].set_open(alive)
		_side_lamps[i].visible = alive
		_arm_targets[i].get_node("SideMark").visible = alive
	for rack in deck.sentries:
		deck.play(rack, "idle_sentry")
	for shell in _armor:
		shell.set_deferred("collision_layer", 4)
	deck.set_screens(0.0 if _arms_alive() > 2 else 1.0, 0.62)
	_emit_health()
	checkpoint.emit("platform_combat")


func _tick_combat(delta: float, here: Vector3) -> void:
	for i in range(_ports.size()):
		if _ports[i].current_hp == 0 and _clock >= _port_ready[i] - PORT_REARM:
			_ports[i].current_hp = 1
			for rack in _side_racks(i):
				deck.play(rack, "idle_sentry")
	if _active_arm >= 0:
		_tick_slam(delta, here)
		return
	if _barrage != Barrage.NONE:
		_tick_gun(delta)
		return
	if not _rounds.is_empty() or _clock < _next_attack_at or maxf(absf(here.x), absf(here.z)) >= 12.48 or absf(here.y) > 1.6:
		return
	if _projectiles != null:
		if _arms_alive() <= 2 and _clock >= _volley_at and _start_pattern(Barrage.VOLLEY):
			return
		if (_arms_alive() <= 3 or _clock >= 20.0) and _clock >= _cross_at and _start_pattern(Barrage.CROSS):
			return
	if _prefer_palm and _start_slam():
		return
	if _projectiles != null and _start_gun():
		return
	if not _prefer_palm and _start_slam():
		return
	if _clock >= _next_scan_at:
		for i in range(_arm_targets.size()):
			if _arm_targets[i].current_hp > 0:
				deck.play(deck.grapples[i], "scan_grapple")
				break
		_next_scan_at = _clock + 1.4
	_next_attack_at = _clock + 0.18


func _next_attack_gap() -> float:
	return 3.25 if _arms_alive() > 2 else 2.95


func _start_slam() -> bool:
	var best_age := INF
	var best: Dictionary = {}
	for i in range(_arm_targets.size()):
		if _arm_targets[i].current_hp <= 0 or _arm_ready[i] > _clock:
			continue
		var candidate := _closest_slam_slot(i, _player.global_position)
		if not candidate.is_empty() and _arm_ready[i] < best_age:
			_active_arm = i
			best = candidate
			best_age = _arm_ready[i]
	if _active_arm < 0:
		return false
	_arm_ready[_active_arm] = _clock + ARM_COOLDOWN
	_next_attack_at = _clock + _next_attack_gap()
	_prefer_palm = false
	_arm_clock = 0.0
	_slam_angle = float(best.angle)
	_slam_point = _predicted_palm(_active_arm, _slam_angle)
	_slam_point.y = global_position.y + 0.036
	_slam_marker = _circle_warning(_slam_point)
	_play_slam_pose()
	var windup := _palm_world(_active_arm)
	_fx(VfxPool3D.FX01_METAL_SPARK_HIT, windup, 0.75)
	AudioManager.play_sfx("door_open", -11.0, 0.74)
	return true


func _closest_slam_slot(index: int, where: Vector3) -> Dictionary:
	var best := SLAM_RADIUS - 0.12
	var match_slot: Dictionary = {}
	for slot in _arm_slots[index]:
		var point: Vector3 = slot.point
		var distance := (where - to_global(point)).slide(Vector3.UP).length()
		if distance <= best:
			best = distance
			match_slot = slot
	return match_slot


func _predicted_palm(index: int, angle: float) -> Vector3:
	var outer: Dictionary = _arm_slots[index][0]
	var pivot: Vector3 = outer.pivot
	var point: Vector3 = outer.point
	return to_global(pivot + (point - pivot).rotated(Vector3.UP, angle))


func _play_slam_pose() -> void:
	var arm := deck.grapples[_active_arm]
	var rig := deck.skeleton_for(arm)
	rig.clear_bones_global_pose_override()
	var time := _arm_clock
	if time > SLAM_HOLD_POSE:
		var release := IMPACT + SLAM_RESPONSE
		var blend := clampf(inverse_lerp(release, SLAM_END, time), 0.0, 1.0)
		time = lerpf(SLAM_HOLD_POSE, SLAM_CLIP_END, blend)
	deck.play(arm, "attack_grapple_slam", 0.0, time)
	_yaw_arm(arm, _slam_angle)
	_update_grapple_visibility()


func _yaw_arm(arm: Node3D, angle: float) -> void:
	var rig := deck.skeleton_for(arm)
	var shoulder := rig.find_bone("shoulder")
	var pose := rig.get_bone_global_pose(shoulder)
	var axis := rig.global_basis.inverse() * Vector3.UP
	pose.basis = Basis(axis.normalized(), angle) * pose.basis
	rig.set_bone_global_pose_override(shoulder, pose, 1.0, true)
	deck.sync_skeleton(arm)


func _update_grapple_visibility() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var anchor := deck.grapples[_active_arm].global_position
	var outward := (anchor - global_position).slide(Vector3.UP).normalized()
	var foreground := (camera.global_position - _player.global_position).slide(Vector3.UP).dot(outward) > 0.5
	var near := (anchor - _player.global_position).slide(Vector3.UP).length() < 8.5
	for mesh: GeometryInstance3D in _grapple_meshes[_active_arm]:
		mesh.transparency = 0.77 if foreground and near else 0.0


func _tick_slam(delta: float, here: Vector3) -> void:
	var before := _arm_clock
	_arm_clock = minf(_arm_clock + delta, SLAM_END)
	if _arm_clock < IMPACT - 0.35:
		var desired := _closest_slam_slot(_active_arm, _player.global_position)
		if not desired.is_empty():
			_slam_angle = move_toward(_slam_angle, float(desired.angle), 1.6 * delta)
		_slam_point = _predicted_palm(_active_arm, _slam_angle)
		_slam_point.y = global_position.y + 0.036
		_slam_marker.global_position = _slam_point
	_play_slam_pose()
	if before < IMPACT and _arm_clock >= IMPACT:
		_resolve_slam(here)
	if _active_arm < 0:
		return
	if _arm_clock >= IMPACT and _arm_clock <= IMPACT + SLAM_RESPONSE:
		var point := _palm_world(_active_arm) + Vector3.UP * 0.82
		_arm_targets[_active_arm].expose_wrist(point)
	elif before <= IMPACT + SLAM_RESPONSE and _arm_clock > IMPACT + SLAM_RESPONSE:
		_arm_targets[_active_arm].hide_wrist()
	if _arm_clock >= SLAM_END:
		_finish_slam(true)


func _finish_slam(standby: bool) -> void:
	if _active_arm < 0:
		return
	var arm := deck.grapples[_active_arm]
	deck.skeleton_for(arm).clear_bones_global_pose_override()
	_arm_targets[_active_arm].hide_wrist()
	for mesh: GeometryInstance3D in _grapple_meshes[_active_arm]:
		mesh.transparency = 0.0
	if standby:
		deck.play(arm, "idle_grapple")
	_active_arm = -1
	if is_instance_valid(_slam_marker):
		_slam_marker.queue_free()
	_slam_marker = null


func _resolve_slam(here: Vector3) -> void:
	if is_instance_valid(_slam_marker):
		_slam_marker.queue_free()
	_slam_marker = null
	_fx(VfxPool3D.FX01_MELEE_IMPACT, _slam_point + Vector3.UP * 0.1, 3.8)
	_fx(VfxPool3D.FX01_IMPACT, _slam_point + Vector3.UP * 0.38, 2.15)
	AudioManager.play_sfx("melee_impact", -2.0, 0.76)
	if _player.camera_feedback != null:
		var strength := clampf(1.0 - _player.global_position.distance_to(_slam_point) / 17.0, 0.0, 1.0)
		_player.camera_feedback.request_environment_impact(strength, 0.19)
	_next_attack_at = maxf(_next_attack_at, _clock + SLAM_RESPONSE)
	var offset := _player.global_position - _slam_point
	if offset.slide(Vector3.UP).length() < SLAM_RADIUS and offset.y > -0.25 and offset.y < 1.9:
		var rim := maxf(absf(here.x), absf(here.z)) > 10.45
		_hit_player(24, Vector3.ZERO if rim else offset.normalized(), 0.0 if rim else 3.1)


func _start_gun() -> bool:
	var best := INF
	var target := _player.global_position
	var choice := -1
	for i in range(deck.sentries.size()):
		var side := floori(float(i) / RACKS_PER_SIDE)
		if _gun_ready[side] > _clock or _ports[side].current_hp == 0:
			continue
		var lane := _gun_rest_lanes[i]
		var base := to_global(lane[0])
		var forward := base.direction_to(to_global(lane[1]))
		var delta := (target - base).slide(Vector3.UP)
		var distance := delta.length()
		var direction := delta.normalized()
		var angle := forward.angle_to(direction)
		var score := angle * 14.0 + distance * 0.07
		if distance < 0.8 or distance > GUN_RANGE - 1.0 or angle > GUN_YAW_LIMIT or score >= best:
			continue
		var at_height := Vector3(target.x, base.y, target.z)
		if not _obstruction(base, at_height).is_empty():
			continue
		best = score
		choice = i
	if choice < 0:
		return false
	if not _prime_rack(choice, target):
		return false
	_active_gun = choice
	_begin_barrage(Barrage.BURST)
	return true


func _start_pattern(pattern: Barrage) -> bool:
	_cross_side = _next_cross_side
	for index in range(deck.sentries.size()):
		var side := _side_of(index)
		if _ports[side].current_hp == 0 or (pattern == Barrage.CROSS and side != _cross_side and side != (_cross_side + 2) % 4):
			continue
		var base := to_global(_gun_rest_lanes[index][0])
		var offset := to_local(base)
		var inward := Vector3(-signf(offset.x), 0.0, 0.0) if absf(offset.x) > absf(offset.z) else Vector3(0.0, 0.0, -signf(offset.z))
		_prime_rack(index, base + global_basis * inward * 26.0)
	if _barrage_lanes.is_empty():
		return false
	if pattern == Barrage.CROSS:
		_cross_at = _clock + CROSS_COOLDOWN
		_next_cross_side = (_next_cross_side + 1) % 4
	else:
		_volley_at = _clock + VOLLEY_COOLDOWN
	_begin_barrage(pattern)
	return true


func _prime_rack(index: int, target: Vector3) -> bool:
	var rack := deck.sentries[index]
	deck.play(rack, "attack_sentry", 0.0, AUTHORED_FIRE)
	_aim_sentry(rack, target)
	var lane := _shot_lane(rack)
	if lane.is_empty():
		_reset_gun_pose(rack)
		return false
	if not _obstruction(lane[0], lane[0].move_toward(lane[1], 1.0)).is_empty():
		_reset_gun_pose(rack)
		return false
	_barrage_lanes[index] = lane
	var rig := deck.skeleton_for(rack)
	_recoil_poses[index] = rig.get_bone_global_pose(rig.find_bone("recoil"))
	return true


func _begin_barrage(pattern: Barrage) -> void:
	_barrage = pattern
	_gun_clock = 0.0
	_shot_index = 0
	_prefer_palm = true
	_next_attack_at = _clock + _next_attack_gap()
	for index: int in _barrage_lanes:
		_gun_ready[_side_of(index)] = _clock + GUN_COOLDOWN
	_warn_barrage()


func _side_of(index: int) -> int:
	return floori(float(index) / RACKS_PER_SIDE)


func _warn_barrage() -> void:
	_clear_gun_warning()
	var announced: Array[int] = []
	for index: int in _barrage_lanes:
		var side := _side_of(index)
		if _barrage == Barrage.CROSS and side != (_cross_side + 2 * _shot_index) % 4:
			continue
		if _ports[side].current_hp == 0:
			continue
		var lane: Array[Vector3] = _barrage_lanes[index]
		if _barrage == Barrage.BURST and _shot_index == 3:
			for angle in [-7.0, 7.0]:
				var edge := lane[0] + (lane[1] - lane[0]).rotated(Vector3.UP, deg_to_rad(angle))
				_gun_markers.append(_gun_warning([lane[0], edge], true))
		else:
			_gun_markers.append(_gun_warning(lane, _barrage != Barrage.BURST))
		if not announced.has(side):
			announced.append(side)
			if _clock >= _port_ready[side]:
				_ports[side].set_open(true)
			AudioManager.emit_event("combat.weapon.reload_start", {"gun_id": "bp_rifle", "source_position": lane[0], "max_distance": 32.0, "unit_size": 7.0, "volume_db": -10.0})


func _clear_gun_warning() -> void:
	for marker in _gun_markers:
		marker.queue_free()
	_gun_markers.clear()
	for port in _ports:
		port.set_open(false)


func _aim_sentry(rack: Node3D, target: Vector3) -> void:
	var rig := deck.skeleton_for(rack)
	var aim_bone := rig.find_bone("gimbal_pitch")
	var pose := rig.get_bone_global_pose(aim_bone)
	var pivot := rig.to_global(pose.origin)
	var muzzle := deck.socket(rack, "muzzle_exit")
	var forward := deck.socket(rack, "muzzle_forward")
	var axis := muzzle.global_position.direction_to(forward.global_position)
	var aim := (target - pivot).slide(Vector3.UP).normalized()
	var correction := Basis(Quaternion(axis, aim))
	pose.basis = rig.global_basis.inverse() * correction * rig.global_basis * pose.basis
	rig.set_bone_global_pose_override(aim_bone, pose, 1.0, true)
	deck.sync_skeleton(rack)


func _tick_gun(delta: float) -> void:
	_gun_clock += delta
	var times: Array = BURST_TIMES
	match _barrage:
		Barrage.CROSS:
			times = CROSS_TIMES
		Barrage.VOLLEY:
			times = VOLLEY_TIMES
	if _shot_index > 0:
		var elapsed := _gun_clock - float(times[_shot_index - 1])
		if elapsed < 0.16 + delta:
			for index: int in _barrage_lanes:
				var side := _side_of(index)
				if _ports[side].current_hp == 0 or (_barrage == Barrage.CROSS and side != (_cross_side + 2 * (_shot_index - 1)) % 4):
					continue
				_set_recoil(index, maxf(0.0, 1.0 - elapsed / 0.16))
	while _shot_index < times.size() and _gun_clock >= times[_shot_index]:
		_fire_pulse()
		_shot_index += 1
		if (_barrage != Barrage.BURST and _shot_index < times.size()) or (_barrage == Barrage.BURST and _shot_index == 3):
			_warn_barrage()
	if _gun_clock >= float(times.back()) + 0.42:
		_finish_gun(true)
		_next_attack_at = maxf(_next_attack_at, _clock + 0.85)


func _set_recoil(index: int, kick: float) -> void:
	var rack := deck.sentries[index]
	var rig := deck.skeleton_for(rack)
	var lane: Array[Vector3] = _barrage_lanes[index]
	var pose: Transform3D = _recoil_poses[index]
	pose.origin -= (rig.global_basis.inverse() * lane[0].direction_to(lane[1])) * kick * 0.23
	rig.set_bone_global_pose_override(rig.find_bone("recoil"), pose, 1.0, true)
	deck.sync_skeleton(rack)


func _fire_pulse() -> void:
	var sound_played: Array[int] = []
	var spread: Array = [0.0]
	if _barrage == Barrage.CROSS:
		spread = CROSS_SPREAD
	elif _barrage == Barrage.VOLLEY or _shot_index == BURST_TIMES.size() - 1:
		spread = SPREAD
	if _barrage != Barrage.BURST or _shot_index == 0 or _shot_index == BURST_TIMES.size() - 1:
		_clear_gun_warning()
	for index: int in _barrage_lanes:
		var side := _side_of(index)
		if _ports[side].current_hp == 0 or (_barrage == Barrage.CROSS and side != (_cross_side + 2 * _shot_index) % 4):
			continue
		_set_recoil(index, 0.0)
		var lane: Array[Vector3] = _barrage_lanes[index]
		var axis := lane[0].direction_to(lane[1])
		_fx(VfxPool3D.FX01_MUZZLE_FLASH, lane[0], 1.25, {"forward": axis})
		if not sound_played.has(side):
			sound_played.append(side)
			var context := {"source_position": lane[0], "max_distance": 40.0, "unit_size": 9.0, "volume_db": -8.0}
			context["weapon_audio_profile"] = "rifle" if spread.size() == 1 else "shotgun"
			AudioManager.emit_event("combat.weapon.fire", context)
		for angle: float in spread:
			_spawn_round(lane[0], axis.rotated(Vector3.UP, deg_to_rad(angle)), spread.size() > 1)


func _spawn_round(origin: Vector3, direction: Vector3, pellet: bool) -> void:
	var flight_range := 29.0 if _barrage == Barrage.BURST else 15.8 if _barrage == Barrage.VOLLEY else 22.0
	var round := _projectiles.acquire({
		"shooter": self, "direction": direction, "speed": PELLET_SPEED if pellet else BULLET_SPEED,
		"range": flight_range, "damage": (5 if _barrage == Barrage.VOLLEY else 6) if pellet else 8,
		"hostile": true, "target_group": "player_3d", "projectile_collision_mask": 1,
		"visual_scale": 1.60 if not pellet else 1.43, "billboard": false, "hit_knockback": 0.0,
		"color": Color("#ffc04f") if pellet else Color("#ff7150"), "visual_id": "mod_bullet_standard",
	}, origin)
	_rounds.append(round)
	round.retired.connect(_on_barrage_round_retired, CONNECT_ONE_SHOT)


func _on_barrage_round_retired(round: Projectile3D) -> void:
	_rounds.erase(round)


func _cancel_rounds() -> void:
	for round: Projectile3D in _rounds.duplicate():
		if is_instance_valid(round):
			round.cancel()
	_rounds.clear()


func _shot_lane(rack: Node3D) -> Array[Vector3]:
	var muzzle := deck.socket(rack, "muzzle_exit")
	var forward := deck.socket(rack, "muzzle_forward")
	if muzzle == null or forward == null:
		return []
	var from := muzzle.global_position
	var direction := (forward.global_position - from).slide(Vector3.UP).normalized()
	return [from, from + direction * GUN_RANGE]


func _obstruction(from: Vector3, to: Vector3) -> Dictionary:
	var ray := PhysicsRayQueryParameters3D.create(from, to, 1, [_player.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(ray)


func _reset_gun_pose(rack: Node3D) -> void:
	deck.skeleton_for(rack).clear_bones_global_pose_override()
	deck.play(rack, "idle_sentry")


func _finish_gun(standby: bool) -> void:
	for index: int in _barrage_lanes:
		var rack := deck.sentries[index]
		if standby and _ports[_side_of(index)].current_hp > 0:
			_reset_gun_pose(rack)
		else:
			deck.skeleton_for(rack).clear_bones_global_pose_override()
	_active_gun = -1
	_barrage = Barrage.NONE
	_barrage_lanes.clear()
	_recoil_poses.clear()
	_clear_gun_warning()


func _side_racks(side: int) -> Array[Node3D]:
	return deck.sentries.slice(side * RACKS_PER_SIDE, (side + 1) * RACKS_PER_SIDE)


func _suppress_side(side: int) -> void:
	if stage != Stage.COMBAT or _barrage == Barrage.NONE:
		return
	_port_ready[side] = _clock + PORT_OFFLINE + PORT_REARM
	_gun_ready[side] = maxf(_gun_ready[side], _clock + PORT_OFFLINE)
	for rack in _side_racks(side):
		deck.skeleton_for(rack).clear_bones_global_pose_override()
		deck.play(rack, "servo_pause_sentry", 0.0, 0.41)
	if _barrage == Barrage.BURST:
		_finish_gun(false)
		_shot_index = 0
	else:
		_warn_barrage()
	_fx(VfxPool3D.FX01_METAL_SPARK_HIT, _ports[side].global_position, 1.6)
	AudioManager.play_sfx("door_locked", -6.0)


func _on_arm_destroyed(index: int) -> void:
	if _active_arm == index:
		_finish_slam(false)
	deck.play(deck.grapples[index], "death_grapple")
	_fx(VfxPool3D.FX01_EXPLOSION, _arm_targets[index].global_position, 2.65)
	_side_lamps[index].hide()
	_arm_targets[index].get_node("SideMark").hide()
	var live := _arms_alive()
	deck.set_screens(0.0 if live > 2 else 1.0, 0.62)
	if live == 0:
		_begin_collapse()
	else:
		_next_attack_at = maxf(_next_attack_at, _clock + 0.85)
	checkpoint.emit("platform_arm_disabled")


func _begin_collapse(announce := true) -> void:
	_finish_slam(false)
	_finish_gun(false)
	_cancel_rounds()
	for shell in _armor:
		shell.set_deferred("collision_layer", 0)
	stage = Stage.COLLAPSE
	_clock = 0.0
	_outer_start = PlatformSentinelDeck3D.OUTER_START
	_inner_start = PlatformSentinelDeck3D.INNER_START
	if is_instance_valid(_player):
		var slow_speed := _player.get_move_speed()
		# 角到下一圈内侧留出胶囊和步行余量，普通配置沿用源时轴。
		var walk_budget := 5.45 * sqrt(2.0) / maxf(0.5, slow_speed) + 0.5
		_outer_start = maxf(_outer_start, walk_budget)
		_inner_start = maxf(_inner_start + _outer_start - PlatformSentinelDeck3D.OUTER_START, _outer_start + walk_budget)
	_last_broken = 0
	_sent_racks = false
	for rack in deck.sentries:
		deck.play(rack, "servo_pause_sentry")
	deck.set_screens(2.0, 0.62)
	if announce:
		_show_safe_route(7.12)
		AudioManager.play_sfx("boss_phase", -4.0)
	_emit_health()


func _tick_collapse() -> void:
	for motor in deck.sample_collapse(_clock, _outer_start, _inner_start):
		_fx(VfxPool3D.FX01_METAL_SPARK_HIT, motor, 1.7)
		_fx(VfxPool3D.FX01_EXPLOSION, motor, 1.26)
	if not _sent_racks and _clock >= _outer_start + 0.12:
		_sent_racks = true
		for rack in deck.sentries:
			deck.play(rack, "death_sentry")
		_fx(VfxPool3D.FX01_EXPLOSION, to_global(Vector3(9.0, 0.5, -8.0)), 3.6)
		AudioManager.play_sfx("door_locked", -3.0, 0.73)
		_collapse_jolt(0.58)
	if _clock >= _inner_warning_at() and _last_broken == 0:
		_last_broken = 1
		_show_safe_route(2.18)
		AudioManager.play_sfx("door_locked", -10.0, 0.84)
	if _clock >= _inner_start and _last_broken == 1:
		_last_broken = 2
		_fx(VfxPool3D.FX01_EXPLOSION, to_global(Vector3(-5.0, 0.25, 5.0)), 3.2)
		AudioManager.play_sfx("door_locked", -3.0, 0.69)
		_collapse_jolt(0.70)
		checkpoint.emit("platform_inner_ring")
	if _clock >= _collapse_finish():
		_activate_core()


func _collapse_jolt(strength: float) -> void:
	if is_instance_valid(_player) and _player.camera_feedback != null:
		_player.camera_feedback.request_environment_impact(strength, 0.25)


func _inner_warning_at() -> float:
	return _outer_start


func _collapse_finish() -> float:
	return _inner_start + (PlatformSentinelDeck3D.FINISH - PlatformSentinelDeck3D.INNER_START)


func _show_safe_route(half: float) -> void:
	_clear_safe_route()
	# 连续边界画在本轮保留侧。四个箭头的底座也落在保留区内。
	var ink := Color(0.64, 1.0, 0.88, 0.83)
	var corners := [Vector3(-half, 0.06, -half), Vector3(half, 0.06, -half), Vector3(half, 0.06, half), Vector3(-half, 0.06, half)]
	for i in range(4):
		_route_markers.append(_line(to_global(corners[i]), to_global(corners[(i + 1) % 4]), 0.12, ink))
		var heading := Vector3.FORWARD.rotated(Vector3.UP, i * PI / 2.0)
		var cross := heading.rotated(Vector3.UP, PI / 2.0)
		var tip := heading * (half - 0.8) + Vector3.UP * 0.061
		var tail := tip + heading * 0.63
		_route_markers.append(_line(to_global(tail + cross * 0.47), to_global(tip), 0.13, ink))
		_route_markers.append(_line(to_global(tail - cross * 0.47), to_global(tip), 0.13, ink))


func _clear_safe_route() -> void:
	for node in _route_markers:
		node.queue_free()
	_route_markers.clear()


func _activate_core() -> void:
	stage = Stage.CORE
	_clock = 0.0
	_shutdown_clock = -1.0
	_bridge_wait = -1.0
	_core.show()
	deck.set_center_screen(2.0, 0.34)
	_show_safe_route(2.18)
	_emit_health()
	checkpoint.emit("platform_core")


func get_interaction_candidate(actor: Player3D) -> Dictionary:
	if not _can_shutdown(actor):
		return {}
	return {
		"available": true, "interaction_id": "platform_core_shutdown",
		"position": _core.global_position, "priority": 65, "prompt": "停机",
	}


func is_interaction_dot_visible() -> bool:
	return stage == Stage.CORE and _bridge_wait < 0.0


func get_interaction_dot_anchor() -> Vector3:
	return _core.global_position + Vector3.UP * 0.32


func get_interaction_progress() -> Dictionary:
	return {
		"active": stage == Stage.CORE and _shutdown_clock >= 0.0 and _bridge_wait < 0.0,
		"progress": clampf(_shutdown_clock / SHUTDOWN_TIME, 0.0, 1.0),
	}


func perform_interaction(actor: Player3D, candidate: Dictionary) -> bool:
	if not _can_shutdown(actor) or _shutdown_clock >= 0.0 or candidate.get("interaction_id") != "platform_core_shutdown":
		return false
	_shutdown_clock = 0.0
	return true


func _can_shutdown(actor: Player3D) -> bool:
	if stage != Stage.CORE or _bridge_wait >= 0.0 or actor != _player or not is_instance_valid(actor) or actor.current_hp <= 0:
		return false
	var here := to_local(actor.global_position)
	return maxf(absf(here.x), absf(here.z)) < 2.42 and absf(here.y) < 0.45 and _core.global_position.distance_to(actor.global_position) < 2.12


func _tick_core(delta: float) -> void:
	if _bridge_wait >= 0.0:
		_bridge_wait -= delta
		deck.set_bridge_retraction(1.0, smoothstep(0.0, 0.8, _bridge_wait))
		if _bridge_wait <= 0.0:
			_win()
		return
	if _shutdown_clock < 0.0:
		return
	if not _can_shutdown(_player):
		_shutdown_clock = -1.0
		return
	_shutdown_clock += delta
	if _shutdown_clock >= SHUTDOWN_TIME:
		_bridge_wait = 0.8
		_core.hide()
		_clear_safe_route()
		deck.set_center_screen(2.0, 0.0)
		_fx(VfxPool3D.FX01_METAL_SPARK_HIT, _core.global_position, 1.3)
		AudioManager.play_sfx("boss_defeat", -3.0)


func _win() -> void:
	if stage != Stage.CORE:
		return
	stage = Stage.WON
	deck.open_return_bridge()
	_emit_health()
	defeated.emit()
	checkpoint.emit("platform_victory")


func export_state() -> Dictionary:
	var hp: Array[int] = []
	for target in _arm_targets:
		hp.append(target.current_hp)
	var result := {"schema": 2, "stage": int(stage), "arm_hp": hp, "clock": _clock}
	if stage == Stage.COLLAPSE:
		result["outer_start"] = _outer_start
		result["inner_start"] = _inner_start
		result["outer_started"] = _sent_racks
		result["inner_started"] = _last_broken == 2
	if stage == Stage.TAKEOVER and is_instance_valid(_proxy):
		var p := to_local(_proxy.global_position)
		result["proxy_position"] = [p.x, p.y, p.z]
	return result

func restore_state(state: Dictionary, already_cleared: bool) -> void:
	_finish_slam(false)
	_finish_gun(false)
	_cancel_rounds()
	if state.is_empty():
		if already_cleared:
			stage = Stage.WON
			deck.open_return_bridge()
		return
	var hp: Array = state.get("arm_hp", [])
	for i in range(mini(hp.size(), _arm_targets.size())):
		_arm_targets[i].current_hp = clampi(int(hp[i]), 0, ARM_HP)
	var saved_stage := clampi(int(state.get("stage", Stage.DORMANT)), Stage.DORMANT, Stage.WON)
	if saved_stage >= Stage.COMBAT:
		_break_stairs(false)
		deck.set_bridge_retraction(1.0, 1.0)
	if saved_stage >= Stage.COLLAPSE:
		for i in range(deck.grapples.size()):
			deck.play(deck.grapples[i], "death_grapple", 0.0, 2.16)
		for rack in deck.sentries:
			deck.play(rack, "death_sentry", 0.0, 1.68)
	match saved_stage:
		Stage.TAKEOVER:
			stage = Stage.TAKEOVER
			_clock = 0.0
			_takeover_requested = false
			if not is_instance_valid(_proxy):
				_proxy = MONITOR_VISUAL.instantiate() as Node3D
				add_child(_proxy)
				var p: Array = state.get("proxy_position", [-6.5, 0.12, -5.0])
				_proxy.position = Vector3(p[0], p[1], p[2])
		Stage.DEPLOY:
			stage = Stage.DORMANT
			_returning_visit = true
		Stage.COMBAT:
			_arm_combat()
		Stage.COLLAPSE:
			_begin_collapse(false)
			_outer_start = maxf(PlatformSentinelDeck3D.OUTER_START, float(state.get("outer_start", PlatformSentinelDeck3D.OUTER_START)))
			_inner_start = maxf(_outer_start + 0.5, float(state.get("inner_start", PlatformSentinelDeck3D.INNER_START)))
			_clock = clampf(float(state.get("clock", 0.0)), 0.0, _collapse_finish())
			_sent_racks = bool(state.get("outer_started", _clock >= _outer_start + 0.12))
			if _sent_racks:
				for rack in deck.sentries:
					deck.play(rack, "death_sentry", 0.0, 1.68)
			var inner := _clock >= _inner_warning_at()
			_last_broken = 2 if bool(state.get("inner_started", _clock >= _inner_start)) else 1 if inner else 0
			deck.sample_collapse(_clock, _outer_start, _inner_start)
			_show_safe_route(2.18 if inner else 7.12)
		Stage.CORE:
			deck.sample_collapse(PlatformSentinelDeck3D.FINISH)
			_activate_core()
		Stage.WON:
			stage = Stage.WON
			deck.sample_collapse(PlatformSentinelDeck3D.FINISH)
			deck.set_center_screen(2.0, 0.0)
			deck.open_return_bridge()
	_emit_health()

func _add_side_controls(index: int, target: PlatformSentinelWeakPoint3D, inward: Vector3) -> void:
	var edge := target.position - inward * 3.04
	edge.y = 0.075
	var start := Vector3(target.position.x, edge.y, target.position.z)
	var signal_strip := _line(to_global(start), to_global(edge), 0.14, Color(0.34, 0.83, 1.0, 0.80))
	signal_strip.hide()
	var label := Label3D.new()
	label.name = "SideMark"
	label.hide()
	label.text = SIDE_LABELS[index]
	label.position = Vector3(0.0, 1.05, 0.0)
	label.pixel_size = 0.013
	label.font_size = 50
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	target.add_child(label)
	_side_lamps.append(signal_strip)
	var port := _new_target(1, 0.57)
	port.name = "GunFeed_%02d" % (index + 1)
	port.position = -inward * 10.9 + Vector3.UP * 1.0
	port.position += inward.rotated(Vector3.UP, PI / 2.0) * -2.75
	port.destroyed.connect(_suppress_side.bind(index))
	_ports.append(port)


func _prepare_attack_poses() -> void:
	for index in range(deck.grapples.size()):
		var arm := deck.grapples[index]
		_grapple_meshes.append(arm.find_children("*", "GeometryInstance3D", true, false))
		deck.play(arm, "attack_grapple_slam", 0.0, IMPACT)
		var rig := deck.skeleton_for(arm)
		var pivot := rig.to_global(rig.get_bone_global_pose(rig.find_bone("shoulder")).origin)
		var point := _palm_world(index)
		var slots := [{"angle": 0.0, "point": to_local(point), "pivot": to_local(pivot)}]
		var best := to_local(point).slide(Vector3.UP).length()
		for angle in [deg_to_rad(18.0), deg_to_rad(-18.0)]:
			var candidate := pivot + (point - pivot).rotated(Vector3.UP, angle)
			var local := to_local(candidate)
			if local.slide(Vector3.UP).length() < best - 0.35 and maxf(absf(local.x), absf(local.z)) < 10.9:
				best = local.slide(Vector3.UP).length()
				if slots.size() > 1:
					slots.pop_back()
				slots.append({"angle": angle, "point": local, "pivot": to_local(pivot)})
		_arm_slots.append(slots)
		deck.play(arm, "activate_grapple", 0.0, 0.0)
	for rack in deck.sentries:
		deck.play(rack, "attack_sentry", 0.0, AUTHORED_FIRE)
		var lane := _shot_lane(rack)
		_gun_rest_lanes.append([to_local(lane[0]), to_local(lane[1])])
		_add_sentry_armor(rack)
		deck.play(rack, "activate_sentry", 0.0, 0.0)


func _add_sentry_armor(rack: Node3D) -> void:
	var rig := deck.skeleton_for(rack)
	var holder := BoneAttachment3D.new()
	holder.bone_name = "trunnion"
	rig.add_child(holder)
	var shell := StaticBody3D.new()
	shell.name = "SentryArmor"
	shell.collision_layer = 0
	shell.collision_mask = 0
	var shield := SphereShape3D.new()
	shield.radius = 0.54
	var shape := CollisionShape3D.new()
	shape.shape = shield
	shell.add_child(shape)
	holder.add_child(shell)
	_armor.append(shell)


func _new_target(hp: int, radius: float) -> PlatformSentinelWeakPoint3D:
	var target := PlatformSentinelWeakPoint3D.new()
	add_child(target)
	target.configure(hp, radius)
	return target

func _on_target_damaged(_current: int, target: PlatformSentinelWeakPoint3D) -> void:
	_emit_health()
	_fx(VfxPool3D.FX01_METAL_SPARK_HIT, target.global_position, 0.85)

func arm_health() -> Array[int]:
	var values: Array[int] = []
	for target in _arm_targets:
		values.append(target.current_hp)
	return values


func _emit_health() -> void:
	var total := 0
	for target in _arm_targets:
		total += target.current_hp
	health_changed.emit(total, TOTAL_HP, 1 if stage <= Stage.COMBAT else 2 if stage == Stage.COLLAPSE else 3)

func _arms_alive() -> int:
	var count := 0
	for target in _arm_targets:
		count += int(target.current_hp > 0)
	return count

func _palm_world(index: int) -> Vector3:
	var arm := deck.grapples[index]
	deck.sync_skeleton(arm)
	var point := Vector3.ZERO
	var count := 0
	for key in ["palm_contact_ll", "palm_contact_lr", "palm_contact_ul", "palm_contact_ur"]:
		var socket := deck.socket(arm, key)
		if socket != null:
			point += socket.global_position
			count += 1
	return point / float(count) if count > 0 else _arm_targets[index].global_position

func _hit_player(amount: int, direction: Vector3, kick: float) -> void:
	_player.notify_attacked_by(self)
	_player.take_damage(amount, false, direction, kick > 0.0, kick)

func _fx(id: StringName, point: Vector3, scale_m: float, context: Dictionary = {}) -> void:
	var pool := get_tree().get_first_node_in_group("vfx_pool_3d") as VfxPool3D
	if pool != null:
		pool.acquire(id, point, Color("#ffaf65"), scale_m, context)

func _line(from: Vector3, to: Vector3, width: float, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, 0.028, maxf(0.01, from.distance_to(to)))
	var node := _marker(mesh, (from + to) * 0.5, color)
	node.look_at(to)
	return node

func _circle_warning(point: Vector3) -> MeshInstance3D:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in range(49):
		var outward := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 48.0)
		mesh.surface_add_vertex(outward * (SLAM_RADIUS - 0.075))
		mesh.surface_add_vertex(outward * SLAM_RADIUS)
	mesh.surface_end()
	var ring := _marker(mesh, point, Color(1.0, 0.67, 0.26, 0.95))
	var material := ring.material_override as StandardMaterial3D
	material.no_depth_test = true
	material.render_priority = 6
	return ring


func _gun_warning(lane: Array[Vector3], local_warning: bool) -> MeshInstance3D:
	var from := to_local(lane[0])
	var to := to_local(lane[1])
	var edge := 12.48
	var start := Vector2(from.x, from.z)
	var finish := Vector2(to.x, to.z)
	var corners := [Vector2(-edge, -edge), Vector2(edge, -edge), Vector2(edge, edge), Vector2(-edge, edge)]
	var visible: Array[Vector2] = []
	for point in [start, finish]:
		if maxf(absf(point.x), absf(point.y)) <= edge:
			visible.append(point)
	for i in range(4):
		var intersection: Variant = Geometry2D.segment_intersects_segment(start, finish, corners[i], corners[(i + 1) % 4])
		if intersection is Vector2:
			visible.append(intersection)
	if visible.size() >= 2:
		visible.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_squared_to(start) < b.distance_squared_to(start))
		start = visible.front()
		finish = visible.back()
	if local_warning:
		finish = start.move_toward(finish, 4.8)
	var color := Color(1.0, 0.56, 0.14, 0.76) if local_warning else Color(1.0, 0.32, 0.16, 0.74)
	return _line(to_global(Vector3(start.x, 0.037, start.y)), to_global(Vector3(finish.x, 0.037, finish.y)), 0.63, color)


func _marker(mesh: Mesh, point: Vector3, color: Color) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	node.global_position = point
	return node
