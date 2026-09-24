class_name LevelAreaBudget
extends RefCounted
## 关卡面积预算唯一实现（依据 docs/v0.1/05.2 §5「面积预算」与 §3.7 走廊公式）。
##
## 抽出的原因：面积预算原先只存在于 FloorPlanGenerator 的私有函数里，
## 而校验器与数据驱动加载路径都要用它 —— 直接引用会形成
## FloorPlanGenerator → LevelPlanValidator → FloorPlanGenerator 的循环依赖。
## 本类即为该公式的唯一实现，FloorPlanGenerator 保留同名转发函数，行为不变。
##
## 走廊长度走 RoomDoorLane.corridor_clear（同一公式，唯一实现）。

const ROOM_DOOR_LANE := preload("res://src/map/RoomDoorLane.gd")

const MAP_SIZE_M := 250.0
const CORE_SIZE_M := 65.0
const WALL_THICKNESS_M := 0.30
const CORRIDOR_WIDTH_M := 6.0
const TARGET_OCCUPANCY_RATIO := 0.42
const REFERENCE_CONTENT_ROOM_COST_M2 := 1450.0
## 电梯井、双楼梯折返区、楼板洞、门前净空与不可规整角区统一先扣除。
const STAIR_AND_UTILITY_RESERVE_M2 := 6500.0
const CONTENT_ROOM_TARGET_CLAMP := Vector2i(14, 16)


## rooms 为 plan 房间数组（需含 position / dimensions / parent_key）。
## policy 为 L1 generation_policy（可选，缺省 = 塔楼口径，行为与加形参前逐位一致）：
##   - `target_occupancy_ratio`：覆盖占用率上限（缺省 TARGET_OCCUPANCY_RATIO）。
##   - `enforce_area_budget`：false 时**只算不判**（返回值里 `area_budget_enforced=false`），
##     供单层独立关卡放开总面积约束（远征01，见设计页 §4.7）；缺省 true。
## 本函数只产出数字与两个开关的读值，**判定落在 LevelPlanValidator**（单一落点）。
static func calculate(rooms: Array, policy: Dictionary = {}) -> Dictionary:
	var total_floor_area := MAP_SIZE_M * MAP_SIZE_M
	var outer_wall_area := MAP_SIZE_M * 4.0 * WALL_THICKNESS_M
	var core_area := CORE_SIZE_M * CORE_SIZE_M
	var available_area := (
		total_floor_area - outer_wall_area - core_area - STAIR_AND_UTILITY_RESERVE_M2
	)
	var room_area := 0.0
	var interior_wall_area := 0.0
	var corridor_area := 0.0
	var room_by_key: Dictionary = {}
	for value in rooms:
		var room := value as Dictionary
		room_by_key[str(room.get("key", ""))] = room
		var dimensions := room.get("dimensions", Vector2.ZERO) as Vector2
		room_area += dimensions.x * dimensions.y
		interior_wall_area += (dimensions.x + dimensions.y) * 2.0 * WALL_THICKNESS_M
	for value in rooms:
		var room := value as Dictionary
		var parent_key := str(room.get("parent_key", ""))
		if parent_key.is_empty() or not room_by_key.has(parent_key):
			continue
		var parent := room_by_key[parent_key] as Dictionary
		corridor_area += (
			ROOM_DOOR_LANE.corridor_clear(
				parent.get("position", Vector2.ZERO) as Vector2,
				parent.get("dimensions", Vector2.ZERO) as Vector2,
				room.get("position", Vector2.ZERO) as Vector2,
				room.get("dimensions", Vector2.ZERO) as Vector2
			)
			* CORRIDOR_WIDTH_M
		)
	var estimated_used := room_area + interior_wall_area + corridor_area
	# 占用率可被 L1 政策覆盖；越界值（<=0 或 >1）落回常量，绝不因此产出非法 target。
	var occupancy_ratio := float(policy.get("target_occupancy_ratio", TARGET_OCCUPANCY_RATIO))
	if occupancy_ratio <= 0.0 or occupancy_ratio > 1.0:
		occupancy_ratio = TARGET_OCCUPANCY_RATIO
	var target_usable_area := available_area * occupancy_ratio
	# 放开开关：只影响**是否判定**，不影响上面任何计算值 —— 数字照出，供文档与验收读。
	var enforce_area_budget := bool(policy.get("enforce_area_budget", true))
	return {
		"total_floor_area_m2": total_floor_area,
		"outer_wall_area_m2": outer_wall_area,
		"core_area_m2": core_area,
		"stair_corridor_utility_reserve_m2": STAIR_AND_UTILITY_RESERVE_M2,
		"available_area_m2": available_area,
		"target_occupancy_ratio": occupancy_ratio,
		"target_usable_area_m2": target_usable_area,
		"area_budget_enforced": enforce_area_budget,
		"reference_content_room_cost_m2": REFERENCE_CONTENT_ROOM_COST_M2,
		"calculated_content_room_target": clampi(
			int(floor(target_usable_area / REFERENCE_CONTENT_ROOM_COST_M2)),
			CONTENT_ROOM_TARGET_CLAMP.x,
			CONTENT_ROOM_TARGET_CLAMP.y
		),
		"room_area_m2": room_area,
		"interior_wall_area_m2": interior_wall_area,
		"corridor_area_m2": corridor_area,
		"estimated_used_area_m2": estimated_used,
	}
