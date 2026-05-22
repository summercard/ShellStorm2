extends CharacterBody2D

signal hp_changed(current: int, maximum: int)
signal enemy_died()  # 敌人死亡信号
signal enemy_hit(hit_from: Vector2)  # 被击中时发射（用于震屏/击中特效）

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

## 碰撞层
const LAYER_PLAYER: int = 2
const LAYER_ENEMY: int = 4

@onready var shape: ColorRect = $Shape
@onready var hp_bar: ProgressBar = $HPBar

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
func take_damage(amount: int) -> void:
	current_hp -= amount
	_update_hp_bar()
	flash_damage()
	enemy_hit.emit(global_position)  # 触发震屏
	
	# 弹出伤害数字
	_spawn_damage_number(global_position, amount)

	if current_hp <= 0:
		die()

## ========== 死亡 ==========
func die() -> void:
	enemy_died.emit()
	queue_free()

func _update_hp_bar() -> void:
	if hp_bar:
		hp_bar.max_value = max_hp
		hp_bar.value = current_hp

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
func _spawn_damage_number(world_pos: Vector2, damage: int) -> void:
	var scene_path := "res://scenes/DamageNumber.tscn"
	var num_scene: PackedScene = load(scene_path)
	if num_scene:
		var label := num_scene.instantiate()
		if label is Label:
			label.text = str(damage)
			label.position = world_pos + Vector2(randf_range(-8, 8), -20)
			label.z_index = 200
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			get_tree().root.add_child(label)
			var tween := label.create_tween()
			tween.set_parallel(true)
			tween.tween_property(label, "position:y", world_pos.y - 50.0, 0.7).set_trans(Tween.TRANS_LINEAR)
			tween.tween_property(label, "mod:a", 0.0, 0.7).set_trans(Tween.TRANS_LINEAR)
			tween.chain().tween_callback(label.queue_free)