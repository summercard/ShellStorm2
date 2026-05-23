extends CharacterBody2D

signal hp_changed(current: int, maximum: int)
signal enemy_died()  # 敌人死亡信号
signal enemy_hit(hit_from: Vector2, damage: int, is_crit: bool)  # 被击中时发射（用于震屏/击中特效）

@export var max_hp: int = 30
@export var speed: float = 80.0
@export var damage: int = 10

var current_hp: int = 30
var player_ref: Node2D = null

## AI 行为控制
var ai_type: String = "chase"       # chase / ranged / summoner / bomber / trapper
var use_default_chase: bool = true  # 是否使用默认追击行为

## 特殊 AI 参数
var shoot_interval: float = 2.0     # 远程射击间隔（秒）
var summon_interval: float = 5.0     # 召唤间隔（秒）
var explosion_radius: float = 80.0   # 爆炸半径
var explosion_damage: int = 25       # 爆炸伤害
var trigger_radius: float = 100.0    # 触发半径（潜伏型）

## 内部计时器
var _shoot_timer: float = 0.0
var _summon_timer: float = 0.0
var _triggered: bool = false         # 潜伏型是否已触发
var _exploded: bool = false          # 自爆型是否已爆炸

## 词缀引用
var _modifiers: Array = []

## 存储怪物数据（由 RoomWaveSpawner 设置，用于死亡时回调）
var _enemy_data: Dictionary = {}

## 碰撞层
const LAYER_PLAYER: int = 2
const LAYER_ENEMY: int = 4

@onready var shape: ColorRect = $Shape
@onready var hp_bar: ProgressBar = $HPBar

## 设置怪物数据（由 RoomWaveSpawner 在生成时调用）
func set_enemy_data(data: Dictionary) -> void:
	_enemy_data = data

## 获取怪物数据
func get_enemy_data() -> Dictionary:
	return _enemy_data

func _ready() -> void:
	current_hp = max_hp
	_add_to_group()
	_fire_timers()

func _fire_timers() -> void:
	_shoot_timer = shoot_interval
	_summon_timer = summon_interval

func _physics_process(delta: float) -> void:
	if not player_ref or not is_instance_valid(player_ref):
		player_ref = get_tree().get_first_node_in_group("player")
		return

	match ai_type:
		"chase":
			_behavior_chase(delta)
		"ranged":
			_behavior_ranged(delta)
		"summoner":
			_behavior_summoner(delta)
		"bomber":
			_behavior_bomber(delta)
		"trapper":
			_behavior_trapper(delta)
		_:
			_behavior_chase(delta)

	_move_and_slide()

## ========== 行为：追击型 ==========
func _behavior_chase(delta: float) -> void:
	var direction = (player_ref.global_position - global_position).normalized()
	velocity = direction * speed

## ========== 行为：远程弹幕型 ==========
func _behavior_ranged(delta: float) -> void:
	var to_player := player_ref.global_position - global_position
	var dist := to_player.length()
	var dir := to_player.normalized()

	# 保持距离
	var preferred_dist := 250.0
	if dist < preferred_dist:
		velocity = -dir * speed
	else:
		velocity = Vector2.ZERO

	# 周期性射击
	_shoot_timer -= delta
	if _shoot_timer <= 0:
		_shoot_timer = shoot_interval
		_ranged_shoot(dir)

## ========== 行为：召唤型 ==========
func _behavior_summoner(delta: float) -> void:
	# 缓慢靠近
	var direction = (player_ref.global_position - global_position).normalized()
	velocity = direction * speed

	# 周期性召唤小怪
	_summon_timer -= delta
	if _summon_timer <= 0:
		_summon_timer = summon_interval
		_spawn_minion()

## ========== 行为：自爆型 ==========
func _behavior_bomber(delta: float) -> void:
	if _exploded:
		return

	var to_player := player_ref.global_position - global_position
	var dist := to_player.length()
	var dir := to_player.normalized()

	# 追击玩家
	velocity = dir * speed

	# 接触即爆炸
	if dist < 20.0:
		_trigger_explosion()
		_exploded = true

## ========== 行为：潜伏型 ==========
func _behavior_trapper(delta: float) -> void:
	if _triggered:
		# 触发后快速冲刺
		var direction = (player_ref.global_position - global_position).normalized()
		velocity = direction * speed * 3.0
		return

	var to_player := player_ref.global_position - global_position
	var dist := to_player.length()

	if dist < trigger_radius:
		_triggered = true
		# 触发时冲向玩家并攻击
		velocity = to_player.normalized() * speed * 3.0
	else:
		velocity = Vector2.ZERO

func _move_and_slide() -> void:
	move_and_slide()

## ========== 射击（远程型）==========
func _ranged_shoot(dir: Vector2) -> void:
	var bullet_scene: PackedScene = preload("res://scenes/Bullet.tscn")
	if bullet_scene:
		var bullet = bullet_scene.instantiate()
		var spawn_pos := global_position + dir * 20.0
		bullet.fire(spawn_pos, dir, 300.0, damage)
		get_tree().root.add_child(bullet)

## ========== 召唤小怪 ==========
func _spawn_minion() -> void:
	var minion_scene: PackedScene = preload("res://scenes/Enemy.tscn")
	if minion_scene:
		var minion = minion_scene.instantiate()
		var offset := Vector2(randf_range(-30, 30), randf_range(-30, 30))
		minion.position = global_position + offset
		get_tree().root.add_child(minion)

## ========== 爆炸（自爆型）==========
func _trigger_explosion() -> void:
	# 对玩家造成伤害
	if player_ref and is_instance_valid(player_ref):
		var to_player := player_ref.global_position - global_position
		if to_player.length() < explosion_radius:
			if player_ref.has_method("take_damage"):
				player_ref.take_damage(explosion_damage)

	die()

## ========== 受伤 ==========
func take_damage(amount: int, is_crit: bool = false) -> void:
	current_hp -= amount
	_update_hp_bar()
	flash_damage()
	enemy_hit.emit(global_position, amount, is_crit)  # 触发震屏（带伤害值和暴击标记）
	
	# 弹出伤害数字（暴击时更大更亮）
	_spawn_damage_number(global_position, amount, is_crit)

	if current_hp <= 0:
		die()

## ========== 死亡 ==========
func die() -> void:
	enemy_died.emit()
	# 死亡闪光特效：先闪白，再缩小淡出
	_spawn_death_flash()
	# 屏幕震动（精英/Boss击杀时更强）
	emit_death_screen_effect()
	# 死亡消散动画：缩小+淡出
	if shape:
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(shape, "scale", Vector2(0.1, 0.1), 0.25).set_trans(Tween.TRANS_QUAD)
		tween.tween_property(shape, "mod:a", 0.0, 0.25).set_trans(Tween.TRANS_QUAD)
		tween.chain().tween_callback(queue_free)
	else:
		queue_free()

## 死亡闪光：生成一个短暂的白光覆盖层，模拟爆炸光效
func _spawn_death_flash() -> void:
	if not shape:
		return
	# 创建一个闪光节点（白色方块，放大后消失）
	var flash := ColorRect.new()
	flash.name = "DeathFlash"
	var parent_node := get_parent()
	if parent_node:
		parent_node.add_child(flash)
	else:
		get_tree().root.add_child(flash)
	
	flash.global_position = global_position
	flash.z_index = global_position.y + 100  # 在敌人上方
	flash.color = Color(1.0, 1.0, 0.8, 0.9)
	
	# 闪光从大变小，透明度快速淡出
	var flash_tween := flash.create_tween()
	flash_tween.set_parallel(true)
	flash_tween.tween_property(flash, "scale", Vector2(2.5, 2.5), 0.12).set_trans(Tween.TRANS_QUAD)
	flash_tween.tween_property(flash, "mod:a", 0.0, 0.15).set_trans(Tween.TRANS_LINEAR)
	flash_tween.chain().tween_callback(flash.queue_free)

## 死亡屏幕效果：触发震屏和音效
func emit_death_screen_effect() -> void:
	# 查找 ScreenShake
	var shake := get_tree().root.find_child("ScreenShake", false, false) as Node
	if shake and shake.has_method("trigger"):
		# 根据敌人 HP 决定震动强度（精英怪更强）
		var intensity := 5.0
		if max_hp >= 40:
			intensity = 12.0
		elif max_hp >= 20:
			intensity = 8.0
		shake.trigger(intensity, 0.15)
	
	# 播放死亡音效
	var audio := get_node_or_null("/root/AudioManager") as Node
	if audio and audio.has_method("play_enemy_die_sfx"):
		audio.play_enemy_die_sfx()

func _update_hp_bar() -> void:
	if hp_bar:
		hp_bar.max_value = max_hp
		# HP 条平滑过渡动画（受伤时不会瞬间跳变）
		var tween := hp_bar.create_tween()
		tween.tween_property(hp_bar, "value", float(current_hp), 0.12).set_trans(Tween.TRANS_LINEAR)
		# 受伤时 HP 条红色闪烁提示
		_hp_bar_flash()

## HP条被击中时的红色闪烁
func _hp_bar_flash() -> void:
	if not hp_bar:
		return
	var orig_mod := hp_bar.modulate
	hp_bar.modulate = Color(2.0, 0.5, 0.5, 1.0)
	await get_tree().create_timer(0.08).timeout
	if hp_bar:
		hp_bar.modulate = orig_mod

func flash_damage() -> void:
	if shape:
		var original = shape.color
		shape.color = Color.WHITE
		await get_tree().create_timer(0.05).timeout
		if shape:
			shape.color = original

func _add_to_group() -> void:
	add_to_group("enemy")

## ========== 词缀接入 ==========
func add_modifier(modifier_id: String, tier: int = 1) -> void:
	var mod = EnemyModifier.Factory.create(modifier_id, tier)
	if mod:
		_modifiers.append(mod)
		mod.apply(self)

## ========== 伤害数字（内部工具）==========
func _spawn_damage_number(world_pos: Vector2, damage: int, is_crit: bool = false) -> void:
	var scene_path := "res://scenes/DamageNumber.tscn"
	var num_scene: PackedScene = load(scene_path)
	if num_scene:
		var label := num_scene.instantiate()
		if label is Label:
			label.text = str(damage)
			if is_crit:
				label.text = str(damage) + "!"
			label.position = world_pos + Vector2(randf_range(-8, 8), -20)
			label.z_index = 200
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			if is_crit:
				label.add_theme_font_size_override("font_size", 28)
				label.mod = Color(1.0, 0.9, 0.2, 1.0)
			get_tree().root.add_child(label)
			var tween := label.create_tween()
			tween.set_parallel(true)
			tween.tween_property(label, "position:y", world_pos.y - 50.0, 0.7).set_trans(Tween.TRANS_LINEAR)
			tween.tween_property(label, "mod:a", 0.0, 0.7).set_trans(Tween.TRANS_LINEAR)
			tween.chain().tween_callback(label.queue_free)