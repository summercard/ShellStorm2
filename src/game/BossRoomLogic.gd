class_name BossRoomLogic
extends Node2D
## Boss 房逻辑 — Boss 房氛围视觉 + Boss 生成触发
## 由 RoomGameMode 在进入房间时调用 setup() 激活
## Boss 的实际数据管理由 BossRoomDirector（MapManager 内部）处理

signal boss_spawn_triggered(boss_data: Dictionary)
signal boss_defeated_triggered()

## 状态
var _setup_done: bool = false
var _boss_spawned: bool = false

## Boss 视觉组件引用
var _boss_arena: ColorRect = null
var _boss_arena_inner: ColorRect = null
var _boss_markers: Array[ColorRect] = []
var _pulse_timer: float = 0.0

## Boss 数据（由外部配置）
var _boss_data: Dictionary = {}

func _ready() -> void:
	_setup_boss_room()
	_connect_signals()

func _process(delta: float) -> void:
	# Boss Arena 脉冲动画（深红节奏，压迫感）
	if _boss_arena != null:
		_pulse_timer += delta
		var pulse: float = (sin(_pulse_timer * 2.0) * 0.5 + 0.5) * 0.20 + 0.12
		_boss_arena.color = Color(0.50, 0.08, 0.08, pulse)

func _setup_boss_room() -> void:
	# 查找 Boss Arena 光圈
	_boss_arena = get_node_or_null("BossArena") as ColorRect
	_boss_arena_inner = get_node_or_null("BossArenaInner") as ColorRect
	
	# 查找方向标记
	var marker_names: Array[String] = ["BossMarker_N", "BossMarker_S", "BossMarker_W", "BossMarker_E"]
	for name in marker_names:
		var marker: ColorRect = get_node_or_null(name) as ColorRect
		if marker != null:
			_boss_markers.append(marker)

func _connect_signals() -> void:
	var actor: Node = get_node_or_null("BossActor")
	if actor == null or not actor.has_signal("boss_defeated"):
		return
	var defeated_signal := Signal(actor, "boss_defeated")
	if not defeated_signal.is_connected(_on_boss_actor_defeated):
		defeated_signal.connect(_on_boss_actor_defeated)


func _on_boss_actor_defeated() -> void:
	## Scene-local consequences are independent from map progression; RoomGameMode
	## forwards the same actor event into BossRoomDirector for rewards/extraction.
	trigger_boss_defeated()

## 设置 Boss 房（由 RoomGameMode 调用，进入后立即激活）
func setup(boss_data: Dictionary = {}) -> void:
	if _setup_done:
		return
	_setup_done = true
	_boss_data = boss_data
	
	# 初始化 Arena 颜色（初始状态，深红色）
	if _boss_arena != null:
		_boss_arena.color = Color(0.50, 0.08, 0.08, 0.12)
	if _boss_arena_inner != null:
		_boss_arena_inner.color = Color(0.60, 0.10, 0.10, 0.06)
	
	print("[BossRoomLogic] Boss房已设置，boss_data=%s" % _boss_data)

## 触发 Boss 生成（由外部调用，生成 Boss 并通知 RoomGameMode）
func trigger_boss_spawn(boss_data: Dictionary) -> void:
	_boss_spawned = true
	_boss_data = boss_data
	boss_spawn_triggered.emit(boss_data)
	
	# 高亮 Arena 表示 Boss 已激活
	if _boss_arena != null:
		_boss_arena.color = Color(0.65, 0.10, 0.10, 0.20)
	if _boss_arena_inner != null:
		_boss_arena_inner.color = Color(0.70, 0.12, 0.12, 0.10)
	
	print("[BossRoomLogic] Boss已生成: %s" % boss_data.get("boss_id", "unknown"))

## 触发 Boss 击败（由外部调用，通知 Boss 已死亡）
func trigger_boss_defeated() -> void:
	boss_defeated_triggered.emit()
	
	# Arena 熄灭（深红色变暗，表示战斗结束）
	if _boss_arena != null:
		_boss_arena.color = Color(0.20, 0.05, 0.05, 0.15)
	
	print("[BossRoomLogic] Boss击败触发")

## 获取当前 Boss 数据
func get_boss_data() -> Dictionary:
	return _boss_data

## 检查 Boss 是否已生成
func is_boss_spawned() -> bool:
	return _boss_spawned
