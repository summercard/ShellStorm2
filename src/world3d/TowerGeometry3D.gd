class_name TowerGeometry3D
extends RefCounted
## 塔楼模块统一使用米制。门、楼道、平台和楼梯只能从这里读取净宽与位移，
## 避免局部函数各用一套数字造成接缝、重叠或不可通行。

const DOOR_CLEAR_WIDTH_M := 2.2
const DOOR_CLEAR_HEIGHT_M := 2.5
const GRID_UNIT_M := 5.0
const MAP_SIZE_M := 250.0
const CORE_SIZE_M := 65.0
# 50×50 偶数格整层与13×13奇数格核心无法同时以世界原点为格线中心；
# 核心平移半格后，65m边界、楼梯洞口与250m地砖边界重新严格对齐。
const CORE_CENTER_XZ := Vector2(2.5, 2.5)
const COMBAT_ROOM_SIZE_M := 30.0
const COMBAT_ROOM_SIZE_Y_M := 25.0
const COMBAT_ROOM_GRID := Vector2i(6, 5)
const ROOM_CORRIDOR_GAP_M := GRID_UNIT_M
const COMBAT_STAIR_LOBBY_SIZE_M := 15.0
const BOSS_ARENA_SIZE_M := 90.0
const COMBAT_GRID_CENTERS_M := [-77.5, -27.5, 27.5, 77.5]
const PASSAGE_WIDTH_M := 6.0
const APPROACH_OUTSET_M := 6.0
const RUN_LENGTH_M := 15.0
const LANE_GAP_M := 2.0
const LANE_CENTER_SPACING_M := PASSAGE_WIDTH_M + LANE_GAP_M
# Blender v006 两套楼梯共用的局部接口坐标。根节点位于上层门轴，
# local +X 指向核心外侧；导入 Godot 后 Blender local +Y 对应 local -Z。
const STAIR_UPPER_LANE_OFFSET_M := 11.501
const STAIR_LOWER_LANE_OFFSET_M := STAIR_UPPER_LANE_OFFSET_M - LANE_CENTER_SPACING_M
const STAIR_RUN_START_M := 3.1203
const STAIR_RUN_END_M := STAIR_RUN_START_M + RUN_LENGTH_M
const STAIR_TURN_CENTER_M := 21.0071
const STAIR_FOOTPRINT_SIZE_M := Vector2(15.0, 30.0)
const STAIR_FOOTPRINT_MIN_LOCAL_XZ_M := Vector2(0.0, -2.5)
const STAIR_FOOTPRINT_MAX_LOCAL_XZ_M := Vector2(15.0, 27.5)
const STAIR_LOWER_LANDING_RAISE_M := 0.1
const GUARD_HEIGHT_M := 1.2
const GUARD_END_CLEARANCE_M := 4.0
const FLOOR_THICKNESS_M := 0.30
const FLOOR_HEIGHT_M := 9.0
# 墙体逻辑/阻挡仍覆盖完整层高；视觉网格顶部留0.1m，避免与上层地板共面。
const WALL_LOGICAL_HEIGHT_M := 9.0
const WALL_VISUAL_HEIGHT_M := 8.9
const WALL_VISUAL_TOP_CLEARANCE_M := WALL_LOGICAL_HEIGHT_M - WALL_VISUAL_HEIGHT_M


static func snap_component_axis(center_m: float, size_m: float) -> float:
	# 组件边界落在 5m 格线上，奇数格组件中心自然落在半格，偶数格落在整格。
	return snappedf(center_m - size_m * 0.5, GRID_UNIT_M) + size_m * 0.5


static func is_component_axis_aligned(center_m: float, size_m: float) -> bool:
	return is_equal_approx(center_m, snap_component_axis(center_m, size_m))
