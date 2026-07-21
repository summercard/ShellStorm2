class_name Player3D
extends CharacterBody3D
## 首张 3D 地图使用的玩家外壳。复用六态 ID 与 StateMachine 契约，
## 但把移动、鼠标射线与碰撞转换到 XZ 平面。

signal hp_changed(current: int, maximum: int)
signal dash_started()
signal dash_ended()
signal dash_cooldown_changed(cooldown_ratio: float)
signal presentation_state_changed(state_id: String, context: Dictionary)
signal input_lock_changed(locked: bool)
signal weapon_changed(gun_id: String, bullet_id: String)
signal ammo_changed(current: int, maximum: int)

const SPEED := 7.0
const DASH_SPEED := 16.5
const DASH_DURATION := 0.17
const DASH_COOLDOWN := 2.2
const INVINCIBLE_DURATION := 0.24

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

@onready var avatar: PlayerAvatar3D = $Avatar3D
@onready var camera: Camera3D = $Camera3D
@onready var aim_cursor: Node3D = $AimCursor


func _ready() -> void:
	current_hp = max_hp
	add_to_group("player")
	add_to_group("player_3d")
	_init_state_machine()
	if start_with_weapon:
		equip_weapon(default_gun_id, default_bullet_id)
	hp_changed.emit(current_hp, max_hp)
	_update_aim_from_mouse()


func _physics_process(delta: float) -> void:
	_update_invincibility(delta)
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


func get_move_speed() -> float:
	return SPEED


func get_dash_speed() -> float:
	return DASH_SPEED


func get_dash_duration() -> float:
	return DASH_DURATION


func get_state_machine_state() -> String:
	return _state_machine.current_state_name if _state_machine != null else ""


func get_state_machine_snapshot() -> Dictionary:
	return _state_machine.get_snapshot() if _state_machine != null else {}


func is_low_health() -> bool:
	return current_hp > 0 and float(current_hp) / float(maxi(1, max_hp)) <= 0.30


func take_damage(amount: int, _critical := false, _hit_direction := Vector3.ZERO) -> void:
	if current_hp <= 0 or is_invincible:
		return
	_last_damage_amount = maxi(1, amount)
	current_hp = maxi(0, current_hp - _last_damage_amount)
	hp_changed.emit(current_hp, max_hp)
	is_invincible = true
	_invincible_remaining = INVINCIBLE_DURATION
	if current_hp <= 0:
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


func equip_weapon(gun_id: String, bullet_id: String) -> bool:
	if avatar == null or avatar.weapon_socket == null:
		return false
	if weapon == null or not is_instance_valid(weapon):
		var scene := load("res://assets/art/weapons/weapon_3d/wpn_gun_kit_root_top3d_v001.tscn") as PackedScene
		if scene == null:
			return false
		weapon = scene.instantiate() as WeaponModel3D
		avatar.weapon_socket.add_child(weapon)
		weapon.ammo_changed.connect(_on_weapon_ammo_changed)
		weapon.loadout_changed.connect(_on_weapon_loadout_changed)
	return weapon.configure(gun_id, bullet_id)


func clear_weapon() -> void:
	if weapon != null and is_instance_valid(weapon):
		weapon.clear_weapon()


func get_weapon_snapshot() -> Dictionary:
	return weapon.get_snapshot() if weapon != null and is_instance_valid(weapon) else {
		"gun_id": "", "bullet_id": "", "has_model": false, "is_3d": true,
	}


func _on_weapon_ammo_changed(current: int, maximum: int) -> void:
	ammo_changed.emit(current, maximum)


func _on_weapon_loadout_changed(gun_id: String, bullet_id: String) -> void:
	weapon_changed.emit(gun_id, bullet_id)


func _update_combat_input() -> void:
	if not combat_enabled or input_locked or current_hp <= 0 or weapon == null:
		return
	if Input.is_action_pressed("shoot"):
		weapon.try_fire(aim_direction, self)
	if Input.is_action_just_pressed("reload"):
		weapon.request_reload()


func _begin_dash() -> bool:
	if input_locked or current_hp <= 0 or is_dashing or dash_cooldown_timer > 0.0:
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


func _transition_to_locomotion() -> void:
	if _state_machine == null or current_hp <= 0:
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
	var intersection = Plane(Vector3.UP, 0.0).intersects_ray(ray_origin, ray_direction)
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
	_state_machine.register("dead", Player3DDeadState.new())
	_state_machine.configure_transition_map({
		"idle": ["moving", "dashing", "hurt", "locked", "dead"],
		"moving": ["idle", "dashing", "hurt", "locked", "dead"],
		"dashing": ["idle", "moving", "hurt", "locked", "dead"],
		"hurt": ["idle", "moving", "locked", "dead"],
		"locked": ["idle", "moving", "hurt", "dead"],
		"dead": [],
	})
	_state_machine.start("idle")
