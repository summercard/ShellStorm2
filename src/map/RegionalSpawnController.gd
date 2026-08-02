class_name RegionalSpawnController
extends Node
## v0.1 P1 区域刷怪控制器 + P2 精英警觉增援
## 挂载在每个房间节点（RoomCombat/RoomElite）上，监听本房间敌人追击状态，
## 当敌人进入 CHASE 时触发区域增援，在相邻房间（或本房间）生成额外敌人。
## P2: 精英怪进入 CHASE 时还会通知相邻房间敌人进入 ALERT（跨房间AI联动）。
## 由 RoomGameMode 在进入房间时统一管理生命周期。

signal reinforcement_ready(room_id: String, count: int)
signal reinforcement_triggered(source_enemy: Node, target_room_id: int, count: int)
## 相邻房间敌人被精英警觉唤醒
signal adjacent_alert_triggered(source_elite: Node, adjacent_room_id: int)

## 可配置
@export var reinforcement_enabled: bool = true  # 总开关
@export var reinforce_cooldown: float = 12.0   # 增援冷却（秒）
@export var reinforce_count: int = 3            # 每次增援生成敌人数
@export var reinforce_spread: float = 280.0     # 增援范围（超出房间边界的距离）
## P2: 精英警觉联动
@export var elite_alert_enabled: bool = true    # 精英警觉联动总开关
@export var elite_alert_range: int = 1          # 精英警觉影响相邻房间层数（默认1=直接相邻）
@export var elite_alert_cooldown: float = 8.0   # 精英警觉冷却（秒）

## 内部状态
var _parent_room: Node2D = null
var _room_data: RoomData = null
var _room_bounds: Rect2 = Rect2(-GridConstants.ROOM_PIXEL_WIDTH * 0.5, -GridConstants.ROOM_PIXEL_HEIGHT * 0.5, GridConstants.ROOM_PIXEL_WIDTH, GridConstants.ROOM_PIXEL_HEIGHT)
var _room_center: Vector2 = Vector2.ZERO
var _cooldown_timer: float = 0.0
var _reinforcements_available: bool = true
var _triggered_rooms: Array[int] = []  # 已触发过增援的房间ID列表
var _rng: RandomNumberGenerator
## P2 相邻房间敌人引用（room_id -> [enemy_nodes]）
var _adjacent_room_enemies: Dictionary = {}  # {room_id: Array[Node]}
var _elite_alert_timer: float = 0.0
var _elite_alert_available: bool = true
## 当前房间敌人集合（用于连接 elite_entered_chase 信号）
var _current_enemies: Array[Node] = []

func _init() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = Time.get_ticks_msec()

## 初始化（RoomGameMode 进入房间时调用）
func setup(parent_room: Node2D, room_data: RoomData, room_bounds: Rect2, spawner_owner: Node) -> void:
	_parent_room = parent_room
	_room_data = room_data
	_room_bounds = room_bounds
	_room_center = room_bounds.position + room_bounds.size * 0.5
	_cooldown_timer = 0.0
	_reinforcements_available = true
	_triggered_rooms.clear()
	_elite_alert_timer = 0.0
	_elite_alert_available = true
	_adjacent_room_enemies.clear()
	_current_enemies.clear()

## 设置增援冷却时长
func set_cooldown(seconds: float) -> void:
	reinforce_cooldown = seconds

## 设置每次增援敌人数
func set_count(count: int) -> void:
	reinforce_count = count

## P2: 注入相邻房间的敌人列表（由 RoomGameMode 在进入房间时调用）
## adjacent_enemies: {room_id: Array[Node2D]} — 相邻房间的敌人节点
func set_adjacent_enemies(adjacent_enemies: Dictionary) -> void:
	_adjacent_room_enemies = adjacent_enemies.duplicate(true)

## P2: 注册当前房间的敌人（用于连接 elite_entered_chase 信号）
func register_enemies(enemies: Array[Node]) -> void:
	# 先断开旧连接
	for enemy in _current_enemies:
		if is_instance_valid(enemy) and enemy.has_signal("elite_entered_chase"):
			if enemy.elite_entered_chase.is_connected(_on_elite_chase):
				enemy.elite_entered_chase.disconnect(_on_elite_chase)
	_current_enemies = enemies
	# 连接精英警觉信号
	for enemy in _current_enemies:
		if is_instance_valid(enemy) and enemy.has_signal("elite_entered_chase"):
			if not enemy.elite_entered_chase.is_connected(_on_elite_chase):
				enemy.elite_entered_chase.connect(_on_elite_chase)

func get_active_enemies() -> Array[Node]:
	var alive: Array[Node] = []
	for e in _current_enemies:
		if is_instance_valid(e) and not e.is_queued_for_deletion():
			alive.append(e)
	return alive


## 每帧更新（由 RoomGameMode._process 调用）
func tick(delta: float) -> void:
	if not reinforcement_enabled:
		return
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta
		_reinforcements_available = (_cooldown_timer <= 0.0)
	else:
		_reinforcements_available = true
	# P2 精英警觉冷却
	if _elite_alert_timer > 0.0:
		_elite_alert_timer -= delta
		_elite_alert_available = (_elite_alert_timer <= 0.0)
	else:
		_elite_alert_available = true

## 外部触发增援（由 RoomWaveSpawner.trigger_extra_spawn 调用，或由 FateCardEngine 调用）
func trigger_reinforcement(count_override: int = -1) -> void:
	if not reinforcement_enabled:
		return
	if not _reinforcements_available:
		print("[RegionalSpawnController] 增援冷却中，忽略触发")
		return
	var count: int = count_override if count_override > 0 else reinforce_count
	_cooldown_timer = reinforce_cooldown
	_reinforcements_available = false
	reinforcement_ready.emit(_room_data.room_id if _room_data else "", count)
	print("[RegionalSpawnController] 区域增援触发！房间=%s，数量=%d" % [
		_room_data.get_type_name(_room_data.room_type) if _room_data else "?", count])

## 内部触发增援（当本房间敌人进入 CHASE 时调用）
func _on_enemy_chase(enemy: Node, last_known_pos: Vector2) -> void:
	if not reinforcement_enabled:
		return
	if not _reinforcements_available:
		return
	# 有概率触发增援（避免每次追击都触发）
	if _rng.randf() > 0.4:
		return
	trigger_reinforcement()

## P2: 精英进入 CHASE 回调 — 唤醒相邻房间敌人
func _on_elite_chase(elite: Node, last_known_pos: Vector2) -> void:
	if not elite_alert_enabled:
		return
	if not _elite_alert_available:
		return
	_elite_alert_timer = elite_alert_cooldown
	_elite_alert_available = false
	print("[RegionalSpawnController] 精英进入CHASE！触发相邻房间AI联动，精英=%s" % elite.name if elite else "?")
	# 向相邻房间敌人广播 ALERT
	var alerted_count: int = 0
	for room_id in _adjacent_room_enemies:
		var enemies: Array = _adjacent_room_enemies[room_id]
		for enemy in enemies:
			if not is_instance_valid(enemy):
				continue
			# 强制唤醒相邻房间敌人进入 ALERT 状态
			if enemy.has_method("force_alert"):
				enemy.force_alert(last_known_pos)
				alerted_count += 1
		if alerted_count > 0:
			adjacent_alert_triggered.emit(elite, room_id)

## 获取当前增援可用状态
func is_reinforcement_available() -> bool:
	return _reinforcements_available

## 获取房间边界（供外部调用，用于计算生成位置）
func get_room_bounds() -> Rect2:
	return _room_bounds
