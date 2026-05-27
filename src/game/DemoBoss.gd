class_name DemoBoss
extends CharacterBody2D
## Demo Boss — 纯演示用 Boss 实体
## 功能：HP 管理、受伤扣血 + 伤害飘字 + 震屏反馈、Boss HP 同步 GameUIManager
## 供 DemoRoomChain 的 Boss 房使用（独立于完整 Boss 系统）

signal boss_damaged(boss_id: String, damage: float, new_hp: float, max_hp: float)
signal boss_defeated()

## Boss 配置
@export var boss_id: String = "demo_boss_01"
@export var max_hp: float = 500.0
@export var current_hp: float = 500.0
@export var damage_cooldown: float = 0.3   # 受伤硬直（防止一秒内扣太多血）

## 视觉
@onready var shape: ColorRect = $Shape as ColorRect
@onready var hp_bar_bg: PanelContainer = $HPBarBG as PanelContainer
@onready var hp_bar: ProgressBar = $HPBarBG/HPBar as ProgressBar
@onready var boss_name_label: Label = $BossNameLabel as Label

var _current_hp: float = 500.0
var _damage_cooldown_timer: float = 0.0
var _is_dead: bool = false
var _invulnerable: bool = false
var _activated: bool = false

func _ready() -> void:
	# 设为敌人碰撞层（与普通 Enemy 同层，方便子弹检测）
	collision_layer = 4
	collision_mask = 0  # 不检测其他碰撞体
	
	# DemoBoss 也加入 enemy 组，让 Bullet._find_nearest_enemy() 能找到
	add_to_group("enemy")
	
	# 初始化 HP
	_current_hp = max_hp
	current_hp = max_hp
	_setup_hp_bar()
	
	z_index = 100
	print("[DemoBoss] Ready - HP: %d/%d" % [_current_hp, max_hp])


func activate() -> void:
	if _activated:
		return
	_activated = true
	_connect_to_game_ui()


func _setup_hp_bar() -> void:
	if hp_bar:
		hp_bar.max_value = max_hp
		hp_bar.value = _current_hp
		hp_bar.show_percentage = false
	if boss_name_label:
		boss_name_label.text = boss_id

func _connect_to_game_ui() -> void:
	# 延迟获取 GameUIManager（等场景完全加载）
	await get_tree().create_timer(0.1).timeout
	var gui: Node = get_tree().root.find_child("GameUIManager", true, false)
	if gui != null and gui.has_method("on_boss_spawned"):
		gui.call("on_boss_spawned", {
			"boss_id": boss_id,
			"max_hp": max_hp,
			"current_hp": _current_hp,
		})
		print("[DemoBoss] Notified GameUIManager of spawn")

func _process(delta: float) -> void:
	if _is_dead:
		return
	if _damage_cooldown_timer > 0:
		_damage_cooldown_timer -= delta

func take_damage(damage: float, is_crit: bool = false) -> void:
	if _is_dead or _invulnerable:
		return
	if _damage_cooldown_timer > 0:
		return  # 受伤硬直中
	
	_current_hp -= damage
	_damage_cooldown_timer = damage_cooldown
	current_hp = _current_hp
	
	# 更新视觉 HP 条
	if hp_bar:
		hp_bar.value = max(0, _current_hp)
	
	# 受伤闪白效果
	_take_damage_feedback(is_crit)
	
	# 伤害飘字
	var world_pos: Vector2 = global_position
	DamageNumbers.spawn(world_pos, int(damage), is_crit)
	
	# 震屏（受伤反馈）
	_trigger_hit_screen_shake(damage, is_crit)
	
	# 通知 GameUIManager（Boss HP UI 同步）
	_notify_boss_damaged(damage)
	
	# 死亡检查
	if _current_hp <= 0:
		_trigger_death()
	
	print("[DemoBoss] took %.0f damage, HP now: %.0f/%d" % [damage, _current_hp, max_hp])

func _take_damage_feedback(is_crit: bool) -> void:
	if shape == null:
		return
	# 快速闪白 → 恢复正常色
	var original_color := shape.color
	shape.color = Color(1.0, 1.0, 1.0, 0.9)
	var tween := create_tween()
	tween.tween_property(shape, "color", original_color, 0.15)
	
	# 暴击时额外放大弹回
	if is_crit:
		shape.scale = Vector2(1.3, 1.3)
		tween.set_parallel(true)
		tween.tween_property(shape, "scale", Vector2(1.0, 1.0), 0.2).set_trans(Tween.TRANS_BOUNCE)

func _trigger_hit_screen_shake(damage: float, is_crit: bool) -> void:
	var shake: Node = get_tree().root.find_child("ScreenShake", true, false)
	if shake != null and shake.has_method("trigger"):
		var intensity := 6.0
		if damage >= 30:
			intensity = 12.0
		elif damage >= 15:
			intensity = 8.0
		if is_crit:
			intensity *= 1.6
		var duration := 0.15 if not is_crit else 0.22
		shake.call("trigger", intensity, duration)

func _notify_boss_damaged(damage: float) -> void:
	var gui: Node = get_tree().root.find_child("GameUIManager", true, false)
	if gui != null and gui.has_method("on_boss_damaged"):
		gui.call("on_boss_damaged", boss_id, damage, _current_hp, max_hp)

## Boss 死亡粒子爆炸效果（放射状扩散消散）
func _spawn_death_particles() -> void:
	if shape == null:
		return
	var boss_pos: Vector2 = shape.global_position
	var particle_count: int = 16
	var particle_parent: Node = shape.get_parent()
	var particles: Array[Node] = []
	for i in range(particle_count):
		var angle: float = TAU * i / particle_count
		var particle := ColorRect.new()
		particle.name = "DeathParticle_%d" % i
		particle.custom_minimum_size = Vector2(12, 12)
		particle.size = Vector2(12, 12)
		particle.color = Color(0.9, 0.15, 0.15, 0.9)
		particle.z_index = 150
		var start_pos: Vector2 = boss_pos + Vector2(cos(angle) * 20.0, sin(angle) * 20.0)
		particle.global_position = start_pos
		particle_parent.add_child(particle)
		particles.append(particle)
		
		var tween := create_tween()
		tween.set_parallel(true)
		var end_pos: Vector2 = boss_pos + Vector2(cos(angle) * 100.0, sin(angle) * 100.0)
		tween.tween_property(particle, "global_position", end_pos, 0.35)
		tween.tween_property(particle, "modulate:a", 0.0, 0.35)
		tween.tween_property(particle, "size", Vector2(4, 4), 0.35)
	
	# 动画结束后批量清理残留粒子
	var cleanup := func() -> void:
		for p in particles:
			if is_instance_valid(p):
				p.queue_free()
	get_tree().create_timer(0.4).timeout.connect(cleanup)

func _trigger_death() -> void:
	if _is_dead:
		return
	_is_dead = true
	collision_layer = 0  # 关闭碰撞
	
	print("[DemoBoss] DEFEATED!")
	
	# 震屏 + 全屏白闪（死亡特效）
	var shake: Node = get_tree().root.find_child("ScreenShake", true, false)
	if shake != null:
		if shake.has_method("screen_shake_death"):
			shake.call("screen_shake_death")
		elif shake.has_method("trigger"):
			shake.call("trigger", 22.0, 0.5)
		if shake.has_method("screen_flash"):
			shake.call("screen_flash", Color(1.0, 1.0, 1.0, 0.8), 0.2)
	
	# 死亡视觉效果：Boss收缩 + 屏幕中心粒子爆炸（模拟）
	_spawn_death_particles()
	
	if shape:
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(shape, "modulate:a", 0.0, 0.5)
		tween.tween_property(shape, "scale", Vector2(1.5, 1.5), 0.5)
		await tween.finished
	
	# 通知 BossRoomLogic（Boss 已击败，触发撤离）
	var boss_logic: Node = get_parent().get_node_or_null("BossRoomLogic") as Node
	if boss_logic != null and boss_logic.has_method("trigger_boss_defeated"):
		boss_logic.call("trigger_boss_defeated")
	
	# 通知 GameUIManager
	var gui: Node = get_tree().root.find_child("GameUIManager", true, false)
	if gui != null and gui.has_method("on_boss_defeated"):
		gui.call("on_boss_defeated", boss_id, {})

# 供外部调用的受伤接口（子弹 / 武器系统）
func apply_damage(damage: float, is_crit: bool = false) -> void:
	take_damage(damage, is_crit)

# 获取当前 HP（供外部查询）
func get_hp() -> float:
	return _current_hp

func get_max_hp() -> float:
	return max_hp
