extends CharacterBody2D
class_name Player

signal hp_changed(current: int, maximum: int)
signal enemy_killed()
signal dash_started()
signal dash_ended()
signal dash_cooldown_changed(cooldown_ratio: float)
signal presentation_state_changed(state_id: String, context: Dictionary)
signal low_health_changed(active: bool, hp_ratio: float)
signal damage_taken(amount: int, current: int, maximum: int)
signal input_lock_changed(locked: bool)
signal status_effect_changed(effect_id: String, active: bool, duration: float)
signal weapon_instance_changed(snapshot: Dictionary)

const SPEED: float = 350.0
const DASH_SPEED: float = 820.0
const DASH_DURATION: float = 0.15
const DASH_COOLDOWN: float = 2.2
const INVINCIBLE_DURATION: float = 0.22
const VISUAL_FACING_DEADZONE: float = 0.15
const WEAPON_SOCKET_X: float = 24.0
const PLAYER_AVATAR_RENDERER_SCRIPT := preload("res://src/player/PlayerAvatarRenderer.gd")

@export var max_hp: int = 100
@export var armor: int = 0
@export var combat_enabled: bool = true

var current_hp: int = 100
var is_invincible: bool = false
var is_dashing: bool = false
var dash_cooldown_timer: float = 0.0
var aim_direction: Vector2 = Vector2.RIGHT
var visual_facing_sign: float = 1.0
var last_move_direction: Vector2 = Vector2.RIGHT
var dash_direction: Vector2 = Vector2.RIGHT
var input_locked: bool = false
var _damage_multiplier: float = 1.0  # 伤害倍率（由命运触发器/祝福效果设置，如 BLESS_DEAD）
var _presentation_state := "idle"
var _low_health_active := false
var _last_damage_amount := 0

## 沉默状态（被精英"抢枪"词缀 skill_countershot 命中时生效）
var _is_silenced: bool = false
var _silence_timer: float = 0.0
var _silence_duration: float = 0.0

var _audio: AudioManager = null

@onready var weapon_anchor: Marker2D = $WeaponAnchor
@onready var invincible_timer: Timer = $InvincibleTimer
@onready var body_visuals: Node = get_node_or_null("Body")

## 角色组件系统（2026-06-10 PHxx 通用组件框架接入）
## 集中管理 body/head/hand 三个组件 + 武器挂载 + 反馈广播
var components: CharacterComponents = null

## 玩家武器装配树（由命运卡片系统使用）
var weapon_tree: WeaponAssemblyTree
var equipped_weapon_instance: WeaponInstance = null
var _loading_weapon_instance := false

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
	_init_state_machine()
	_init_components()
	_update_low_health_state()

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
	if weapon_tree != null:
		if not weapon_tree.tree_changed.is_connected(_on_weapon_runtime_changed):
			weapon_tree.tree_changed.connect(_on_weapon_runtime_changed)
		if not weapon_tree.ammo_changed.is_connected(_on_weapon_ammo_changed):
			weapon_tree.ammo_changed.connect(_on_weapon_ammo_changed)
	if equipped_weapon_instance == null and weapon_tree != null and weapon_tree.get_root() != null:
		equipped_weapon_instance = WeaponInstance.from_runtime_tree(weapon_tree)

func _physics_process(delta: float) -> void:
	# 沉默是叠加标志（不进入独立状态），由 _handle_silence 单独推进
	_handle_silence(delta)
	# 移动 + 冲刺 + 冷却 都交给状态机调度
	if _state_machine and _state_machine_initialized:
		_state_machine.physics_update(delta)
	# 组件摆动动画（待机上下浮动 + 移动左右倾斜 + 头手跟随）
	if components != null:
		var animation_direction := velocity.normalized() if velocity.length_squared() > 100.0 else Vector2.ZERO
		components.tick_animations(delta, animation_direction)

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

func _start_dash() -> void:
	# 由 idle 状态机内部实际处理（看 PlayerIdleState._start_dash）
	# 这里保留作为外部入口（移动端 dash 按钮调用），转发到状态机
	if _state_machine and _state_machine_initialized:
		_state_machine.dispatch_event("request_dash", null)
	else:
		# 状态机未启动：保留原行为作为兜底
		dash_started.emit()
		if _audio and DisplayServer.get_name() != "headless":
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


func _tick_dash_cooldown(delta: float) -> void:
	if dash_cooldown_timer > 0.0:
		dash_cooldown_timer = maxf(0.0, dash_cooldown_timer - delta)
	dash_cooldown_changed.emit(clampf(dash_cooldown_timer / DASH_COOLDOWN, 0.0, 1.0))


func _begin_dash() -> bool:
	if input_locked or current_hp <= 0 or is_dashing or dash_cooldown_timer > 0.0:
		return false
	var direction := _get_input_direction()
	var target_direction := direction if direction != Vector2.ZERO else aim_direction
	if target_direction == Vector2.ZERO:
		target_direction = last_move_direction
	dash_direction = target_direction.normalized()
	is_dashing = true
	is_invincible = true
	dash_cooldown_timer = DASH_COOLDOWN
	if invincible_timer:
		invincible_timer.start(INVINCIBLE_DURATION)
	dash_started.emit()
	if _audio and DisplayServer.get_name() != "headless":
		_audio.play_dash_sfx()
	if _state_machine and _state_machine_initialized:
		_state_machine.transition_to("dashing")
	return true


func _transition_to_locomotion() -> void:
	if _state_machine == null or not _state_machine_initialized or current_hp <= 0:
		return
	if input_locked:
		_state_machine.transition_to("locked")
	elif _get_input_direction() != Vector2.ZERO:
		_state_machine.transition_to("moving")
	else:
		_state_machine.transition_to("idle")


func _set_presentation_state(state_id: String, context: Dictionary = {}) -> void:
	var changed := _presentation_state != state_id
	_presentation_state = state_id
	if changed or not context.is_empty():
		presentation_state_changed.emit(state_id, context.duplicate(true))


func get_presentation_state() -> String:
	return _presentation_state


func get_state_machine_state() -> String:
	return _state_machine.current_state_name if _state_machine != null else ""


func get_registered_player_states() -> Array:
	return _state_machine.get_state_names() if _state_machine != null else []


func get_state_machine_snapshot() -> Dictionary:
	if _state_machine == null:
		return {}
	var snapshot := _state_machine.get_snapshot()
	snapshot["overlays"] = {
		"low_health": _low_health_active,
		"silenced": _is_silenced,
		"invincible": is_invincible,
	}
	return snapshot


func _update_low_health_state() -> void:
	var ratio := float(current_hp) / maxf(1.0, float(max_hp))
	var active := current_hp > 0 and ratio <= 0.30
	if active != _low_health_active:
		_low_health_active = active
		low_health_changed.emit(active, ratio)


func is_low_health() -> bool:
	return _low_health_active

func set_input_locked(locked: bool) -> void:
	if input_locked == locked:
		return
	input_locked = locked
	if locked:
		is_dashing = false
		velocity = Vector2.ZERO
		if current_hp > 0 and _state_machine and _state_machine_initialized:
			_state_machine.transition_to("locked")
	elif current_hp > 0:
		_transition_to_locomotion()
	input_lock_changed.emit(locked)


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
	status_effect_changed.emit("silenced", true, duration)
	print("[Player] 被沉默 %.1f 秒" % duration)

func _handle_silence(delta: float) -> void:
	if not _is_silenced:
		return
	_silence_timer -= delta
	if _silence_timer <= 0.0:
		_is_silenced = false
		_silence_timer = 0.0
		status_effect_changed.emit("silenced", false, 0.0)
		print("[Player] 沉默解除")

func take_damage(amount: int, hit_dir: Vector2 = Vector2.ZERO) -> void:
	if is_invincible or current_hp <= 0:
		return
	# 获取武器树超频惩罚（每次射击叠加效果，超频命卡写入 overheat_penalty>1）
	var overheat_mult: float = 1.0
	if weapon_tree != null and weapon_tree.has_method("get_overheat_penalty"):
		overheat_mult = weapon_tree.call("get_overheat_penalty")
	var final_damage: int = maxi(1, int(float(amount - armor) * overheat_mult))
	_last_damage_amount = final_damage
	current_hp = max(0, current_hp - final_damage)
	hp_changed.emit(current_hp, max_hp)
	damage_taken.emit(final_damage, current_hp, max_hp)
	_update_low_health_state()
	if hit_dir.length_squared() > 0.0001:
		velocity += hit_dir.normalized() * 90.0
	_flash_damage()
	_play_damage_sfx()
	is_invincible = true
	if invincible_timer:
		invincible_timer.start(INVINCIBLE_DURATION)
	if current_hp <= 0:
		if _state_machine and _state_machine_initialized:
			_state_machine.transition_to("dead", true)
		Global.trigger_game_over()
	elif _state_machine and _state_machine_initialized:
		_state_machine.transition_to("hurt", true)

func heal(amount: int) -> void:
	if current_hp <= 0:
		return
	current_hp = min(max_hp, current_hp + amount)
	hp_changed.emit(current_hp, max_hp)
	_update_low_health_state()
	if body_visuals and body_visuals.has_method("flash_heal"):
		body_visuals.call("flash_heal")
	var renderer := get_node_or_null("Components/Body/AvatarRenderer") as Node
	if renderer != null and renderer.has_method("flash_heal"):
		renderer.call("flash_heal")


func _flash_damage() -> void:
	if body_visuals and body_visuals.has_method("flash_damage"):
		body_visuals.call("flash_damage")
	var renderer := get_node_or_null("Components/Body/AvatarRenderer") as Node
	if renderer != null and renderer.has_method("flash_damage"):
		renderer.call("flash_damage")
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
	if _audio and DisplayServer.get_name() != "headless":
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

func get_visual_facing_sign() -> float:
	return visual_facing_sign

func set_aim_direction(dir: Vector2) -> void:
	if dir.length_squared() > 0.0001:
		aim_direction = dir.normalized()
		# 身体与握持手只做离散左右换边；接近正上/正下时保留上一次朝向，
		# 避免鼠标跨过垂直中线时手和枪械挂点反复抖动。
		if absf(aim_direction.x) > VISUAL_FACING_DEADZONE:
			visual_facing_sign = -1.0 if aim_direction.x < 0.0 else 1.0
		if weapon_anchor != null:
			weapon_anchor.position = Vector2(WEAPON_SOCKET_X * visual_facing_sign, 0.0)
		# 可见手不连续旋转；枪械视觉仍读取完整 aim_direction 独立瞄准。
		if components != null:
			components.set_aim_direction(aim_direction)

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


func get_weapon_presentation_snapshot() -> Dictionary:
	var instance := get_equipped_weapon_instance()
	return instance.get_presentation_snapshot(weapon_tree, "已装备") if instance != null else {}


func equip_weapon_item(item: Dictionary) -> Dictionary:
	if str(item.get("type", "")) != "weapon":
		return {"success": false, "message": "目标不是枪械"}
	_ensure_weapon_tree()
	var candidate := WeaponInstance.from_item(item)
	if candidate == null:
		return {"success": false, "message": "枪械实例数据无效"}
	if equipped_weapon_instance != null and (
		candidate.weapon_instance_id == equipped_weapon_instance.weapon_instance_id
	):
		return {"success": false, "message": "当前已经装备该枪械实例"}
	_sync_equipped_weapon_instance()
	var old_item: Dictionary = {}
	if equipped_weapon_instance != null:
		old_item = equipped_weapon_instance.to_item_dictionary()
	_loading_weapon_instance = true
	var loaded := candidate.load_into_runtime_tree(weapon_tree)
	_loading_weapon_instance = false
	if not loaded:
		return {"success": false, "message": "枪械构筑快照无法恢复"}
	equipped_weapon_instance = candidate
	_sync_equipped_weapon_instance()
	var snapshot := get_weapon_presentation_snapshot()
	weapon_instance_changed.emit(snapshot)
	return {
		"success": true,
		"message": "已装备 %s #%s" % [
			snapshot.get("display_name", "武器"), snapshot.get("instance_suffix", "")
		],
		"old_item": old_item,
		"new_item": equipped_weapon_instance.to_item_dictionary(),
		"snapshot": snapshot,
	}


func append_equipped_fate_upgrade(card: FateCard, transaction_id: String = "") -> Dictionary:
	var instance := get_equipped_weapon_instance()
	if instance == null:
		return {"success": false, "reason": "当前没有装备枪械"}
	var result := instance.append_fate_upgrade(card, transaction_id)
	if bool(result.get("success", false)):
		instance.capture_runtime_tree(weapon_tree)
		weapon_instance_changed.emit(get_weapon_presentation_snapshot())
	return result


func _sync_equipped_weapon_instance() -> void:
	if _loading_weapon_instance or equipped_weapon_instance == null or weapon_tree == null:
		return
	equipped_weapon_instance.capture_runtime_tree(weapon_tree)


func _on_weapon_runtime_changed() -> void:
	_sync_equipped_weapon_instance()
	if equipped_weapon_instance != null:
		weapon_instance_changed.emit(equipped_weapon_instance.get_presentation_snapshot(
			weapon_tree, "已装备"
		))


func _on_weapon_ammo_changed(_current: int, _maximum: int) -> void:
	_sync_equipped_weapon_instance()


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

# ========== 玩家顶层状态机 ==========
## 6 个互斥状态（idle/moving/dashing/hurt/locked/dead）均为独立 State 子类。
##
## 沉默（silenced）和无敌（invincible）不是顶层状态：
## - 沉默：_is_silenced 叠加标志，与任何状态共存
## - 无敌：dashing 副作用 + take_damage 后短暂无敌，由 InvincibleTimer 唯一解除
##
## 对外行为兼容：
## - is_dashing / is_invincible / input_locked 字段保留并由各 State.enter/exit 同步
## - set_input_locked() / _start_dash() / take_damage() 外部调用不需改

## 状态机节点（_ready 末尾挂上）
var _state_machine: StateMachine = null

## 状态机启动标志（防止重复 init）
var _state_machine_initialized: bool = false

## 初始化状态机（_ready 末尾调一次）
func _init_state_machine() -> void:
	if _state_machine_initialized:
		return
	_state_machine = StateMachine.new()
	_state_machine.name = "StateMachine"
	_state_machine.owner_node = self
	add_child(_state_machine)
	# 顶层互斥状态；低血/沉默/无敌作为叠加状态。
	_state_machine.register("idle", PlayerIdleState.new())
	_state_machine.register("moving", PlayerMovingState.new())
	_state_machine.register("dashing", PlayerDashingState.new())
	_state_machine.register("hurt", PlayerHurtState.new())
	_state_machine.register("locked", PlayerLockedState.new())
	_state_machine.register("dead", PlayerDeadState.new())
	# 玩家使用显式白名单；dead 为终态，非法跳转会被拒绝而非悄悄改写状态。
	_state_machine.configure_transition_map({
		"idle": ["moving", "dashing", "hurt", "locked", "dead"],
		"moving": ["idle", "dashing", "hurt", "locked", "dead"],
		"dashing": ["idle", "moving", "hurt", "locked", "dead"],
		"hurt": ["idle", "moving", "locked", "dead"],
		"locked": ["idle", "moving", "hurt", "dead"],
		"dead": [],
	})
	# 启动到 idle
	_state_machine.start("idle")
	_state_machine_initialized = true


# ========== 组件系统接入 (2026-06-10) ==========
## 挂 CharacterComponents 节点 + 用现有场景里的 Body/WeaponAnchor 作为组件引用的目标
## 不创建新视觉节点，保留 PlayerVisuals.gd 的现有 flash_damage/flash_heal 实现
func _init_components() -> void:
	if components != null:
		return
	components = CharacterComponents.new()
	components.name = "Components"
	add_child(components)
	# 让组件自己创建临时占位资产（emoji 头部 / 方块身体 / 长方形武器挂在 emoji 手上）
	# 不传任何视觉路径 —— 组件 _ready 会自建。
	# 同时把场景里旧的 Body / WeaponAnchor / Shape / Emoji 隐藏掉（避免新旧重叠）
	components.create_default_layout(NodePath(""), NodePath(""), NodePath(""))
	_install_avatar_renderer()
	_hide_legacy_visuals()
	# Components 现在是 Node2D，body 是它的子 Node2D，相对 (0,0) 即 Player 中心
	# 旧的 legacy_body.position 也是 (0, 0)，不需要再设
	var has_body: bool = components.get("body") != null
	var has_head: bool = components.get("head") != null
	var has_hand: bool = components.get("hand") != null
	print("[Player] 组件系统已挂载: body=%s head=%s hand=%s" % [has_body, has_head, has_hand])


func _install_avatar_renderer() -> void:
	if components == null or components.body == null:
		return
	var renderer := components.body.get_node_or_null("AvatarRenderer") as Node
	if renderer == null:
		renderer = PLAYER_AVATAR_RENDERER_SCRIPT.new() as Node
		renderer.name = "AvatarRenderer"
		components.body.add_child(renderer)
	# Keep component transforms for aiming/bob feedback, but hide their temporary
	# emoji/rectangle assets behind the semantic, replaceable renderer.
	for path in ["BodyShape", "Head/Emoji", "HandL/Emoji", "HandL/WeaponAnchor/WeaponDisplay", "HandR/Emoji", "HandR/WeaponAnchor/WeaponDisplay"]:
		var placeholder := components.body.get_node_or_null(path)
		if placeholder is CanvasItem:
			(placeholder as CanvasItem).visible = false
	if weapon_anchor != null:
		weapon_anchor.z_index = 6

## 隐藏场景里旧的视觉节点（Shape / Emoji / WeaponAnchor / WeaponDisplay / MuzzleFlash 等）
## 组件系统会自己生成新的；旧的留着不删，方便回退
func _hide_legacy_visuals() -> void:
	# 只隐藏 Body（因为我们用 Components/Body 替代它）
	# 注意：不能隐藏 WeaponAnchor 及其子节点 —— 组件系统的 WeaponAnchor 是新建的，
	#       Player 根下的这个是 WeaponDisplay + 武器的渲染位置，必须保持可见
	var n: Node = get_node_or_null("Body")
	if n is CanvasItem:
		(n as CanvasItem).visible = false
