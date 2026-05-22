class_name ExtractionDirector
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

signal extraction_started(point_id: String)
signal extraction_completed(point_id: String, player_escaped: bool)

## 添加撤离点
func add_extraction_point(extraction_type: ExtractionType, requirements: Dictionary = {}) -> String:
	var point_id := "extract_%d_%d" % [_extraction_points.size(), extraction_type]
	var point := ExtractionPoint.new(point_id, extraction_type)
	point.requirements = requirements
	
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
	# 创建精英专属撤离点
	add_extraction_point(ExtractionType.ELITE_KILL, {"must_kill_elite": true})
	unlock_extraction()

## 解锁Boss撤离
func unlock_boss_extraction() -> void:
	add_extraction_point(ExtractionType.BOSS_KILL, {"must_kill_boss": true})
	unlock_extraction()

## 使用信标道具召唤撤离
func summon_beacon_extraction() -> bool:
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
	
	if reqs.get("must_kill_elite", false):
		# 需要当前房间精英怪已击杀
		# 检查逻辑由外部提供，这里简化处理
		pass
	
	if reqs.get("must_kill_boss", false):
		# 需要Boss已击杀
		pass
	
	if reqs.get("min_items", 0) > 0:
		# 需要携带最低数量物品
		pass
	
	return true

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

## 获取当前撤离点
func get_current_extraction() -> ExtractionPoint:
	return _current_extraction

## 清除所有撤离点
func clear() -> void:
	_extraction_points.clear()
	_current_extraction = null

## 获取指定类型的所有撤离点
func get_points_by_type(extraction_type: ExtractionType) -> Array[ExtractionPoint]:
	var result: Array[ExtractionPoint] = []
	for p in _extraction_points:
		if p.type == extraction_type:
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