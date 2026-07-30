class_name Player3D
extends CharacterBody3D
## 首张 3D 地图使用的玩家外壳。八态状态机包含真实下落与落地，
## 移动、鼠标射线与碰撞统一工作在 XZ 平面和世界 Y 重力轴。

signal hp_changed(current: int, maximum: int)
signal dash_started()
signal dash_ended()
signal dash_cooldown_changed(cooldown_ratio: float)
signal presentation_state_changed(state_id: String, context: Dictionary)
signal input_lock_changed(locked: bool)
signal weapon_changed(gun_id: String, bullet_id: String)
signal ammo_changed(current: int, maximum: int)
signal reload_started(duration: float)
signal reload_progress_changed(progress: float, remaining: float)
signal reload_ended(completed: bool)
signal action_overlay_changed(snapshot: Dictionary)
signal avatar_customization_changed(loadout: Dictionary)

const SPEED := 7.0
const DASH_SPEED := 16.5
const DASH_DURATION := 0.17
const DASH_COOLDOWN := 2.2
const INVINCIBLE_DURATION := 0.24
const FIRE_ANIMATION_DURATION := 0.14
const KNOCKBACK_MIN_DURATION := 0.16
const KNOCKBACK_MAX_DURATION := 0.42
const GRAVITY_MPS2 := 24.0
const TERMINAL_FALL_SPEED_MPS := 32.0
const AIRBORNE_GRACE_S := 0.10
const FALL_STATE_SPEED_MPS := 2.0
const AIR_CONTROL_ACCEL_MPS2 := 24.0
const LANDING_MIN_DURATION_S := 0.12
const LANDING_MAX_DURATION_S := 0.30
const LANDING_FULL_IMPACT_MPS := 16.0
const FALL_RECOVERY_DISTANCE_M := 15.0

@export var max_hp := 100
@export var combat_enabled := false
@export var start_with_weapon := true
@export var default_gun_id := "bp_pistol"
@export var default_bullet_id := "mod_bullet_standard"

var current_hp := 100
var aim_direction := Vector3(0, 0, -1)
var aim_yaw := 0.0
var last_move_direction := Vector3(0, 0, -1)
var dash_direction := Vector3(0, 0, -1)
var dash_cooldown_timer := 0.0
var is_dashing := false
var is_invincible := false
var input_locked := false
var _presentation_state := "idle"
var _last_damage_amount := 0
var _invincible_remaining := 0.0
var _state_machine: StateMachine = null
var _test_move_direction: Variant = null
var weapon: WeaponModel3D = null
var weapon_tree: WeaponAssemblyTree = null
var _silence_remaining := 0.0
var _named_damage_multipliers: Dictionary = {}
var _fire_animation_remaining := 0.0
var _fire_animation_duration := FIRE_ANIMATION_DURATION
var _fire_animation_intensity := 0.0
var _knockback_remaining := 0.0
var _knockback_duration := 0.0
var _knockback_strength := 0.0
var _knockback_direction := Vector3.ZERO
var _avatar_customization := PlayerAvatar3D.DEFAULT_CUSTOMIZATION.duplicate()
var _airborne_elapsed := 0.0
var _fall_start_y := 0.0
var _last_impact_speed := 0.0
var _landing_duration := LANDING_MIN_DURATION_S
var _last_safe_ground_position := Vector3.ZERO
var _has_safe_ground_position := false
var _fall_recovery_count := 0

@onready var avatar: PlayerAvatar3D = $Avatar3D
@onready var camera: Camera3D = $Camera3D
@onready var aim_cursor: Node3D = $AimCursor


func _ready() -> void:
	current_hp = max_hp
	# PH43：坡面由真实承重盒负责。短距离吸附只跨越数厘米接缝，
	# 不再用持续向下速度或世界坐标吸附模拟楼梯。
	floor_snap_length = 0.32
	floor_max_angle = deg_to_rad(44.0)
	floor_stop_on_slope = true
	floor_constant_speed = true
	safe_margin = 0.035
	add_to_group("player")
	add_to_group("player_3d")
	_init_state_machine()
	_ensure_weapon_tree()
	if start_with_weapon:
		_ensure_weapon_model()
		_sync_weapon_from_tree()
	if avatar != null:
		avatar.set_customization(_avatar_customization)
	hp_changed.emit(current_hp, max_hp)
	_update_aim_from_mouse()


func _physics_process(delta: float) -> void:
	_update_invincibility(delta)
	_tick_action_overlays(delta)
	_silence_remaining = maxf(0.0, _silence_remaining - delta)
	_update_aim_from_mouse()
	_update_combat_input()
	if _state_machine != null:
		_state_machine.physics_update(delta)


func _get_input_direction_3d() -> Vector3:
	if _test_move_direction is Vector3:
		return (_test_move_direction as Vector3).normalized()
	var input_2d := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var direction := Vector3(input_2d.x, 0.0, input_2d.y)
	return direction.normalized() if direction.length_squared() > 0.0001 else Vector3.ZERO


func set_test_move_direction(direction: Variant) -> void:
	_test_move_direction = direction


func set_input_locked(locked: bool) -> void:
	if input_locked == locked or current_hp <= 0:
		return
	input_locked = locked
	if locked and weapon != null:
		weapon.cancel_charge()
	input_lock_changed.emit(locked)
	if _state_machine == null:
		return
	if locked:
		_state_machine.transition_to("locked")
	elif _state_machine.current_state_name == "locked":
		_transition_to_locomotion()


func set_combat_enabled(enabled: bool) -> void:
	combat_enabled = enabled


func get_presentation_state() -> String:
	return _presentation_state


## 外观装配是纯表现数据；不改碰撞、武器树、伤害或八态逻辑。
func set_avatar_customization(slot_id: String, variant_id: String) -> bool:
	if not PlayerAvatar3D.has_customization_variant(slot_id, variant_id):
		return false
	_avatar_customization[slot_id] = variant_id
	if avatar != null:
		avatar.set_customization(_avatar_customization)
	avatar_customization_changed.emit(get_avatar_customization())
	return true


func set_avatar_customization_loadout(loadout: Dictionary) -> void:
	for slot_id in loadout:
		var variant_id := str(loadout[slot_id])
		if PlayerAvatar3D.has_customization_variant(str(slot_id), variant_id):
			_avatar_customization[str(slot_id)] = variant_id
	if avatar != null:
		avatar.set_customization(_avatar_customization)
	avatar_customization_changed.emit(get_avatar_customization())


func get_avatar_customization() -> Dictionary:
	return _avatar_customization.duplicate()


func get_avatar_customization_options() -> Dictionary:
	return PlayerAvatar3D.CUSTOMIZATION_OPTIONS.duplicate(true)


func get_move_speed() -> float:
	return SPEED


func get_grounded_velocity(planar_velocity: Vector3) -> Vector3:
	var result := planar_velocity
	result.y = 0.0
	return result


func move_grounded(planar_velocity: Vector3, delta: float, allow_fall_transition := true) -> bool:
	var next_velocity := planar_velocity
	if is_on_floor():
		# 极小负值让 floor snap 保持接触，但不会把无输入角色沿斜坡推下。
		next_velocity.y = -0.01
	else:
		next_velocity.y = maxf(
			velocity.y - GRAVITY_MPS2 * maxf(delta, 0.0),
			-TERMINAL_FALL_SPEED_MPS
		)
	velocity = next_velocity
	move_and_slide()
	if is_on_floor():
		_airborne_elapsed = 0.0
		_record_safe_ground_position()
		return false
	_airborne_elapsed += maxf(delta, 0.0)
	if allow_fall_transition and _should_enter_falling():
		_begin_fall()
		return true
	_recover_from_invalid_fall_if_needed()
	return false


func move_airborne(target_planar_velocity: Vector3, delta: float) -> bool:
	var planar := Vector3(velocity.x, 0.0, velocity.z)
	planar = planar.move_toward(
		Vector3(target_planar_velocity.x, 0.0, target_planar_velocity.z),
		AIR_CONTROL_ACCEL_MPS2 * maxf(delta, 0.0)
	)
	var impact_speed := maxf(0.0, -velocity.y)
	velocity = Vector3(
		planar.x,
		maxf(velocity.y - GRAVITY_MPS2 * maxf(delta, 0.0), -TERMINAL_FALL_SPEED_MPS),
		planar.z
	)
	move_and_slide()
	if is_on_floor():
		_last_impact_speed = impact_speed
		_landing_duration = lerpf(
			LANDING_MIN_DURATION_S,
			LANDING_MAX_DURATION_S,
			clampf(
				(_last_impact_speed - FALL_STATE_SPEED_MPS)
				/ (LANDING_FULL_IMPACT_MPS - FALL_STATE_SPEED_MPS),
				0.0,
				1.0
			)
		)
		_airborne_elapsed = 0.0
		_record_safe_ground_position()
		return true
	_airborne_elapsed += maxf(delta, 0.0)
	_recover_from_invalid_fall_if_needed()
	return false


func get_landing_duration() -> float:
	return _landing_duration


func get_landing_impact_speed() -> float:
	return _last_impact_speed


func get_fall_speed_ratio() -> float:
	return clampf(maxf(0.0, -velocity.y) / TERMINAL_FALL_SPEED_MPS, 0.0, 1.0)


func get_vertical_physics_snapshot() -> Dictionary:
	return {
		"on_floor": is_on_floor(),
		"airborne_elapsed_s": _airborne_elapsed,
		"fall_start_y": _fall_start_y,
		"impact_speed_mps": _last_impact_speed,
		"landing_duration_s": _landing_duration,
		"safe_ground_position": _last_safe_ground_position,
		"has_safe_ground_position": _has_safe_ground_position,
		"fall_recovery_count": _fall_recovery_count,
		"gravity_mps2": GRAVITY_MPS2,
		"terminal_speed_mps": TERMINAL_FALL_SPEED_MPS,
	}


func _should_enter_falling() -> bool:
	return (
		not is_on_floor()
		and _airborne_elapsed >= AIRBORNE_GRACE_S
		and velocity.y <= -FALL_STATE_SPEED_MPS
	)


func _begin_fall() -> void:
	if _state_machine == null or _state_machine.current_state_name in ["falling", "dead"]:
		return
	_fall_start_y = global_position.y
	_state_machine.transition_to("falling")


func _record_safe_ground_position() -> void:
	_last_safe_ground_position = global_position
	_has_safe_ground_position = true


func _recover_from_invalid_fall_if_needed() -> void:
	if not _has_safe_ground_position:
		return
	if global_position.y >= _last_safe_ground_position.y - FALL_RECOVERY_DISTANCE_M:
		return
	global_position = _last_safe_ground_position + Vector3.UP * 0.08
	velocity = Vector3.ZERO
	_airborne_elapsed = 0.0
	_fall_recovery_count += 1
	if _state_machine != null and _state_machine.current_state_name == "falling":
		_last_impact_speed = TERMINAL_FALL_SPEED_MPS
		_landing_duration = LANDING_MAX_DURATION_S
		_state_machine.transition_to("landing")


func get_dash_speed() -> float:
	return DASH_SPEED


func get_dash_duration() -> float:
	return DASH_DURATION


func get_state_machine_state() -> String:
	return _state_machine.current_state_name if _state_machine != null else ""


func get_state_machine_snapshot() -> Dictionary:
	if _state_machine == null:
		return {}
	var snapshot := _state_machine.get_snapshot()
	var reload_snapshot := get_reload_snapshot()
	snapshot["overlays"] = {
		"low_health": is_low_health(),
		"silenced": _silence_remaining > 0.0,
		"invincible": is_invincible,
		"reloading": bool(reload_snapshot.get("active", false)),
		"firing": _fire_animation_remaining > 0.0,
		"charging": bool(get_action_snapshot().get("charging", false)),
		"knockback": _knockback_remaining > 0.0,
	}
	snapshot["reload"] = reload_snapshot
	snapshot["actions"] = get_action_snapshot()
	return snapshot


func is_low_health() -> bool:
	return current_hp > 0 and float(current_hp) / float(maxi(1, max_hp)) <= 0.30


func take_damage(amount: int, _critical := false, hit_direction := Vector3.ZERO) -> void:
	if current_hp <= 0 or is_invincible:
		return
	var overheat_multiplier := weapon_tree.get_overheat_penalty() if weapon_tree != null else 1.0
	_last_damage_amount = maxi(1, int(amount * overheat_multiplier))
	current_hp = maxi(0, current_hp - _last_damage_amount)
	if AudioManager != null:
		AudioManager.play_player_hit_sfx()
	hp_changed.emit(current_hp, max_hp)
	var recoil_direction := hit_direction
	if recoil_direction.length_squared() <= 0.001:
		recoil_direction = -aim_direction
	apply_knockback(
		recoil_direction,
		clampf(3.2 + float(_last_damage_amount) * 0.11, 3.2, 7.4),
		clampf(0.16 + float(_last_damage_amount) * 0.004, KNOCKBACK_MIN_DURATION, KNOCKBACK_MAX_DURATION),
		false,
	)
	is_invincible = true
	_invincible_remaining = INVINCIBLE_DURATION
	if current_hp <= 0:
		if weapon != null:
			weapon.cancel_reload()
		_clear_action_overlays()
		_state_machine.transition_to("dead", true)
	else:
		_state_machine.transition_to("hurt", true)


func heal(amount: int) -> void:
	if current_hp <= 0:
		return
	current_hp = mini(max_hp, current_hp + maxi(0, amount))
	hp_changed.emit(current_hp, max_hp)


func request_dash() -> void:
	if _state_machine != null:
		_state_machine.dispatch_event("request_dash")


## 受击击退是短时动作覆盖层；它让 hurt 状态延长到冲量结束，但不增加第七个顶层状态。
func apply_knockback(direction: Vector3, strength := 5.4, duration := 0.24, trigger_hurt := true) -> bool:
	if current_hp <= 0:
		return false
	var planar_direction := direction
	planar_direction.y = 0.0
	if planar_direction.length_squared() <= 0.001:
		planar_direction = -aim_direction
	planar_direction = planar_direction.normalized()
	_knockback_direction = planar_direction
	_knockback_strength = clampf(strength, 0.5, 10.0)
	_knockback_duration = clampf(duration, KNOCKBACK_MIN_DURATION, KNOCKBACK_MAX_DURATION)
	_knockback_remaining = _knockback_duration
	if trigger_hurt and _state_machine != null and _state_machine.current_state_name != "dead":
		_state_machine.transition_to("hurt", true)
	action_overlay_changed.emit(get_action_snapshot())
	return true


func consume_knockback_velocity(delta: float) -> Vector3:
	if _knockback_remaining <= 0.0 or _knockback_direction == Vector3.ZERO:
		return Vector3.ZERO
	var ratio := clampf(_knockback_remaining / maxf(0.01, _knockback_duration), 0.0, 1.0)
	var impulse := _knockback_direction * _knockback_strength * pow(ratio, 0.62)
	_knockback_remaining = maxf(0.0, _knockback_remaining - delta)
	if _knockback_remaining <= 0.0:
		_knockback_strength = 0.0
		action_overlay_changed.emit(get_action_snapshot())
	return impulse


func get_hurt_recovery_duration() -> float:
	return maxf(0.14, _knockback_remaining)


func get_action_snapshot() -> Dictionary:
	var weapon_snapshot := get_weapon_snapshot()
	var charge_active := bool(weapon_snapshot.get("charge_active", false))
	return {
		"firing": _fire_animation_remaining > 0.0,
		"fire_progress": clampf(1.0 - _fire_animation_remaining / maxf(0.01, _fire_animation_duration), 0.0, 1.0),
		"fire_intensity": _fire_animation_intensity,
		"charging": charge_active,
		"charge_progress": float(weapon_snapshot.get("charge_ratio", 0.0)),
		"knockback": _knockback_remaining > 0.0,
		"knockback_progress": clampf(1.0 - _knockback_remaining / maxf(0.01, _knockback_duration), 0.0, 1.0),
		"knockback_direction": _knockback_direction,
		"knockback_strength": _knockback_strength,
	}


func equip_weapon(gun_id: String, bullet_id: String) -> bool:
	_ensure_weapon_tree()
	var gun := BlueprintRegistry.create_assembly_node(gun_id)
	var bullet := BlueprintRegistry.create_assembly_node(bullet_id)
	if gun == null or bullet == null:
		if gun != null:
			gun.free()
		if bullet != null:
			bullet.free()
		return false
	weapon_tree.clear_assembly(false)
	if not weapon_tree.set_root(gun):
		gun.free()
		bullet.free()
		return false
	if not weapon_tree.mount(gun, AssemblyNode.SlotType.BULLET, bullet):
		bullet.free()
		return false
	_ensure_weapon_model()
	_sync_weapon_from_tree()
	return true


func _ensure_weapon_model() -> void:
	if avatar == null or avatar.weapon_socket == null:
		return
	if weapon == null or not is_instance_valid(weapon):
		var scene := load("res://assets/art/weapons/weapon_3d/wpn_gun_kit_root_top3d_v001.tscn") as PackedScene
		if scene == null:
			return
		weapon = scene.instantiate() as WeaponModel3D
		weapon.gun_id = ""
		weapon.render_layers = 2
		avatar.weapon_socket.add_child(weapon)
		weapon.ammo_changed.connect(_on_weapon_ammo_changed)
		weapon.loadout_changed.connect(_on_weapon_loadout_changed)
		weapon.reload_started.connect(_on_weapon_reload_started)
		weapon.reload_progress_changed.connect(_on_weapon_reload_progress_changed)
		weapon.reload_ended.connect(_on_weapon_reload_ended)
		weapon.shot_fired.connect(_on_weapon_shot_fired)


func _ensure_weapon_tree() -> void:
	if weapon_tree == null:
		weapon_tree = BlueprintRegistry.get_starting_weapon_tree()
	if weapon_tree == null:
		weapon_tree = WeaponAssemblyTree.new()
	if weapon_tree.get_parent() == null:
		weapon_tree.name = "WeaponAssemblyTree"
		add_child(weapon_tree)
	if not weapon_tree.tree_changed.is_connected(_sync_weapon_from_tree):
		weapon_tree.tree_changed.connect(_sync_weapon_from_tree)
	if not weapon_tree.stats_changed.is_connected(_on_weapon_tree_stats_changed):
		weapon_tree.stats_changed.connect(_on_weapon_tree_stats_changed)


func _sync_weapon_from_tree() -> void:
	if weapon_tree == null:
		return
	_ensure_weapon_model()
	if weapon != null:
		weapon.configure_from_tree(weapon_tree)
		_apply_named_damage_multipliers()


func _on_weapon_tree_stats_changed(_stats: Dictionary) -> void:
	_sync_weapon_from_tree()


func get_weapon_tree() -> WeaponAssemblyTree:
	_ensure_weapon_tree()
	return weapon_tree


func refill_ammo() -> bool:
	return weapon != null and weapon.refill_ammo()


func set_damage_multiplier(source: String, multiplier: float) -> void:
	_named_damage_multipliers[source] = maxf(0.1, multiplier)
	_apply_named_damage_multipliers()


func apply_damage_buff(source: String, bonus: float) -> void:
	_named_damage_multipliers[source] = 1.0 + bonus
	_apply_named_damage_multipliers()


func remove_damage_buff(source: String) -> void:
	_named_damage_multipliers.erase(source)
	_apply_named_damage_multipliers()


func _apply_named_damage_multipliers() -> void:
	var final_multiplier := 1.0
	for value in _named_damage_multipliers.values():
		final_multiplier = maxf(final_multiplier, float(value))
	if weapon != null:
		weapon.set_damage_multiplier(final_multiplier)


func apply_silence(duration: float) -> void:
	_silence_remaining = maxf(_silence_remaining, duration)


func clear_weapon() -> void:
	if weapon_tree != null:
		weapon_tree.clear_assembly()
	if weapon != null and is_instance_valid(weapon):
		weapon.clear_weapon()


func get_weapon_snapshot() -> Dictionary:
	return weapon.get_snapshot() if weapon != null and is_instance_valid(weapon) else {
		"gun_id": "", "bullet_id": "", "has_model": false, "is_3d": true,
	}


func is_reloading() -> bool:
	return weapon != null and is_instance_valid(weapon) and weapon.is_reloading()


func get_reload_progress() -> float:
	return weapon.get_reload_progress() if weapon != null and is_instance_valid(weapon) else 0.0


func get_reload_snapshot() -> Dictionary:
	return weapon.get_reload_snapshot() if weapon != null and is_instance_valid(weapon) else {
		"active": false,
		"progress": 0.0,
		"remaining": 0.0,
		"duration": 0.0,
	}


func _on_weapon_ammo_changed(current: int, maximum: int) -> void:
	ammo_changed.emit(current, maximum)


func _on_weapon_loadout_changed(gun_id: String, bullet_id: String) -> void:
	weapon_changed.emit(gun_id, bullet_id)


func _on_weapon_reload_started(duration: float) -> void:
	reload_started.emit(duration)


func _on_weapon_reload_progress_changed(progress: float, remaining: float) -> void:
	reload_progress_changed.emit(progress, remaining)


func _on_weapon_reload_ended(completed: bool) -> void:
	reload_ended.emit(completed)


func _on_weapon_shot_fired(projectile_count: int) -> void:
	_fire_animation_duration = FIRE_ANIMATION_DURATION
	_fire_animation_remaining = _fire_animation_duration
	_fire_animation_intensity = clampf(0.72 + float(projectile_count) * 0.12, 0.72, 1.35)
	action_overlay_changed.emit(get_action_snapshot())


func _update_combat_input() -> void:
	if weapon != null and Input.is_action_just_released("shoot"):
		weapon.release_charge()
	if input_locked or current_hp <= 0 or weapon == null or _silence_remaining > 0.0:
		if weapon != null:
			weapon.cancel_charge()
		return
	# 禁用玩家输入不应打断脚本、测试场或 AI 显式启动的蓄力；只有真实输入读取被跳过。
	if not combat_enabled:
		return
	if Input.is_action_pressed("shoot"):
		weapon.try_fire(aim_direction, self)
	if Input.is_action_just_pressed("reload"):
		weapon.request_reload()


func _begin_dash() -> bool:
	if (
		input_locked
		or current_hp <= 0
		or is_dashing
		or dash_cooldown_timer > 0.0
		or (_state_machine != null and _state_machine.current_state_name in ["falling", "landing"])
	):
		return false
	var direction := _get_input_direction_3d()
	dash_direction = direction if direction != Vector3.ZERO else aim_direction
	if dash_direction == Vector3.ZERO:
		dash_direction = last_move_direction
	dash_direction = dash_direction.normalized()
	dash_cooldown_timer = DASH_COOLDOWN
	_state_machine.transition_to("dashing")
	return true


func _tick_dash_cooldown(delta: float) -> void:
	if dash_cooldown_timer > 0.0:
		dash_cooldown_timer = maxf(0.0, dash_cooldown_timer - delta)
	dash_cooldown_changed.emit(clampf(dash_cooldown_timer / DASH_COOLDOWN, 0.0, 1.0))


func _tick_action_overlays(delta: float) -> void:
	if _fire_animation_remaining <= 0.0:
		return
	_fire_animation_remaining = maxf(0.0, _fire_animation_remaining - delta)
	if _fire_animation_remaining <= 0.0:
		_fire_animation_intensity = 0.0
		action_overlay_changed.emit(get_action_snapshot())


func _clear_action_overlays() -> void:
	_fire_animation_remaining = 0.0
	_fire_animation_intensity = 0.0
	_knockback_remaining = 0.0
	_knockback_duration = 0.0
	_knockback_strength = 0.0
	_knockback_direction = Vector3.ZERO
	action_overlay_changed.emit(get_action_snapshot())


func _transition_to_locomotion() -> void:
	if _state_machine == null or current_hp <= 0:
		return
	if _should_enter_falling():
		_begin_fall()
		return
	if input_locked:
		_state_machine.transition_to("locked")
	elif _get_input_direction_3d() != Vector3.ZERO:
		_state_machine.transition_to("moving")
	else:
		_state_machine.transition_to("idle")


func _set_presentation_state(state_id: String, context: Dictionary = {}) -> void:
	_presentation_state = state_id
	presentation_state_changed.emit(state_id, context)


func _update_invincibility(delta: float) -> void:
	if not is_invincible:
		return
	_invincible_remaining = maxf(0.0, _invincible_remaining - delta)
	if _invincible_remaining <= 0.0 and not is_dashing:
		is_invincible = false


func _update_aim_from_mouse() -> void:
	if camera == null or not camera.is_inside_tree():
		return
	var mouse_position := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_position)
	var ray_direction := camera.project_ray_normal(mouse_position)
	# 塔楼使用真实层高和连续楼梯坡面。瞄准平面必须跟随角色当前物理高度，
	# 不能固定在世界 Y=0，否则下楼后光标会一直悬在楼顶。
	var intersection = Plane(Vector3.UP, global_position.y).intersects_ray(ray_origin, ray_direction)
	if not intersection is Vector3:
		return
	var target := intersection as Vector3
	var flat_direction := target - global_position
	flat_direction.y = 0.0
	if flat_direction.length_squared() <= 0.0001:
		return
	aim_direction = flat_direction.normalized()
	aim_yaw = atan2(-aim_direction.x, -aim_direction.z)
	aim_cursor.global_position = target + Vector3(0, 0.035, 0)


func _init_state_machine() -> void:
	_state_machine = StateMachine.new()
	_state_machine.name = "StateMachine"
	_state_machine.owner_node = self
	add_child(_state_machine)
	_state_machine.register("idle", Player3DIdleState.new())
	_state_machine.register("moving", Player3DMovingState.new())
	_state_machine.register("dashing", Player3DDashingState.new())
	_state_machine.register("hurt", Player3DHurtState.new())
	_state_machine.register("locked", Player3DLockedState.new())
	_state_machine.register("falling", Player3DFallingState.new())
	_state_machine.register("landing", Player3DLandingState.new())
	_state_machine.register("dead", Player3DDeadState.new())
	_state_machine.configure_transition_map({
		"idle": ["moving", "dashing", "hurt", "locked", "falling", "dead"],
		"moving": ["idle", "dashing", "hurt", "locked", "falling", "dead"],
		"dashing": ["idle", "moving", "hurt", "locked", "falling", "dead"],
		"hurt": ["idle", "moving", "locked", "falling", "dead"],
		"locked": ["idle", "moving", "hurt", "falling", "dead"],
		"falling": ["landing", "hurt", "dead"],
		"landing": ["idle", "moving", "hurt", "locked", "falling", "dead"],
		"dead": [],
	})
	_state_machine.start("idle")
