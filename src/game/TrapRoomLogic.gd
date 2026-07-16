class_name TrapRoomLogic
extends Node2D
## 陷阱房逻辑 — 处理陷阱触发、埋伏怪物
## 进入房间时可能触发陷阱（如毒雾、落石）
## 房间角落埋伏着怪物，玩家开门时突袭
## 在玩家进入房间后显示警告并激活埋伏点

signal trap_triggered(trap_type: String)
signal ambush_activated()

enum TrapType {
	NONE,
	POISON_FOG,
	FALLING_ROCKS,
	AMBUSH,
}

enum TrapState {
	ARMED,      # 陷阱待命
	TRIGGERED,  # 陷阱已触发
	CLEARED,     # 陷阱/埋伏已清理
}

## 配置
@export var trap_type: TrapType = TrapType.AMBUSH     # 陷阱类型
@export var trap_damage: float = 10.0                   # 陷阱伤害
@export var trap_duration: float = 5.0                 # 陷阱持续时间
@export var ambush_count: int = 3                       # 埋伏怪物数量
@export var ambush_delay: float = 1.5                   # 埋伏触发延迟（秒）

## 状态
var _state: TrapState = TrapState.ARMED
var _triggered: bool = false
var _ambush_active: bool = false
var _player_entered: bool = false
var _trap_timer: float = 0.0
var _ambush_timer: float = 0.0

## 引用
var _wave_spawner: Node = null
var _warning_label: Label = null
var _inventory_module: InventoryModule = null
var player: Node2D = null  # 玩家引用（在陷阱房范围内时有效）

func _ready() -> void:
	_setup_trap_room()
	_connect_signals()
	_setup_damage_zones()

func _process(delta: float) -> void:
	if not _player_entered:
		return

	# 更新伤害冷却
	if _player_hurt_cooldown > 0.0:
		_player_hurt_cooldown -= delta

	# 处理埋伏延迟
	if not _ambush_active and _ambush_timer > 0.0:
		_ambush_timer -= delta
		if _ambush_timer <= 0.0:
			_activate_ambush()

	# 处理陷阱持续时间
	if _triggered and _trap_timer > 0.0:
		_trap_timer -= delta
		if _trap_timer <= 0.0:
			_clear_trap()

	# 毒雾持续伤害
	if _state == TrapState.TRIGGERED and trap_type == TrapType.POISON_FOG:
		_apply_poison_fog_damage(delta)

func _setup_trap_room() -> void:
	# 查找警告标签
	_warning_label = get_node_or_null("TrapWarningLabel") as Label
	if _warning_label != null:
		_warning_label.visible = false

	# 获取波次生成器
	_wave_spawner = get_node_or_null("WaveSpawner")

	_ambush_active = false
	_ambush_timer = 0.0

func _connect_signals() -> void:
	# 连接玩家进入信号（由房间场景的 Area2D 触发）
	var room_area: Area2D = get_node_or_null("RoomTrigger") as Area2D
	if room_area != null:
		room_area.body_entered.connect(_on_player_enter_room)

## 玩家进入房间
func _on_player_enter_room(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if _player_entered:
		return

	_player_entered = true
	player = body  # 缓存玩家引用
	print("[TrapRoomLogic] 玩家进入陷阱房，陷阱类型: %s" % _get_trap_type_name())

	# 显示警告
	_show_warning()

	# 根据陷阱类型触发对应效果
	match trap_type:
		TrapType.POISON_FOG:
			_trigger_poison_fog()
		TrapType.FALLING_ROCKS:
			_trigger_falling_rocks()
		TrapType.AMBUSH:
			# 埋伏延迟触发
			_schedule_ambush()
		_:
			pass

func _show_warning() -> void:
	if _warning_label != null:
		_warning_label.visible = true
		var warning_timer := get_node_or_null("WarningHideTimer") as Timer
		if warning_timer == null:
			warning_timer = Timer.new()
			warning_timer.name = "WarningHideTimer"
			warning_timer.one_shot = true
			warning_timer.timeout.connect(_hide_warning)
			add_child(warning_timer)
		warning_timer.start(2.0)


func _hide_warning() -> void:
	if is_instance_valid(_warning_label):
		_warning_label.visible = false

func _trigger_poison_fog() -> void:
	_state = TrapState.TRIGGERED
	_triggered = true
	_trap_timer = trap_duration
	trap_triggered.emit("poison_fog")
	print("[TrapRoomLogic] 毒雾陷阱已触发，持续 %s 秒" % trap_duration)

func _trigger_falling_rocks() -> void:
	_state = TrapState.TRIGGERED
	_triggered = true
	_trap_timer = 2.0  # 落石快速结束
	trap_triggered.emit("falling_rocks")
	print("[TrapRoomLogic] 落石陷阱已触发")

	# 启动落石伤害计时器（延迟 1.5 秒后开始落下）
	if _falling_rocks_damage_timer != null and is_instance_valid(_falling_rocks_damage_timer):
		_falling_rocks_damage_timer.start()
	else:
		# fallback：直接开始伤害检测
		_on_falling_rocks_damage_start()

func _schedule_ambush() -> void:
	_ambush_timer = ambush_delay
	print("[TrapRoomLogic] 埋伏已安排，%s 秒后触发" % ambush_delay)

func _activate_ambush() -> void:
	if _ambush_active:
		return
	_ambush_active = true
	_state = TrapState.TRIGGERED
	ambush_activated.emit()
	print("[TrapRoomLogic] 埋伏触发！生成 %d 只怪物" % ambush_count)

	# 通过波次生成器生成埋伏怪物
	if _wave_spawner != null and _wave_spawner.has_method("spawn_ambush_enemies"):
		_wave_spawner.spawn_ambush_enemies(ambush_count)
	else:
		print("[TrapRoomLogic] WaveSpawner 无 ambush 方法，跳过埋伏生成")

func _clear_trap() -> void:
	_state = TrapState.CLEARED
	_triggered = false
	print("[TrapRoomLogic] 陷阱已清除")

func _get_trap_type_name() -> String:
	match trap_type:
		TrapType.POISON_FOG: return "毒雾"
		TrapType.FALLING_ROCKS: return "落石"
		TrapType.AMBUSH: return "埋伏"
		_: return "无"

## 设置背包引用
func set_inventory(inventory: InventoryModule) -> void:
	_inventory_module = inventory

## 获取状态
func get_state() -> TrapState:
	return _state

## 是否已触发
func is_triggered() -> bool:
	return _triggered

## ============================================================
## 伤害区域系统（毒雾 / 落石实际效果）
## ============================================================

## 伤害冷却（避免每秒多次扣血）
var _player_hurt_cooldown: float = 0.0
const HURT_COOLDOWN: float = 0.5  # 每次扣血间隔（秒）
## 落石触发计时器引用（用于延迟触发落石伤害）
var _falling_rocks_damage_timer: Timer = null
## 落石是否正在下落（触发伤害窗口）
var _rocks_falling: bool = false

func _setup_damage_zones() -> void:
	_player_hurt_cooldown = 0.0
	_rocks_falling = false

	# 落石伤害计时器：延迟 1.5 秒后开始检测（模拟落石从天花板落下）
	_falling_rocks_damage_timer = Timer.new()
	_falling_rocks_damage_timer.one_shot = true
	_falling_rocks_damage_timer.wait_time = 1.5
	_falling_rocks_damage_timer.timeout.connect(_on_falling_rocks_damage_start)
	add_child(_falling_rocks_damage_timer)

func _apply_poison_fog_damage(_delta: float) -> void:
	# 每 HURT_COOLDOWN 秒对玩家造成一次毒雾伤害
	if _player_hurt_cooldown > 0.0:
		return
	if player == null or not is_instance_valid(player):
		return
	# 检查玩家是否在毒雾范围内（以本节点为中心，半径 400px）
	if player.global_position.distance_to(global_position) < 400.0:
		_player_hurt_cooldown = HURT_COOLDOWN
		_damage_player(trap_damage, "poison_fog")
		_show_damage_number(player.global_position, trap_damage)

func _on_falling_rocks_damage_start() -> void:
	_rocks_falling = true
	# 落石窗口 2 秒（与 trap_timer 同步），期间每 0.3 秒随机检测一次
	print("[TrapRoomLogic] 落石开始！2 秒伤害窗口")
	var damage_timer := get_node_or_null("RocksDamageTimer") as Timer
	if damage_timer == null:
		damage_timer = Timer.new()
		damage_timer.name = "RocksDamageTimer"
		damage_timer.wait_time = 0.3
		damage_timer.timeout.connect(_check_falling_rocks_hit)
		add_child(damage_timer)
	damage_timer.start()
	var stop_timer := get_node_or_null("RocksStopTimer") as Timer
	if stop_timer == null:
		stop_timer = Timer.new()
		stop_timer.name = "RocksStopTimer"
		stop_timer.one_shot = true
		stop_timer.timeout.connect(_stop_falling_rocks)
		add_child(stop_timer)
	stop_timer.start(2.0)


func _stop_falling_rocks() -> void:
	var damage_timer := get_node_or_null("RocksDamageTimer") as Timer
	if damage_timer != null:
		damage_timer.stop()
	_rocks_falling = false

func _check_falling_rocks_hit() -> void:
	# 落石命中：玩家在房间范围内时随机受击（60% 概率命中）
	if player == null or not is_instance_valid(player) or _player_hurt_cooldown > 0.0:
		return
	if player.global_position.distance_to(global_position) < 500.0:
		if randf() < 0.6:
			_player_hurt_cooldown = HURT_COOLDOWN
			_damage_player(trap_damage * 2.0, "falling_rocks")  # 落石伤害双倍
			_show_damage_number(player.global_position + Vector2(randf_range(-30, 30), randf_range(-30, 30)), trap_damage * 2.0)

func _damage_player(amount: float, source: String) -> void:
	if player == null or not is_instance_valid(player):
		return
	if player.has_method("take_damage"):
		player.take_damage(int(amount))
		print("[TrapRoomLogic] 陷阱伤害: %s, 伤害值: %.0f" % [source, amount])

func _show_damage_number(world_pos: Vector2, amount: float) -> void:
	# 通过 GameUIManager 显示飘字
	var ui: Node = get_node_or_null("/root/Main/GameUIManager")
	if ui != null and ui.has_method("show_damage_popup"):
		ui.show_damage_popup(world_pos, int(amount), false)
