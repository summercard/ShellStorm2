class_name PlatformSentinelEncounter3D
extends Node3D

signal health_changed(current: int, maximum: int, phase: int)
signal defeated
signal checkpoint(reason: String)

const TAKEOVER := "nar_main_032_platform_takeover"
const ARM_HP := PlatformSentinelUnit3D.ARM_HP
const TOTAL_HP := ARM_HP * 4
const SLAM_RADIUS := PlatformSentinelUnit3D.SLAM_RADIUS
const SLAM_CLIP_END := 80.0 / 30.0
const SLAM_HOLD_POSE := 47.0 / 30.0
const SLAM_RESPONSE := 1.2
const SLAM_END := 3.12
const ARM_COOLDOWN := 6.5
const RACKS_PER_SIDE := 4
const GUN_RANGE := 33.0
const BULLET_SPEED := 8.4
const PELLET_SPEED := 7.4
const GUN_FLIGHT_HEIGHT := 0.75
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
const SHUTDOWN_TIME := 0.6
const SIDE_LABELS := ["入口", "东", "后", "西"]
const MONITOR_VISUAL := preload("res://assets/art/enemies/bosses/enm_boss_monitor002/runtime/enm_boss_monitor002/enm_boss_monitor002_root_top3d.tscn")
const IMPACT := 35.0 / 30.0
const REAR := 2
const FULL_DEPLOY := 3.15
const DEFEAT_BEAT := 0.55
const GRAB_POSE := 1.145
const MONITOR_MARK := Vector3(-7.15, 0.08, -8.55)
const THROW_DURATION := 0.78
const CARRY_LIFT_POSE := 1.075
const THROW_LOAD_POSE := 1.09

enum Stage { DORMANT, TAKEOVER, DEPLOY, COMBAT, COLLAPSE, CORE, WON }
enum Barrage { NONE, BURST, CROSS, VOLLEY }

@onready var deck: PlatformSentinelDeck3D = $Deck
var grapples: Array[PlatformSentinelUnit3D] = []
var sentries: Array[PlatformSentinelUnit3D] = []
var stage := Stage.DORMANT
var _player: Player3D
var _director: Node
var _arm_targets: Array[PlatformSentinelWeakPoint3D] = []
var _core: MeshInstance3D
var _gun_rest_lanes: Array[Array] = []
var _gun_ready: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _screen_wake_at := -1.0
var _route_markers: Array[Node3D] = []
var _barrage := Barrage.NONE
var _barrage_lanes: Dictionary = {}
var _rounds: Array[Projectile3D] = []
var _cross_at := 12.0
var _volley_at := 22.0
var _cross_side := 0
var _next_cross_side := 0
var _projectiles: ProjectilePool3D
var _bridges_releasing := false
var _slam_angle := 0.0
var _next_attack_at := 0.0
var _next_scan_at := 0.0
var _prefer_palm := true
var _shutdown_clock := -1.0
var _bridge_wait := -1.0
var _outer_start := PlatformSentinelDeck3D.OUTER_START
var _clock := 0.0
var _arm_clock := 0.0
var _gun_clock := 0.0
var _active_arm := -1
var _active_gun := -1
var _slam_point := Vector3.ZERO
var _shot_index := 0
var _returning_visit := false
var _takeover_requested := false
var _rear_started := false
var _stairs_broken := false
var _sent_racks := false
var _proxy: Node3D
var _proxy_attached := false
var _proxy_grip_offset := Transform3D.IDENTITY
var _arm_motion: Tween
var _proxy_motion: Tween
var _voice: Node
var _deployment_started_at := -1.0

func _ready() -> void:
	set_physics_process(false)
	grapples.assign($Arms.get_children())
	sentries.assign($Sentries.get_children())
	for i in range(grapples.size()):
		var target := grapples[i].hit_body
		target.damaged.connect(_on_target_damaged.bind(target))
		target.destroyed.connect(_on_arm_destroyed.bind(i))
		_arm_targets.append(target)
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
	var visual := enemy.avatar.get_animated_boss_root() as Node3D
	_spawn_proxy(visual.global_basis.get_scale() if visual != null else Vector3.ONE)
	AudioManager.play_sfx("melee_impact", -3.0, 0.72)
	_fx(VfxPool3D.FX01_METAL_SPARK_HIT, to_global(MONITOR_MARK + Vector3.UP * 1.2), 1.8)
	stage = Stage.TAKEOVER
	deck.set_rear_signal(PlatformSentinelDeck3D.SignalPicture.LINK_LOST, true)
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
			_sample_rear_pose(0.0)
			_arm_motion = create_tween()
			_arm_motion.tween_method(_sample_rear_pose, 0.0, GRAB_POSE, 1.17).set_trans(Tween.TRANS_SINE)
		"grab":
			if _arm_motion != null:
				_arm_motion.kill()
			_sample_rear_pose(GRAB_POSE)
			AudioManager.play_sfx("melee_impact", -9.0, 0.78)
			if is_instance_valid(_proxy):
				_proxy_grip_offset = _grip_frame().affine_inverse() * _proxy.global_transform
				_proxy_attached = true
			_arm_motion = create_tween()
			_arm_motion.tween_method(_sample_rear_pose, GRAB_POSE, CARRY_LIFT_POSE, 0.78).set_trans(Tween.TRANS_SINE).set_delay(0.10)
			_arm_motion.tween_interval(0.18)
			_arm_motion.tween_method(_sample_rear_pose, CARRY_LIFT_POSE, THROW_LOAD_POSE, 0.79).set_trans(Tween.TRANS_SINE)
		"throw":
			_throw_monitor()
		"ignite":
			_screen_wake_at = _clock
			deck.wake_screens(0.0)
			_start_deploy_motion()
		_:
			return false
	return true

func _start_rear() -> void:
	if _rear_started:
		return
	_rear_started = true
	deck.set_rear_screen_retraction(true, true)
	grapples[REAR].play("activate_grapple", 1.10)
	_fx(VfxPool3D.FX01_METAL_SPARK_HIT, grapples[REAR].global_position + Vector3.UP * 5.0, 2.5)

func _spawn_proxy(proxy_scale := Vector3.ONE) -> void:
	_clear_proxy()
	_proxy = MONITOR_VISUAL.instantiate() as MonitorBossPresentation
	add_child(_proxy)
	_proxy.position = MONITOR_MARK
	_proxy.scale = proxy_scale
	(_proxy as MonitorBossPresentation).sync_context({"action_id": "stun_loop", "time": 0.22}, false)


func _sample_rear_pose(at: float) -> void:
	grapples[REAR].play("attack_grapple_slam", 0.0, at)
	if _proxy_attached and is_instance_valid(_proxy):
		_proxy.global_transform = _grip_frame() * _proxy_grip_offset
		_proxy.position.y = maxf(_proxy.position.y, MONITOR_MARK.y)


func _grip_frame() -> Transform3D:
	var arm := grapples[REAR]
	var left := arm.socket("grip_contact_l")
	var right := arm.socket("grip_contact_r")
	var palm := arm.socket("palm_contact_ll")
	return Transform3D(palm.global_basis.orthonormalized(), (left.global_position + right.global_position) * 0.5)


func _throw_monitor() -> void:
	if not is_instance_valid(_proxy) or _proxy_motion != null:
		return
	if not _proxy_attached:
		_clear_proxy() # Skip/fallback does not show a throw from a stationary actor.
		return
	if _arm_motion != null:
		_arm_motion.kill()
	var attack_time := grapples[REAR].animation.current_animation_position
	_arm_motion = create_tween()
	_arm_motion.tween_method(_sample_rear_pose, attack_time, IMPACT, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_arm_motion.tween_callback(_release_monitor)
	_arm_motion.tween_method(_sample_rear_pose, IMPACT, SLAM_HOLD_POSE, 0.15)
	_arm_motion.tween_method(_sample_rear_pose, SLAM_HOLD_POSE, SLAM_CLIP_END, 0.52).set_trans(Tween.TRANS_SINE)
	_arm_motion.tween_callback(func() -> void: grapples[REAR].play("idle_grapple"))


func _release_monitor() -> void:
	if not is_instance_valid(_proxy) or not _proxy_attached:
		return
	AudioManager.play_sfx("melee_impact", -2.0, 0.69)
	_fx(VfxPool3D.FX01_METAL_SPARK_HIT, _proxy.global_position + Vector3.UP, 1.8)
	_proxy_attached = false
	var from := _proxy.position
	var start_basis := _proxy.basis
	var out := Vector3(-9.8, -14.0, -22.0)
	_proxy_motion = create_tween()
	_proxy_motion.tween_method(func(t: float) -> void:
		_proxy.position = from.lerp(out, t)
		_proxy.position.y = lerpf(from.y, out.y, t * t) + 4.0 * t * (1.0 - t)
		_proxy.basis = Basis.from_euler(Vector3(2.4, -0.8, 2.0) * t) * start_basis,
		0.0, 1.0, THROW_DURATION)
	_proxy_motion.tween_callback(_clear_proxy)


func _clear_proxy() -> void:
	if _proxy_motion != null:
		_proxy_motion.kill()
		_proxy_motion = null
	_proxy_attached = false
	if is_instance_valid(_proxy):
		_proxy.queue_free()
	_proxy = null


func _reset_takeover() -> void:
	var proxy_scale := _proxy.scale if is_instance_valid(_proxy) else Vector3.ONE
	if _arm_motion != null:
		_arm_motion.kill()
	_arm_motion = null
	_rear_started = false
	_takeover_requested = false
	_screen_wake_at = -1.0
	_deployment_started_at = -1.0
	_clock = 0.0
	for arm in grapples:
		arm.play("activate_grapple", 0.0)
	for rack in sentries:
		rack.play("activate_sentry", 0.0)
	deck.set_screens(0.0, 0.0)
	deck.sample_launch_lift(0.0)
	deck.set_rear_signal(PlatformSentinelDeck3D.SignalPicture.LINK_LOST)
	deck.set_rear_screen_retraction(false)
	_spawn_proxy(proxy_scale)


func _on_narrative_finished(id: String, reason: String) -> void:
	if id != TAKEOVER or stage != Stage.TAKEOVER:
		return
	_stop_voice()
	if reason in ["flow.end", "duration", "skip"]:
		_deploy()
	else:
		_reset_takeover()

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
	_clear_proxy()
	if _arm_motion != null:
		_arm_motion.kill()
		_arm_motion = null
	var elapsed := 0.0 if _deployment_started_at < 0.0 else _clock - _deployment_started_at
	if _deployment_started_at < 0.0:
		_start_deploy_motion()
	_takeover_safe_position()

	stage = Stage.DEPLOY
	_clock = elapsed
	_screen_wake_at = -1.0
	_emit_health()
	checkpoint.emit("platform_deploy")


func _start_deploy_motion() -> void:
	if _deployment_started_at >= 0.0:
		return
	_deployment_started_at = _clock
	deck.set_rear_signal(PlatformSentinelDeck3D.SignalPicture.RISING, true)
	deck.set_rear_screen_retraction(true)
	AudioManager.play_sfx("door_open", -5.0, 0.63)
	for i in range(grapples.size()):
		var clip := "idle_grapple" if i == REAR and _rear_started else "activate_grapple"
		grapples[i].play(clip)
	_rear_started = true
	for i in range(sentries.size()):
		var rack := sentries[i]
		rack.play("activate_sentry")
		rack.delay_motion(floori(float(i) / RACKS_PER_SIDE) * 0.14)

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
			if is_instance_valid(_proxy) and _clock < DEFEAT_BEAT:
				(_proxy as MonitorBossPresentation).sync_context({"action_id": "hurt", "time": _clock}, false)
			elif is_instance_valid(_proxy) and (_proxy as MonitorBossPresentation).action_id == "hurt":
				(_proxy as MonitorBossPresentation).sync_context({"action_id": "stun_loop", "time": 0.22}, false)
			if _deployment_started_at >= 0.0:
				var deploying := _clock - _deployment_started_at
				deck.sample_launch_lift(deploying)
				_tick_deploy_geometry(deploying)
			if _screen_wake_at >= 0.0:
				deck.wake_screens(_clock - _screen_wake_at)
			if not _takeover_requested and _clock > 0.25:
				if is_instance_valid(_director):
					_takeover_requested = _director.play(TAKEOVER, {"priority": 32})
					if not _takeover_requested and _clock > 8.0:
						push_warning("Platform Sentinel takeover could not start; continuing encounter.")
						_deploy()
				elif _clock > 1.0:
					_deploy()
		Stage.DEPLOY:
			if _screen_wake_at < 0.0:
				deck.wake_screens(_clock)
			deck.sample_launch_lift(_clock)
			_tick_deploy_geometry(_clock)
			if _clock >= FULL_DEPLOY:
				_arm_combat()
		Stage.COMBAT:
			if _arms_alive() > 2:
				deck.sample_combat_feed(_clock)
			_tick_combat(delta, here)
			for target in _arm_targets:
				if target.current_hp > 0:
					target.sync_pose()
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


func _tick_deploy_geometry(elapsed: float) -> void:
	if elapsed >= 0.72:
		_deck_link_release(elapsed)
	if not _stairs_broken and elapsed > 1.75:
		_break_stairs(true)


func _deck_link_release(elapsed: float) -> void:
	if not _bridges_releasing:
		_bridges_releasing = true
		for side in [-1.0, 1.0]:
			_fx(VfxPool3D.FX01_METAL_SPARK_HIT, to_global(Vector3(side * 12.54, 0.38, 0.0)), 1.25)
		AudioManager.play_sfx("door_open", -7.0, 0.68)
	var motion := smoothstep(0.95, 2.65, elapsed)
	deck.set_bridge_retraction(motion, motion)


func _arm_combat() -> void:
	deck.set_bridge_retraction(1.0, 1.0)
	stage = Stage.COMBAT
	deck.set_rear_signal(PlatformSentinelDeck3D.SignalPicture.ONLINE)
	_clock = 0.0
	_next_attack_at = 1.15
	_next_scan_at = 0.0
	_standby_end = 0.0
	_next_standby_at = 0.0
	_active_arm = -1
	_active_gun = -1
	_cross_at = 12.0
	_volley_at = 22.0
	_next_cross_side = 0
	_prefer_palm = true
	_gun_ready.fill(0.0)
	for i in range(grapples.size()):
		grapples[i].ready_at = 0.0
		var alive := _arm_targets[i].current_hp > 0
		grapples[i].play("idle_grapple" if alive else "death_grapple", 1.0 if alive else 0.0, 0.0 if alive else 2.16)
		_arm_targets[i].set_open(alive)
		_arm_targets[i].sync_pose()
	for rack in sentries:
		rack.play("idle_sentry")
	for rack in sentries:
		rack.armor.set_deferred("collision_layer", 4)
	deck.set_screens(0.0 if _arms_alive() > 2 else 1.0, 0.62)
	if _arms_alive() > 2:
		deck.sample_combat_feed(0.0)
	_emit_health()
	checkpoint.emit("platform_combat")


var _standby_arm: PlatformSentinelUnit3D
var _standby_rack: PlatformSentinelUnit3D
var _standby_end := 0.0
var _standby_started := 0.0
var _next_standby_at := 0.0
var _standby_rng := RandomNumberGenerator.new()

func _finish_standby() -> void:
	if is_instance_valid(_standby_arm):
		_standby_arm.rig.clear_bones_global_pose_override()
		_standby_arm.play("idle_grapple")
	if is_instance_valid(_standby_rack):
		_standby_rack.rig.clear_bones_global_pose_override()
		_standby_rack.play("idle_sentry")
	_standby_arm = null
	_standby_rack = null

func _tick_standby() -> void:
	if _clock < _standby_end and is_instance_valid(_player):
		var weight := inverse_lerp(_standby_started, _standby_end, _clock)
		if is_instance_valid(_standby_arm):
			_standby_arm.sample_standby(weight, _player.global_position, global_position)
		if is_instance_valid(_standby_rack):
			_standby_rack.sample_standby(weight, _player.global_position, global_position)
		return
	_finish_standby()
	if _clock < _next_standby_at:
		return
	var living: Array[PlatformSentinelUnit3D] = []
	for i in range(_arm_targets.size()):
		if _arm_targets[i].current_hp > 0:
			living.append(grapples[i])
	if not living.is_empty():
		_standby_arm = living[_standby_rng.randi_range(0, living.size() - 1)]
		_standby_arm.play("scan_grapple" if _standby_rng.randi_range(0, 1) == 0 else "servo_pause_grapple")
	if not sentries.is_empty():
		_standby_rack = sentries[_standby_rng.randi_range(0, sentries.size() - 1)]
		_standby_rack.play("scan_sentry" if _standby_rng.randi_range(0, 1) == 0 else "servo_pause_sentry")
	_standby_started = _clock
	_standby_end = _clock + 1.4
	_next_standby_at = _clock + _standby_rng.randf_range(2.4, 3.7)


func _tick_combat(delta: float, here: Vector3) -> void:
	if _active_arm >= 0:
		_tick_slam(delta, here)
		return
	if _barrage != Barrage.NONE:
		_tick_gun(delta)
		return
	if not _rounds.is_empty() or _clock < _next_attack_at or maxf(absf(here.x), absf(here.z)) >= 12.48 or absf(here.y) > 1.6:
		_tick_standby()
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
	_tick_standby()
	if _clock >= _next_scan_at:
		_next_scan_at = _clock + 1.4
		_next_attack_at = _clock + 0.18


func _next_attack_gap() -> float:
	return 3.25 if _arms_alive() > 2 else 2.95


func _start_slam() -> bool:
	var best_age := INF
	var best: Dictionary = {}
	for i in range(_arm_targets.size()):
		var arm := grapples[i]
		var candidate := arm.choose_slam(self, _player.global_position, _clock)
		if not candidate.is_empty() and arm.ready_at < best_age:
			_active_arm = i
			best = candidate
			best_age = arm.ready_at
	if _active_arm < 0:
		return false
	_finish_standby()
	grapples[_active_arm].ready_at = _clock + ARM_COOLDOWN
	_next_attack_at = _clock + _next_attack_gap()
	_prefer_palm = false
	_arm_clock = 0.0
	_slam_angle = float(best.angle)
	_slam_point = _predicted_palm(_active_arm, _slam_angle)
	_slam_point.y = global_position.y + 0.036
	_play_slam_pose()
	var windup := _palm_world(_active_arm)
	_fx(VfxPool3D.FX01_METAL_SPARK_HIT, windup, 0.75)
	AudioManager.play_sfx("door_open", -11.0, 0.74)
	return true





func _predicted_palm(index: int, angle: float) -> Vector3:
	var outer := grapples[index].slam_slots[0]
	var pivot: Vector3 = outer.pivot
	var point: Vector3 = outer.point
	return to_global(pivot + (point - pivot).rotated(Vector3.UP, angle))


func _play_slam_pose() -> void:
	var arm := grapples[_active_arm]
	var rig := arm.rig
	rig.clear_bones_global_pose_override()
	var time := _arm_clock
	if time > SLAM_HOLD_POSE:
		var release := IMPACT + SLAM_RESPONSE
		var blend := clampf(inverse_lerp(release, SLAM_END, time), 0.0, 1.0)
		time = lerpf(SLAM_HOLD_POSE, SLAM_CLIP_END, blend)
	arm.play("attack_grapple_slam", 0.0, time)
	arm.slew(_slam_angle)
	_update_grapple_visibility()





func _update_grapple_visibility() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var anchor := grapples[_active_arm].global_position
	var outward := (anchor - global_position).slide(Vector3.UP).normalized()
	var foreground := (camera.global_position - _player.global_position).slide(Vector3.UP).dot(outward) > 0.5
	var near := (anchor - _player.global_position).slide(Vector3.UP).length() < 8.5
	grapples[_active_arm].set_fade(0.77 if foreground and near else 0.0)


func _tick_slam(delta: float, here: Vector3) -> void:
	var before := _arm_clock
	_arm_clock = minf(_arm_clock + delta, SLAM_END)
	if _arm_clock < IMPACT - 0.35:
		var desired := grapples[_active_arm].choose_slam(self, _player.global_position, INF)
		if not desired.is_empty():
			_slam_angle = move_toward(_slam_angle, float(desired.angle), 1.6 * delta)
		_slam_point = _predicted_palm(_active_arm, _slam_angle)
		_slam_point.y = global_position.y + 0.036
	_play_slam_pose()
	if before < IMPACT and _arm_clock >= IMPACT:
		_resolve_slam(here)
	if _active_arm < 0:
		return
	if _arm_clock >= SLAM_END:
		_finish_slam(true)


func _finish_slam(standby: bool) -> void:
	if _active_arm < 0:
		return
	var arm := grapples[_active_arm]
	arm.rig.clear_bones_global_pose_override()
	arm.set_fade(0.0)
	if standby:
		arm.play("idle_grapple")
	_active_arm = -1


func _resolve_slam(here: Vector3) -> void:
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
	for i in range(sentries.size()):
		var side := floori(float(i) / RACKS_PER_SIDE)
		if _gun_ready[side] > _clock:
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
	for index in range(sentries.size()):
		var side := _side_of(index)
		if pattern == Barrage.CROSS and side != _cross_side and side != (_cross_side + 2) % 4:
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
	_finish_standby()
	var rack := sentries[index]
	rack.play("attack_sentry", 0.0, AUTHORED_FIRE)
	rack.aim_sentry(target)
	var lane := _shot_lane(rack)
	if lane.is_empty():
		_reset_gun_pose(rack)
		return false
	if not _obstruction(lane[0], lane[0].move_toward(lane[1], 1.0)).is_empty():
		_reset_gun_pose(rack)
		return false
	_barrage_lanes[index] = lane
	return true


func _begin_barrage(pattern: Barrage) -> void:
	_barrage = pattern
	_gun_clock = 0.0
	_shot_index = 0
	_prefer_palm = true
	_next_attack_at = _clock + _next_attack_gap()
	for index: int in _barrage_lanes:
		_gun_ready[_side_of(index)] = _clock + GUN_COOLDOWN
	_cue_barrage_audio()


func _side_of(index: int) -> int:
	return floori(float(index) / RACKS_PER_SIDE)


func _cue_barrage_audio() -> void:
	var announced: Array[int] = []
	for index: int in _barrage_lanes:
		var side := _side_of(index)
		if _barrage == Barrage.CROSS and side != (_cross_side + 2 * _shot_index) % 4:
			continue
		var lane: Array[Vector3] = _barrage_lanes[index]
		if not announced.has(side):
			announced.append(side)
			AudioManager.emit_event("combat.weapon.reload_start", {"gun_id": "bp_rifle", "source_position": lane[0], "max_distance": 32.0, "unit_size": 7.0, "volume_db": -10.0})


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
				if _barrage == Barrage.CROSS and side != (_cross_side + 2 * (_shot_index - 1)) % 4:
					continue
				_set_recoil(index, maxf(0.0, 1.0 - elapsed / 0.16))
	if _barrage == Barrage.VOLLEY:
		var since_last := 1.0 if _shot_index == 0 else _gun_clock - float(times[_shot_index - 1])
		var until_next := 1.0 if _shot_index >= times.size() else float(times[_shot_index]) - _gun_clock
		var flash := maxf(0.0, 1.0 - since_last / 0.19)
		var charge := 0.55 * (1.0 - smoothstep(0.0, 0.36, until_next))
		deck.set_gun_alert(maxf(flash, charge))
	while _shot_index < times.size() and _gun_clock >= times[_shot_index]:
		_fire_pulse()
		_shot_index += 1
		if (_barrage != Barrage.BURST and _shot_index < times.size()) or (_barrage == Barrage.BURST and _shot_index == 3):
			_cue_barrage_audio()
	if _gun_clock >= float(times.back()) + 0.42:
		_finish_gun(true)
		_next_attack_at = maxf(_next_attack_at, _clock + 0.85)


func _set_recoil(index: int, kick: float) -> void:
	var lane: Array[Vector3] = _barrage_lanes[index]
	sentries[index].set_recoil(lane[0].direction_to(lane[1]), kick)


func _fire_pulse() -> void:
	var sound_played: Array[int] = []
	var spread: Array = [0.0]
	if _barrage == Barrage.CROSS:
		spread = CROSS_SPREAD
	elif _barrage == Barrage.VOLLEY or _shot_index == BURST_TIMES.size() - 1:
		spread = SPREAD
	for index: int in _barrage_lanes:
		var side := _side_of(index)
		if _barrage == Barrage.CROSS and side != (_cross_side + 2 * _shot_index) % 4:
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
			_spawn_round(sentries[index], lane[0], axis.rotated(Vector3.UP, deg_to_rad(angle)), spread.size() > 1)


func _spawn_round(rack: PlatformSentinelUnit3D, origin: Vector3, direction: Vector3, pellet: bool) -> void:
	var flight_range := 29.0 if _barrage == Barrage.BURST else 15.8 if _barrage == Barrage.VOLLEY else 22.0
	var round := _projectiles.acquire({
		"shooter": rack, "direction": direction,
		"level_flight_y": global_position.y + GUN_FLIGHT_HEIGHT, "speed": PELLET_SPEED if pellet else BULLET_SPEED,
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


func _shot_lane(rack: PlatformSentinelUnit3D) -> Array[Vector3]:
	var muzzle := rack.socket("muzzle_exit")
	var forward := rack.socket("muzzle_forward")
	if muzzle == null or forward == null:
		return []
	var from := muzzle.global_position
	var direction := (forward.global_position - from).slide(Vector3.UP).normalized()
	return [from, from + direction * GUN_RANGE]


func _obstruction(from: Vector3, to: Vector3) -> Dictionary:
	var ray := PhysicsRayQueryParameters3D.create(from, to, 1, [_player.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(ray)


func _reset_gun_pose(rack: PlatformSentinelUnit3D) -> void:
	rack.rig.clear_bones_global_pose_override()
	rack.play("idle_sentry")


func _finish_gun(standby: bool) -> void:
	deck.set_gun_alert(0.0)
	for index: int in _barrage_lanes:
		var rack := sentries[index]
		if standby:
			_reset_gun_pose(rack)
		else:
			rack.rig.clear_bones_global_pose_override()
	_active_gun = -1
	_barrage = Barrage.NONE
	_barrage_lanes.clear()


func _on_arm_destroyed(index: int) -> void:
	_finish_standby()
	if _active_arm == index:
		_finish_slam(false)
	grapples[index].play("death_grapple")
	_fx(VfxPool3D.FX01_EXPLOSION, _arm_targets[index].last_hit_position, 2.65)
	var live := _arms_alive()
	deck.set_screens(0.0 if live > 2 else 1.0, 0.62)
	if live <= 2:
		deck.clear_combat_feed()
	if live == 0:
		_begin_collapse()
	else:
		_next_attack_at = maxf(_next_attack_at, _clock + 0.85)
	checkpoint.emit("platform_arm_disabled")


func _begin_collapse(announce := true) -> void:
	_finish_standby()
	_finish_slam(false)
	_finish_gun(false)
	_cancel_rounds()
	for rack in sentries:
		rack.armor.set_deferred("collision_layer", 0)
	stage = Stage.COLLAPSE
	deck.clear_combat_feed()
	deck.set_rear_signal(PlatformSentinelDeck3D.SignalPicture.OUTER_WARNING)
	_clock = 0.0
	_outer_start = PlatformSentinelDeck3D.OUTER_START
	if is_instance_valid(_player):
		var slow_speed := _player.get_move_speed()
		# 角到下一圈内侧留出胶囊和步行余量，普通配置沿用源时轴。
		var walk_budget := 5.45 * sqrt(2.0) / maxf(0.5, slow_speed) + 0.5
		_outer_start = maxf(_outer_start, walk_budget)
	_sent_racks = false
	for rack in sentries:
		rack.play("servo_pause_sentry")
	deck.set_screens(2.0, 0.62)
	if announce:
		_show_safe_route(7.12)
		AudioManager.play_sfx("boss_phase", -4.0)
	_emit_health()


func _tick_collapse() -> void:
	var releases := deck.sample_collapse(_clock, _outer_start)
	deck.sample_sentry_mounts(sentries)
	for motor in releases:
		_fx(VfxPool3D.FX01_METAL_SPARK_HIT, motor, 1.7)
		_fx(VfxPool3D.FX01_EXPLOSION, motor, 1.26)
	if not releases.is_empty():
		_collapse_jolt(0.58 if not _sent_racks else 0.22)
		if not _sent_racks:
			_sent_racks = true
			deck.set_rear_signal(PlatformSentinelDeck3D.SignalPicture.OUTER_RELEASE, true)
			for rack in sentries:
				rack.play("death_sentry")
			AudioManager.play_sfx("door_locked", -3.0, 0.73)
			checkpoint.emit("platform_outer_ring")
	if _clock >= _collapse_finish():
		_activate_core()


func _collapse_jolt(strength: float) -> void:
	if is_instance_valid(_player) and _player.camera_feedback != null:
		_player.camera_feedback.request_environment_impact(strength, 0.25)


func _collapse_finish() -> float:
	return _outer_start + PlatformSentinelDeck3D.OUTER_FALL_DURATION


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
		node.hide()
		node.queue_free()
	_route_markers.clear()


func _activate_core() -> void:
	stage = Stage.CORE
	deck.set_rear_signal(PlatformSentinelDeck3D.SignalPicture.SAFE)
	_clock = 0.0
	_shutdown_clock = -1.0
	_bridge_wait = -1.0
	_core.show()
	deck.set_center_screen(2.0, 0.34)
	_clear_safe_route()
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
		deck.sample_return_bridge(1.0 - smoothstep(0.0, 0.8, _bridge_wait))
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
		result["outer_started"] = _sent_racks
	if stage == Stage.TAKEOVER and is_instance_valid(_proxy):
		result["proxy_scale"] = _proxy.scale.x
	return result

func restore_state(state: Dictionary, already_cleared: bool) -> void:
	deck.clear_combat_feed()
	_finish_standby()
	_standby_end = 0.0
	_finish_slam(false)
	_finish_gun(false)
	_cancel_rounds()
	for target in _arm_targets:
		target.set_open(false)
	if state.is_empty():
		if already_cleared:
			stage = Stage.WON
			deck.set_rear_signal(PlatformSentinelDeck3D.SignalPicture.SAFE)
			deck.set_rear_screen_retraction(true)

			deck.sample_launch_lift(FULL_DEPLOY)
			deck.sample_collapse(PlatformSentinelDeck3D.FINISH)
			deck.sample_sentry_mounts(sentries)
			deck.open_return_bridge()
		return
	var hp: Array = state.get("arm_hp", [])
	for i in range(mini(hp.size(), _arm_targets.size())):
		_arm_targets[i].current_hp = clampi(int(hp[i]), 0, ARM_HP)
	var saved_stage := clampi(int(state.get("stage", Stage.DORMANT)), Stage.DORMANT, Stage.WON)

	deck.set_rear_screen_retraction(saved_stage >= Stage.DEPLOY)
	deck.sample_launch_lift(FULL_DEPLOY if saved_stage >= Stage.COMBAT else 0.0)
	if saved_stage >= Stage.COMBAT:
		_break_stairs(false)
		deck.set_bridge_retraction(1.0, 1.0)
	if saved_stage >= Stage.COLLAPSE:
		for i in range(grapples.size()):
			grapples[i].play("death_grapple", 0.0, 2.16)
		for rack in sentries:
			rack.play("death_sentry", 0.0, 1.68)
	match saved_stage:
		Stage.TAKEOVER:
			stage = Stage.TAKEOVER
			_reset_takeover()
			_proxy.scale = Vector3.ONE * float(state.get("proxy_scale", 1.0))
		Stage.DEPLOY:
			_deploy()
			deck.set_rear_signal(PlatformSentinelDeck3D.SignalPicture.RISING)
		Stage.COMBAT:
			_arm_combat()
		Stage.COLLAPSE:
			_begin_collapse(false)
			_outer_start = maxf(PlatformSentinelDeck3D.OUTER_START, float(state.get("outer_start", PlatformSentinelDeck3D.OUTER_START)))
			_clock = clampf(float(state.get("clock", 0.0)), 0.0, _collapse_finish())
			_sent_racks = bool(state.get("outer_started", _clock >= _outer_start + 0.12))
			if _sent_racks:
				deck.set_rear_signal(PlatformSentinelDeck3D.SignalPicture.OUTER_RELEASE)
				for rack in sentries:
					rack.play("death_sentry", 0.0, 1.68)
			deck.sample_collapse(_clock, _outer_start)
			deck.sample_sentry_mounts(sentries)
			_show_safe_route(7.12)
		Stage.CORE:
			deck.sample_collapse(PlatformSentinelDeck3D.FINISH)
			deck.sample_sentry_mounts(sentries)
			_activate_core()
		Stage.WON:
			stage = Stage.WON
			deck.set_rear_signal(PlatformSentinelDeck3D.SignalPicture.SAFE)
			deck.sample_collapse(PlatformSentinelDeck3D.FINISH)
			deck.sample_sentry_mounts(sentries)
			deck.set_center_screen(2.0, 0.0)
			deck.open_return_bridge()
	_emit_health()

func _prepare_attack_poses() -> void:
	for arm in grapples:
		arm.prepare_slam_slots(self, IMPACT)
	for rack in sentries:
		rack.play("attack_sentry", 0.0, AUTHORED_FIRE)
		var lane := _shot_lane(rack)
		_gun_rest_lanes.append([to_local(lane[0]), to_local(lane[1])])
		rack.play("activate_sentry", 0.0, 0.0)





func _on_target_damaged(_current: int, target: PlatformSentinelWeakPoint3D) -> void:
	_emit_health()
	_fx(VfxPool3D.FX01_METAL_SPARK_HIT, target.last_hit_position, 0.85)

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
	return grapples[index].palm_position()


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
