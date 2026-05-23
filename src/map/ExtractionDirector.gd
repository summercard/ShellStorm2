class_name ExtractionDirector
extends RefCounted
## 撤离点管理 — 管理各种类型的撤离点

signal extraction_unlocked(extraction_type: String)
signal extraction_used(extraction_type: String, success: bool)
signal extraction_countdown_started(type: String, duration: float)

enum ExtractionType {
	STANDARD = 0,   # 基础撤离点（地图生成时存在）
	ELITE_KILL = 1, # 精英击杀后开启
	BOSS_KILL = 2,  # Boss击杀后开启
	BEACON = 3,     # 信标道具召唤
	TRADE = 4,      # 向NPC支付资源
}

class ExtractionPoint:
	var id: String
	var type: ExtractionType
	var position: Vector2
	var is_unlocked: bool = false
	var is_used: bool = false
	var requirements: Dictionary = {}
	var countdown_duration: float = 0.0
	var current_countdown: float = 0.0
	
	func _init(p_id: String, p_type: ExtractionType):
		id = p_id
		type = p_type

var _extraction_points: Array[ExtractionPoint] = []
var _current_extraction: ExtractionPoint = null
var _beacon_count: int = 0
var _beacon_item_id: String = "item_beacon"  ## 信标道具ID，与物品系统对齐
var _inventory_ref: InventoryModule = null  ## 背包引用（用于真实消耗物品）
var _room_game_mode: RoomGameMode = null  ## 房间游戏模式引用（用于精英/Boss击杀计数回调）

signal extraction_started(point_id: String)
signal extraction_completed(point_id: String, player_escaped: bool)

## 添加撤离点
func add_extraction_point(extraction_type: ExtractionType, requirements: Dictionary = {}) -> String:
	var point_id: String = "extract_%d_%d" % [_extraction_points.size(), extraction_type]
	var point := ExtractionPoint.new(point_id, extraction_type)
	point.requirements = requirements
	if extraction_type == ExtractionType.STANDARD:
		point.is_unlocked = true
	
	_extraction_points.append(point)
	return point_id

## 解锁撤离点
func unlock_extraction(point_id: String = "") -> bool:
	var point: ExtractionPoint
	
	if point_id.is_empty():
		# 解锁第一个可用的撤离点
		for p in _extraction_points:
			if not p.is_unlocked:
				point = p
				break
	else:
		point = _get_point(point_id)
	
	if point == null:
		return false
	
	point.is_unlocked = true
	extraction_unlocked.emit(ExtractionType.keys()[point.type])
	return true

## 解锁精英击杀撤离
func unlock_elite_extraction() -> void:
	# 找到第一个 ELITE_KILL 类型的撤离点并解锁
	var elite_point: ExtractionPoint = null
	for p in _extraction_points:
		if p.type == ExtractionType.ELITE_KILL:
			elite_point = p
			break
	if elite_point == null:
		# 不存在则创建一个
		add_extraction_point(ExtractionType.ELITE_KILL, {"must_kill_elite": true})
		elite_point = _extraction_points[-1]
	if not elite_point.is_unlocked:
		elite_point.is_unlocked = true
		extraction_unlocked.emit("ELITE_KILL")

## 解锁Boss撤离
func unlock_boss_extraction() -> void:
	# 找到第一个 BOSS_KILL 类型的撤离点并解锁
	var boss_point: ExtractionPoint = null
	for p in _extraction_points:
		if p.type == ExtractionType.BOSS_KILL:
			boss_point = p
			break
	if boss_point == null:
		# 不存在则创建一个
		add_extraction_point(ExtractionType.BOSS_KILL, {"must_kill_boss": true})
		boss_point = _extraction_points[-1]
	if not boss_point.is_unlocked:
		boss_point.is_unlocked = true
		extraction_unlocked.emit("BOSS_KILL")

## 解锁交易撤离（由商人房触发）
func unlock_trade_extraction() -> void:
	var trade_point: ExtractionPoint = null
	for p in _extraction_points:
		if p.type == ExtractionType.TRADE:
			trade_point = p
			break
	if trade_point == null:
		add_extraction_point(ExtractionType.TRADE, {"must_pay_currency": true})
		trade_point = _extraction_points[-1]
	if not trade_point.is_unlocked:
		trade_point.is_unlocked = true
		extraction_unlocked.emit("TRADE")

## 获取交易撤离的花费（楼层越高越高）
func get_trade_cost(floor: int = 1) -> int:
	return floor * 30

## 尝试执行交易撤离（花费货币，永久消耗撤离点）
## 返回是否成功
func try_use_trade_extraction(player_escaped: bool, current_currency: int, floor: int = 1) -> bool:
	# 找到 TRADE 撤离点
	var trade_point: ExtractionPoint = null
	for p in _extraction_points:
		if p.type == ExtractionType.TRADE and p.is_unlocked and not p.is_used:
			trade_point = p
			break
	if trade_point == null:
		return false
	
	var cost: int = get_trade_cost(floor)
	# 货币已在 GameUIManager 层面预扣，这里只做最终结算
	if player_escaped:
		trade_point.is_used = true
		extraction_completed.emit(trade_point.id, true)
		extraction_used.emit(ExtractionType.keys()[trade_point.type], true)
		# 通知货币已花费（供外部更新 GameManager）
		print("[ExtractionDirector] TRADE extraction used, cost %d魂" % cost)
	return true

## 绑定背包引用（由 RoomGameMode 在初始化时调用）
func bind_inventory(inventory: InventoryModule) -> void:
	_inventory_ref = inventory
	sync_beacon_count_from_inventory(inventory)

## 绑定房间游戏模式引用（用于精英/Boss击杀状态回调）
func bind_room_game_mode(game_mode: RoomGameMode) -> void:
	_room_game_mode = game_mode

## 使用信标道具召唤撤离
## 真实从背包消耗物品（_beacon_count 仅作镜像，不参与消耗逻辑）
func summon_beacon_extraction() -> bool:
	# 优先用背包引用真实消耗，没有则用内存计数兜底
	if _inventory_ref != null:
		if not _inventory_ref.consume_item(_beacon_item_id, 1):
			return false
		# 同步镜像计数（防止 bind_inventory 和此处消耗之间的时序差）
		_beacon_count = _inventory_ref.get_item_count(_beacon_item_id)
	else:
		if _beacon_count <= 0:
			return false
		_beacon_count -= 1
	
	add_extraction_point(ExtractionType.BEACON, {"beacon_used": true})
	var point_id = unlock_extraction()
	extraction_countdown_started.emit("BEACON", 10.0)
	return true

## 开始撤离读条
func start_extraction(point_id: String) -> bool:
	var point: ExtractionPoint = _get_point(point_id)
	if point == null or not point.is_unlocked or point.is_used:
		return false
	
	if not _check_requirements(point):
		return false
	
	_current_extraction = point
	point.current_countdown = point.countdown_duration
	extraction_started.emit(point_id)
	return true

## 检查撤离条件
func _check_requirements(point: ExtractionPoint) -> bool:
	var reqs: Dictionary = point.requirements
	
	# 检查精英/Boss击杀计数（通过 RoomGameMode 回调）
	var room_killed_count: int = 0
	var room_boss_killed: bool = false
	if _room_game_mode != null:
		room_killed_count = _room_game_mode.get_elites_killed_in_current_room()
		room_boss_killed = _room_game_mode.is_boss_killed_in_current_room()
	
	if reqs.get("must_kill_elite", false):
		# 需要当前房间精英怪已全部击杀
		var elite_count: int = _get_elite_count_for_point(point)
		if elite_count > 0 and room_killed_count < elite_count:
			return false
	
	if reqs.get("must_kill_boss", false):
		# 需要Boss已击杀
		if not room_boss_killed:
			return false
	
	if reqs.get("min_items", 0) > 0:
		# 需要携带最低数量物品
		if _inventory_ref == null or _inventory_ref.get_item_count_all() < reqs.get("min_items", 0):
			return false
	
	return true

## 获取指定撤离点关联房间的精英怪数量（通过 requirements.room_node_id 查找）
func _get_elite_count_for_point(point: ExtractionPoint) -> int:
	var room_node_id = point.requirements.get("room_node_id", -1)
	if room_node_id == -1 or _room_game_mode == null:
		# 无关联房间信息，尝试从 map_manager 获取当前房间
		var current_room_elites: int = _room_game_mode.get_current_room_elite_count() if _room_game_mode else 0
		return current_room_elites
	return _room_game_mode.get_room_elite_count(room_node_id)

## 完成撤离
func complete_extraction(player_escaped: bool) -> void:
	if _current_extraction != null:
		_current_extraction.is_used = true
		extraction_completed.emit(_current_extraction.id, player_escaped)
		extraction_used.emit(ExtractionType.keys()[_current_extraction.type], player_escaped)
		_current_extraction = null

## 获取可用的撤离点
func get_available_extractions() -> Array[ExtractionPoint]:
	var available: Array[ExtractionPoint] = []
	for p in _extraction_points:
		if p.is_unlocked and not p.is_used:
			available.append(p)
	return available

## 获取撤离点数量
func get_extraction_count() -> int:
	return _extraction_points.size()

## 获取可用撤离点数量
func get_available_count() -> int:
	return get_available_extractions().size()

## 设置信标数量
func set_beacon_count(count: int) -> void:
	_beacon_count = count

## 获取信标数量
func get_beacon_count() -> int:
	return _beacon_count

## 获取信标道具ID
func get_beacon_item_id() -> String:
	return _beacon_item_id

## 从 InventoryModule 同步信标数量
## 由 RoomGameMode 或 GameManager 每局开始时调用
func sync_beacon_count_from_inventory(inventory: InventoryModule) -> void:
	if inventory == null:
		_beacon_count = 0
		return
	_beacon_count = inventory.get_item_count(_beacon_item_id)

## 检查是否有信标可用（用于UI按钮可用性）
func has_beacon() -> bool:
	return _beacon_count > 0

## 获取当前撤离点
func get_current_extraction() -> ExtractionPoint:
	return _current_extraction

## 清除所有撤离点
func clear() -> void:
	_extraction_points.clear()
	_current_extraction = null

## 获取指定类型的所有撤离点
func get_points_by_type(extraction_type: ExtractionType, only_unlocked: bool = false) -> Array[ExtractionPoint]:
	var result: Array[ExtractionPoint] = []
	for p in _extraction_points:
		if p.type == extraction_type:
			if not only_unlocked or p.is_unlocked:
				result.append(p)
	return result

func _get_point(point_id: String) -> ExtractionPoint:
	for p in _extraction_points:
		if p.id == point_id:
			return p
	return null

## 调试：打印撤离点状态
func debug_status() -> String:
	var lines: Array[String] = ["ExtractionDirector [%d points, %d available]" % [_extraction_points.size(), get_available_count()]]
	lines.append("  Beacons: %d" % [_beacon_count])
	for p in _extraction_points:
		var status: String = "LOCKED"
		if p.is_unlocked:
			status = "UNLOCKED"
		if p.is_used:
			status = "USED"
		lines.append("  %s [%s] type=%s" % [p.id, status, ExtractionType.keys()[p.type]])
	return "\n".join(lines)
