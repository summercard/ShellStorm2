extends CharacterBody2D

signal hp_changed(current: int, maximum: int)
signal enemy_killed()          # 击杀信号，供 UI 计分用
signal dash_started()          # 闪避开始
signal dash_ended()             # 闪避结束
signal dash_cooldown_changed(cooldown_ratio: float)  # 闪避冷却进度 [0.0~1.0]，0=就绪

const SPEED: float = 350.0
const DASH_SPEED: float = 800.0
const DASH_DURATION: float = 0.15
const DASH_COOLDOWN: float = 3.0
const INVINCIBLE_DURATION: float = 0.2

@export var max_hp: int = 100
@export var armor: int = 0

var current_hp: int = 100
var is_invincible: bool = false
var is_dashing: bool = false
var dash_cooldown_timer: float = 0.0
var aim_direction: Vector2 = Vector2.RIGHT

## 音频管理器引用
var _audio: AudioManager = null

@onready var weapon_anchor: Marker2D = $WeaponAnchor
@onready var invincible_timer: Timer = $InvincibleTimer

## 玩家武器装配树（由命运卡片系统使用）
var weapon_tree: WeaponAssemblyTree

func _ready() -> void:
	current_hp = max_hp
	hp_changed.connect(_on_hp_changed)
	_audio = get_node_or_null("/root/AudioManager") as AudioManager
	add_to_group("player")
	
	# 初始化武器装配树（基于蓝图Tier选择初始武器）
	if BlueprintRegistry != null:
		weapon_tree = BlueprintRegistry.get_starting_weapon_tree()
	else:
		weapon_tree = WeaponPresets.build_rifle()

func _physics_process(delta: float) -> void:
	_handle_movement(delta)
	_handle_dash_cooldown(delta)
	_update_invincibility()

func _handle_movement(delta: float) -> void:
	var input_direction = _get_input_direction()
	
	if is_dashing:
		velocity = aim_direction * DASH_SPEED
		move_and_slide()
		return
	
	velocity = input_direction * SPEED
	move_and_slide()

func _get_input_direction() -> Vector2:
	var direction = Vector2.ZERO
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
	if dash_cooldown_timer > 0:
		dash_cooldown_timer -= delta
		# 发射冷却进度（0.0=刚用完，1.0=就绪）
		dash_cooldown_changed.emit(clampf(dash_cooldown_timer / DASH_COOLDOWN, 0.0, 1.0))
	else:
		# 冷却已就绪
		dash_cooldown_changed.emit(0.0)
	
	if Input.is_action_just_pressed("dash") and dash_cooldown_timer <= 0 and not is_dashing:
		_start_dash()

func _start_dash() -> void:
	dash_started.emit()
	if _audio:
		_audio.play_dash_sfx()
	is_dashing = true
	is_invincible = true
	dash_cooldown_timer = DASH_COOLDOWN
	invincible_timer.start(INVINCIBLE_DURATION)
	await get_tree().create_timer(DASH_DURATION).timeout
	is_dashing = false
	dash_ended.emit()

func _update_invincibility() -> void:
	# Handled by timer
	pass

func take_damage(amount: int) -> void:
	if is_invincible:
		return
	
	var final_damage = max(1, amount - armor)
	current_hp -= final_damage
	hp_changed.emit(current_hp, max_hp)
	
	is_invincible = true
	invincible_timer.start(INVINCIBLE_DURATION)
	
	if current_hp <= 0:
		queue_free()
		Global.trigger_game_over()

func heal(amount: int) -> void:
	current_hp = min(max_hp, current_hp + amount)
	hp_changed.emit(current_hp, max_hp)

func _on_hp_changed(current: int, maximum: int) -> void:
	pass

func get_weapon_anchor() -> Marker2D:
	return weapon_anchor

func get_aim_direction() -> Vector2:
	return aim_direction

func set_aim_direction(dir: Vector2) -> void:
	aim_direction = dir.normalized()

## 获取玩家的武器装配树（供 FateCardGameBridge 使用）
func get_weapon_tree() -> WeaponAssemblyTree:
	return weapon_tree