class_name RoomWaveSpawner
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

## 内部状态
var _room: Node2D = null
var _player: Node2D = null
var _enemy_count_per_wave: Array[int] = []  # 每波敌人数
var _floor: int = 1
var _floor_level: int = RoomData.FloorLevel.MEDIUM
var _current_wave: int = 0
var _total_waves: int = 0
var _alive_count: int = 0
var _wave_timer: float = 0.0
var _waiting_next_wave: bool = false
var _active: bool = false
var _all_spawned: bool = false
var _monster_injector: MonsterInjector
var _rng: RandomNumberGenerator

func _init() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = Time.get_ticks_msec()
	_monster_injector = MonsterInjector.new()

## 配置波次（外部调用）
## wave_counts: Array[int] — 每波敌人数，如 [3, 4, 5]
func configure(wave_counts: Array[int], room: Node2D, player: Node2D, floor: int, floor_level: int) -> void:
	_enemy_count_per_wave = wave_counts
	_room = room
	_player = player
	_floor = floor
	_floor_level = floor_level
	_current_wave = 0
	_total_waves = wave_counts.size()
	_alive_count = 0
	_waiting_next_wave = false
	_all_spawned = false

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
		"total": _total_waves,
		"alive": _alive_count
	}

## 是否所有波次已完成
func is_complete() -> bool:
	return _all_spawned and _alive_count <= 0

## 外部通知敌人死亡（RoomGameMode 调用）
func on_enemy_killed() -> void:
	_alive_count -= 1
	if _alive_count <= 0:
		wave_cleared.emit(_current_wave)
		if _all_spawned and _current_wave >= _total_waves:
			_active = false
			all_waves_cleared.emit()
		else:
			_current_wave += 1
			if _current_wave < _total_waves:
				_waiting_next_wave = true
				_wave_timer = inter_wave_delay
			else:
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
	
	# 计算出生点中心
	var center: Vector2 = Vector2.ZERO
	if is_instance_valid(_player):
		center = _player.global_position
	
	for i in range(count):
		var spawn_pos: Vector2 = _get_spawn_position(center)
		var enemy_data: Dictionary = _generate_enemy_data()
		_spawn_enemy_instance(enemy_data, spawn_pos)
		enemy_spawned.emit(1)
		# 每只间隔一点
		if i < count - 1:
			await get_tree().create_timer(0.15).timeout
	
	_all_spawned = true
	wave_enemies_spawned.emit(_current_wave + 1, count)

func _get_spawn_position(center: Vector2) -> Vector2:
	var angle := _rng.randf() * TAU
	var radius := spawn_radius * sqrt(_rng.randf())  # sqrt → 均匀圆分布
	return center + Vector2(cos(angle), sin(angle)) * radius

func _generate_enemy_data() -> Dictionary:
	var config := {"type": "random", "floor": _floor, "floor_level": _floor_level}
	var result: Array = _monster_injector.generate_enemies(config)
	return result[0] if not result.is_empty() else {"enemy_type": "melee_chaser", "hp": 25, "damage": 5, "speed": 80.0}

func _spawn_enemy_instance(data: Dictionary, spawn_pos: Vector2) -> void:
	var scene_path := "res://scenes/Enemy.tscn"
	var enemy_scene: PackedScene = load(scene_path)
	if enemy_scene == null:
		push_warning("[RoomWaveSpawner] Enemy scene not found")
		return
	
	var enemy: CharacterBody2D = enemy_scene.instantiate() as CharacterBody2D
	enemy.global_position = spawn_pos
	
	# 应用属性
	if data.get("hp"):
		enemy.max_hp = data["hp"]
		enemy.current_hp = data["hp"]
	if data.get("damage"):
		enemy.damage = data["damage"]
	if data.get("speed"):
		enemy.speed = data["speed"]
	if data.get("ai_type"):
		enemy.ai_type = data["ai_type"]
	if data.get("is_elite"):
		enemy.add_modifier("巨大化", 1)
	if data.get("modifier"):
		enemy.add_modifier(data["modifier"], 1)
	
	# 连接死亡信号
	if enemy.has_signal("enemy_died"):
		enemy.enemy_died.connect(_on_enemy_died)
	
	if is_instance_valid(_room):
		_room.add_child(enemy)
	else:
		get_tree().root.add_child(enemy)
	
	# 发出进度更新（已被击杀数 / 当前波总数）
	var killed = _enemy_count_per_wave[_current_wave] - _alive_count
	wave_progress_updated.emit(killed, _enemy_count_per_wave[_current_wave], _current_wave + 1)

func _on_enemy_died() -> void:
	# 敌人死亡的信号自动触发计数减少
	on_enemy_killed()
