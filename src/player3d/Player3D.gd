class_name Player3D
extends CharacterBody3D
## 首张 3D 地图使用的玩家外壳。状态机包含真实下落、落地与座椅乘坐，
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

const SPEED := 4.6
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
## 基地可推动家具的低速持续推力；避免接触每帧叠加冲量。
const PUSHABLE_FURNITURE_GROUP := "pushable_furniture"
const FURNITURE_PUSH_ACCELERATION := 3.5
const DEFAULT_BASE_SIZE_MULTIPLIER := 0.80
const DEBUG_SCALE_STEP_RATIO := 0.10
const DEBUG_SCALE_MIN_STEP := -9
const DEBUG_SCALE_MAX_STEP := 20
## 调试快捷键：仅供本地/编辑器测试用，不影响玩法，关闭/重进场景自动归零。
const DEBUG_CAMERA_TRAILING_STEP_M := 0.20
const DEBUG_CAMERA_TRAILING_MIN_M := -8.0
const DEBUG_CAMERA_TRAILING_MAX_M := 8.0
const DEBUG_CAMERA_YAW_STEP_DEG := 5.0
const DEBUG_CAMERA_YAW_MIN_DEG := -75.0
const DEBUG_CAMERA_YAW_MAX_DEG := 75.0
const INTERACTION_CONTROLLER_SCRIPT := preload(
	"res://src/player3d/PlayerInteractionController3D.gd"
)
## 虚拟输入源 autoload 名。移动端虚拟摇杆与手柄输出同名信号，
## 接同一组处理函数，Player3D 不区分来源。
const VIRTUAL_INPUT_SOURCES := ["MobileInput", "GamepadInput"]

## 敌人分组名（Enemy3D._ready 里 add_to_group 的那个）。瞄准辅助按它收集候选。
const ENEMY_GROUP := "enemy_3d"

@export var max_hp := 100
@export var combat_enabled := false
@export var start_with_weapon := true
## 这两个 export 目前没有被任何代码或 .tscn 读取。出厂枪的真源是
## `BlueprintRegistry.DEFAULT_STARTING_GUN_ID`，经 `get_starting_weapon_tree()`
## 装配；改这里不会换枪。
@export var default_gun_id := "bp_pistol"
@export var default_bullet_id := "mod_bullet_standard"

var current_hp := 100
var aim_direction := Vector3(0, 0, -1)
var aim_yaw := 0.0
var last_move_direction := Vector3(0, 0, -1)
var dash_direction := Vector3(0, 0, -1)
const DASH_INPUT_BUFFER_SECONDS := 0.12
var _dash_input_buffer := 0.0
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
## 结算后保护：撤离/阵亡已经提交、但场景还没切走或复位完成的那段时间。
## 此时玩家输入被锁、站着挨打，若被拖死就会在「已结算」之上再叠一次死亡，
## 或者被作废后以 hp=0 卡在原地。由 _update_invincibility 保活，不走倒计时。
var _post_settlement_invulnerable := false
var _state_machine: StateMachine = null
var expression_system: CharacterExpressionSystem
var _expression_state_adapter: PlayerExpressionStateAdapter
@export var expression_random_enabled := true
@export var expression_random_seed := 0
var melee_combat: PlayerMeleeCombat3D = null
var _test_move_direction: Variant = null
var weapon: WeaponModel3D = null
var weapon_tree: WeaponAssemblyTree = null
var equipped_weapon_instance: WeaponInstance = null
var equipped_weapon_slots: Array = [null, null]
var active_weapon_slot := 0
var weapon_holstered := false
var _weapon_transition_phase := ""
var _weapon_transition_elapsed := 0.0
var _weapon_transition_target := -1
var _holstered_active_model: WeaponModel3D = null
const WEAPON_TRANSITION_SECONDS := 0.45
var _loading_weapon_instance := false
var _reload_ammo_provider: Callable
var _stowed_weapon_model: WeaponModel3D = null
var _stowed_weapon_instance_id := ""
var equipped_backpack_item: Dictionary = {}
var equipped_flashlight_module: Dictionary = {}
var interaction_controller: PlayerInteractionController3D
var _mounted_chair: PushableSeat3D = null
var _seat_saved_collision_layer := 0
var _seat_saved_collision_mask := 0
var _seat_saved_camera_position := Vector3.ZERO
var _seat_camera_drop_m := 0.0
var _seat_exit_push_suppression := 0.0
var _active_ladder: Base99TelescopicLadder3D = null
var _ladder_progress := 0.0
var _ladder_direction := 1.0
var _ladder_saved_collision_layer := 0
var _ladder_saved_collision_mask := 0
const LADDER_CLIMB_SPEED_MPS := 2.5

# 虚拟输入状态（来自 MobileInput / GamepadInput 两个 autoload 的信号）。
# 变量名沿用 _mobile_ 前缀：这条通路最初为触屏而建，手柄复用同一套语义。
var _mobile_move_direction := Vector2.ZERO
var _mobile_face_direction := Vector2.ZERO
var _mobile_face_active := false
var _mobile_shoot_active := false
var _mobile_shoot_was_active := false
var _mobile_input_available := false
var _backpack_model: Node3D = null
var _backpack_follow: Node3D = null
const BACKPACK_WORN_SCALE := 0.45
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
## 仅作用于镜头姿态的临时偏移量；玩家朝向/移动方向/战斗数据完全不受影响。
var _debug_camera_trailing_offset_m := 0.0
var _debug_camera_yaw_offset_deg := 0.0
var _fate_damage_source: WeakRef
var _fate_damage_source_frame := -1
var _fate_weapon_trees: Dictionary = {}
var _fate_weapon_model_states: Dictionary = {}
const CHARACTER_FATE_DEFAULTS := {
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
	"max_hp_delta": 0,
	"critical_chance_bonus": 0.0,
	"dash_distance_multiplier": 1.0,
	"dash_invulnerability_multiplier": 1.0,
	"dash_invulnerability_bonus": 0.0,
	"reflect_ratio": 0.0,
	"room_damage": 0,
	"clear_heal": 0,
	"elite_engage_shield": 0,
	"shield": 0,
	"first_reload_speed": 1.0,
	"first_reload_ready": false,
	"room_hit_count": 0,
	"following_guards": [],
	"last_stands": [],
	"blessings": [],
	"kill_rules": [],
	"entered_rooms": {},
	"cleared_rooms": {},
	"elite_encounters": {},
}
var _character_fate: Dictionary = CHARACTER_FATE_DEFAULTS.duplicate(true)

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
	interaction_controller = INTERACTION_CONTROLLER_SCRIPT.new() as PlayerInteractionController3D
	interaction_controller.name = "PlayerInteractionController3D"
	add_child(interaction_controller)
	interaction_controller.configure(self)
	_init_state_machine()
	_init_expression_system()
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
		return
	if _is_debug_scale_down_key(key_event):
		adjust_debug_scale(-1)
		get_viewport().set_input_as_handled()
		return
	if _is_debug_camera_zoom_in_key(key_event):
		adjust_debug_camera_trailing(-DEBUG_CAMERA_TRAILING_STEP_M)
		get_viewport().set_input_as_handled()
		return
	if _is_debug_camera_zoom_out_key(key_event):
		adjust_debug_camera_trailing(DEBUG_CAMERA_TRAILING_STEP_M)
		get_viewport().set_input_as_handled()
		return
	if _is_debug_camera_yaw_left_key(key_event):
		adjust_debug_camera_yaw(-DEBUG_CAMERA_YAW_STEP_DEG)
		get_viewport().set_input_as_handled()
		return
	if _is_debug_camera_yaw_right_key(key_event):
		adjust_debug_camera_yaw(DEBUG_CAMERA_YAW_STEP_DEG)
		get_viewport().set_input_as_handled()
		return
	if _is_debug_camera_reset_key(key_event):
		reset_debug_camera_adjustments()
		get_viewport().set_input_as_handled()


func request_interaction_for_test() -> bool:
	return (
		interaction_controller != null
		and interaction_controller.request_interaction()
	)


func get_interaction_focus_snapshot() -> Dictionary:
	return (
		interaction_controller.get_focus_snapshot()
		if interaction_controller != null
		else {}
	)


func _is_debug_scale_up_key(event: InputEventKey) -> bool:
	return (
		event.unicode == 43
		or event.keycode == KEY_KP_ADD
		or event.physical_keycode == KEY_EQUAL
	)


func _is_debug_scale_down_key(event: InputEventKey) -> bool:
	return (
		event.unicode == 45
		or event.keycode == KEY_KP_SUBTRACT
		or event.physical_keycode == KEY_MINUS
	)


## 调试快捷键：仅本地/编辑器手动验证用，不属于玩法、不进存档。
## 按一次减少镜头到焦点的距离，让相机贴近角色；同步作用于每帧的相机姿态计算。
func _is_debug_camera_zoom_in_key(event: InputEventKey) -> bool:
	return (
		event.physical_keycode == KEY_SEMICOLON
		or event.keycode == KEY_SEMICOLON
	)


func _is_debug_camera_zoom_out_key(event: InputEventKey) -> bool:
	return (
		event.physical_keycode == KEY_APOSTROPHE
		or event.keycode == KEY_APOSTROPHE
	)


func _is_debug_camera_yaw_left_key(event: InputEventKey) -> bool:
	return event.physical_keycode == KEY_BRACKETLEFT or event.keycode == KEY_BRACKETLEFT


func _is_debug_camera_yaw_right_key(event: InputEventKey) -> bool:
	return event.physical_keycode == KEY_BRACKETRIGHT or event.keycode == KEY_BRACKETRIGHT


func _is_debug_camera_reset_key(event: InputEventKey) -> bool:
	return event.physical_keycode == KEY_R or event.keycode == KEY_R


func adjust_debug_camera_trailing(step_m: float) -> void:
	var clamped_step := clampf(
		_debug_camera_trailing_offset_m + step_m,
		DEBUG_CAMERA_TRAILING_MIN_M,
		DEBUG_CAMERA_TRAILING_MAX_M
	)
	if is_equal_approx(clamped_step, _debug_camera_trailing_offset_m):
		return
	_debug_camera_trailing_offset_m = clamped_step


func adjust_debug_camera_yaw(step_deg: float) -> void:
	var clamped_step := clampf(
		_debug_camera_yaw_offset_deg + step_deg,
		DEBUG_CAMERA_YAW_MIN_DEG,
		DEBUG_CAMERA_YAW_MAX_DEG
	)
	if is_equal_approx(clamped_step, _debug_camera_yaw_offset_deg):
		return
	_debug_camera_yaw_offset_deg = clamped_step


func reset_debug_camera_adjustments() -> void:
	_debug_camera_trailing_offset_m = 0.0
	_debug_camera_yaw_offset_deg = 0.0


func get_debug_camera_trailing_offset_m() -> float:
	return _debug_camera_trailing_offset_m


func get_debug_camera_yaw_offset_deg() -> float:
	return _debug_camera_yaw_offset_deg


func _initialize_debug_scale_contract() -> void:
	# 旧资产尺寸的80%现在定义为角色的新100%基础尺寸。
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
	_seat_exit_push_suppression = maxf(0.0, _seat_exit_push_suppression - delta)
	_update_invincibility(delta)
	_tick_action_overlays(delta)
	_tick_weapon_transition(delta)
	_silence_remaining = maxf(0.0, _silence_remaining - delta)
	_update_aim_from_mouse()
	_update_combat_input()
	if _state_machine != null:
		_state_machine.physics_update(delta)
	if melee_combat != null:
		melee_combat.physics_update(delta)
	_tick_dash_input_buffer(delta)
	_tick_footstep_sound(delta)
	var flashlight := get_node_or_null("PlayerFlashlight3D")
	if flashlight != null:
		flashlight.set_in_facility(is_player_inside_facility())


func is_seated_on_chair(chair: PushableSeat3D = null) -> bool:
	return _mounted_chair != null and is_instance_valid(_mounted_chair) and (chair == null or _mounted_chair == chair)


func try_start_ladder_climb(ladder: Base99TelescopicLadder3D, upward: bool) -> bool:
	if ladder == null or not is_instance_valid(ladder) or not ladder.deployed or _active_ladder != null:
		return false
	if input_locked or current_hp <= 0 or get_state_machine_state() not in ["idle", "moving"]:
		return false
	var start := ladder.get_exit_position(not upward)
	if global_position.distance_to(start) > 1.5:
		return false
	_ladder_saved_collision_layer = collision_layer
	_ladder_saved_collision_mask = collision_mask
	_active_ladder = ladder
	_ladder_progress = 0.0 if upward else 1.0
	_ladder_direction = 1.0 if upward else -1.0
	# 攀爬期间角色由固定导轨控制。结束时恢复完整世界碰撞。
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	global_position = ladder.get_climb_position(_ladder_progress)
	_clear_action_overlays()
	if weapon != null:
		weapon.cancel_charge()
	_state_machine.transition_to("climbing")
	return true


func _tick_ladder_climb(delta: float) -> void:
	if _active_ladder == null or not is_instance_valid(_active_ladder):
		_finish_ladder_climb(false)
		_transition_to_locomotion()
		return
	# 仅反方向输入改变行进方向；松开后继续自动攀爬。
	var vertical_input := Input.get_axis("move_up", "move_down")
	if _mobile_input_available and absf(_mobile_move_direction.y) > 0.3:
		vertical_input = _mobile_move_direction.y
	if _test_move_direction is Vector3 and absf((_test_move_direction as Vector3).z) > 0.3:
		vertical_input = (_test_move_direction as Vector3).z
	if vertical_input < -0.3:
		_ladder_direction = 1.0
	elif vertical_input > 0.3:
		_ladder_direction = -1.0
	_ladder_progress = clampf(_ladder_progress + _ladder_direction * LADDER_CLIMB_SPEED_MPS * delta / Base99TelescopicLadder3D.TRAVEL_HEIGHT, 0.0, 1.0)
	if _ladder_progress >= 0.9:
		_active_ladder.prepare_upper_exit()
	global_position = _active_ladder.get_climb_position(_ladder_progress)
	velocity = Vector3.ZERO
	if _ladder_progress >= 1.0 or _ladder_progress <= 0.0:
		_finish_ladder_climb(_ladder_progress >= 1.0)
		_transition_to_locomotion()


func _finish_ladder_climb(at_top: bool) -> void:
	if _active_ladder != null and is_instance_valid(_active_ladder):
		global_position = _active_ladder.get_exit_position(at_top)
	_active_ladder = null
	collision_layer = _ladder_saved_collision_layer | 1
	collision_mask = _ladder_saved_collision_mask | 1
	virtual_collision_capsule.disabled = false
	velocity = Vector3.ZERO


func try_mount_chair(chair: PushableSeat3D) -> bool:
	if chair == null or not is_instance_valid(chair) or chair.rider != null or chair.is_tipped() or is_seated_on_chair():
		return false
	if input_locked or current_hp <= 0 or get_state_machine_state() not in ["idle", "moving"]:
		return false
	var gap := chair.global_position - global_position
	gap.y = 0.0
	if gap.length() > 1.35:
		return false
	_seat_saved_collision_layer = collision_layer
	_seat_saved_collision_mask = collision_mask
	_seat_saved_camera_position = camera.position
	var standing_height := global_position.y
	_mounted_chair = chair
	chair.rider = self
	# 自身胶囊不能与承载的椅子互顶；椅子刚体仍与墙、地面和家具碰撞。
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	global_position = chair.get_seat_position()
	# Root rises to the seat, but the camera must keep its standing world height.
	_seat_camera_drop_m = global_position.y - standing_height
	camera.position = _seat_saved_camera_position - Vector3.UP * _seat_camera_drop_m
	_clear_action_overlays()
	if weapon != null:
		weapon.cancel_charge()
	_state_machine.transition_to("seated")
	return true


func try_dismount_chair() -> bool:
	if not is_seated_on_chair():
		return false
	var exit_position := _find_chair_exit_position(_mounted_chair)
	if not exit_position.is_finite():
		return false
	_release_chair(exit_position)
	_transition_to_locomotion()
	return true


func _force_leave_chair() -> void:
	if not is_seated_on_chair():
		return
	var exit_position := _find_chair_exit_position(_mounted_chair)
	if not exit_position.is_finite():
		exit_position = _mounted_chair.get_seat_position() + Vector3.UP * 1.2
	_release_chair(exit_position)


func _tick_seated(_delta: float) -> void:
	if not is_seated_on_chair():
		_mounted_chair = null
		_restore_chair_collision()
		_seat_camera_drop_m = 0.0
		camera.position = _seat_saved_camera_position
		_transition_to_locomotion()
		return
	if _mounted_chair.is_tipped():
		_force_leave_chair()
		_transition_to_locomotion()
		return
	_mounted_chair.drive(_get_input_direction_3d())
	_mounted_chair.set_swivel_yaw(aim_yaw)
	global_position = _mounted_chair.get_seat_position()
	velocity = _mounted_chair.linear_velocity


func _find_chair_exit_position(chair: PushableSeat3D) -> Vector3:
	var space := get_world_3d().direct_space_state
	var directions := [chair.global_basis.x, -chair.global_basis.x, chair.global_basis.z, -chair.global_basis.z]
	for basis_direction in directions:
		var flat := Vector3(basis_direction.x, 0.0, basis_direction.z).normalized()
		var horizontal := chair.global_position + flat * 1.1
		var ray := PhysicsRayQueryParameters3D.create(horizontal + Vector3.UP * 1.5, horizontal + Vector3.DOWN * 0.8, 1, [get_rid(), chair.get_rid()])
		var ground := space.intersect_ray(ray)
		if ground.is_empty():
			continue
		var candidate: Vector3 = (ground["position"] as Vector3) + Vector3.UP * 0.04
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = virtual_collision_capsule.shape
		query.transform = Transform3D(global_basis, candidate + virtual_collision_capsule.position)
		query.collision_mask = _seat_saved_collision_mask
		query.exclude = [get_rid()]
		if space.intersect_shape(query, 1).is_empty():
			return candidate
	return Vector3.INF


func _release_chair(exit_position: Vector3) -> void:
	if is_seated_on_chair():
		_mounted_chair.finish_ride()
	_mounted_chair = null
	_seat_exit_push_suppression = 0.45
	global_position = exit_position
	_restore_chair_collision()
	_seat_camera_drop_m = 0.0
	camera.position = _seat_saved_camera_position
	velocity = Vector3.ZERO


func _restore_chair_collision() -> void:
	# The player scene's world channel is mandatory after leaving a vehicle.
	# Restore any extra channels that were active before mounting as well.
	collision_layer = _seat_saved_collision_layer | 1
	collision_mask = _seat_saved_collision_mask | 1
	virtual_collision_capsule.disabled = false


func get_seated_camera_drop_m() -> float:
	return _seat_camera_drop_m if is_seated_on_chair() else 0.0


func _hook_mobile_input() -> void:
	# 虚拟输入源：移动端虚拟摇杆与手柄各是一个 autoload，但输出同一组信号
	# （move_direction / face_direction / shoot_pressed / shoot_released）。
	# 这里只做一次接线，Player3D 不区分来源、取最新值即可 —— 同一时刻实际
	# 活动的源由 InputDevice 决定，两个源不会同时产生有效输入。
	#
	# 找不到 autoload 时（极端情况：未注册）静默退化，键盘鼠标照旧。
	# R/SHIFT/F/E 四位动作以 Dungeon3D 的 HUD 按钮为准，走 Input.parse_input_event 入口。
	_mobile_input_available = false
	for source_name in VIRTUAL_INPUT_SOURCES:
		var source: Node = get_node_or_null("/root/%s" % source_name)
		if source == null:
			continue
		if not source.move_direction.is_connected(_on_mobile_move_direction):
			source.move_direction.connect(_on_mobile_move_direction)
		if not source.face_direction.is_connected(_on_mobile_face_direction):
			source.face_direction.connect(_on_mobile_face_direction)
		if not source.shoot_pressed.is_connected(_on_mobile_shoot_pressed):
			source.shoot_pressed.connect(_on_mobile_shoot_pressed)
		if not source.shoot_released.is_connected(_on_mobile_shoot_released):
			source.shoot_released.connect(_on_mobile_shoot_released)
		_mobile_input_available = true


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
	# 屏幕右 = 把「前方」在俯视 (x,z) 平面上顺时针转 90°，即 (u,v) -> (-v,u)。
	# 原式 (v,-u) 是逆时针，算出来的是「屏幕左」：右摇杆推右时准星会往左偏。
	# 这与 MobileInput「右摇杆空载时退回左摇杆，让移动和面朝一致」的意图正好相反 ——
	# 移动走的是 +X（推右 = 世界 +X），面朝却落在 -X。
	var right_2d := Vector2(-forward_2d.y, forward_2d.x)
	var aim := right_2d * _mobile_face_direction.x + forward_2d * (-_mobile_face_direction.y)
	return Vector3(aim.x, 0.0, aim.y).normalized() if aim.length_squared() > 0.0001 else Vector3.ZERO


## 收集瞄准辅助的候选敌人（已过滤）。准入规则本身是纯函数 `AimAssist3D.is_eligible`
## （便于 headless 逐值断言），本函数只负责取数并组装成 solve 要的形状。
func _collect_aim_assist_candidates(aim_dir: Vector3) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	if not InputSettings.is_aim_assist_enabled():
		return candidates
	var tree := get_tree()
	if tree == null:
		return candidates
	var flat_aim := Vector2(aim_dir.x, aim_dir.z)
	if flat_aim.length_squared() <= 0.000001:
		return candidates
	var origin := global_position
	for node in tree.get_nodes_in_group(ENEMY_GROUP):
		var enemy := node as Enemy3D
		if enemy == null:
			continue
		var to_enemy := enemy.global_position - origin
		to_enemy.y = 0.0
		var distance := to_enemy.length()
		var direction := to_enemy / distance if distance > 0.0001 else Vector3.ZERO
		var angle_deg := rad_to_deg(absf(flat_aim.angle_to(Vector2(direction.x, direction.z))))
		var eligible: bool = AimAssist3D.is_eligible(
			enemy.current_hp > 0,
			enemy.get_illumination_state(),
			distance,
			angle_deg
		)
		if not eligible:
			continue
		candidates.append({AimAssist3D.KEY_DIRECTION: direction, AimAssist3D.KEY_DISTANCE: distance})
	return candidates


func set_test_move_direction(direction: Variant) -> void:
	_test_move_direction = direction


func set_input_locked(locked: bool) -> void:
	if locked:
		_dash_input_buffer = 0.0
		_force_leave_chair()
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


func get_locomotion_presentation_snapshot() -> Dictionary:
	# Read-only parameters; directional clips never become gameplay states.
	return {"state": _presentation_state, "world_velocity": Vector3(velocity.x, 0, velocity.z),
		"aim_yaw": aim_yaw, "speed_mps": Vector2(velocity.x, velocity.z).length()}


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
	_push_collided_furniture(next_velocity)
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
	_push_collided_furniture(planar)
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


## CharacterBody3D 会阻挡刚体，但不会自动给出可调的推力；这里在真实滑动
## 碰撞时施加受限平面力，避免连续每帧冲量把椅子弹飞。
func _push_collided_furniture(requested_velocity: Vector3) -> void:
	if _seat_exit_push_suppression > 0.0:
		return
	# move_and_slide() 会在接触阻挡时改写 velocity；必须保留碰撞前的输入速度，
	# 否则角色正面顶住椅子时推力会被清成零。
	var planar_velocity := Vector3(requested_velocity.x, 0.0, requested_velocity.z)
	if planar_velocity.length_squared() < 0.01:
		return
	for collision_index in get_slide_collision_count():
		var collision := get_slide_collision(collision_index)
		var collider := collision.get_collider() as Node
		var body := collider as RigidBody3D
		if body == null and collider != null and collider.name == "PlayerBlocker":
			body = collider.get_parent() as RigidBody3D
		if body == null or not body.is_in_group(PUSHABLE_FURNITURE_GROUP):
			continue
		var push_direction := planar_velocity.normalized()
		var current_speed := Vector2(body.linear_velocity.x, body.linear_velocity.z).length()
		if current_speed < 2.2:
			body.apply_central_force(push_direction * body.mass * FURNITURE_PUSH_ACCELERATION)


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
	return DASH_SPEED * float(_character_fate.get("dash_distance_multiplier", 1.0))


func get_dash_duration() -> float:
	return DASH_DURATION


func begin_fate_dash_invulnerability() -> void:
	is_invincible = true
	_invincible_remaining = maxf(_invincible_remaining, DASH_DURATION * float(_character_fate["dash_invulnerability_multiplier"]) + float(_character_fate["dash_invulnerability_bonus"]))


func get_fate_critical_chance_bonus() -> float:
	return float(_character_fate["critical_chance_bonus"])


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
	snapshot["locomotion"] = get_locomotion_presentation_snapshot()
	snapshot["melee_action_machine"] = melee_combat.get_snapshot() if melee_combat != null else {}
	return snapshot


func is_low_health() -> bool:
	return current_hp > 0 and float(current_hp) / float(maxi(1, max_hp)) <= 0.30


func take_damage(amount: int, _critical := false, hit_direction := Vector3.ZERO, knockback_override := false, knockback_strength := 0.0, fate_health_loss := false) -> void:
	var damage_source: Node3D = null
	if _fate_damage_source != null and _fate_damage_source_frame == Engine.get_process_frames():
		damage_source = _fate_damage_source.get_ref() as Node3D
	_fate_damage_source = null
	if current_hp <= 0 or (is_invincible and not fate_health_loss) or amount <= 0:
		return
	var overheat_multiplier := weapon_tree.get_overheat_penalty() if weapon_tree != null else 1.0
	var fate_multiplier := float(_character_fate.get("damage_taken_multiplier", 1.0))
	if not fate_health_loss and bool(_character_fate.get("first_hit_ready", false)):
		fate_multiplier *= float(_character_fate.get("first_hit_multiplier", 1.0))
		_character_fate["first_hit_ready"] = false
	var hit_index := int(_character_fate["room_hit_count"])
	for guard: Dictionary in _character_fate["following_guards"]:
		if hit_index > 0 and hit_index <= int(guard["count"]):
			fate_multiplier *= float(guard["multiplier"])
	if not fate_health_loss:
		_character_fate["room_hit_count"] = hit_index + 1
	_last_damage_amount = amount if fate_health_loss else maxi(1, int(round(float(amount) * overheat_multiplier * fate_multiplier)))
	var absorbed := 0 if fate_health_loss else mini(_last_damage_amount, int(_character_fate["shield"]))
	_character_fate["shield"] = int(_character_fate["shield"]) - absorbed
	_last_damage_amount -= absorbed
	var actual_damage := mini(current_hp, _last_damage_amount)
	if hit_direction.length_squared() > 0.001:
		_last_hit_direction = Vector3(hit_direction.x, 0.0, hit_direction.z).normalized()
	var next_hp := current_hp - _last_damage_amount
	if next_hp <= 0:
		var rescues: Array = _character_fate["last_stands"]
		for index in range(rescues.size()):
			var rescue: Dictionary = rescues[index]
			var cost := int(rescue["currency_cost"])
			if cost > 0 and not GameManager.spend_currency(cost):
				continue
			next_hp = maxi(1, roundi(max_hp * float(rescue["heal_ratio"])))
			rescues.remove_at(index)
			_character_fate["last_stand_charges"] = rescues.size()
			break
	current_hp = maxi(0, next_hp)
	var reflected := 0 if fate_health_loss else roundi(actual_damage * float(_character_fate["reflect_ratio"]))
	if reflected > 0 and is_instance_valid(damage_source) and damage_source != self:
		if damage_source.has_method("take_projectile_damage"):
			var reflection_tags: Array[String] = []
			damage_source.call("take_projectile_damage", reflected, false, -hit_direction, reflection_tags, {"fate_reflection": true}, self)
		elif damage_source.has_method("take_damage"):
			damage_source.call("take_damage", reflected)
	_force_leave_chair()
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
	_fate_damage_source = weakref(source) if is_instance_valid(source) else null
	_fate_damage_source_frame = Engine.get_process_frames()
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
	if int(effect.get("action", -1)) == FateCard.EffectAction.GRANT_RANDOM_CARD:
		modifier = "kill_card"
	elif int(effect.get("action", -1)) == FateCard.EffectAction.BLESS_DEAD:
		modifier = "survival_blessing"
	match modifier:
		"kill_card":
			var rule := effect.duplicate(true)
			rule["kills"] = 0
			_character_fate["kill_rules"].append(rule)
		"survival_blessing":
			var rule := effect.duplicate(true)
			rule["elapsed"] = 0.0
			rule["stacks"] = 0
			_character_fate["blessings"].append(rule)
		"max_hp":
			var previous_max := max_hp
			var amount := int(effect.get("amount", 0))
			max_hp = maxi(1, max_hp + amount)
			_character_fate["max_hp_delta"] = int(_character_fate["max_hp_delta"]) + max_hp - previous_max
			current_hp = mini(max_hp, current_hp + maxi(0, int(effect.get("heal", amount))))
			hp_changed.emit(current_hp, max_hp)
		"move_speed":
			_character_fate["move_speed_multiplier"] = float(_character_fate["move_speed_multiplier"]) * float(effect.get("multiplier", 1.0))
			_character_fate["dash_invulnerability_bonus"] += float(effect.get("dash_invulnerability_bonus", 0.0))
		"dash_cooldown":
			_character_fate["dash_cooldown_multiplier"] = float(_character_fate["dash_cooldown_multiplier"]) * float(effect.get("multiplier", 1.0))
			_character_fate["dash_distance_multiplier"] *= float(effect.get("distance_multiplier", 1.0))
			_character_fate["dash_invulnerability_multiplier"] *= float(effect.get("invulnerability_multiplier", 1.0))
		"damage_taken":
			_character_fate["damage_taken_multiplier"] = float(_character_fate["damage_taken_multiplier"]) * float(effect.get("multiplier", 1.0))
			_character_fate["reflect_ratio"] += float(effect.get("reflect_ratio", 0.0))
		"weapon_damage":
			_character_fate["weapon_damage_multiplier"] = float(_character_fate["weapon_damage_multiplier"]) * float(effect.get("multiplier", 1.0))
			_character_fate["critical_chance_bonus"] += float(effect.get("crit_chance_bonus", 0.0))
			set_damage_multiplier("fate_moon_power", float(_character_fate["weapon_damage_multiplier"]))
		"room_heal":
			var amount := int(effect.get("amount", 0))
			_character_fate["room_heal"] += maxi(0, amount)
			_character_fate["room_damage"] += maxi(0, -amount)
			_character_fate["clear_heal"] += int(effect.get("clear_heal", 0))
		"elite_heal":
			_character_fate["elite_heal"] = int(_character_fate["elite_heal"]) + int(effect.get("amount", 0))
			_character_fate["elite_engage_shield"] += int(effect.get("elite_engage_shield", 0))
		"first_hit_guard":
			_character_fate["first_hit_multiplier"] = float(_character_fate["first_hit_multiplier"]) * float(effect.get("multiplier", 1.0))
			_character_fate["first_hit_ready"] = true
			if effect.has("following_hit_count"):
				_character_fate["following_guards"].append({"count": int(effect["following_hit_count"]), "multiplier": float(effect["following_hit_multiplier"])})
		"last_stand":
			for _charge in range(int(effect.get("charges", 1))):
				_character_fate["last_stands"].append({"currency_cost": int(effect.get("currency_cost", 0)), "heal_ratio": float(effect.get("heal_ratio", 0.0))})
			_character_fate["last_stand_charges"] = _character_fate["last_stands"].size()
		"room_ammo":
			_character_fate["room_ammo_ratio"] = float(_character_fate["room_ammo_ratio"]) + float(effect.get("ratio", 0.0))
			_character_fate["first_reload_speed"] *= float(effect.get("first_reload_speed", 1.0))
		_:
			return {"success": false, "message": "未知月亮命运效果：" + modifier}
	return {"success": true, "message": "月亮命运已写入角色本局状态"}


func on_fate_room_entered(room_id: String = "") -> Dictionary:
	if not room_id.is_empty():
		if _character_fate["entered_rooms"].has(room_id):
			return {"healed": 0, "ammo_added": 0, "duplicate": true}
		_character_fate["entered_rooms"][room_id] = true
	_character_fate["first_hit_ready"] = float(_character_fate.get("first_hit_multiplier", 1.0)) < 1.0
	_character_fate["room_hit_count"] = 0
	_character_fate["first_reload_ready"] = float(_character_fate["first_reload_speed"]) > 1.0
	var before_hp := current_hp
	heal(int(_character_fate["room_heal"]))
	var healed := current_hp - before_hp
	var loss := int(_character_fate["room_damage"])
	if loss > 0:
		take_damage(loss, false, Vector3.ZERO, false, 0.0, true)
	var ammo_added := 0
	if weapon != null and is_instance_valid(weapon):
		var before_ammo := weapon.current_ammo
		ammo_added = int(ceil(float(weapon.magazine_size) * float(_character_fate.get("room_ammo_ratio", 0.0))))
		if ammo_added > 0:
			weapon.current_ammo = mini(weapon.magazine_size, weapon.current_ammo + ammo_added)
			ammo_added = weapon.current_ammo - before_ammo
			weapon_tree.current_ammo = weapon.current_ammo
			weapon.ammo_changed.emit(weapon.current_ammo, weapon.magazine_size)
	return {"healed": healed, "damage": loss, "ammo_added": ammo_added}


func on_fate_room_cleared(room_id: String = "") -> int:
	if not room_id.is_empty():
		if _character_fate["cleared_rooms"].has(room_id):
			return 0
		_character_fate["cleared_rooms"][room_id] = true
	var before := current_hp
	heal(int(_character_fate["clear_heal"]))
	return current_hp - before


func on_fate_elite_combat_started(encounter_id: String = "") -> int:
	if not encounter_id.is_empty():
		if _character_fate["elite_encounters"].has(encounter_id):
			return 0
		_character_fate["elite_encounters"][encounter_id] = true
	var amount := int(_character_fate["elite_engage_shield"])
	_character_fate["shield"] += amount
	return amount


func update_fate_survival(delta: float) -> void:
	if current_hp <= 0 or delta <= 0.0:
		return
	var ratio := float(current_hp) / maxi(1, max_hp)
	var rules: Array = _character_fate["blessings"]
	for index in range(rules.size()):
		var rule: Dictionary = rules[index]
		var threshold := float(rule.get("hp_threshold", 0.3))
		var eligible := ratio > threshold if str(rule.get("threshold_mode", "below")) == "above" else ratio < threshold
		if not eligible:
			rule["elapsed"] = 0.0
			continue
		var limit := maxi(1, int(rule.get("max_stacks", 3)))
		if int(rule["stacks"]) >= limit:
			continue
		rule["elapsed"] = float(rule["elapsed"]) + delta
		var duration := maxf(0.01, float(rule.get("survive_duration", 30.0)))
		while float(rule["elapsed"]) >= duration and int(rule["stacks"]) < limit:
			rule["elapsed"] -= duration
			rule["stacks"] += 1
		set_damage_multiplier("fate_bless_dead_%d" % index, 1.0 + float(rule.get("damage_bonus", 0.1)) * int(rule["stacks"]))


func on_fate_kill_recorded() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var bridge := get_tree().get_first_node_in_group("fate_cards")
	# 固定本次规则列表，新获得的愚者从下一次击杀开始计数。
	var rules: Array = (_character_fate["kill_rules"] as Array).duplicate()
	for rule: Dictionary in rules:
		rule["kills"] = int(rule["kills"]) + 1
		var threshold := maxi(1, int(rule.get("kill_threshold", 10)))
		if int(rule["kills"]) % threshold != 0:
			continue
		var probability := float(rule.get("chance", rule.get("grant_probability", 0.5)))
		if randf() >= probability:
			continue
		if bridge != null:
			results.append(bridge.call("grant_random_card_from_character", int(rule.get("currency_cost", 0))) as Dictionary)
	return results


func reset_character_fate_state() -> void:
	max_hp = maxi(1, max_hp - int(_character_fate["max_hp_delta"]))
	current_hp = mini(current_hp, max_hp)
	_character_fate = CHARACTER_FATE_DEFAULTS.duplicate(true)
	_fate_damage_source = null
	for tree: WeaponAssemblyTree in _fate_weapon_trees.values():
		if not is_instance_valid(tree):
			continue
		for key in ["growth_stacks", "_overheat_shots", "_crit_damage_shots", "_crit_on_kill_stack"]:
			tree.set(key, 0)
		tree.set("_attachment_ready_at", 0.0)
	_fate_weapon_model_states.clear()
	if is_instance_valid(weapon):
		weapon.set("_reload_first_shot", false)
		weapon.set("_fire_sequence", 0)
	for source: String in _named_damage_multipliers.keys():
		if source.begins_with("fate_") or source == "bless_dead":
			_named_damage_multipliers.erase(source)
	_apply_named_damage_multipliers()
	hp_changed.emit(current_hp, max_hp)


func on_fate_elite_killed() -> int:
	var amount := int(_character_fate.get("elite_heal", 0))
	if amount > 0:
		heal(amount)
	return amount


func get_character_fate_snapshot() -> Dictionary:
	return _character_fate.duplicate(true)


static func is_fate_snapshot_number(value: Variant, minimum: float, maximum: float, integer := false) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum and (not integer or float(value) == floor(float(value)))


## JSON 边界只接受默认模板声明的类型；缺字段兼容，错误类型/负计数拒绝。
static func read_fate_snapshot_fields(value: Variant, defaults: Dictionary, signed_fields: Array = []) -> Dictionary:
	if not value is Dictionary:
		return {}
	var result := defaults.duplicate(true)
	for key in defaults:
		if not value.has(key):
			continue
		var item: Variant = value[key]
		var sample: Variant = defaults[key]
		if sample is int or sample is float:
			if not is_fate_snapshot_number(item, -2147483647 if key in signed_fields else 0, 2147483647, sample is int):
				return {}
			result[key] = int(item) if sample is int else float(item)
		elif typeof(item) != typeof(sample):
			return {}
		else:
			result[key] = item.duplicate(true) if item is Array or item is Dictionary else item
	return result


func clear_fate_weapon_cache_for_restore() -> void:
	# 仅在装备槽卸空后使用，避免同进程重载复用旧装配或泄漏未入树的副槽树。
	for tree: WeaponAssemblyTree in _fate_weapon_trees.values():
		if is_instance_valid(tree) and tree != weapon_tree:
			tree.free()
	_fate_weapon_trees.clear()
	_fate_weapon_model_states.clear()


func export_fate_snapshot() -> Dictionary:
	_sync_equipped_weapon_instance()
	var weapons: Dictionary = {}
	for instance: WeaponInstance in equipped_weapon_slots:
		if instance == null:
			continue
		var tree := _fate_weapon_trees.get(instance.weapon_instance_id) as WeaponAssemblyTree
		if not is_instance_valid(tree):
			continue
		var state: Dictionary = {}
		for key in ["growth_stacks", "_overheat_shots", "_crit_damage_shots", "_crit_on_kill_stack"]:
			state[key] = tree.get(key)
		state["attachment_cooldown_remaining"] = maxf(0.0, float(tree.get("_attachment_ready_at")) - Time.get_ticks_msec() / 1000.0)
		state["model"] = _fate_weapon_model_states.get(instance.weapon_instance_id, {}).duplicate(true)
		weapons[instance.weapon_instance_id] = state
	return {"version": 1, "character": _character_fate.duplicate(true), "weapons": weapons}


## 装备实例先恢复；仅按实际槽内永久 ID 恢复运行树，绝不创建幽灵装备。
func import_fate_snapshot(value: Variant) -> bool:
	reset_character_fate_state()
	if not value is Dictionary or value.get("version", 0) != 1:
		return false
	var character := read_fate_snapshot_fields(value.get("character"), CHARACTER_FATE_DEFAULTS, ["max_hp_delta"])
	if character.is_empty() or not value.get("weapons", {}) is Dictionary:
		return false
	for key in ["move_speed_multiplier", "dash_cooldown_multiplier", "dash_distance_multiplier", "dash_invulnerability_multiplier", "first_reload_speed"]:
		if float(character[key]) <= 0.0:
			return false
	for key in ["entered_rooms", "cleared_rooms", "elite_encounters"]:
		for id in character[key]:
			if not id is String or id.is_empty() or character[key][id] != true:
				return false
	var rule_defaults := {
		"following_guards": {"count": 0, "multiplier": 1.0},
		"last_stands": {"currency_cost": 0, "heal_ratio": 0.0},
		"blessings": {"action": 0, "hp_threshold": 0.3, "threshold_mode": "below", "survive_duration": 30.0, "damage_bonus": 0.1, "max_stacks": 3, "elapsed": 0.0, "stacks": 0, "orientation": "UPRIGHT"},
		"kill_rules": {"action": 0, "kill_threshold": 10, "grant_probability": 0.5, "chance": 0.5, "currency_cost": 0, "kills": 0, "orientation": "UPRIGHT"},
	}
	for key in rule_defaults:
		var rules: Array = []
		for row in character[key]:
			var rule := read_fate_snapshot_fields(row, rule_defaults[key])
			if rule.is_empty():
				return false
			if key == "blessings" and (rule["threshold_mode"] not in ["above", "below"] or rule["survive_duration"] <= 0 or rule["stacks"] > rule["max_stacks"] or rule["hp_threshold"] > 1):
				return false
			if key == "kill_rules":
				if rule["kill_threshold"] < 1 or rule["chance"] > 1 or rule["grant_probability"] > 1:
					return false
				if not row.has("chance"):
					rule.erase("chance")
			if key == "last_stands" and rule["heal_ratio"] > 1:
				return false
			rules.append(rule)
		character[key] = rules
	character["last_stand_charges"] = character["last_stands"].size()
	_character_fate = character
	max_hp = maxi(1, max_hp + int(character["max_hp_delta"]))
	set_damage_multiplier("fate_moon_power", float(character["weapon_damage_multiplier"]))
	for index in character["blessings"].size():
		var rule: Dictionary = character["blessings"][index]
		set_damage_multiplier("fate_bless_dead_%d" % index, 1.0 + float(rule["damage_bonus"]) * int(rule["stacks"]))
	for instance: WeaponInstance in equipped_weapon_slots:
		if instance == null:
			continue
		var raw: Variant = value.get("weapons", {}).get(instance.weapon_instance_id, {})
		var state := read_fate_snapshot_fields(raw, {"growth_stacks": 0, "_overheat_shots": 0, "_crit_damage_shots": 0, "_crit_on_kill_stack": 0, "attachment_cooldown_remaining": 0.0, "model": {}})
		if state.is_empty():
			continue
		var model := read_fate_snapshot_fields(state["model"], {"_reload_first_shot": false, "_fire_sequence": 0})
		if model.is_empty():
			continue
		var tree := _fate_weapon_trees.get(instance.weapon_instance_id) as WeaponAssemblyTree
		if not is_instance_valid(tree):
			tree = instance.build_runtime_tree()
			if tree == null:
				continue
			_fate_weapon_trees[instance.weapon_instance_id] = tree
			add_child(tree)
		var stats := tree.get_computed_stats()
		var bullet := tree.root.slots.get(AssemblyNode.SlotType.BULLET) as AssemblyNode
		var growth: Dictionary = bullet.get_computed_stats() if bullet != null else {}
		tree.growth_stacks = mini(int(state["growth_stacks"]), int(growth.get("growth_max_stacks", 5))) if bool(growth.get("size_growth", false)) else 0
		tree.set("_overheat_shots", int(state["_overheat_shots"]))
		tree.set("_crit_damage_shots", mini(int(state["_crit_damage_shots"]), int(stats.get("crit_kill_bonus_shots", 0))))
		tree.set("_crit_on_kill_stack", mini(int(state["_crit_on_kill_stack"]), WeaponAssemblyTree.MAX_CRIT_STACK) if bool(stats.get("crit_on_kill", false)) else 0)
		tree.set("_attachment_ready_at", Time.get_ticks_msec() / 1000.0 + minf(float(state["attachment_cooldown_remaining"]), float(stats.get("attachment_cooldown", 0.0))))
		_fate_weapon_model_states[instance.weapon_instance_id] = model
		if instance == equipped_weapon_instance and is_instance_valid(weapon):
			for key in model:
				weapon.set(key, model[key])
	return true


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
	if not _weapon_transition_phase.is_empty(): return false
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
	_sync_equipped_weapon_instance()
	_detach_fate_weapon_tree()
	_loading_weapon_instance = true
	equipped_weapon_instance = null
	_ensure_weapon_tree()
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
	_loading_weapon_instance = false
	_sync_equipped_weapon_instance()
	_refresh_stowed_weapon_model(true)
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
		weapon.character_authored_reload = str(avatar.get_meta("assembly_version", "")) == "v021"
		avatar.weapon_socket.add_child(weapon)
		weapon.ammo_changed.connect(_on_weapon_ammo_changed)
		weapon.loadout_changed.connect(_on_weapon_loadout_changed)
		weapon.reload_started.connect(_on_weapon_reload_started)
		weapon.reload_progress_changed.connect(_on_weapon_reload_progress_changed)
		weapon.reload_ended.connect(_on_weapon_reload_ended)
		weapon.shot_fired.connect(_on_weapon_shot_fired)
		if _reload_ammo_provider.is_valid():
			weapon.set_reload_ammo_provider(_reload_ammo_provider)


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


func owns_fate_source_node(source: AssemblyNode) -> bool:
	for instance: WeaponInstance in equipped_weapon_slots:
		if instance == null:
			continue
		var tree := _fate_weapon_trees.get(instance.weapon_instance_id) as WeaponAssemblyTree
		if is_instance_valid(tree) and tree.root != null and (source == tree.root or source in tree.root.get_all_descendants()):
			return true
	return false


func _detach_fate_weapon_tree() -> void:
	if weapon_tree != null:
		if weapon_tree.tree_changed.is_connected(_sync_weapon_from_tree):
			weapon_tree.tree_changed.disconnect(_sync_weapon_from_tree)
		if weapon_tree.stats_changed.is_connected(_on_weapon_tree_stats_changed):
			weapon_tree.stats_changed.disconnect(_on_weapon_tree_stats_changed)
	weapon_tree = WeaponAssemblyTree.new()
	add_child(weapon_tree)


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
		presentation["active"] = slot_index == active_weapon_slot and not weapon_holstered
		presentation["selected"] = slot_index == active_weapon_slot
		presentation["held"] = slot_index == active_weapon_slot and not weapon_holstered
		slots.append(presentation)
	var stowed_visible := _stowed_weapon_model != null and is_instance_valid(_stowed_weapon_model)
	var stowed_slot := 1 - active_weapon_slot if stowed_visible else -1
	var stowed_socket: Marker3D = null
	if stowed_visible and avatar != null:
		stowed_socket = avatar.get_stowed_weapon_socket(stowed_slot)
	return {
		"active_slot": active_weapon_slot,
		"held_slot": -1 if weapon_holstered else active_weapon_slot,
		"holstered": weapon_holstered,
		"transition": get_weapon_transition_snapshot(),
		"stowed_count": int(stowed_visible) + int(_holstered_active_model != null and is_instance_valid(_holstered_active_model)),
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
	var cached := _fate_weapon_trees.get(instance.weapon_instance_id) as WeaponAssemblyTree
	if is_instance_valid(cached):
		var combat_state := {}
		for key in ["growth_stacks", "_overheat_shots", "_crit_damage_shots", "_crit_on_kill_stack", "_attachment_ready_at"]:
			combat_state[key] = cached.get(key)
		_loading_weapon_instance = true
		var loaded := instance.load_into_runtime_tree(cached)
		_loading_weapon_instance = false
		if not loaded:
			return false
		for key: String in combat_state:
			cached.set(key, combat_state[key])
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
	if is_instance_valid(_backpack_follow):
		_backpack_follow.queue_free()
	_backpack_follow = null
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
	# 模型仍由BackpackSocket持有；只让背负视觉继承躯干动作，不改变挂点或源资产。
	var sizes := {2: Vector3(0.56, 0.60, 0.28), 4: Vector3(0.66, 0.74, 0.33), 8: Vector3(0.76, 0.88, 0.38)}
	var size: Vector3 = sizes.get(int(equipped_backpack_item.get("extra_slots", 2)), sizes[2])
	_backpack_follow = Node3D.new()
	_backpack_follow.name = "BackpackBodyFollow"
	avatar.body.add_child(_backpack_follow)
	# BodyJoint 是背包真正的动作父级；模型仍由BackpackSocket持有。
	# 该缩放只属于角色背负表现，世界掉落和UI继续使用源尺寸。
	const WORN_SCALE := 0.68
	_backpack_model.scale = Vector3.ONE * WORN_SCALE
	_backpack_follow.position = Vector3(0.0, 0.04, -0.20 - size.z * WORN_SCALE * 0.5 - 0.015)
	_sync_backpack_body_follow()

func _sync_backpack_body_follow() -> void:
	if not is_instance_valid(_backpack_model) or not is_instance_valid(_backpack_follow):
		return
	_backpack_model.global_transform = _backpack_follow.global_transform * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.68), Vector3.ZERO)


func equip_weapon_item(item: Dictionary) -> Dictionary:
	return equip_weapon_item_to_slot(item, active_weapon_slot)


func equip_weapon_item_to_slot(item: Dictionary, slot_index: int) -> Dictionary:
	if not _weapon_transition_phase.is_empty():
		return {"success": false, "reason": "收取武器期间不能替换装备"}
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
	if not _weapon_transition_phase.is_empty():
		return {"success": false, "reason": "收取武器期间不能卸下装备"}
	var current := get_equipped_weapon_instance_for_slot(slot_index)
	if current == null:
		return {"success": false, "reason": "该装备槽没有枪械"}
	_sync_equipped_weapon_instance()
	var old_item := current.to_item_dictionary()
	equipped_weapon_slots[slot_index] = null
	if slot_index == active_weapon_slot:
		_loading_weapon_instance = true
		_detach_fate_weapon_tree()
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


func get_weapon_transition_snapshot() -> Dictionary:
	var slot := active_weapon_slot
	var instance := equipped_weapon_slots[slot] as WeaponInstance
	var gun := instance.assembly_id if instance != null else ""
	var family := "sidearm" if gun == "bp_pistol" else "machinegun" if gun in ["bp_machinegun", "bp_sprinkler"] else "longgun"
	return {"active": not _weapon_transition_phase.is_empty(), "phase": _weapon_transition_phase,
		"progress": clampf(_weapon_transition_elapsed / WEAPON_TRANSITION_SECONDS, 0.0, 1.0),
		"slot": slot, "family": family, "target_slot": _weapon_transition_target}


func request_weapon_slot(slot_index: int) -> Dictionary:
	if slot_index < 0 or slot_index >= equipped_weapon_slots.size() or equipped_weapon_slots[slot_index] == null:
		return {"success": false, "reason": "该武器槽未装备"}
	if not _weapon_transition_phase.is_empty() or input_locked or current_hp <= 0 or get_state_machine_state() not in ["idle", "moving", "seated"]:
		return {"success": false, "reason": "当前动作不能切换武器"}
	_sync_equipped_weapon_instance()
	_weapon_transition_target = -1 if slot_index == active_weapon_slot and not weapon_holstered else slot_index
	if weapon != null:
		weapon.cancel_charge()
		weapon.cancel_reload()
	_clear_action_overlays()
	if weapon_holstered:
		var result := switch_weapon_slot(slot_index)
		if not bool(result.get("success", false)): return result
		set_weapon_holstered(false)
		_weapon_transition_phase = "draw"
	else:
		_weapon_transition_phase = "stow"
	_weapon_transition_elapsed = 0.0
	if weapon != null: weapon.display_only = true
	weapon_loadout_changed.emit(get_weapon_loadout_snapshot())
	return {"success": true, "pending": true, "holstering": _weapon_transition_target == -1, "slot_index": slot_index}


func set_weapon_holstered(value: bool) -> void:
	weapon_holstered = value
	if weapon != null:
		weapon.visible = not value
		weapon.display_only = value or not _weapon_transition_phase.is_empty()
		if value:
			weapon.cancel_charge()
			weapon.cancel_reload()
	_refresh_stowed_weapon_model(true)
	weapon_loadout_changed.emit(get_weapon_loadout_snapshot())


func _tick_weapon_transition(delta: float) -> void:
	if _weapon_transition_phase.is_empty(): return
	if input_locked or current_hp <= 0 or get_state_machine_state() not in ["idle", "moving", "seated"]:
		_weapon_transition_phase = ""
		_weapon_transition_target = -1
		set_weapon_holstered(weapon_holstered)
		return
	_weapon_transition_elapsed += delta
	if _weapon_transition_elapsed < WEAPON_TRANSITION_SECONDS: return
	if _weapon_transition_phase == "stow":
		if _weapon_transition_target < 0:
			_weapon_transition_phase = ""
			set_weapon_holstered(true)
		else:
			var result := switch_weapon_slot(_weapon_transition_target)
			if not bool(result.get("success", false)):
				_weapon_transition_phase = ""
				set_weapon_holstered(false)
				return
			_weapon_transition_phase = "draw"
			_weapon_transition_elapsed = 0.0
			set_weapon_holstered(false)
	else:
		_weapon_transition_phase = ""
		_weapon_transition_target = -1
		set_weapon_holstered(false)


func clear_all_equipped_weapons() -> Array[Dictionary]:
	_weapon_transition_phase = ""
	_weapon_transition_target = -1
	weapon_holstered = false
	_sync_equipped_weapon_instance()
	var removed: Array[Dictionary] = []
	for slot_index in range(equipped_weapon_slots.size()):
		var instance := equipped_weapon_slots[slot_index] as WeaponInstance
		if instance != null:
			removed.append(instance.to_item_dictionary())
		equipped_weapon_slots[slot_index] = null
	_loading_weapon_instance = true
	_detach_fate_weapon_tree()
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
	var stored_ammo := instance.current_ammo
	_loading_weapon_instance = true
	var previous_tree := weapon_tree
	var next_tree := _fate_weapon_trees.get(instance.weapon_instance_id) as WeaponAssemblyTree
	if next_tree == null or not is_instance_valid(next_tree):
		next_tree = instance.build_runtime_tree()
		if next_tree == null:
			_loading_weapon_instance = false
			return false
		_fate_weapon_trees[instance.weapon_instance_id] = next_tree
	if previous_tree != next_tree:
		if previous_tree.tree_changed.is_connected(_sync_weapon_from_tree):
			previous_tree.tree_changed.disconnect(_sync_weapon_from_tree)
		if previous_tree.stats_changed.is_connected(_on_weapon_tree_stats_changed):
			previous_tree.stats_changed.disconnect(_on_weapon_tree_stats_changed)
	weapon_tree = next_tree
	equipped_weapon_instance = instance
	_ensure_weapon_tree()
	equipped_weapon_slots[active_weapon_slot] = instance
	# configure_from_tree 会短暂把模型设为满弹。整个投影加载必须保持原子，
	# 不能让这个中间 ammo_changed 覆盖枪械实例保存的真实余弹。
	_sync_weapon_from_tree()
	if weapon != null and stored_ammo >= 0:
		weapon.current_ammo = clampi(stored_ammo, 0, weapon.magazine_size)
		instance.current_ammo = weapon.current_ammo
		weapon.ammo_changed.emit(weapon.current_ammo, weapon.magazine_size)
	var model_state: Dictionary = _fate_weapon_model_states.get(instance.weapon_instance_id, {})
	for key: String in model_state:
		weapon.set(key, model_state[key])
	_loading_weapon_instance = false
	_sync_equipped_weapon_instance()
	var bridge := get_tree().get_first_node_in_group("fate_cards")
	if bridge != null:
		bridge.call("set_player", self)
	return true


func _refresh_stowed_weapon_model(force := false) -> void:
	if weapon != null:
		weapon.visible = not weapon_holstered
		weapon.display_only = weapon_holstered or not _weapon_transition_phase.is_empty()
	_refresh_holstered_active_model()
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
	var scene := _get_stowed_weapon_scene()
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


func _get_stowed_weapon_scene() -> PackedScene:
	return load("res://assets/art/weapons/weapon_3d/wpn_gun_kit_root_top3d_v001.tscn") as PackedScene


func _refresh_holstered_active_model() -> void:
	if _holstered_active_model != null and is_instance_valid(_holstered_active_model):
		_holstered_active_model.queue_free()
	_holstered_active_model = null
	var instance := equipped_weapon_slots[active_weapon_slot] as WeaponInstance
	if not weapon_holstered or instance == null or avatar == null: return
	var scene := _get_stowed_weapon_scene()
	if scene == null: return
	_holstered_active_model = scene.instantiate() as WeaponModel3D
	_holstered_active_model.name = "HolsteredActiveWeaponModel3D"
	_holstered_active_model.display_only = true
	_holstered_active_model.render_layers = 2
	_holstered_active_model.set_meta("weapon_item_data", instance.to_item_dictionary())
	_holstered_active_model.set_meta("weapon_slot_index", active_weapon_slot)
	avatar.get_stowed_weapon_socket(active_weapon_slot).add_child(_holstered_active_model)
	_holstered_active_model.scale = Vector3.ONE * (0.70 if instance.assembly_id in ["bp_baseball_bat", "bp_greatblade", "bp_waraxe"] else 0.52)


func commit_fate_weapon_upgrade(card: FateCard, staged_tree: WeaponAssemblyTree, transaction_id: String) -> Dictionary:
	var instance := get_equipped_weapon_instance()
	if instance == null or staged_tree == null or staged_tree.root == null:
		return {"success": false, "reason": "枪械事务目标无效"}
	var before := instance.assembly_snapshot.duplicate(true)
	var result := instance.append_fate_upgrade(card, transaction_id)
	if not bool(result.get("success", false)):
		return result
	instance.capture_runtime_tree(staged_tree)
	if not _refresh_weapon_slot_after_instance_change(active_weapon_slot, instance):
		instance.fate_upgrades.pop_back()
		instance.assembly_snapshot = before
		return {"success": false, "reason": "枪械事务投影失败"}
	return result


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
	_fate_weapon_trees[equipped_weapon_instance.weapon_instance_id] = weapon_tree
	if weapon != null:
		_fate_weapon_model_states[equipped_weapon_instance.weapon_instance_id] = {
			"_reload_first_shot": weapon.get("_reload_first_shot"),
			"_fire_sequence": weapon.get("_fire_sequence"),
		}
	equipped_weapon_slots[active_weapon_slot] = equipped_weapon_instance
	if weapon != null and is_instance_valid(weapon):
		equipped_weapon_instance.current_ammo = weapon.current_ammo


func refill_ammo() -> bool:
	return weapon != null and weapon.refill_ammo()


func set_reload_ammo_provider(provider: Callable) -> void:
	_reload_ammo_provider = provider
	if weapon != null and is_instance_valid(weapon):
		weapon.set_reload_ammo_provider(provider)


func request_reload() -> bool:
	return not weapon_holstered and _weapon_transition_phase.is_empty() and weapon != null and is_instance_valid(weapon) and weapon.request_reload()


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
		final_multiplier *= float(value)
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
	if weapon_holstered:
		return {"gun_id": "", "bullet_id": "", "has_model": false, "is_3d": true, "holstered": true}
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
	# 自动空弹换弹也发此信号，统一在角色桥消费本房第一次成功开始的换弹。
	if bool(_character_fate["first_reload_ready"]):
		_character_fate["first_reload_ready"] = false
		duration /= float(_character_fate["first_reload_speed"])
		weapon.set("_active_reload_duration", duration)
		weapon.set("_reload_remaining", duration)
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
	return not weapon_holstered and _weapon_transition_phase.is_empty() and melee_combat != null and melee_combat.request_attack()


func _update_combat_input() -> void:
	if weapon_holstered or not _weapon_transition_phase.is_empty():
		if weapon != null: weapon.cancel_charge()
		return
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
	if input_locked or current_hp <= 0 or weapon == null or _silence_remaining > 0.0 or _active_ladder != null:
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
		request_reload()


func _tick_dash_input_buffer(delta: float) -> void:
	if _dash_input_buffer <= 0.0:
		return
	if input_locked or current_hp <= 0 or get_state_machine_state() not in ["idle", "moving"]:
		_dash_input_buffer = 0.0
		return
	if dash_cooldown_timer <= 0.0:
		_dash_input_buffer = 0.0
		_begin_dash()
	else:
		_dash_input_buffer = maxf(0.0, _dash_input_buffer - delta)


func _begin_dash() -> bool:
	if (
		not input_locked and current_hp > 0
		and get_state_machine_state() in ["idle", "moving"]
		and dash_cooldown_timer > 0.0
		and dash_cooldown_timer <= DASH_INPUT_BUFFER_SECONDS
	):
		_dash_input_buffer = DASH_INPUT_BUFFER_SECONDS
		return false
	if (
		input_locked
		or current_hp <= 0
		or is_dashing
		or dash_cooldown_timer > 0.0
		or (_state_machine != null and _state_machine.current_state_name in ["falling", "landing"])
	):
		return false
	_dash_input_buffer = 0.0
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
	if is_seated_on_chair():
		_state_machine.transition_to("seated")
		return
	if _active_ladder != null:
		_state_machine.transition_to("climbing")
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


func _init_expression_system() -> void:
	expression_system = CharacterExpressionSystem.new()
	expression_system.name = "CharacterExpressionSystem"
	expression_system.random_seed = expression_random_seed
	add_child(expression_system)
	expression_system.set_random_enabled(expression_random_enabled)
	_expression_state_adapter = PlayerExpressionStateAdapter.new()
	_expression_state_adapter.configure(expression_system, get_presentation_state())
	presentation_state_changed.connect(_expression_state_adapter.on_presentation_state_changed)
	if avatar != null:
		var display := avatar.head.get_node_or_null("FaceAccessorySocket/ElectronicMask")
		if display != null and display.has_method("bind_expression_system"):
			display.bind_expression_system(expression_system)


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
	# 结算后保护不参与倒计时：撤离/阵亡已定，返航窗口内不能再被伤害改变结局。
	if _post_settlement_invulnerable:
		return
	_invincible_remaining = maxf(0.0, _invincible_remaining - delta)
	if _invincible_remaining <= 0.0 and not is_dashing:
		is_invincible = false


## 行动结算已提交、场景尚未切换或复位完成时调用：屏蔽返航窗口内的伤害。
## 玩家此时输入被锁、无法走位，被残留拦截怪拖死会污染已写盘的结算结果。
func hold_post_settlement_invulnerability() -> void:
	_post_settlement_invulnerable = true
	is_invincible = true
	_invincible_remaining = 0.0


## 进入新一轮行动（例如塔楼成功返航复位）时解除结算后保护。
func release_post_settlement_invulnerability() -> void:
	if not _post_settlement_invulnerable:
		return
	_post_settlement_invulnerable = false
	is_invincible = false
	_invincible_remaining = 0.0


func _update_aim_from_mouse() -> void:
	if camera == null or not camera.is_inside_tree():
		return
	# 叙事用 actor.face 接管朝向时鼠标瞄准必须让位：input_locked 不拦瞄准
	# （锁定期间仍可转向），所以玩家一晃鼠标就会把剧本刚摆好的"左右张望"顶掉，
	# 表现为中间画面/朝向错乱，且运行时零报错。
	if _narrative_holds_aim():
		return
	# 移动端：触屏瞄准方向由摇杆控制时跳过鼠标射线
	if _mobile_input_available and _mobile_face_active:
		var aim_dir_3d := _get_mobile_face_direction()
		if aim_dir_3d.length_squared() > 0.0001:
			# 虚拟摇杆瞄准辅助（磁吸）：只对摇杆输入生效 —— 键鼠走鼠标射线，
			# 精度本来就够，加吸附反而变成「准星不听话」。触屏虚拟摇杆同样受益。
			aim_dir_3d = AimAssist3D.solve(aim_dir_3d, _collect_aim_assist_candidates(aim_dir_3d))
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


## 叙事是否正在接管角色朝向（见 NarrativeDirector.is_actor_facing_overridden）。
func _narrative_holds_aim() -> bool:
	return (
		NarrativeDirector != null
		and NarrativeDirector.has_method("is_actor_facing_overridden")
		and bool(NarrativeDirector.is_actor_facing_overridden())
	)


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
	_state_machine.register("seated", Player3DSeatedState.new())
	_state_machine.register("climbing", Player3DClimbingState.new())
	_state_machine.register("dead", Player3DDeadState.new())
	_state_machine.configure_transition_map({
		"idle": ["moving", "dashing", "hurt", "locked", "falling", "seated", "climbing", "dead"],
		"moving": ["idle", "dashing", "hurt", "locked", "falling", "seated", "climbing", "dead"],
		"dashing": ["idle", "moving", "hurt", "locked", "falling", "dead"],
		"hurt": ["idle", "moving", "locked", "falling", "dead"],
		"locked": ["idle", "moving", "hurt", "falling", "dead"],
		"falling": ["landing", "hurt", "dead"],
		"landing": ["idle", "moving", "hurt", "locked", "falling", "dead"],
		"seated": ["idle", "moving", "locked", "hurt", "falling", "dead"],
		"climbing": ["idle", "moving", "falling", "dead"],
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
