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
@export var combat_enabled: bool = true

var current_hp: int = 100
var is_invincible: bool = false
var is_dashing: bool = false
var dash_cooldown_timer: float = 0.0
var aim_direction: Vector2 = Vector2.RIGHT
var last_move_direction: Vector2 = Vector2.RIGHT
var dash_direction: Vector2 = Vector2.RIGHT
var input_locked: bool = false
var _damage_multiplier: float = 1.0  # 伤害倍率（由命运触发器/祝福效果设置，如 BLESS_DEAD）

## 沉默状态（被精英"抢枪"词缀 skill_countershot 命中时生效）
var _is_silenced: bool = false
var _silence_timer: float = 0.0
var _silence_duration: float = 0.0

var _audio: AudioManager = null

@onready var weapon_anchor: Marker2D = $WeaponAnchor
@onready var invincible_timer: Timer = $InvincibleTimer
@onready var body_visuals: Node = get_node_or_null("Body")

## 玩家武器装配树（由命运卡片系统使用）
var weapon_tree: WeaponAssemblyTree

## 调试用标签（屏幕显示）
var _debug_label: Label = null

## 移动端输入方向
var _mobile_input: Vector2 = Vector2.ZERO

func _enter_tree() -> void:
	_ensure_weapon_tree()

func _ready() -> void:
	_ensure_weapon_tree()
	current_hp = max_hp
	_audio = get_node_or_null("/root/AudioManager") as AudioManager
	if invincible_timer and not invincible_timer.timeout.is_connected(_on_invincible_timeout):
		invincible_timer.timeout.connect(_on_invincible_timeout)
	add_to_group("player")
	set_combat_enabled(combat_enabled)
	hp_changed.emit(current_hp, max_hp)

	# 连接移动端控制信号
	var mobile := get_node_or_null("/root/MobileControls")
	if mobile != null and mobile.has_signal("move_direction"):
		mobile.connect("move_direction", _on_mobile_move)
		mobile.connect("dash_pressed", _on_mobile_dash)
		mobile.connect("shoot_pressed", _on_mobile_shoot)


func _on_mobile_move(dir: Vector2) -> void:
	_mobile_input = dir


func _on_mobile_dash() -> void:
	if dash_cooldown_timer <= 0.0 and not is_dashing:
		_start_dash()


func _on_mobile_shoot() -> void:
	pass  # 射击由武器系统处理，这里只是占位

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
	_handle_silence(delta)

func _handle_movement(_delta: float) -> void:
	if input_locked:
		velocity = Vector2.ZERO
		move_and_slide()
		return
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

	# 合并移动端输入（优先级更高）
	if _mobile_input != Vector2.ZERO:
		direction = _mobile_input

	return direction.normalized() if direction != Vector2.ZERO else Vector2.ZERO


var _debug_visible := false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_ray") or (event is InputEventKey and event.pressed and event.keycode == 86):
		_debug_visible = not _debug_visible
		if _debug_visible:
			_print_collision_debug()
		elif _debug_label != null:
			_debug_label.text = ""


func _print_collision_debug() -> void:
	# 获取或创建调试UI
	if _debug_label == null or not is_instance_valid(_debug_label):
		_debug_label = Label.new()
		_debug_label.name = "DebugCollisionLabel"
		_debug_label.z_index = 1000
		_debug_label.add_theme_font_size_override("font_size", 16)
		_debug_label.modulate = Color(1, 1, 0.2, 1)
		add_child(_debug_label)

	var space_rid := get_world_2d().direct_space_state
	var pos := global_position
	var msg := "========== 碰撞调试 ==========\n"
	msg += "玩家位置: (%.0f, %.0f)\n\n" % [pos.x, pos.y]

	var dist: float
	var result: Dictionary
	var query := PhysicsRayQueryParameters2D.new()
	query.collision_mask = 7
	query.exclude = [self]

	# 右
	query.from = pos
	query.to = pos + Vector2(500.0, 0)
	result = space_rid.intersect_ray(query)
	if result.size() > 0:
		dist = pos.distance_to(result.get("position", Vector2.ZERO))
		var collider_name = result.get("collider", null)
		var name_str = collider_name.name if collider_name else "null"
		msg += "[右] 碰撞! 距离=%.1f %s\n" % [dist, name_str]
	else:
		msg += "[右] 无碰撞\n"

	# 左
	query.from = pos
	query.to = pos + Vector2(-500.0, 0)
	result = space_rid.intersect_ray(query)
	if result.size() > 0:
		dist = pos.distance_to(result.get("position", Vector2.ZERO))
		var collider_name = result.get("collider", null)
		var name_str = collider_name.name if collider_name else "null"
		msg += "[左] 碰撞! 距离=%.1f %s\n" % [dist, name_str]
	else:
		msg += "[左] 无碰撞\n"

	# 上
	query.from = pos
	query.to = pos + Vector2(0, -500.0)
	result = space_rid.intersect_ray(query)
	if result.size() > 0:
		dist = pos.distance_to(result.get("position", Vector2.ZERO))
		var collider_name = result.get("collider", null)
		var name_str = collider_name.name if collider_name else "null"
		msg += "[上] 碰撞! 距离=%.1f %s\n" % [dist, name_str]
	else:
		msg += "[上] 无碰撞\n"

	# 下
	query.from = pos
	query.to = pos + Vector2(0, 500.0)
	result = space_rid.intersect_ray(query)
	if result.size() > 0:
		dist = pos.distance_to(result.get("position", Vector2.ZERO))
		var collider_name = result.get("collider", null)
		var name_str = collider_name.name if collider_name else "null"
		msg += "[下] 碰撞! 距离=%.1f %s\n" % [dist, name_str]
	else:
		msg += "[下] 无碰撞\n"

	msg += "================================\n按 V 键关闭"

	_debug_label.text = msg

func _handle_dash_cooldown(delta: float) -> void:
	if input_locked:
		dash_cooldown_changed.emit(clampf(dash_cooldown_timer / DASH_COOLDOWN, 0.0, 1.0) if dash_cooldown_timer > 0.0 else 0.0)
		return
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

func set_input_locked(locked: bool) -> void:
	input_locked = locked
	if locked:
		is_dashing = false
		velocity = Vector2.ZERO


func set_combat_enabled(enabled: bool) -> void:
	combat_enabled = enabled
	var aim_node := get_node_or_null("Aim") as CanvasItem
	var weapon_display := get_node_or_null("WeaponAnchor") as CanvasItem
	if aim_node != null:
		aim_node.visible = enabled
	if weapon_display != null:
		weapon_display.visible = enabled


func is_combat_enabled() -> bool:
	return combat_enabled

## 沉默入口（被精英"抢枪"词缀 skill_countershot 命中时由 EliteActiveSkillComponent 调用）
func apply_silence(duration: float) -> void:
	if current_hp <= 0:
		return
	_is_silenced = true
	_silence_duration = duration
	_silence_timer = duration
	print("[Player] 被沉默 %.1f 秒" % duration)

func _handle_silence(delta: float) -> void:
	if not _is_silenced:
		return
	_silence_timer -= delta
	if _silence_timer <= 0.0:
		_is_silenced = false
		_silence_timer = 0.0
		print("[Player] 沉默解除")

func take_damage(amount: int) -> void:
	if is_invincible or current_hp <= 0:
		return
	# 获取武器树超频惩罚（每次射击叠加效果，超频命卡写入 overheat_penalty>1）
	var overheat_mult: float = 1.0
	if weapon_tree != null and weapon_tree.has_method("get_overheat_penalty"):
		overheat_mult = weapon_tree.call("get_overheat_penalty")
	var final_damage: int = maxi(1, int(float(amount - armor) * overheat_mult))
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
	# 全屏红闪（0.15s 衰减）— 强化受击反馈
	_spawn_damage_red_flash()


## 生成全屏红闪（半透明 ColorRect 覆盖整个视口，0.15s 衰减）
func _spawn_damage_red_flash() -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	var flash := ColorRect.new()
	flash.name = "DamageRedFlash"
	flash.color = Color(0.95, 0.15, 0.15, 0.0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.offset_left = 0
	flash.offset_top = 0
	flash.offset_right = 0
	flash.offset_bottom = 0
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 500
	# 找到合适的 CanvasLayer 挂载（优先 HUD 层，避免被 3D 覆盖）
	var host: Node = tree.root
	var canvas: CanvasLayer = host.get_node_or_null("GameUI") as CanvasLayer
	if canvas != null:
		canvas.add_child(flash)
	else:
		host.add_child(flash)
	# 快速闪红后衰减
	var tween := flash.create_tween()
	tween.tween_property(flash, "color:a", 0.42, 0.04)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(flash, "color:a", 0.0, 0.15)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(flash.queue_free)

func _play_damage_sfx() -> void:
	if _audio:
		_audio.play_player_hit_sfx()
	# 受伤震屏（通过 HitEffects 或直接找 ScreenShake）
	var shake: Node = get_tree().root.find_child("ScreenShake", true, false)
	if shake == null:
		shake = get_node_or_null("../fx/HitEffects")
	if shake != null and shake.has_method("trigger"):
		shake.call("trigger", 6.0, 0.12)

func is_moving() -> bool:
	return velocity.length() > 10.0

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


## 设置玩家伤害倍率（由命运触发器/祝福效果调用，如 BLESS_DEAD）
func apply_damage_multiplier(multiplier: float) -> void:
	_damage_multiplier = multiplier
	# 同时同步给 WeaponAssemblyTree，确保完整伤害链路生效
	if weapon_tree != null and weapon_tree.has_method("apply_damage_multiplier"):
		weapon_tree.apply_damage_multiplier(multiplier)


## 设置指定 key 的临时伤害加成（由 RoomEventHandler 祝福效果调用）
## source_key: "blessing"/"curse" 等标识，叠加时覆盖
var _named_damage_multipliers: Dictionary = {}


func set_damage_multiplier(source_key: String, multiplier: float) -> void:
	_named_damage_multipliers[source_key] = multiplier
	_apply_named_multipliers()


func apply_damage_buff(source_key: String, additive_bonus: float) -> void:
	# additive_bonus: 0.10 表示+10%
	var target_mult: float = 1.0 + additive_bonus
	_named_damage_multipliers[source_key] = target_mult
	_apply_named_multipliers()


func remove_damage_buff(source_key: String) -> void:
	_named_damage_multipliers.erase(source_key)
	_apply_named_multipliers()


func _apply_named_multipliers() -> void:
	# 合并所有 named 增益，取最大值作为最终倍率
	var final_mult: float = 1.0
	for k in _named_damage_multipliers:
		final_mult = max(final_mult, _named_damage_multipliers[k])
	_damage_multiplier = final_mult
	if weapon_tree != null and weapon_tree.has_method("apply_damage_multiplier"):
		weapon_tree.apply_damage_multiplier(_damage_multiplier)
