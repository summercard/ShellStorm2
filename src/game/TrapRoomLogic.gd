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

func _ready() -> void:
	_setup_trap_room()
	_connect_signals()

func _process(delta: float) -> void:
	if not _player_entered:
		return
	
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
		# 2秒后自动隐藏警告
		await get_tree().create_timer(2.0).timeout
		if _warning_label != null:
			_warning_label.visible = false

func _trigger_poison_fog() -> void:
	_state = TrapState.TRIGGERED
	_triggered = true
	_trap_timer = trap_duration
	trap_triggered.emit("poison_fog")
	print("[TrapRoomLogic] 毒雾陷阱已触发，持续 %s 秒" % trap_duration)
	
	# TODO: 实际应用毒雾效果（如持续伤害区域、视野降低等）

func _trigger_falling_rocks() -> void:
	_state = TrapState.TRIGGERED
	_triggered = true
	_trap_timer = 2.0  # 落石快速结束
	trap_triggered.emit("falling_rocks")
	print("[TrapRoomLogic] 落石陷阱已触发")
	
	# TODO: 实际应用落石伤害

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
