extends CharacterBody2D
class_name Player

signal hp_changed(current: int, maximum: int)
signal enemy_killed()
signal dash_started()
signal dash_ended()
signal dash_cooldown_changed(cooldown_ratio: float)

const SPEED: float = 350.0
const DASH_SPEED: float = 820.0
const DASH_DURATION: float = 0.15
const DASH_COOLDOWN: float = 2.2
const INVINCIBLE_DURATION: float = 0.22

@export var max_hp: int = 100
@export var armor: int = 0

var current_hp: int = 100
var is_invincible: bool = false
var is_dashing: bool = false
var dash_cooldown_timer: float = 0.0
var aim_direction: Vector2 = Vector2.RIGHT
var last_move_direction: Vector2 = Vector2.RIGHT
var dash_direction: Vector2 = Vector2.RIGHT

var _audio: AudioManager = null

@onready var weapon_anchor: Marker2D = $WeaponAnchor
@onready var invincible_timer: Timer = $InvincibleTimer
@onready var body_visuals: Node = get_node_or_null("Body")

## 玩家武器装配树（由命运卡片系统使用）
var weapon_tree: WeaponAssemblyTree

func _enter_tree() -> void:
	_ensure_weapon_tree()

func _ready() -> void:
	_ensure_weapon_tree()
	current_hp = max_hp
	_audio = get_node_or_null("/root/AudioManager") as AudioManager
	if invincible_timer and not invincible_timer.timeout.is_connected(_on_invincible_timeout):
		invincible_timer.timeout.connect(_on_invincible_timeout)
	add_to_group("player")
	hp_changed.emit(current_hp, max_hp)

func _ensure_weapon_tree() -> void:
	if weapon_tree == null:
		var blueprint_registry := get_node_or_null("/root/BlueprintRegistry")
		if blueprint_registry != null and blueprint_registry.has_method("get_starting_weapon_tree"):
			weapon_tree = blueprint_registry.call("get_starting_weapon_tree") as WeaponAssemblyTree
		if weapon_tree == null:
			weapon_tree = WeaponPresets.build_rifle()
	if weapon_tree != null and weapon_tree.get_parent() == null:
		weapon_tree.name = "WeaponAssemblyTree"
		add_child(weapon_tree)

func _physics_process(delta: float) -> void:
	_handle_movement(delta)
	_handle_dash_cooldown(delta)

func _handle_movement(_delta: float) -> void:
	var input_direction := _get_input_direction()
	if input_direction != Vector2.ZERO:
		last_move_direction = input_direction
	
	if is_dashing:
		velocity = dash_direction * DASH_SPEED
		move_and_slide()
		return
	
	velocity = input_direction * SPEED
	move_and_slide()

func _get_input_direction() -> Vector2:
	var direction := Vector2.ZERO
	if Input.is_action_pressed("move_up"):
		direction.y -= 1
	if Input.is_action_pressed("move_down"):
		direction.y += 1
	if Input.is_action_pressed("move_left"):
		direction.x -= 1
	if Input.is_action_pressed("move_right"):
		direction.x += 1
	return direction.normalized() if direction != Vector2.ZERO else Vector2.ZERO

func _handle_dash_cooldown(delta: float) -> void:
	if dash_cooldown_timer > 0.0:
		dash_cooldown_timer = max(0.0, dash_cooldown_timer - delta)
		dash_cooldown_changed.emit(clampf(dash_cooldown_timer / DASH_COOLDOWN, 0.0, 1.0))
	else:
		dash_cooldown_changed.emit(0.0)
	
	if Input.is_action_just_pressed("dash") and dash_cooldown_timer <= 0.0 and not is_dashing:
		_start_dash()

func _start_dash() -> void:
	dash_started.emit()
	if _audio:
		_audio.play_dash_sfx()
	is_dashing = true
	is_invincible = true
	dash_cooldown_timer = DASH_COOLDOWN
	var input_direction := _get_input_direction()
	dash_direction = input_direction if input_direction != Vector2.ZERO else aim_direction
	if dash_direction == Vector2.ZERO:
		dash_direction = last_move_direction
	invincible_timer.start(INVINCIBLE_DURATION)
	await get_tree().create_timer(DASH_DURATION).timeout
	is_dashing = false
	dash_ended.emit()

func _on_invincible_timeout() -> void:
	if not is_dashing:
		is_invincible = false

func take_damage(amount: int) -> void:
	if is_invincible or current_hp <= 0:
		return
	var final_damage: int = maxi(1, amount - armor)
	current_hp = max(0, current_hp - final_damage)
	hp_changed.emit(current_hp, max_hp)
	_flash_damage()
	_play_damage_sfx()
	is_invincible = true
	if invincible_timer:
		invincible_timer.start(INVINCIBLE_DURATION)
	if current_hp <= 0:
		Global.trigger_game_over()

func heal(amount: int) -> void:
	if current_hp <= 0:
		return
	current_hp = min(max_hp, current_hp + amount)
	hp_changed.emit(current_hp, max_hp)
	if body_visuals and body_visuals.has_method("flash_heal"):
		body_visuals.call("flash_heal")

func _flash_damage() -> void:
	if body_visuals and body_visuals.has_method("flash_damage"):
		body_visuals.call("flash_damage")

func _play_damage_sfx() -> void:
	if _audio:
		_audio.play_player_hit_sfx()

func get_weapon_anchor() -> Marker2D:
	return weapon_anchor

func get_aim_direction() -> Vector2:
	return aim_direction

func set_aim_direction(dir: Vector2) -> void:
	if dir.length_squared() > 0.0001:
		aim_direction = dir.normalized()

func get_weapon_tree() -> WeaponAssemblyTree:
	_ensure_weapon_tree()
	return weapon_tree
