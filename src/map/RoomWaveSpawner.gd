class_name RoomWaveSpawner
extends Node
## 波次生成器 — 挂载在房间节点上，管理波次怪物生成
## 由 RoomGameMode 在进入房间时调用 configure() + start()

signal wave_started(wave: int, total: int)
signal wave_enemies_spawned(wave: int, spawned: int)
signal enemy_spawned(count: int)
signal wave_progress_updated(killed: int, total: int, wave: int)
signal all_waves_cleared()
signal wave_cleared(wave: int)

## 可配置属性
@export var spawn_radius: float = 400.0   # 敌人出生范围（相对玩家中心）
@export var inter_wave_delay: float = 1.5 # 波次之间等待时间
@export var max_enemies_per_wave: int = 8  # 每波最大敌人数
@export var min_spawn_distance: float = 60.0  # 同波次敌人生成最小间隔
@export var room_size: Vector2 = Vector2(800, 600)  # 房间尺寸（用于限制出生点在房间内）

## 内部状态
var _room: Node2D = null
var _player: Node2D = null
var _room_game_mode: Node = null  ## RoomGameMode 引用（用于通知击杀）
var _enemy_count_per_wave: Array[int] = []  # 每波敌人数
var _floor: int = 1
var _floor_level: int = RoomData.FloorLevel.MEDIUM
var _current_wave: int = 0
var _total_waves: int = 0
var _alive_count: int = 0
var _total_enemy_count: int = 0
var _killed_count: int = 0
var _wave_timer: float = 0.0
var _waiting_next_wave: bool = false
var _active: bool = false
var _all_spawned: bool = false
var _enemy_pool: Array[Dictionary] = []
var _monster_injector: MonsterInjector
var _rng: RandomNumberGenerator

func _init() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = Time.get_ticks_msec()
	_monster_injector = MonsterInjector.new()

## 配置波次（外部调用）
## wave_counts: Array[int] — 每波敌人数，如 [3, 4, 5]
## room_game_mode: RoomGameMode 引用，用于通知击杀（货币+飘字）
## room_size_override: Vector2 — 可选，指定房间尺寸用于限制出生点
func configure(wave_counts: Array[int], room: Node2D, player: Node2D, floor: int, floor_level: int, room_game_mode: Node = null, room_size_override: Vector2 = Vector2.ZERO) -> void:
	_enemy_count_per_wave = wave_counts
	_room = room
	_player = player
	_floor = floor
	_floor_level = floor_level
	_room_game_mode = room_game_mode
	_current_wave = 0
	_total_waves = wave_counts.size()
	_alive_count = 0
	_total_enemy_count = 0
	for count in wave_counts:
		_total_enemy_count += count
	_killed_count = 0
	_waiting_next_wave = false
	_all_spawned = false
	_enemy_pool.clear()
	if room_size_override != Vector2.ZERO:
		room_size = room_size_override

func set_enemy_pool(enemy_pool: Array[Dictionary]) -> void:
	_enemy_pool.clear()
	for enemy_data in enemy_pool:
		if enemy_data is Dictionary:
			_enemy_pool.append(enemy_data.duplicate(true))

## 开始波次生成
func start() -> void:
	if _enemy_count_per_wave.is_empty():
		all_waves_cleared.emit()
		return
	_active = true
	_spawn_next_wave()

## 停止（切换房间时调用）
func stop() -> void:
	_active = false

## 每帧更新
func tick(delta: float) -> void:
	if not _active:
		return
	if _waiting_next_wave:
		_wave_timer -= delta
		if _wave_timer <= 0:
			_waiting_next_wave = false
			_spawn_next_wave()

## 获取当前波次信息
func get_wave_info() -> Dictionary:
	return {
		"current": _current_wave + 1,
		"waves": _total_waves,
		"total": _total_enemy_count,
		"alive": _alive_count,
		"killed": _killed_count,
	}

## 是否所有波次已完成
func is_complete() -> bool:
	return _all_spawned and _alive_count <= 0

## 外部通知敌人死亡（RoomGameMode 调用）
func on_enemy_killed() -> void:
	_alive_count = max(0, _alive_count - 1)
	_killed_count = min(_total_enemy_count, _killed_count + 1)
	if _alive_count <= 0:
		wave_cleared.emit(_current_wave)
		if _current_wave >= _total_waves - 1:
			_all_spawned = true
			_active = false
			all_waves_cleared.emit()
		else:
			_current_wave += 1
			if _current_wave < _total_waves:
				_waiting_next_wave = true
				_wave_timer = inter_wave_delay
			else:
				_all_spawned = true
				_active = false
				all_waves_cleared.emit()

## ========== 内部方法 ==========

func _spawn_next_wave() -> void:
	if _current_wave >= _total_waves:
		_all_spawned = true
		_active = false
		all_waves_cleared.emit()
		return

	var count: int = _enemy_count_per_wave[_current_wave]
	wave_started.emit(_current_wave + 1, _total_waves)
	_alive_count = count
	_all_spawned = _current_wave >= _total_waves - 1

	# 计算出生点中心
	var center: Vector2 = Vector2.ZERO
	if is_instance_valid(_player):
		center = _player.global_position

	# 预先生成所有不重叠的出生位置
	var spawn_positions: Array[Vector2] = []
	for i in range(count):
		var attempts: int = 0
		var spawn_pos: Vector2
		var found_valid: bool = false
		while attempts < 20 and not found_valid:
			spawn_pos = _get_spawn_position(center)
			found_valid = true
			# 检查是否与已生成位置重叠
			for prev in spawn_positions:
				if spawn_pos.distance_to(prev) < min_spawn_distance:
					found_valid = false
					break
			attempts += 1
		spawn_positions.append(spawn_pos)

		var enemy_data: Dictionary = _generate_enemy_data()
		_spawn_enemy_instance(enemy_data, spawn_pos)
		enemy_spawned.emit(1)
		# 每只间隔一点
		if i < count - 1:
			await get_tree().create_timer(0.15).timeout

	_all_spawned = _current_wave >= _total_waves - 1
	wave_enemies_spawned.emit(_current_wave + 1, count)

func _get_spawn_position(center: Vector2) -> Vector2:
	# 计算房间边界（以 center 为中心的矩形区域）
	var half_room: Vector2 = (room_size * 0.5) - Vector2(50, 50)  # 留50px边距
	var half_spawn: Vector2 = Vector2(spawn_radius, spawn_radius)
	var max_offset: Vector2 = half_room.abs().min(half_spawn)

	# 在圆盘内均匀采样
	var angle := _rng.randf() * TAU
	var radius := spawn_radius * sqrt(_rng.randf())  # sqrt → 均匀圆分布
	var offset := Vector2(cos(angle), sin(angle)) * radius

	# 限制在房间边界内
	var raw_pos: Vector2 = center + offset
	var clamped := Vector2(
		clamp(raw_pos.x, center.x - max_offset.x, center.x + max_offset.x),
		clamp(raw_pos.y, center.y - max_offset.y, center.y + max_offset.y)
	)
	return clamped

func _generate_enemy_data() -> Dictionary:
	if not _enemy_pool.is_empty():
		var planned: Dictionary = _enemy_pool.pop_front()
		if not planned.has("currency_value"):
			planned["currency_value"] = 10
		return planned

	var config := {"type": "random", "floor": _floor, "floor_level": _floor_level}
	var result: Array = _monster_injector.generate_enemies(config)
	var base: Dictionary = result[0] if not result.is_empty() else {"enemy_type": "melee_chaser", "hp": 25, "damage": 5, "speed": 80.0}
	# 确保包含货币价值字段
	if not base.has("currency_value"):
		base["currency_value"] = 10  # 默认普通怪 +10魂
	return base

func _spawn_enemy_instance(data: Dictionary, spawn_pos: Vector2) -> void:
	var scene_path := "res://scenes/Enemy.tscn"
	var enemy_scene: PackedScene = load(scene_path)
	if enemy_scene == null:
		push_warning("[RoomWaveSpawner] Enemy scene not found")
		return

	var enemy: CharacterBody2D = enemy_scene.instantiate() as CharacterBody2D

	# 应用属性（必须在 add_child 前设置 max_hp；Enemy._ready 会按 max_hp 初始化 current_hp）
	if data.get("hp"):
		enemy.max_hp = data["hp"]
		enemy.current_hp = data["hp"]
	if data.get("damage"):
		enemy.damage = data["damage"]
	if data.get("speed"):
		enemy.speed = data["speed"]
	if data.get("ai_type"):
		enemy.ai_type = data["ai_type"]
	else:
		_apply_ai_type_from_enemy_kind(enemy, data.get("enemy_type", ""))
	if data.get("is_elite"):
		enemy.add_modifier("巨大化", 1)
	if data.get("modifier"):
		enemy.add_modifier(data["modifier"], 1)

	# 将 enemy_data 存储在 enemy 节点上，供死亡时回调使用
	if enemy.has_method("set_enemy_data"):
		enemy.set_enemy_data(data)

	# 连接死亡信号
	if enemy.has_signal("enemy_died"):
		enemy.enemy_died.connect(_on_enemy_died)

	# 先挂到树上，再设置 global_position；否则有父节点偏移时会生成到错误位置。
	if is_instance_valid(_room):
		_room.add_child(enemy)
	else:
		get_tree().root.add_child(enemy)
	enemy.global_position = spawn_pos

	# 发出进度更新（已被击杀数 / 当前波总数）
	var killed = _enemy_count_per_wave[_current_wave] - _alive_count
	wave_progress_updated.emit(killed, _enemy_count_per_wave[_current_wave], _current_wave + 1)

func _apply_ai_type_from_enemy_kind(enemy: CharacterBody2D, enemy_type: String) -> void:
	match enemy_type:
		"ranged_caster":
			enemy.ai_type = "ranged"
		"summoner":
			enemy.ai_type = "summoner"
		"exploder":
			enemy.ai_type = "bomber"
		"ambusher":
			enemy.ai_type = "trapper"
		_:
			enemy.ai_type = "chase"

func _on_enemy_died() -> void:
	# 敌人死亡时获取其数据用于货币结算
	# 查找刚刚死亡的 enemy（通过 get_tree().get_nodes_in_group）
	var dead_enemies: Array[Node] = get_tree().get_nodes_in_group("enemy")
	var dying_enemy: Node = null
	var dying_data: Dictionary = {}
	var dying_pos: Vector2 = Vector2.ZERO

	# 找到标记为正在死亡的敌人
	for e in dead_enemies:
		if e is CharacterBody2D and e.current_hp <= 0:
			dying_enemy = e
			if e.has_method("get_enemy_data"):
				dying_data = e.get_enemy_data()
			dying_pos = e.global_position
			break

	# 通知 RoomGameMode（如果有引用）
	if _room_game_mode != null and _room_game_mode.has_method("notify_enemy_killed"):
		if dying_data.is_empty():
			# 如果没有存储的 data，构建一个基本数据（货币值默认10）
			dying_data = {"currency_value": 10, "xp_value": 10}
		dying_data["last_position"] = dying_pos
		_room_game_mode.notify_enemy_killed(dying_data)

	on_enemy_killed()
