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
signal melee_action_changed(snapshot: Dictionary)
signal melee_hit_resolved(result: Dictionary)
signal avatar_customization_changed(loadout: Dictionary)
signal weapon_instance_changed(snapshot: Dictionary)
signal weapon_loadout_changed(snapshot: Dictionary)
signal backpack_equipment_changed(snapshot: Dictionary)
signal flashlight_module_changed(snapshot: Dictionary)
signal debug_scale_changed(snapshot: Dictionary)
signal death_animation_finished()

const SPEED := 5.0
const DASH_SPEED := 16.5
const DASH_DURATION := 0.204
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
const DEFAULT_BASE_SIZE_MULTIPLIER := 0.70
const DEBUG_SCALE_STEP_RATIO := 0.10
const DEBUG_SCALE_MIN_STEP := -9
const DEBUG_SCALE_MAX_STEP := 20

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
var _last_hit_direction := Vector3.ZERO
var _last_damage_source_snapshot: Dictionary = {}
var _last_damage_source_at_msec := 0
var _death_animation_progress := 0.0
var _death_animation_finished_emitted := false
var _invincible_remaining := 0.0
var _state_machine: StateMachine = null
var melee_combat: PlayerMeleeCombat3D = null
var _test_move_direction: Variant = null
var weapon: WeaponModel3D = null
var weapon_tree: WeaponAssemblyTree = null
var equipped_weapon_instance: WeaponInstance = null
var equipped_weapon_slots: Array = [null, null]
var active_weapon_slot := 0
var _loading_weapon_instance := false
var _stowed_weapon_model: WeaponModel3D = null
var _stowed_weapon_instance_id := ""
var equipped_backpack_item: Dictionary = {}
var equipped_flashlight_module: Dictionary = {}

# 移动端虚拟输入状态（来自 MobileInput autoload 的信号）。
var _mobile_move_direction := Vector2.ZERO
var _mobile_face_direction := Vector2.ZERO
var _mobile_face_active := false
var _mobile_shoot_active := false
var _mobile_shoot_was_active := false
var _mobile_input_available := false
var _mobile_input: Node = null
var _backpack_model: Node3D = null
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
var _footstep_sound_accumulator := 0.0
var _debug_scale_step := 0
var _base_avatar_scale := Vector3.ONE
var _base_collision_position := Vector3.ZERO
var _base_collision_radius := 0.0
var _base_collision_height := 0.0
var _debug_scale_initialized := false
var _character_fate := {
	"move_speed_multiplier": 1.0,
	"dash_cooldown_multiplier": 1.0,
	"damage_taken_multiplier": 1.0,
	"weapon_damage_multiplier": 1.0,
	"room_heal": 0,
	"elite_heal": 0,
	"first_hit_multiplier": 1.0,
	"first_hit_ready": false,
	"last_stand_charges": 0,
	"room_ammo_ratio": 0.0,
}

@onready var avatar: PlayerAvatar3D = $Avatar3D
@onready var camera: Camera3D = $Camera3D
@onready var aim_cursor: Node3D = $AimCursor
@onready var virtual_collision_capsule: CollisionShape3D = $VirtualCollisionCapsule


func _ready() -> void:
	current_hp = max_hp
	# v0.1：坡面由真实承重盒负责。短距离吸附只跨越数厘米接缝，
	# 不再用持续向下速度或世界坐标吸附模拟楼梯。
	floor_snap_length = 0.32
	floor_max_angle = deg_to_rad(44.0)
	floor_stop_on_slope = true
	floor_constant_speed = true
	safe_margin = 0.035
	add_to_group("player")
	add_to_group("player_3d")
	_init_state_machine()
	_init_melee_combat()
	_ensure_weapon_tree()
	if start_with_weapon:
		_ensure_weapon_model()
		_sync_weapon_from_tree()
	_refresh_stowed_weapon_model(true)
	if avatar != null:
		avatar.set_customization(_avatar_customization)
	_initialize_debug_scale_contract()
	hp_changed.emit(current_hp, max_hp)
	_hook_mobile_input()
	# 嵌入式运行窗口在首个 _ready 帧里可能尚未完成 Viewport/Camera 投影初始化。
	# 此时 project_ray_* 会返回非有限向量；若直接写入 top_level 的准星，
	# RenderingServer 会在之后每帧反复报告 instance_set_transform 并拖死编辑器。
	call_deferred("_update_aim_from_mouse")


func _unhandled_input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if _is_debug_scale_up_key(key_event):
		adjust_debug_scale(1)
		get_viewport().set_input_as_handled()
	elif _is_debug_scale_down_key(key_event):
		adjust_debug_scale(-1)
		get_viewport().set_input_as_handled()


func _is_debug_scale_up_key(event: InputEventKey) -> bool:
	return (
		event.unicode == 43
		or event.keycode == KEY_KP_ADD
		or (event.physical_keycode == KEY_EQUAL and event.shift_pressed)
	)


func _is_debug_scale_down_key(event: InputEventKey) -> bool:
	return (
		event.unicode == 45
		or event.keycode == KEY_KP_SUBTRACT
		or event.physical_keycode == KEY_MINUS
	)


func _initialize_debug_scale_contract() -> void:
	# 旧资产尺寸的70%现在定义为角色的新100%基础尺寸。
	_base_avatar_scale = avatar.scale * DEFAULT_BASE_SIZE_MULTIPLIER
	_base_collision_position = virtual_collision_capsule.position * DEFAULT_BASE_SIZE_MULTIPLIER
	if virtual_collision_capsule.shape != null:
		# 运行时体型调试不得修改场景共享的Shape资源。
		virtual_collision_capsule.shape = virtual_collision_capsule.shape.duplicate()
	var capsule := virtual_collision_capsule.shape as CapsuleShape3D
	if capsule != null:
		_base_collision_radius = capsule.radius * DEFAULT_BASE_SIZE_MULTIPLIER
		_base_collision_height = capsule.height * DEFAULT_BASE_SIZE_MULTIPLIER
	_debug_scale_initialized = true
	_apply_debug_scale()


func adjust_debug_scale(step_delta: int) -> void:
	set_debug_scale_step(_debug_scale_step + step_delta)


func set_debug_scale_step(step: int) -> void:
	if not _debug_scale_initialized:
		_initialize_debug_scale_contract()
	var clamped_step := clampi(step, DEBUG_SCALE_MIN_STEP, DEBUG_SCALE_MAX_STEP)
	if clamped_step == _debug_scale_step:
		return
	_debug_scale_step = clamped_step
	_apply_debug_scale()
	debug_scale_changed.emit(get_debug_scale_snapshot())


func reset_debug_scale() -> void:
	set_debug_scale_step(0)


func get_debug_scale_snapshot() -> Dictionary:
	var ratio := _get_debug_scale_ratio()
	var capsule := virtual_collision_capsule.shape as CapsuleShape3D
	return {
		"step": _debug_scale_step,
		"step_percent": roundi(DEBUG_SCALE_STEP_RATIO * 100.0),
		"base_size_multiplier": DEFAULT_BASE_SIZE_MULTIPLIER,
		"scale_ratio": ratio,
		"scale_percent": roundi(ratio * 100.0),
		"minimum_percent": roundi((1.0 + DEBUG_SCALE_MIN_STEP * DEBUG_SCALE_STEP_RATIO) * 100.0),
		"maximum_percent": roundi((1.0 + DEBUG_SCALE_MAX_STEP * DEBUG_SCALE_STEP_RATIO) * 100.0),
		"avatar_scale": avatar.scale,
		"collision_position": virtual_collision_capsule.position,
		"collision_radius": capsule.radius if capsule != null else 0.0,
		"collision_height": capsule.height if capsule != null else 0.0,
	}


func _get_debug_scale_ratio() -> float:
	# 永远从初始尺寸做线性加减：第2档是120%，不是110%再乘110%。
	return 1.0 + float(_debug_scale_step) * DEBUG_SCALE_STEP_RATIO


func _apply_debug_scale() -> void:
	if not _debug_scale_initialized:
		return
	var ratio := _get_debug_scale_ratio()
	avatar.scale = _base_avatar_scale * ratio
	virtual_collision_capsule.position = _base_collision_position * ratio
	var capsule := virtual_collision_capsule.shape as CapsuleShape3D
	if capsule != null:
		capsule.radius = _base_collision_radius * ratio
		capsule.height = _base_collision_height * ratio


func _physics_process(delta: float) -> void:
	_update_invincibility(delta)
	_tick_action_overlays(delta)
	_silence_remaining = maxf(0.0, _silence_remaining - delta)
	_update_aim_from_mouse()
	_update_combat_input()
	if _state_machine != null:
		_state_machine.physics_update(delta)
	if melee_combat != null:
		melee_combat.physics_update(delta)
	_tick_footstep_sound(delta)
	var flashlight := get_node_or_null("PlayerFlashlight3D")
	if flashlight != null:
		flashlight.set_in_facility(is_player_inside_facility())


func _hook_mobile_input() -> void:
	# 移动端 autoload 名为 MobileInput。autoload 加载顺序在 Player3D 之前。
	# 找不到时（极端情况：autoload 没注册）静默退化，键盘鼠标照旧。
	# v0.1 MobileInput 只暴露 move_direction / shoot_pressed / shoot_released / face_direction 。
	# R/SHIFT/F/E 四位动作以 Dungeon3D 的 HUD 按钮为准，走 Input.parse_input_event 入口。
	var mi: Node = get_node_or_null("/root/MobileInput")
	if mi == null:
		_mobile_input_available = false
		return
	_mobile_input = mi
	_mobile_input_available = true
	if not mi.move_direction.is_connected(_on_mobile_move_direction):
		mi.move_direction.connect(_on_mobile_move_direction)
	if not mi.face_direction.is_connected(_on_mobile_face_direction):
		mi.face_direction.connect(_on_mobile_face_direction)
	if not mi.shoot_pressed.is_connected(_on_mobile_shoot_pressed):
		mi.shoot_pressed.connect(_on_mobile_shoot_pressed)
	if not mi.shoot_released.is_connected(_on_mobile_shoot_released):
		mi.shoot_released.connect(_on_mobile_shoot_released)


func _on_mobile_move_direction(direction: Vector2) -> void:
	_mobile_move_direction = direction


func _on_mobile_face_direction(aim: Vector2) -> void:
	# aim: 正右、正下；_mobile_face_direction 用于替换鼠标 aim；Vector2 → Vector3(x, 0, y)
	_mobile_face_direction = aim
	_mobile_face_active = aim.length_squared() > 0.05



func _on_mobile_shoot_pressed() -> void:
	_mobile_shoot_active = true


func _on_mobile_shoot_released() -> void:
	_mobile_shoot_active = false





func _get_input_direction_3d() -> Vector3:
	if _test_move_direction is Vector3:
		return (_test_move_direction as Vector3).normalized()
	# 移动端优先：在摇杆活动时使用虚拟摇杆
	if _mobile_input_available and _mobile_move_direction.length_squared() > 0.0001:
		var direction := Vector3(_mobile_move_direction.x, 0.0, _mobile_move_direction.y)
		return direction.normalized() if direction.length_squared() > 0.0001 else Vector3.ZERO
	var input_2d := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var direction := Vector3(input_2d.x, 0.0, input_2d.y)
	return direction.normalized() if direction.length_squared() > 0.0001 else Vector3.ZERO


func _get_mobile_face_direction() -> Vector3:
	if not _mobile_input_available or not _mobile_face_active:
		return Vector3.ZERO
	# 屏幕坐标 → 世界空间：使用相机当前 yaw 投影，使右滑 = 玩家右转、上滑 = 玩家后退
	var cam_basis := camera.global_basis if camera != null else global_basis
	var forward_2d := -Vector2(cam_basis.z.x, cam_basis.z.z).normalized()
	var right_2d := Vector2(forward_2d.y, -forward_2d.x)
	var aim := right_2d * _mobile_face_direction.x + forward_2d * (-_mobile_face_direction.y)
	return Vector3(aim.x, 0.0, aim.y).normalized() if aim.length_squared() > 0.0001 else Vector3.ZERO


func set_test_move_direction(direction: Variant) -> void:
	_test_move_direction = direction


func set_input_locked(locked: bool) -> void:
	if input_locked == locked or current_hp <= 0:
		return
	input_locked = locked
	if locked and weapon != null:
		weapon.cancel_charge()
	if locked and melee_combat != null:
		melee_combat.cancel("input_locked")
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
	return SPEED * float(_character_fate.get("move_speed_multiplier", 1.0))


func get_dash_cooldown_duration() -> float:
	return DASH_COOLDOWN * float(_character_fate.get("dash_cooldown_multiplier", 1.0))


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
	var flashlight := get_node_or_null("PlayerFlashlight3D")
	snapshot["overlays"] = {
		"low_health": is_low_health(),
		"silenced": _silence_remaining > 0.0,
		"invincible": is_invincible,
		"reloading": bool(reload_snapshot.get("active", false)),
		"firing": _fire_animation_remaining > 0.0,
		"charging": bool(get_action_snapshot().get("charging", false)),
		"melee": bool(get_action_snapshot().get("melee_active", false)),
		"knockback": _knockback_remaining > 0.0,
		"flashlight": flashlight.get_snapshot() if flashlight != null else {"enabled": false, "charge_ratio": 1.0, "depleted": false, "in_facility": false},
	}
	snapshot["reload"] = reload_snapshot
	snapshot["actions"] = get_action_snapshot()
	snapshot["melee_action_machine"] = melee_combat.get_snapshot() if melee_combat != null else {}
	return snapshot


func is_low_health() -> bool:
	return current_hp > 0 and float(current_hp) / float(maxi(1, max_hp)) <= 0.30


func take_damage(amount: int, _critical := false, hit_direction := Vector3.ZERO, knockback_override := false, knockback_strength := 0.0) -> void:
	if current_hp <= 0 or is_invincible:
		return
	var overheat_multiplier := weapon_tree.get_overheat_penalty() if weapon_tree != null else 1.0
	var fate_multiplier := float(_character_fate.get("damage_taken_multiplier", 1.0))
	if bool(_character_fate.get("first_hit_ready", false)):
		fate_multiplier *= float(_character_fate.get("first_hit_multiplier", 1.0))
		_character_fate["first_hit_ready"] = false
	_last_damage_amount = maxi(1, int(round(float(amount) * overheat_multiplier * fate_multiplier)))
	if hit_direction.length_squared() > 0.001:
		_last_hit_direction = Vector3(hit_direction.x, 0.0, hit_direction.z).normalized()
	var next_hp := current_hp - _last_damage_amount
	if next_hp <= 0 and int(_character_fate.get("last_stand_charges", 0)) > 0:
		_character_fate["last_stand_charges"] = int(_character_fate["last_stand_charges"]) - 1
		next_hp = 1
	current_hp = maxi(0, next_hp)
	if AudioManager != null:
		AudioManager.play_player_hit_sfx()
	hp_changed.emit(current_hp, max_hp)
	# 普通受击不击退；只有特殊攻击 (knockback_override=true) 才推角色。
	if knockback_override:
		var recoil_direction := hit_direction
		if recoil_direction.length_squared() <= 0.001:
			recoil_direction = -aim_direction
		var strength := knockback_strength if knockback_strength > 0.0 else clampf(3.2 + float(_last_damage_amount) * 0.11, 3.2, 7.4)
		var duration := clampf(0.16 + float(_last_damage_amount) * 0.004, KNOCKBACK_MIN_DURATION, KNOCKBACK_MAX_DURATION)
		apply_knockback(recoil_direction, strength, duration, false)
	is_invincible = true
	_invincible_remaining = INVINCIBLE_DURATION
	if current_hp <= 0:
		if weapon != null:
			weapon.cancel_reload()
		_clear_action_overlays()
		_death_animation_progress = 0.0
		_death_animation_finished_emitted = false
		_state_machine.transition_to("dead", true)
	else:
		_state_machine.transition_to("hurt", true)


func notify_attacked_by(source: Node3D) -> void:
	_last_damage_source_snapshot.clear()
	_last_damage_source_at_msec = Time.get_ticks_msec()
	if source == null or not is_instance_valid(source) or not source.has_method("get_enemy_data"):
		return
	var source_data := source.call("get_enemy_data") as Dictionary
	_last_damage_source_snapshot = {
		"elite_id": str(source_data.get("elite_id", "")),
		"encounter_instance_id": str(source_data.get("encounter_instance_id", "")),
		"room_id": str(source.get("room_id")),
		"floor_number": int(source_data.get("floor_number", source_data.get("floor", 0))),
	}


func get_last_damage_source_snapshot(max_age_msec := 2500) -> Dictionary:
	if Time.get_ticks_msec() - _last_damage_source_at_msec > maxi(0, max_age_msec):
		return {}
	return _last_damage_source_snapshot.duplicate(true)


func heal(amount: int) -> void:
	if current_hp <= 0:
		return
	current_hp = mini(max_hp, current_hp + maxi(0, amount))
	hp_changed.emit(current_hp, max_hp)


func apply_character_fate_modifier(effect: Dictionary) -> Dictionary:
	var modifier := str(effect.get("modifier", ""))
	match modifier:
		"max_hp":
			var amount := maxi(0, int(effect.get("amount", 0)))
			max_hp += amount
			current_hp = mini(max_hp, current_hp + amount)
			hp_changed.emit(current_hp, max_hp)
		"move_speed":
			_character_fate["move_speed_multiplier"] = float(_character_fate["move_speed_multiplier"]) * float(effect.get("multiplier", 1.0))
		"dash_cooldown":
			_character_fate["dash_cooldown_multiplier"] = float(_character_fate["dash_cooldown_multiplier"]) * float(effect.get("multiplier", 1.0))
		"damage_taken":
			_character_fate["damage_taken_multiplier"] = float(_character_fate["damage_taken_multiplier"]) * float(effect.get("multiplier", 1.0))
		"weapon_damage":
			_character_fate["weapon_damage_multiplier"] = float(_character_fate["weapon_damage_multiplier"]) * float(effect.get("multiplier", 1.0))
			set_damage_multiplier("fate_moon_power", float(_character_fate["weapon_damage_multiplier"]))
		"room_heal":
			_character_fate["room_heal"] = int(_character_fate["room_heal"]) + int(effect.get("amount", 0))
		"elite_heal":
			_character_fate["elite_heal"] = int(_character_fate["elite_heal"]) + int(effect.get("amount", 0))
		"first_hit_guard":
			_character_fate["first_hit_multiplier"] = float(_character_fate["first_hit_multiplier"]) * float(effect.get("multiplier", 1.0))
			_character_fate["first_hit_ready"] = true
		"last_stand":
			_character_fate["last_stand_charges"] = int(_character_fate["last_stand_charges"]) + int(effect.get("charges", 1))
		"room_ammo":
			_character_fate["room_ammo_ratio"] = float(_character_fate["room_ammo_ratio"]) + float(effect.get("ratio", 0.0))
		_:
			return {"success": false, "message": "未知月亮命运效果：" + modifier}
	return {"success": true, "message": "月亮命运已写入角色本局状态"}


func on_fate_room_entered() -> Dictionary:
	_character_fate["first_hit_ready"] = float(_character_fate.get("first_hit_multiplier", 1.0)) < 1.0
	var healed := int(_character_fate.get("room_heal", 0))
	if healed > 0:
		heal(healed)
	var ammo_added := 0
	if weapon != null and is_instance_valid(weapon):
		ammo_added = int(ceil(float(weapon.magazine_size) * float(_character_fate.get("room_ammo_ratio", 0.0))))
		if ammo_added > 0:
			weapon.current_ammo = mini(weapon.magazine_size, weapon.current_ammo + ammo_added)
			weapon.ammo_changed.emit(weapon.current_ammo, weapon.magazine_size)
	return {"healed": healed, "ammo_added": ammo_added}


func on_fate_elite_killed() -> int:
	var amount := int(_character_fate.get("elite_heal", 0))
	if amount > 0:
		heal(amount)
	return amount


func get_character_fate_snapshot() -> Dictionary:
	return _character_fate.duplicate(true)


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
	var melee_snapshot := melee_combat.get_snapshot() if melee_combat != null else {
		"active": false, "phase": "ready", "phase_progress": 0.0,
		"combo_step": 0, "combo_count": 0, "queued_next": false,
		"attack_instance_id": "",
	}
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
		"melee_active": bool(melee_snapshot.get("active", false)),
		"melee_phase": str(melee_snapshot.get("phase", "ready")),
		"melee_progress": float(melee_snapshot.get("phase_progress", 0.0)),
		"melee_combo_step": int(melee_snapshot.get("combo_step", 0)),
		"melee_combo_count": int(melee_snapshot.get("combo_count", 0)),
		"melee_queued_next": bool(melee_snapshot.get("queued_next", false)),
		"melee_attack_instance_id": str(melee_snapshot.get("attack_instance_id", "")),
		"melee": melee_snapshot,
	}


func equip_weapon(gun_id: String, bullet_id: String) -> bool:
	_ensure_weapon_tree()
	var gun := BlueprintRegistry.create_assembly_node(gun_id)
	var is_melee := gun != null and "melee" in gun.tags
	var bullet := BlueprintRegistry.create_assembly_node(bullet_id) if not is_melee else null
	if gun == null or (not is_melee and bullet == null):
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
	if not is_melee and not weapon_tree.mount(gun, AssemblyNode.SlotType.BULLET, bullet):
		bullet.free()
		return false
	_ensure_weapon_model()
	_sync_weapon_from_tree()
	equipped_weapon_instance = WeaponInstance.from_runtime_tree(weapon_tree)
	equipped_weapon_slots[active_weapon_slot] = equipped_weapon_instance
	_sync_equipped_weapon_instance()
	weapon_instance_changed.emit(get_weapon_presentation_snapshot())
	weapon_loadout_changed.emit(get_weapon_loadout_snapshot())
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
	if equipped_weapon_instance == null and weapon_tree.get_root() != null:
		equipped_weapon_instance = WeaponInstance.from_runtime_tree(weapon_tree)
		equipped_weapon_slots[active_weapon_slot] = equipped_weapon_instance


func _sync_weapon_from_tree() -> void:
	if weapon_tree == null:
		return
	if melee_combat != null:
		melee_combat.cancel("weapon_tree_changed")
	_ensure_weapon_model()
	if weapon != null:
		weapon.set_meta(
			"fate_slot_used",
			equipped_weapon_instance.fate_upgrades.size()
			if equipped_weapon_instance != null else 0,
		)
		weapon.configure_from_tree(weapon_tree)
		_apply_named_damage_multipliers()
	_sync_equipped_weapon_instance()


func _on_weapon_tree_stats_changed(_stats: Dictionary) -> void:
	_sync_weapon_from_tree()


func get_weapon_tree() -> WeaponAssemblyTree:
	_ensure_weapon_tree()
	return weapon_tree


func get_equipped_weapon_instance() -> WeaponInstance:
	_ensure_weapon_tree()
	_sync_equipped_weapon_instance()
	return equipped_weapon_instance


func get_equipped_weapon_item() -> Dictionary:
	var instance := get_equipped_weapon_instance()
	return instance.to_item_dictionary() if instance != null else {}


func get_equipped_weapon_instance_id() -> String:
	var instance := get_equipped_weapon_instance()
	return instance.weapon_instance_id if instance != null else ""


func get_active_weapon_slot() -> int:
	return active_weapon_slot


func get_equipped_weapon_instance_for_slot(slot_index: int) -> WeaponInstance:
	if slot_index < 0 or slot_index >= equipped_weapon_slots.size():
		return null
	if slot_index == active_weapon_slot:
		_sync_equipped_weapon_instance()
	return equipped_weapon_slots[slot_index] as WeaponInstance


func get_equipped_weapon_item_for_slot(slot_index: int) -> Dictionary:
	var instance := get_equipped_weapon_instance_for_slot(slot_index)
	return instance.to_item_dictionary() if instance != null else {}


func get_equipped_weapon_instance_id_for_slot(slot_index: int) -> String:
	var instance := get_equipped_weapon_instance_for_slot(slot_index)
	return instance.weapon_instance_id if instance != null else ""


func get_weapon_loadout_snapshot() -> Dictionary:
	var slots: Array[Dictionary] = []
	for slot_index in range(2):
		var instance := get_equipped_weapon_instance_for_slot(slot_index)
		var presentation := (
			instance.get_presentation_snapshot(
				weapon_tree if slot_index == active_weapon_slot else null,
				"主武器" if slot_index == 0 else "副武器"
			)
			if instance != null else {}
		)
		presentation["slot_index"] = slot_index
		presentation["slot_name"] = "主武器" if slot_index == 0 else "副武器"
		presentation["active"] = slot_index == active_weapon_slot
		slots.append(presentation)
	var stowed_visible := _stowed_weapon_model != null and is_instance_valid(_stowed_weapon_model)
	var stowed_slot := 1 - active_weapon_slot if stowed_visible else -1
	var stowed_socket: Marker3D = null
	if stowed_visible and avatar != null:
		stowed_socket = avatar.get_stowed_weapon_socket(stowed_slot)
	return {
		"active_slot": active_weapon_slot,
		"slots": slots,
		"stowed_visible": stowed_visible,
		"stowed_instance_id": _stowed_weapon_instance_id,
		"stowed_slot": stowed_slot,
		"stowed_socket_name": stowed_socket.name if stowed_socket != null else "",
		"stowed_socket_position": stowed_socket.position if stowed_socket != null else Vector3.ZERO,
		"stowed_muzzle_direction": -stowed_socket.global_basis.z.normalized() if stowed_socket != null else Vector3.ZERO,
	}


func get_weapon_presentation_snapshot() -> Dictionary:
	var instance := get_equipped_weapon_instance()
	return instance.get_presentation_snapshot(weapon_tree, "已装备") if instance != null else {}


func get_weapon_attachment_layout_for_slot(slot_index: int) -> Array[Dictionary]:
	var instance := get_equipped_weapon_instance_for_slot(slot_index)
	if instance == null:
		return []
	var presentation := instance.get_presentation_snapshot(
		weapon_tree if slot_index == active_weapon_slot else null,
		"主武器" if slot_index == 0 else "副武器"
	)
	var raw_layout: Variant = presentation.get("attachment_layout", [])
	var layout: Array[Dictionary] = []
	if raw_layout is Array:
		for entry in raw_layout:
			if entry is Dictionary:
				layout.append((entry as Dictionary).duplicate(true))
	return layout


## 给指定主/副武器安装一个普通枪械配件。武器实例拥有完整装配树，因此切枪、
## 整枪入包/落地/保险时配件天然随枪移动；单独拆装只在此事务边界发生。
func install_attachment_item_to_weapon_slot(
	item: Dictionary, weapon_slot_index: int, requested_slot_type := -1
) -> Dictionary:
	if weapon_slot_index < 0 or weapon_slot_index >= equipped_weapon_slots.size():
		return {"success": false, "reason": "武器槽无效"}
	if str(item.get("type", "")) != "attachment":
		return {"success": false, "reason": "该物品不是枪械配件"}
	var instance := get_equipped_weapon_instance_for_slot(weapon_slot_index)
	if instance == null:
		return {"success": false, "reason": "目标武器槽为空"}
	var new_node := BlueprintRegistry.create_assembly_node(str(item.get("assembly_id", item.get("id", ""))))
	if new_node == null or new_node.node_type != AssemblyNode.NodeType.ATTACHMENT:
		if new_node != null:
			new_node.free()
		return {"success": false, "reason": "配件装配数据无效"}
	var slot_type := new_node.get_attachment_slot_type()
	if requested_slot_type >= 0 and slot_type != requested_slot_type:
		new_node.free()
		return {"success": false, "reason": "配件与目标槽位不匹配"}
	var temp_tree := instance.build_runtime_tree()
	if temp_tree == null or temp_tree.get_root() == null:
		new_node.free()
		if temp_tree != null:
			temp_tree.free()
		return {"success": false, "reason": "目标武器构筑无法读取"}
	var root := temp_tree.get_root()
	if not root.supports_attachment_slot(slot_type):
		new_node.free()
		temp_tree.free()
		return {"success": false, "reason": "该枪械未开放%s槽" % AssemblyNode.get_attachment_slot_display_name(slot_type)}
	var existing := root.slots.get(slot_type) as AssemblyNode
	if existing != null and BlueprintRegistry.get_item_id_for_assembly_node(existing) == str(item.get("id", "")):
		new_node.free()
		temp_tree.free()
		return {"success": false, "reason": "目标槽已安装同款配件"}
	var removed_item := BlueprintRegistry.get_item_for_assembly_node(existing)
	if existing != null:
		temp_tree.unmount(existing)
	if not temp_tree.mount(root, slot_type, new_node):
		if existing != null:
			temp_tree.mount(root, slot_type, existing)
		new_node.free()
		temp_tree.free()
		return {"success": false, "reason": "配件安装规则校验失败"}
	instance.capture_runtime_tree(temp_tree)
	temp_tree.free()
	if existing != null and is_instance_valid(existing):
		existing.free()
	if not _refresh_weapon_slot_after_instance_change(weapon_slot_index, instance):
		return {"success": false, "reason": "配件已写入实例，但运行态刷新失败"}
	return {
		"success": true,
		"slot_type": slot_type,
		"slot_key": AssemblyNode.get_attachment_slot_key(slot_type),
		"removed_item": removed_item,
		"weapon_item": instance.to_item_dictionary(),
	}


func remove_attachment_from_weapon_slot(weapon_slot_index: int, slot_type: int) -> Dictionary:
	if slot_type not in AssemblyNode.PUBLIC_ATTACHMENT_SLOTS:
		return {"success": false, "reason": "配件槽无效"}
	var instance := get_equipped_weapon_instance_for_slot(weapon_slot_index)
	if instance == null:
		return {"success": false, "reason": "目标武器槽为空"}
	var temp_tree := instance.build_runtime_tree()
	if temp_tree == null or temp_tree.get_root() == null:
		if temp_tree != null:
			temp_tree.free()
		return {"success": false, "reason": "目标武器构筑无法读取"}
	var existing := temp_tree.get_root().slots.get(slot_type) as AssemblyNode
	if existing == null:
		temp_tree.free()
		return {"success": false, "reason": "该槽位没有配件"}
	var removed_item := BlueprintRegistry.get_item_for_assembly_node(existing)
	if removed_item.is_empty() or not temp_tree.unmount(existing):
		temp_tree.free()
		return {"success": false, "reason": "配件缺少物品映射，已阻止数据丢失"}
	instance.capture_runtime_tree(temp_tree)
	temp_tree.free()
	if is_instance_valid(existing):
		existing.free()
	if not _refresh_weapon_slot_after_instance_change(weapon_slot_index, instance):
		return {"success": false, "reason": "拆卸已写入实例，但运行态刷新失败"}
	return {
		"success": true,
		"slot_type": slot_type,
		"removed_item": removed_item,
		"weapon_item": instance.to_item_dictionary(),
	}


func _refresh_weapon_slot_after_instance_change(slot_index: int, instance: WeaponInstance) -> bool:
	equipped_weapon_slots[slot_index] = instance
	if slot_index == active_weapon_slot:
		if not _load_active_weapon_instance(instance):
			return false
	else:
		_refresh_stowed_weapon_model(true)
	weapon_instance_changed.emit(get_weapon_presentation_snapshot())
	weapon_loadout_changed.emit(get_weapon_loadout_snapshot())
	return true


func get_equipped_backpack_item() -> Dictionary:
	return equipped_backpack_item.duplicate(true)


func get_backpack_equipment_snapshot() -> Dictionary:
	var socket := avatar.get_backpack_socket() if avatar != null else null
	return {
		"equipped": not equipped_backpack_item.is_empty(),
		"item_id": str(equipped_backpack_item.get("id", "")),
		"display_name": str(equipped_backpack_item.get("name", "")),
		"extra_slots": int(equipped_backpack_item.get("extra_slots", 0)),
		"socket_name": socket.name if socket != null else "",
		"socket_position": socket.position if socket != null else Vector3.ZERO,
		"model_visible": _backpack_model != null and is_instance_valid(_backpack_model),
		"model_kind": "backpack" if _backpack_model != null else "",
		"mesh_count": ItemModelFactory3D.count_mesh_instances(_backpack_model) if _backpack_model != null else 0,
	}


func equip_backpack_item(item: Dictionary) -> Dictionary:
	if str(item.get("type", "")) != "equipment" or str(item.get("subtype", "")) != "backpack":
		return {"success": false, "reason": "该物品不是背包装备"}
	var extra_slots := int(item.get("extra_slots", 0))
	if extra_slots not in [2, 4, 8]:
		return {"success": false, "reason": "背包容量配置无效"}
	var old_item := equipped_backpack_item.duplicate(true)
	equipped_backpack_item = item.duplicate(true)
	_refresh_backpack_model()
	var snapshot := get_backpack_equipment_snapshot()
	backpack_equipment_changed.emit(snapshot)
	return {"success": true, "old_item": old_item, "new_item": get_equipped_backpack_item(), "snapshot": snapshot}


func unequip_backpack_item() -> Dictionary:
	if equipped_backpack_item.is_empty():
		return {"success": false, "reason": "背包槽为空"}
	var old_item := equipped_backpack_item.duplicate(true)
	equipped_backpack_item.clear()
	_refresh_backpack_model()
	backpack_equipment_changed.emit(get_backpack_equipment_snapshot())
	return {"success": true, "old_item": old_item}


func clear_equipped_backpack() -> Dictionary:
	if equipped_backpack_item.is_empty():
		return {}
	var removed := equipped_backpack_item.duplicate(true)
	equipped_backpack_item.clear()
	_refresh_backpack_model()
	backpack_equipment_changed.emit(get_backpack_equipment_snapshot())
	return removed


func equip_flashlight_module(item: Dictionary) -> Dictionary:
	if str(item.get("type", "")) != "module" or str(item.get("subtype", "")) != "flashlight_module":
		return {"success": false, "reason": "该物品不是手电筒模块"}
	var raw_id: String = str(item.get("id", ""))
	var module_id: String = str(item.get("module_id", ""))
	if module_id.is_empty() and raw_id.begins_with("item_flashlight_"):
		module_id = raw_id.substr(len("item_flashlight_"))
	if module_id.is_empty():
		module_id = "basic"
	var flashlight := get_node_or_null("PlayerFlashlight3D")
	if flashlight == null:
		return {"success": false, "reason": "手电筒节点不存在"}
	if not bool(flashlight.set_module(module_id)):
		return {"success": false, "reason": "模块切换被拒绝(需在基地内)"}
	var old_item := equipped_flashlight_module.duplicate(true)
	equipped_flashlight_module = item.duplicate(true)
	equipped_flashlight_module["module_id"] = module_id
	var snapshot := get_flashlight_module_snapshot()
	flashlight_module_changed.emit(snapshot)
	return {"success": true, "old_item": old_item, "new_item": equipped_flashlight_module.duplicate(true), "snapshot": snapshot}


## 从长期装备选择创建当前局的运行态。该入口不代表局内换装，因此绕过基地限制。
func restore_flashlight_module(module_id: String) -> bool:
	var flashlight := get_node_or_null("PlayerFlashlight3D")
	if flashlight == null or not flashlight.has_method("restore_module"):
		return false
	if not bool(flashlight.restore_module(module_id)):
		return false
	var item := ItemRegistry.get_instance().get_item("item_flashlight_%s" % module_id)
	if item.is_empty():
		item = {"id": "item_flashlight_%s" % module_id, "module_id": module_id}
	equipped_flashlight_module = item.duplicate(true)
	equipped_flashlight_module["module_id"] = module_id
	flashlight_module_changed.emit(get_flashlight_module_snapshot())
	return true


func unequip_flashlight_module() -> Dictionary:
	if equipped_flashlight_module.is_empty():
		return {"success": false, "reason": "手电筒模块槽为空"}
	var flashlight := get_node_or_null("PlayerFlashlight3D")
	if flashlight != null:
		flashlight.set_module("basic")
	var old_item := equipped_flashlight_module.duplicate(true)
	equipped_flashlight_module.clear()
	flashlight_module_changed.emit(get_flashlight_module_snapshot())
	return {"success": true, "old_item": old_item}


func clear_equipped_flashlight_module() -> Dictionary:
	if equipped_flashlight_module.is_empty():
		return {}
	var removed := equipped_flashlight_module.duplicate(true)
	equipped_flashlight_module.clear()
	flashlight_module_changed.emit(get_flashlight_module_snapshot())
	return removed


func get_flashlight_module_snapshot() -> Dictionary:
	var flashlight := get_node_or_null("PlayerFlashlight3D")
	return {
		"equipped": not equipped_flashlight_module.is_empty(),
		"module_id": str(equipped_flashlight_module.get("module_id", "basic")),
		"item_id": str(equipped_flashlight_module.get("id", "")),
		"drain_multiplier": flashlight.get_drain_multiplier() if flashlight != null else 1.0,
		"reveal_multiplier": flashlight.get_reveal_multiplier() if flashlight != null else 1.0,
	}


func is_player_inside_facility() -> bool:
	var parent_node := get_parent()
	if parent_node != null and parent_node.has_method("is_player_inside_facility"):
		return bool(parent_node.call("is_player_inside_facility"))
	return false


func _refresh_backpack_model() -> void:
	if _backpack_model != null and is_instance_valid(_backpack_model):
		_backpack_model.queue_free()
	_backpack_model = null
	if equipped_backpack_item.is_empty() or avatar == null:
		return
	var socket := avatar.get_backpack_socket()
	if socket == null:
		return
	_backpack_model = ItemModelFactory3D.create_model(equipped_backpack_item)
	_backpack_model.name = "EquippedBackpackModel3D"
	_backpack_model.set_meta("equipment_item_id", str(equipped_backpack_item.get("id", "")))
	_backpack_model.set_meta("extra_slots", int(equipped_backpack_item.get("extra_slots", 0)))
	socket.add_child(_backpack_model)


func equip_weapon_item(item: Dictionary) -> Dictionary:
	return equip_weapon_item_to_slot(item, active_weapon_slot)


func equip_weapon_item_to_slot(item: Dictionary, slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= equipped_weapon_slots.size():
		return {"success": false, "reason": "武器槽无效"}
	_ensure_weapon_tree()
	var candidate := WeaponInstance.from_item(item)
	if candidate == null:
		return {"success": false, "reason": "武器实例无效"}
	for equipped_value in equipped_weapon_slots:
		var equipped := equipped_value as WeaponInstance
		if equipped != null and candidate.weapon_instance_id == equipped.weapon_instance_id:
			return {"success": false, "reason": "该武器实例已在主/副武器栏"}
	_sync_equipped_weapon_instance()
	var old_instance := equipped_weapon_slots[slot_index] as WeaponInstance
	var old_item := old_instance.to_item_dictionary() if old_instance != null else {}
	equipped_weapon_slots[slot_index] = candidate
	if slot_index == active_weapon_slot and not _load_active_weapon_instance(candidate):
		equipped_weapon_slots[slot_index] = old_instance
		if old_instance != null:
			_load_active_weapon_instance(old_instance)
		return {"success": false, "reason": "武器构筑快照无法加载"}
	_refresh_stowed_weapon_model(true)
	var snapshot := (
		get_weapon_presentation_snapshot()
		if slot_index == active_weapon_slot
		else candidate.get_presentation_snapshot(null, "副武器" if slot_index == 1 else "主武器")
	)
	weapon_instance_changed.emit(get_weapon_presentation_snapshot())
	weapon_loadout_changed.emit(get_weapon_loadout_snapshot())
	return {
		"success": true,
		"old_item": old_item,
		"new_item": candidate.to_item_dictionary(),
		"snapshot": snapshot,
		"slot_index": slot_index,
	}


func unequip_weapon_item() -> Dictionary:
	return unequip_weapon_item_from_slot(active_weapon_slot)


func unequip_weapon_item_from_slot(slot_index: int) -> Dictionary:
	var current := get_equipped_weapon_instance_for_slot(slot_index)
	if current == null:
		return {"success": false, "reason": "该装备槽没有枪械"}
	_sync_equipped_weapon_instance()
	var old_item := current.to_item_dictionary()
	equipped_weapon_slots[slot_index] = null
	if slot_index == active_weapon_slot:
		_loading_weapon_instance = true
		if weapon_tree != null:
			weapon_tree.clear_assembly(false)
		if weapon != null and is_instance_valid(weapon):
			weapon.clear_weapon()
		equipped_weapon_instance = null
		_loading_weapon_instance = false
		weapon_instance_changed.emit({})
		weapon_changed.emit("", "")
		ammo_changed.emit(0, 0)
	_refresh_stowed_weapon_model(true)
	weapon_loadout_changed.emit(get_weapon_loadout_snapshot())
	return {"success": true, "old_item": old_item, "slot_index": slot_index}


func switch_weapon_slot(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= equipped_weapon_slots.size():
		return {"success": false, "reason": "武器槽无效"}
	if slot_index == active_weapon_slot:
		return {"success": true, "unchanged": true, "slot_index": slot_index}
	var target := equipped_weapon_slots[slot_index] as WeaponInstance
	if target == null:
		return {"success": false, "reason": "%s未装备" % ("主武器" if slot_index == 0 else "副武器")}
	_sync_equipped_weapon_instance()
	var previous_slot := active_weapon_slot
	active_weapon_slot = slot_index
	if not _load_active_weapon_instance(target):
		active_weapon_slot = previous_slot
		_load_active_weapon_instance(equipped_weapon_slots[previous_slot] as WeaponInstance)
		return {"success": false, "reason": "目标武器构筑无法加载"}
	_refresh_stowed_weapon_model(true)
	var snapshot := get_weapon_presentation_snapshot()
	weapon_instance_changed.emit(snapshot)
	weapon_loadout_changed.emit(get_weapon_loadout_snapshot())
	return {"success": true, "slot_index": slot_index, "snapshot": snapshot}


func clear_all_equipped_weapons() -> Array[Dictionary]:
	_sync_equipped_weapon_instance()
	var removed: Array[Dictionary] = []
	for slot_index in range(equipped_weapon_slots.size()):
		var instance := equipped_weapon_slots[slot_index] as WeaponInstance
		if instance != null:
			removed.append(instance.to_item_dictionary())
		equipped_weapon_slots[slot_index] = null
	_loading_weapon_instance = true
	if weapon_tree != null:
		weapon_tree.clear_assembly(false)
	if weapon != null and is_instance_valid(weapon):
		weapon.clear_weapon()
	equipped_weapon_instance = null
	_loading_weapon_instance = false
	_refresh_stowed_weapon_model(true)
	weapon_instance_changed.emit({})
	weapon_loadout_changed.emit(get_weapon_loadout_snapshot())
	weapon_changed.emit("", "")
	ammo_changed.emit(0, 0)
	return removed


func _load_active_weapon_instance(instance: WeaponInstance) -> bool:
	if instance == null:
		return false
	_ensure_weapon_tree()
	_loading_weapon_instance = true
	var loaded := instance.load_into_runtime_tree(weapon_tree)
	_loading_weapon_instance = false
	if not loaded:
		return false
	equipped_weapon_instance = instance
	equipped_weapon_slots[active_weapon_slot] = instance
	_sync_weapon_from_tree()
	if weapon != null and instance.current_ammo >= 0:
		weapon.current_ammo = clampi(instance.current_ammo, 0, weapon.magazine_size)
		weapon.ammo_changed.emit(weapon.current_ammo, weapon.magazine_size)
	_sync_equipped_weapon_instance()
	return true


func _refresh_stowed_weapon_model(force := false) -> void:
	var stowed_slot := 1 - active_weapon_slot
	var stowed := equipped_weapon_slots[stowed_slot] as WeaponInstance
	var instance_id := stowed.weapon_instance_id if stowed != null else ""
	if not force and instance_id == _stowed_weapon_instance_id:
		return
	if _stowed_weapon_model != null and is_instance_valid(_stowed_weapon_model):
		_stowed_weapon_model.queue_free()
	_stowed_weapon_model = null
	_stowed_weapon_instance_id = instance_id
	if stowed == null or avatar == null or avatar.visual_root == null:
		return
	var stowed_socket := avatar.get_stowed_weapon_socket(stowed_slot)
	if stowed_socket == null:
		return
	var scene := load("res://assets/art/weapons/weapon_3d/wpn_gun_kit_root_top3d_v001.tscn") as PackedScene
	if scene == null:
		return
	_stowed_weapon_model = scene.instantiate() as WeaponModel3D
	_stowed_weapon_model.name = "StowedPrimaryWeaponModel3D" if stowed_slot == 0 else "StowedSecondaryWeaponModel3D"
	_stowed_weapon_model.display_only = true
	_stowed_weapon_model.render_layers = 2
	_stowed_weapon_model.set_meta("weapon_item_data", stowed.to_item_dictionary())
	_stowed_weapon_model.set_meta("weapon_slot_index", stowed_slot)
	stowed_socket.add_child(_stowed_weapon_model)
	_stowed_weapon_model.position = Vector3.ZERO
	_stowed_weapon_model.rotation = Vector3.ZERO
	_stowed_weapon_model.scale = Vector3.ONE * (0.70 if stowed.assembly_id in ["bp_baseball_bat", "bp_greatblade", "bp_waraxe"] else 0.52)


func append_equipped_fate_upgrade(card: FateCard, transaction_id: String = "") -> Dictionary:
	var instance := get_equipped_weapon_instance()
	if instance == null:
		return {"success": false, "reason": "当前没有装备枪械"}
	var result := instance.append_fate_upgrade(card, transaction_id)
	if bool(result.get("success", false)):
		_sync_equipped_weapon_instance()
		_sync_weapon_from_tree()
		weapon_instance_changed.emit(get_weapon_presentation_snapshot())
	return result


func _sync_equipped_weapon_instance() -> void:
	if _loading_weapon_instance or equipped_weapon_instance == null or weapon_tree == null:
		return
	equipped_weapon_instance.capture_runtime_tree(weapon_tree)
	equipped_weapon_slots[active_weapon_slot] = equipped_weapon_instance
	if weapon != null and is_instance_valid(weapon):
		equipped_weapon_instance.current_ammo = weapon.current_ammo


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
	if equipped_weapon_instance != null and not _loading_weapon_instance:
		equipped_weapon_instance.current_ammo = current
		weapon_instance_changed.emit(get_weapon_presentation_snapshot())
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


func _on_melee_action_changed(snapshot: Dictionary) -> void:
	melee_action_changed.emit(snapshot)
	action_overlay_changed.emit(get_action_snapshot())


func _on_melee_hit_resolved(result: Dictionary) -> void:
	melee_hit_resolved.emit(result)


func request_melee_attack() -> bool:
	return melee_combat != null and melee_combat.request_attack()


func _update_combat_input() -> void:
	var shoot_pressed_here: bool = Input.is_action_pressed("shoot")
	var shoot_just_pressed_here: bool = Input.is_action_just_pressed("shoot")
	var shoot_released_here: bool = Input.is_action_just_released("shoot")
	# 移动端：触屏按住优先级高于键盘鼠标
	if _mobile_input_available:
		if _mobile_shoot_active and not _mobile_shoot_was_active:
			shoot_just_pressed_here = true
		if _mobile_shoot_active:
			shoot_pressed_here = true
		if not _mobile_shoot_active and _mobile_shoot_was_active:
			shoot_released_here = true
		_mobile_shoot_was_active = _mobile_shoot_active
	if weapon != null and shoot_released_here:
		weapon.release_charge()
	if input_locked or current_hp <= 0 or weapon == null or _silence_remaining > 0.0:
		if weapon != null:
			weapon.cancel_charge()
		return
	# 禁用玩家输入不应打断脚本、测试场或 AI 显式启动的蓄力；只有真实输入读取被跳过。
	if not combat_enabled:
		return
	if weapon.is_melee_weapon():
		if shoot_just_pressed_here:
			request_melee_attack()
	elif shoot_pressed_here:
		weapon.try_fire(aim_direction, self)
	if not weapon.is_melee_weapon() and Input.is_action_just_pressed("reload"):
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
	if melee_combat != null:
		melee_combat.cancel("dash_started")
	dash_cooldown_timer = get_dash_cooldown_duration()
	if MonsterAIManager != null:
		MonsterAIManager.broadcast_sound_stimulus(global_position, 6.0, "dash", self)
	_state_machine.transition_to("dashing")
	return true


func _tick_footstep_sound(delta: float) -> void:
	if not is_on_floor() or Vector2(velocity.x, velocity.z).length() < 1.0 or is_dashing:
		_footstep_sound_accumulator = 0.0
		return
	_footstep_sound_accumulator += delta
	if _footstep_sound_accumulator < 0.55:
		return
	_footstep_sound_accumulator = fmod(_footstep_sound_accumulator, 0.55)
	if MonsterAIManager != null:
		MonsterAIManager.broadcast_sound_stimulus(global_position, 3.0, "footstep", self)


func _tick_dash_cooldown(delta: float) -> void:
	if dash_cooldown_timer > 0.0:
		dash_cooldown_timer = maxf(0.0, dash_cooldown_timer - delta)
	dash_cooldown_changed.emit(clampf(dash_cooldown_timer / maxf(0.01, get_dash_cooldown_duration()), 0.0, 1.0))


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
	if melee_combat != null:
		melee_combat.cancel("action_overlays_cleared")
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


func get_death_launch_direction() -> Vector3:
	if _last_hit_direction.length_squared() > 0.001:
		return _last_hit_direction
	var fallback := -aim_direction
	fallback.y = 0.0
	return fallback.normalized() if fallback.length_squared() > 0.001 else Vector3(0.0, 0.0, 1.0)


func _set_death_animation_progress(progress: float) -> void:
	_death_animation_progress = clampf(progress, 0.0, 1.0)


func get_death_animation_progress() -> float:
	return _death_animation_progress


func _complete_death_animation() -> void:
	if _death_animation_finished_emitted:
		return
	_death_animation_finished_emitted = true
	_death_animation_progress = 1.0
	death_animation_finished.emit()


func _update_invincibility(delta: float) -> void:
	if not is_invincible:
		return
	_invincible_remaining = maxf(0.0, _invincible_remaining - delta)
	if _invincible_remaining <= 0.0 and not is_dashing:
		is_invincible = false


func _update_aim_from_mouse() -> void:
	if camera == null or not camera.is_inside_tree():
		return
	# 移动端：触屏瞄准方向由摇杆控制时跳过鼠标射线
	if _mobile_input_available and _mobile_face_active:
		var aim_dir_3d := _get_mobile_face_direction()
		if aim_dir_3d.length_squared() > 0.0001:
			aim_direction = aim_dir_3d
			aim_yaw = atan2(-aim_dir_3d.x, -aim_dir_3d.z)
			var aim_cursor_distance := 3.2
			aim_cursor.global_position = global_position + aim_dir_3d * aim_cursor_distance + Vector3.UP * 0.035
			return
	var viewport := get_viewport()
	if viewport == null:
		return
	var viewport_size := viewport.get_visible_rect().size
	if (
		not viewport_size.is_finite()
		or viewport_size.x <= 1.0
		or viewport_size.y <= 1.0
		or not global_position.is_finite()
	):
		return
	var mouse_position := viewport.get_mouse_position()
	if not mouse_position.is_finite():
		return
	var ray_origin := camera.project_ray_origin(mouse_position)
	var ray_direction := camera.project_ray_normal(mouse_position)
	if (
		not ray_origin.is_finite()
		or not ray_direction.is_finite()
		or ray_direction.length_squared() <= 0.000001
		or absf(ray_direction.y) <= 0.000001
	):
		return
	# 塔楼使用真实层高和连续楼梯坡面。瞄准平面必须跟随角色当前物理高度，
	# 不能固定在世界 Y=0，否则下楼后光标会一直悬在楼顶。
	var intersection = Plane(Vector3.UP, global_position.y).intersects_ray(ray_origin, ray_direction)
	if not intersection is Vector3:
		return
	var target := intersection as Vector3
	if not target.is_finite():
		return
	var flat_direction := target - global_position
	flat_direction.y = 0.0
	if not flat_direction.is_finite() or flat_direction.length_squared() <= 0.0001:
		return
	var next_aim_direction := flat_direction.normalized()
	var next_aim_yaw := atan2(-next_aim_direction.x, -next_aim_direction.z)
	var next_cursor_position := target + Vector3(0, 0.035, 0)
	if (
		not next_aim_direction.is_finite()
		or not is_finite(next_aim_yaw)
		or not next_cursor_position.is_finite()
	):
		return
	aim_direction = next_aim_direction
	aim_yaw = next_aim_yaw
	aim_cursor.global_position = next_cursor_position


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


func _init_melee_combat() -> void:
	melee_combat = PlayerMeleeCombat3D.new()
	melee_combat.name = "MeleeCombat3D"
	add_child(melee_combat)
	melee_combat.configure(self)
	melee_combat.action_changed.connect(_on_melee_action_changed)
	melee_combat.hit_resolved.connect(_on_melee_hit_resolved)
