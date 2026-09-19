class_name RoomDoorLane
extends RefCounted
## 门槽（lane）唯一实现。
##
## 运行时房间装配与白盒版图导出/校验必须共用这一份，禁止第二份镜像实现。
## 历史问题：`scripts/blender/build_battle_level01_whitebox_v003.py` 曾以
## `_nearest_runtime_lane()` 手工复刻运行时算法，两侧无任何断言盯住，
## 导致"白盒门槽"与"运行时门槽"可以静默分叉。本类用于终止该分叉。
##
## 坐标语义：本类所有 world_* 函数返回值都是**世界坐标轴上的绝对坐标**
## （北/南墙取 X 轴，东/西墙取 Z 轴）。相对房间中心的门槽偏移 = 世界值 - 该轴中心。

const GRID_UNIT_M := 5.0
## 门槽同轴容差：两房中心横向偏移超过此值即视为不共轴，不得直接拉走廊。
const LATERAL_TOLERANCE_M := 5.01
## 走廊净距下界：门到门的直线距离减去两端房间半尺寸后不得低于此值。
const MIN_CORRIDOR_CLEAR_M := 5.0


## 一面墙按 5m 模块可切出的槽段数。
static func module_count(length_m: float) -> int:
	return maxi(1, int(round(length_m / GRID_UNIT_M)))


## 该墙长度下允许的合法槽位（相对墙中心线的偏移）。
## 首尾各留一个模块不贴角，因此 count>=3 时从索引 1 取到 count-2。
static func lane_offsets(length_m: float) -> Array[float]:
	var count := module_count(length_m)
	var first_index := 1 if count >= 3 else 0
	var last_index := count - 2 if count >= 3 else count - 1
	var offsets: Array[float] = []
	for module_index in range(first_index, last_index + 1):
		offsets.append(-length_m * 0.5 + GRID_UNIT_M * (float(module_index) + 0.5))
	return offsets


## 最接近墙中心线的合法槽位。偶数段墙没有 0m 槽（30m → -2.5m，40m → -2.5m），
## 奇数段墙有 0m 槽（15m / 25m / 35m）。等距时取先出现的负值。
static func nearest_offset(length_m: float) -> float:
	var offsets := lane_offsets(length_m)
	if offsets.is_empty():
		return 0.0
	var best := offsets[0]
	for offset in offsets:
		if absf(offset) < absf(best):
			best = offset
	return best


## 该墙上全部合法槽位的世界坐标。
static func world_candidates(axis_center_m: float, length_m: float) -> Array[float]:
	var lanes: Array[float] = []
	for offset in lane_offsets(length_m):
		lanes.append(axis_center_m + offset)
	return lanes


## 在两侧候选里择一：先取两侧交集，交集为空则退回本侧候选；
## 再从中选最接近 desired_axis 的一个。等距时保留先出现的候选。
static func pick_shared(
	a_lanes: Array[float], b_lanes: Array[float], desired_axis: float
) -> float:
	if a_lanes.is_empty():
		return desired_axis
	var shared: Array[float] = []
	for lane in a_lanes:
		for b_lane in b_lanes:
			if is_equal_approx(lane, b_lane):
				shared.append(lane)
				break
	var candidates := shared if not shared.is_empty() else a_lanes
	var best := float(candidates[0])
	for candidate in candidates:
		if absf(float(candidate) - desired_axis) < absf(best - desired_axis):
			best = float(candidate)
	return best


## 两个同轴房间之间共享门槽的世界坐标。
## b_lanes 为空（对端不可解析）时，语义等同"只在本侧候选里选"。
static func resolve_shared_world_lane(
	a_axis_center_m: float,
	a_length_m: float,
	b_axis_center_m: float,
	b_length_m: float,
	desired_axis: float
) -> float:
	return pick_shared(
		world_candidates(a_axis_center_m, a_length_m),
		world_candidates(b_axis_center_m, b_length_m),
		desired_axis
	)


## 一对同轴邻房之间共享门槽的推导结果。
##
## 这是「父子房几何 → 门槽」的唯一实现：白盒导出工具、设计源加载器、关卡校验器
## 必须共用本函数，禁止各自复刻（历史病根见类头注释）。
## 返回键：a_side / a_lane / a_wall_length / b_side / b_lane / b_wall_length / world_lane。
## 坐标语义：a_lane / b_lane 是**相对各自墙中心线**的偏移，world_lane 是绝对坐标。
static func port_pair(
	a_center: Vector2, a_size: Vector2, b_center: Vector2, b_size: Vector2
) -> Dictionary:
	var delta := b_center - a_center
	var along_x := absf(delta.x) >= absf(delta.y)
	var a_side := ""
	var b_side := ""
	var a_length := 0.0
	var b_length := 0.0
	var a_axis := 0.0
	var b_axis := 0.0
	if along_x:
		a_side = "east" if delta.x >= 0.0 else "west"
		b_side = "west" if delta.x >= 0.0 else "east"
		a_length = a_size.y
		b_length = b_size.y
		a_axis = a_center.y
		b_axis = b_center.y
	else:
		# 南北约定必须与运行时一致：planar +y 对应世界 +z，即"南"。
		# FloorPlanGenerator._stair_reservation_rect() 用 "north": Vector2.UP(-y)，
		# TowerDescent3D._direction_between() 用 z 减小为 north —— 两者同向。
		# 本处原写作 delta.y >= 0 → "north"，与上述两处相反，属 S1 导出工具的
		# 既有缺陷（当时无消费者故未暴露）；提为唯一实现时一并修正。
		a_side = "north" if delta.y < 0.0 else "south"
		b_side = "south" if delta.y < 0.0 else "north"
		a_length = a_size.x
		b_length = b_size.x
		a_axis = a_center.x
		b_axis = b_center.x
	var world_lane := resolve_shared_world_lane(
		a_axis, a_length, b_axis, b_length, (a_axis + b_axis) * 0.5
	)
	return {
		"a_side": a_side,
		"a_lane": world_lane - a_axis,
		"a_wall_length": a_length,
		"b_side": b_side,
		"b_lane": world_lane - b_axis,
		"b_wall_length": b_length,
		"world_lane": world_lane,
	}


## 两房中心沿主轴方向的净距，已扣除两端半尺寸（即走廊长度）。
## 非主轴方向的分量不参与计算 —— 同轴性由 lateral_offset() 单独把关。
static func corridor_clear(
	a_center: Vector2, a_size: Vector2, b_center: Vector2, b_size: Vector2
) -> float:
	var delta := b_center - a_center
	var along_x := absf(delta.x) >= absf(delta.y)
	if along_x:
		return maxf(0.0, absf(delta.x) - (a_size.x + b_size.x) * 0.5)
	return maxf(0.0, absf(delta.y) - (a_size.y + b_size.y) * 0.5)


## 两房中心的横向偏移（非主轴方向的分量）。> LATERAL_TOLERANCE_M 即不共轴。
static func lateral_offset(a_center: Vector2, b_center: Vector2) -> float:
	var delta := (b_center - a_center).abs()
	return delta.y if delta.x >= delta.y else delta.x


## 门槽校验：返回错误列表（空数组 = 通过）。
static func validate_port_lane(length_m: float, lane_offset_m: float, tolerance := 0.001) -> Array[String]:
	var errors: Array[String] = []
	var offsets := lane_offsets(length_m)
	var matched := false
	for offset in offsets:
		if absf(offset - lane_offset_m) <= tolerance:
			matched = true
			break
	if not matched:
		errors.append(
			"lane %s is not a legal slot on a %sm wall; legal=%s"
			% [str(lane_offset_m), str(length_m), str(offsets)]
		)
	return errors
