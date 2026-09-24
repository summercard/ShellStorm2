class_name RoomShellLayoutBuilder3D
extends RefCounted
## 5m 通用壳体组合器 —— 由「房间尺寸 + 门位 + 邻接」推出 5 类通用件的**区块级**实例清单。
##
## 纯计算：不碰场景树、不读盘、不留状态。**区块级不是逐房** —— 相邻房间墙贴墙时，
## 同一道墙平面上的同一个 lane 只能出一个实例，否则共面墙会重叠两套（几何与碰撞都翻倍）。
## 语义与区块00 摆位源 `placement_model` 逐字一致：
##   「关卡拆成 x/y 常数墙平面，按 5m 切 lane；房间声明所需 lane，L 角件臂各占 1 lane；
##     同一 lane 全局只放一个实例，被 L 臂占用则不放墙。结构上排除共面重叠与漏墙。」
## 两条链共用同一份实现，避免「生成器一套算法、摆位源又抄一遍」：
##   ① 运行时/生成器：FloorPlanGenerator 逐房产出 `authored_layout_instances`；
##   ② 设计期落盘：dump 脚本写 `shellstorm2.battle.room_instance_layout` 布局源。
##
## 组件 ID 一律用**跨区共用件名**（`ENV-SHARED-GENERIC-*`）。运行时由
## `DungeonRoom3D._authored_component_prefab()` 查注册表解析成 PackedScene；该注册表
## 同时把战区批次号登记成 alias，所以摆位源两侧写哪个都能命中同一件。
##
## —— 网格契约（与塔楼 5m 模数一致，别凭直觉写）——
## 房间四边必须落在 5m 格线上（bound 是 5 的整数倍）；lane 中心是**全局**的 `5k + 2.5`，
## lane_key = k。于是房间在某轴上的 lane key 范围 = `[min/5, max/5 − 1]`，
## 与房间落位无关 —— 奇偶格宽（15/25/45 与 50/60/70）**共用同一条公式**，
## 不要分别特判（特判就会在换尺寸时静默错半个 lane）。
##
## —— 三条按顺序执行、顺序不能换的全局规则（换一次就静默错一面墙）——
##  ① **共角去重在前**：同一格点上的四角 L 件全局只留一件（先声明者拥有），
##     被顶掉的角件记进 `corners_dropped`。**被顶掉的角件不预留 lane** ——
##     它的臂根本不存在（区块00 办公室 NE 被会议室 NW 顶掉后，
##     办公室北墙 x=−27.5 那道臂位就空出来放了实墙）。
##  ② **L 臂 lane 预留居中**：只按**留下的**角件预留。每个角件占 2 个 lane，
##     各是「紧邻角点的那一个」（角点 ±2.5）；被臂占掉的 lane 谁都不能放墙。
##     邻房的臂也会占掉本房的 lane（区块00 走廊西墙 y=−2.5 / 7.5 两个 lane 无墙，
##     因为那两段是会议室 SE / NE 的臂）。
##  ③ **共面 lane 归属在后**：同一 `(常量轴, 常量坐标, lane_key)` 全局只出一个实例，
##     先声明者拥有；任一侧声明了门/出口则该 lane 是门洞（覆盖实墙）。
## 地砖按 `(i + j) % 2` 交替取 c01 / c02（棋盘格），与区块00 摆位源 49 块里
## c01=25 / c02=24 的实测计数一致。命名 `R` = y 索引 + 1、`C` = x 索引 + 1（行 / 列）。
##
## —— 坐标契约（照搬 Block00MasterOfficeLayout3D，别重新推导）——
## Blender Z-up：X = 东、Y = 北、**南 = −Y**；`world.x = bx`、`world.z = −by`、
## `rotation.y = rotation_z_deg`（同号）。`position_m` 直接给 Blender 世界坐标，运行时只做
## `local = (bx − cx, y, −(by − cy))` —— 见 `to_runtime_instances()`。
## 边界命名：south = bounds_y 小端、north = 大端、west = bounds_x 小端、east = 大端。

const GRID_UNIT_M := 5.0
## 门位与 lane 中心的容差。门位必须**正好落在某个可用 lane 中心**上，否则报错。
const DOOR_OFFSET_TOLERANCE_M := 0.01

## 摆位源 rotation_z_deg → 世界门向，与 DungeonRoom3D._authored_wall_direction() 互逆。
const FACE_IN_ROTATION_DEG := {"south": 0.0, "north": 180.0, "west": -90.0, "east": 90.0}
## L 角件：原点 = 角点、两臂沿 +X / +Y 各 5m。与 _spawn_room_corner() 的 rotation 表同源。
const CORNER_ROTATION_DEG := {"SW": 0.0, "SE": 90.0, "NE": 180.0, "NW": -90.0}
const CORNER_IDS: Array[String] = ["SW", "SE", "NE", "NW"]
const SIDE_ORDER: Array[String] = ["south", "north", "west", "east"]

const COMPONENT_CORNER_L := "ENV-SHARED-GENERIC-CORNER-L-5M"
const COMPONENT_WALL_STANDARD := "ENV-SHARED-GENERIC-WALL-STANDARD-5M"
const COMPONENT_WALL_DOOR := "ENV-SHARED-GENERIC-WALL-DOOR-5M"
const COMPONENT_DOOR := "ENV-SHARED-GENERIC-DOOR-5M"
const COMPONENT_FLOOR_TILE_C01 := "ENV-SHARED-GENERIC-FLOOR-TILE-R01-C01"
const COMPONENT_FLOOR_TILE_C02 := "ENV-SHARED-GENERIC-FLOOR-TILE-R01-C02"

const SLOT_ROLE_CORNER_L := "corner_l"
const SLOT_ROLE_SOLID_WALL := "solid_wall"
const SLOT_ROLE_DOOR_WALL := "door_wall"
const SLOT_ROLE_DOOR_LEAF_PREVIEW := "door_leaf_preview"
const SLOT_ROLE_FLOOR_TILE := "floor_tile"

## 摆位源的 `package` 字段（= 组件包名，与 asset_ids 的键对应）。运行时只认
## `component_id`，`package` 是给设计期与账本读的。
const PACKAGE_CORNER_L := "runtime_v001"
const PACKAGE_WALL_STANDARD := "wall_standard_5m_通用包"
const PACKAGE_WALL_DOOR := "wall_door_5m_通用包"
const PACKAGE_DOOR := "door_5m_通用包"
const PACKAGE_FLOOR_TILE_C01 := "floor_tile_r01_c01_通用包"
const PACKAGE_FLOOR_TILE_C02 := "floor_tile_r01_c02_通用包"

const CORNER_NOTE := "原点=角点，两臂沿 +X/+Y 各 5m"
const FLOOR_TILE_NOTE := "相邻砖用两种砖面交替，避免大面积同花纹"
const DOOR_LEAF_NOTE := "editor-only 预览；运行时由 RoomDoor3D 生成唯一门扇"


## 全局 lane 网格：中心 `5k + 2.5` ⇄ key `k`。
static func lane_key_of(center_m: float) -> int:
	return int(round(center_m / GRID_UNIT_M - 0.5))


static func lane_center_of(lane_key: int) -> float:
	return GRID_UNIT_M * (float(lane_key) + 0.5)


## 某轴上一段区间占据的 lane key 列表（区间端点必须落在 5m 格线上）。
static func edge_lane_keys(min_m: float, max_m: float) -> Array[int]:
	var keys: Array[int] = []
	var count := int(round((max_m - min_m) / GRID_UNIT_M))
	if count <= 0:
		return keys
	var first := lane_key_of(min_m + GRID_UNIT_M * 0.5)
	for offset in range(count):
		keys.append(first + offset)
	return keys


## 边长 → 每边 lane 数（非 5 的整数倍会被 build_block() 判错，这里不静默取整）。
static func grid_lanes(size_m: Vector2) -> Vector2i:
	return Vector2i(int(round(size_m.x / GRID_UNIT_M)), int(round(size_m.y / GRID_UNIT_M)))


## 某方向跨度占的 lane 数（偶数格宽落 5k、奇数格宽落 5k+2.5，公式同一条）。
static func lane_count_for(span_m: float) -> int:
	return int(round(span_m / GRID_UNIT_M))


## 组合一个区块的壳体。`rooms` 按**声明顺序**给出，顺序决定共面 lane 与共点角件的归属
## （先声明者拥有；见 `_lane_key_str()` 与 `_corner_point_key()`）。
##
## 每个房间：
## {
##   "room_id": String,                    # 唯一，用于 instance_id 与归属记录
##   "bounds_x_m": [x_min, x_max],         # Blender 世界坐标，落在 5m 格线上
##   "bounds_y_m": [y_min, y_max],         # 同上（south = 小端）
##   "doors": {side: offset_m},            # 有门扇的门；offset 是**沿该边轴的绝对坐标**
##   "exits": {side: offset_m},            # 只留门洞、不挂门扇（区块00 的 entry/exit）
##   "use_corner_l": bool,                 # 默认 true；单 lane 宽的窄房应置 false
## }
##
## 返回：
## {
##   "rooms": [ {room_id, bounds_*, size_m, lanes_x, lanes_y, lane_key_*_min,
##              use_corner_l, doors, exits} ],
##   "corners": [ {room_id, corner_id, point_m, rotation_z_deg} ],
##   "corners_dropped": [ {room_id, corner_id, point_m, provided_by} ],
##   "wall_lanes": [ {axis, line_m, lane_key, center_m, role, owner_room,
##                    rotation_z_deg, claims} ],
##   "instances": [ 摆位源 instance 形状的字典 ],
##   "validation": {room_owned_geometry, non_unit_scale_count, illegal_rotation_count,
##                  missing_components, slot_role_counts},
##   "slot_role_counts": {role: n},
##   "errors": [String],
## }
static func build_block(rooms: Array) -> Dictionary:
	var result := {
		"rooms": [],
		"corners": [],
		"corners_dropped": [],
		"wall_lanes": [],
		"instances": [],
		"validation": {},
		"slot_role_counts": {},
		"errors": [],
	}
	var errors: Array[String] = []
	var normalized: Array = []
	var seen_ids: Array[String] = []
	for value in rooms:
		if not (value is Dictionary):
			errors.append("room_not_dictionary")
			continue
		var room := _normalize_room(value as Dictionary, errors)
		if room.is_empty():
			continue
		var room_id := str(room["room_id"])
		if room_id in seen_ids:
			errors.append("duplicate_room_id:%s" % room_id)
			continue
		seen_ids.append(room_id)
		normalized.append(room)
	if normalized.is_empty():
		result["errors"] = errors
		return result

	# ① 共角去重（先于任何预留）：同一格点全局只留一件，先声明者拥有。
	var corner_records := _corner_records(normalized)
	var corner_owner: Dictionary = {}
	var kept_corners: Array = []
	var dropped_corners: Array = []
	for value in corner_records:
		var record := value as Dictionary
		var point_key := _corner_point_key(record)
		if corner_owner.has(point_key):
			var owner := corner_owner[point_key] as Dictionary
			dropped_corners.append({
				"room_id": str(record["room_id"]),
				"corner_id": str(record["corner_id"]),
				"point_m": [float(record["point_x"]), float(record["point_y"])],
				"provided_by": "%s.%s" % [
					str(owner["room_id"]), str(owner["corner_id"])
				],
			})
			continue
		corner_owner[point_key] = record
		kept_corners.append(record)

	# ② 只按**留下的**角件预留两条臂的 lane。
	var corner_reservations: Dictionary = {}
	for value in kept_corners:
		var record := value as Dictionary
		var owner_label := "%s.%s" % [str(record["room_id"]), str(record["corner_id"])]
		for arm_value in record["arms"]:
			var arm := arm_value as Dictionary
			var lane_str := _lane_key_str(
				str(arm["axis"]), float(arm["line_m"]), int(arm["lane_key"])
			)
			if not corner_reservations.has(lane_str):
				corner_reservations[lane_str] = owner_label

	# ③ 逐房逐边声明 lane 归属（含门/出口标记），全局按 lane 合并去重。
	var lane_claims: Dictionary = {}
	for room in normalized:
		var room_id := str(room["room_id"])
		var doors: Dictionary = room["doors"]
		var exits: Dictionary = room["exits"]
		for side in SIDE_ORDER:
			var edge := edge_geometry(side, room)
			var line_m := float(edge["line_m"])
			var keys := edge_lane_keys(float(edge["span_min_m"]), float(edge["span_max_m"]))
			var door_offset: Variant = doors.get(side, null)
			var exit_offset: Variant = exits.get(side, null)
			var door_found := false
			var exit_found := false
			for lane_key in keys:
				var center := lane_center_of(lane_key)
				var lane_str := _lane_key_str(str(edge["axis"]), line_m, lane_key)
				var is_door := (
					door_offset != null
					and absf(center - float(door_offset)) <= DOOR_OFFSET_TOLERANCE_M
				)
				var is_exit := (
					exit_offset != null
					and absf(center - float(exit_offset)) <= DOOR_OFFSET_TOLERANCE_M
				)
				if is_door:
					door_found = true
				if is_exit:
					exit_found = true
				if corner_reservations.has(lane_str):
					# 该 lane 已被某件 L 臂占满。若本房在这里声明了门，就是「门开在 L 臂下」。
					if is_door or is_exit:
						errors.append("door_under_corner_arm:%s.%s@lane=%d by %s" % [
							room_id, side, lane_key, str(corner_reservations[lane_str])
						])
					continue
				var role := "solid"
				if is_door:
					role = "door"
				elif is_exit:
					role = "exit"
				if not lane_claims.has(lane_str):
					lane_claims[lane_str] = {
						"axis": str(edge["axis"]),
						"line_m": line_m,
						"lane_key": lane_key,
						"center_m": center,
						"role": role,
						"owner_room": room_id,
						"rotation_z_deg": float(FACE_IN_ROTATION_DEG[side]),
						"sides": [side],
						"rooms": [room_id],
					}
					continue
				var record := lane_claims[lane_str] as Dictionary
				# 先声明者保留 owner；门/出口优先于实墙（共享墙任一侧有门即开门洞）。
				if role in ["door", "exit"] and str(record["role"]) == "solid":
					record["role"] = role
				var rooms_list: Array = record["rooms"]
				if room_id not in rooms_list:
					rooms_list.append(room_id)
				var sides_list: Array = record["sides"]
				if side not in sides_list:
					sides_list.append(side)
			if door_offset != null and not door_found:
				errors.append("door_offset_off_lane:%s.%s=%s" % [room_id, side, str(door_offset)])
			if exit_offset != null and not exit_found:
				errors.append("exit_offset_off_lane:%s.%s=%s" % [room_id, side, str(exit_offset)])

	# ④ 出实例。
	var instances: Array = []
	for value in kept_corners:
		var record := value as Dictionary
		var room_id := str(record["room_id"])
		var corner_id := str(record["corner_id"])
		instances.append({
			"instance_id": "CORNER_%s_%s" % [room_id.to_upper(), corner_id],
			"package": PACKAGE_CORNER_L,
			"position_m": [float(record["point_x"]), float(record["point_y"]), 0.0],
			"rotation_z_deg": float(record["rotation_z_deg"]),
			"scale": [1.0, 1.0, 1.0],
			"enabled": true,
			"component_id": COMPONENT_CORNER_L,
			"slot_role": SLOT_ROLE_CORNER_L,
			"room_id": room_id,
			"corner_id": corner_id,
			"note": CORNER_NOTE,
		})
	var wall_lanes: Array = []
	var ordered_lanes: Array = lane_claims.values()
	ordered_lanes.sort_custom(_lane_sort_less)
	for record_value in ordered_lanes:
		var record := record_value as Dictionary
		var role := str(record["role"])
		var is_door := role in ["door", "exit"]
		var center := float(record["center_m"])
		var line_m := float(record["line_m"])
		var side := str((record["sides"] as Array)[0])
		var token := _wall_instance_token(str(record["axis"]), side, line_m, center)
		var rooms_list := (record["rooms"] as Array).duplicate()
		rooms_list.sort()
		var shared := ""
		for index in range(rooms_list.size()):
			if index > 0:
				shared += ","
			shared += str(rooms_list[index])
		var claims: Array = []
		for room_value in record["rooms"]:
			var claim_side := _side_for_room(str(record["axis"]), line_m, str(room_value), normalized)
			claims.append("%s.%s" % [str(room_value), claim_side])
		wall_lanes.append({
			"axis": str(record["axis"]),
			"line_m": line_m,
			"lane_key": int(record["lane_key"]),
			"center_m": center,
			"role": role,
			"owner_room": str(record["owner_room"]),
			"rotation_z_deg": float(record["rotation_z_deg"]),
			"claims": claims,
		})
		instances.append({
			"instance_id": "%s_%s" % [("DOORWALL" if is_door else "WALL"), token],
			"package": PACKAGE_WALL_DOOR if is_door else PACKAGE_WALL_STANDARD,
			"position_m": _lane_point_m(str(record["axis"]), line_m, center),
			"rotation_z_deg": float(record["rotation_z_deg"]),
			"scale": [1.0, 1.0, 1.0],
			"enabled": true,
			"component_id": COMPONENT_WALL_DOOR if is_door else COMPONENT_WALL_STANDARD,
			"slot_role": SLOT_ROLE_DOOR_WALL if is_door else SLOT_ROLE_SOLID_WALL,
			"room_id": str(record["owner_room"]),
			"side": side,
			"lane_key": int(record["lane_key"]),
			"claims": claims,
			"shared_with": shared,
		})
		if role == "door":
			instances.append({
				"instance_id": "DOORLEAF_%s" % token,
				"package": PACKAGE_DOOR,
				"position_m": _lane_point_m(str(record["axis"]), line_m, center),
				"rotation_z_deg": float(record["rotation_z_deg"]),
				"scale": [1.0, 1.0, 1.0],
				"enabled": true,
				"component_id": COMPONENT_DOOR,
				"slot_role": SLOT_ROLE_DOOR_LEAF_PREVIEW,
				"room_id": str(record["owner_room"]),
				"side": side,
				"lane_key": int(record["lane_key"]),
				"note": DOOR_LEAF_NOTE,
			})
	for room in normalized:
		var room_id := str(room["room_id"])
		for i in range(int(room["lanes_x"])):
			for j in range(int(room["lanes_y"])):
				var is_c01 := (i + j) % 2 == 0
				instances.append({
					"instance_id": "FLOOR_%s_R%02d_C%02d" % [room_id.to_upper(), j + 1, i + 1],
					"package": PACKAGE_FLOOR_TILE_C01 if is_c01 else PACKAGE_FLOOR_TILE_C02,
					"position_m": [
						lane_center_of(int(room["lane_key_x_min"]) + i),
						lane_center_of(int(room["lane_key_y_min"]) + j),
						0.0,
					],
					"rotation_z_deg": 0.0,
					"scale": [1.0, 1.0, 1.0],
					"enabled": true,
					"component_id": (
						COMPONENT_FLOOR_TILE_C01 if is_c01 else COMPONENT_FLOOR_TILE_C02
					),
					"slot_role": SLOT_ROLE_FLOOR_TILE,
					"room_id": room_id,
					"grid": [i, j],
					"note": FLOOR_TILE_NOTE,
				})

	result["rooms"] = normalized
	# 对外形状：角件只暴露 point_m / rotation_z_deg（内部记录里的 point_x/point_y 不外泄）。
	var public_corners: Array = []
	for value in kept_corners:
		var record := value as Dictionary
		public_corners.append({
			"room_id": str(record["room_id"]),
			"corner_id": str(record["corner_id"]),
			"point_m": [float(record["point_x"]), float(record["point_y"])],
			"rotation_z_deg": float(record["rotation_z_deg"]),
		})
	result["corners"] = public_corners
	result["corners_dropped"] = dropped_corners
	result["wall_lanes"] = wall_lanes
	result["instances"] = instances
	result["slot_role_counts"] = count_slot_roles(instances)
	result["validation"] = {
		"room_owned_geometry": false,
		"non_unit_scale_count": 0,
		"illegal_rotation_count": 0,
		"missing_components": [],
		"slot_role_counts": count_slot_roles(instances),
	}
	result["errors"] = errors
	return result


## 逐 slot_role 计数（反假绿基线的唯一来源）。
static func count_slot_roles(instances: Array) -> Dictionary:
	var counts: Dictionary = {}
	for value in instances:
		var instance := value as Dictionary
		var role := str(instance.get("slot_role", ""))
		counts[role] = int(counts.get(role, 0)) + 1
	return counts


## 摆位源 instance（Blender 世界坐标）→ 运行时实例字典（房间局部）。
## 与 `Block00MasterOfficeLayout3D.room_shell_instances()` 同一口径：
## `world.x = bx`、`world.z = −by` ⇒ 房间局部 `(bx − cx, 0, −(by − cy))`，rotation 同号。
## 只导出本房拥有的实例（摆位源里同一 lane 只归一个房间，所以不会重复也不会漏）。
static func to_runtime_instances(
	instances: Array, room_id: String, center_bx: float, center_by: float
) -> Array:
	var result: Array = []
	for value in instances:
		var instance := value as Dictionary
		if str(instance.get("room_id", "")) != room_id:
			continue
		var position_m := instance.get("position_m", []) as Array
		if position_m.size() < 2:
			continue
		result.append({
			"name": str(instance.get("instance_id", "")),
			"component_id": str(instance.get("component_id", "")),
			"slot_role": str(instance.get("slot_role", "")),
			"corner_id": str(instance.get("corner_id", "")),
			"position": Vector3(
				float(position_m[0]) - center_bx,
				0.0,
				-(float(position_m[1]) - center_by)
			),
			"rotation_y_deg": float(instance.get("rotation_z_deg", 0.0)),
		})
	return result


## 某条边的几何：常量轴、常量坐标、沿边区间、朝向角。
## south/north ⇒ 平面 y = 常量、沿 x 铺；west/east ⇒ 平面 x = 常量、沿 y 铺。
static func edge_geometry(side: String, room: Dictionary) -> Dictionary:
	var x0 := float(room["bounds_x_m"][0])
	var x1 := float(room["bounds_x_m"][1])
	var y0 := float(room["bounds_y_m"][0])
	var y1 := float(room["bounds_y_m"][1])
	match side:
		"south":
			return {
				"axis": "y", "line_m": y0,
				"span_min_m": x0, "span_max_m": x1,
				"rotation_z_deg": float(FACE_IN_ROTATION_DEG["south"]),
			}
		"north":
			return {
				"axis": "y", "line_m": y1,
				"span_min_m": x0, "span_max_m": x1,
				"rotation_z_deg": float(FACE_IN_ROTATION_DEG["north"]),
			}
		"west":
			return {
				"axis": "x", "line_m": x0,
				"span_min_m": y0, "span_max_m": y1,
				"rotation_z_deg": float(FACE_IN_ROTATION_DEG["west"]),
			}
		_:
			return {
				"axis": "x", "line_m": x1,
				"span_min_m": y0, "span_max_m": y1,
				"rotation_z_deg": float(FACE_IN_ROTATION_DEG["east"]),
			}


## 每个（房间, 角位）一条记录，含它若成立会占掉的两条 lane。
static func _corner_records(rooms: Array) -> Array:
	var records: Array = []
	for room in rooms:
		if not bool(room["use_corner_l"]):
			continue
		var room_id := str(room["room_id"])
		for corner_id in CORNER_IDS:
			var sign_x := -1.0 if corner_id.ends_with("W") else 1.0
			var sign_y := -1.0 if corner_id.begins_with("S") else 1.0
			var point_x := (
				float(room["bounds_x_m"][0]) if sign_x < 0.0 else float(room["bounds_x_m"][1])
			)
			var point_y := (
				float(room["bounds_y_m"][0]) if sign_y < 0.0 else float(room["bounds_y_m"][1])
			)
			# 臂 1：平面 x = point_x，沿 y 朝房内，占「紧邻角点的那一个 lane」。
			var arm_y_key := lane_key_of(point_y - sign_y * GRID_UNIT_M * 0.5)
			# 臂 2：平面 y = point_y，沿 x 朝房内，占「紧邻角点的那一个 lane」。
			var arm_x_key := lane_key_of(point_x - sign_x * GRID_UNIT_M * 0.5)
			records.append({
				"room_id": room_id,
				"corner_id": corner_id,
				"point_x": point_x,
				"point_y": point_y,
				"rotation_z_deg": float(CORNER_ROTATION_DEG[corner_id]),
				"arms": [
					{"axis": "x", "line_m": point_x, "lane_key": arm_y_key},
					{"axis": "y", "line_m": point_y, "lane_key": arm_x_key},
				],
			})
	return records


## 摆位源墙/门墙事件的 position_m：常量轴取 line，另一轴取 lane 中心。
static func _lane_point_m(axis: String, line_m: float, center_m: float) -> Array:
	if axis == "x":
		return [line_m, center_m, 0.0]
	return [center_m, line_m, 0.0]


## instance_id 里的坐标 token，与区块00 摆位源逐字同形：
## `west` @x=−40、lane −2.5 ⇒ `west_xm40_m2.5`。
static func _wall_instance_token(
	axis: String, side: String, line_m: float, center_m: float
) -> String:
	var axis_char := "x" if axis == "x" else "y"
	return "%s_%s%s_%s" % [
		side,
		axis_char,
		_signed_number_token(line_m),
		_signed_number_token(center_m),
	]


static func _signed_number_token(value: float) -> String:
	var sign := "m" if value < 0.0 else "p"
	return "%s%s" % [sign, _number_token(absf(value))]


static func _number_token(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(int(roundf(value)))
	return str(value)


static func _lane_key_str(axis: String, line_m: float, lane_key: int) -> String:
	return "%s|%s|%d" % [axis, _number_token(line_m), lane_key]


static func _corner_point_key(record: Dictionary) -> String:
	return "%s|%s" % [
		_number_token(float(record["point_x"])), _number_token(float(record["point_y"]))
	]


## 共面 lane 的稳定排序：先常量轴，再常量坐标，再 lane key。
static func _lane_sort_less(a: Variant, b: Variant) -> bool:
	var left := a as Dictionary
	var right := b as Dictionary
	var left_axis := str(left["axis"])
	var right_axis := str(right["axis"])
	if left_axis != right_axis:
		return left_axis < right_axis
	if not is_equal_approx(float(left["line_m"]), float(right["line_m"])):
		return float(left["line_m"]) < float(right["line_m"])
	return int(left["lane_key"]) < int(right["lane_key"])


## 某房间在某个墙平面上的边名（用于 claims 记录）。
static func _side_for_room(axis: String, line_m: float, room_id: String, rooms: Array) -> String:
	for value in rooms:
		var room := value as Dictionary
		if str(room["room_id"]) != room_id:
			continue
		for side in SIDE_ORDER:
			var edge := edge_geometry(side, room)
			if (
				str(edge["axis"]) == axis
				and is_equal_approx(float(edge["line_m"]), line_m)
			):
				return side
	return ""


static func _normalize_room(room: Dictionary, errors: Array[String]) -> Dictionary:
	var room_id := str(room.get("room_id", ""))
	if room_id.is_empty():
		errors.append("room_without_id")
		return {}
	var bounds_x := room.get("bounds_x_m", []) as Array
	var bounds_y := room.get("bounds_y_m", []) as Array
	if bounds_x.size() < 2 or bounds_y.size() < 2:
		errors.append("room_missing_bounds:%s" % room_id)
		return {}
	var x0 := minf(float(bounds_x[0]), float(bounds_x[1]))
	var x1 := maxf(float(bounds_x[0]), float(bounds_x[1]))
	var y0 := minf(float(bounds_y[0]), float(bounds_y[1]))
	var y1 := maxf(float(bounds_y[0]), float(bounds_y[1]))
	for axis in ["x", "y"]:
		var low := x0 if axis == "x" else y0
		var high := x1 if axis == "x" else y1
		for coordinate in [low, high]:
			if not is_zero_approx(fmod(absf(coordinate), GRID_UNIT_M)):
				errors.append("room_bound_off_grid:%s:%s=%s" % [room_id, axis, str(coordinate)])
	var lanes_x := lane_count_for(x1 - x0)
	var lanes_y := lane_count_for(y1 - y0)
	if lanes_x <= 0 or lanes_y <= 0:
		errors.append("room_zero_lanes:%s" % room_id)
		return {}
	var doors: Dictionary = room.get("doors", {})
	var exits: Dictionary = room.get("exits", {})
	for side_value in doors.keys():
		if str(side_value) not in FACE_IN_ROTATION_DEG:
			errors.append("unknown_door_side:%s.%s" % [room_id, str(side_value)])
	for side_value in exits.keys():
		if str(side_value) not in FACE_IN_ROTATION_DEG:
			errors.append("unknown_exit_side:%s.%s" % [room_id, str(side_value)])
	return {
		"room_id": room_id,
		"bounds_x_m": [x0, x1],
		"bounds_y_m": [y0, y1],
		"size_m": [x1 - x0, y1 - y0],
		"lanes_x": lanes_x,
		"lanes_y": lanes_y,
		"lane_key_x_min": lane_key_of(x0 + GRID_UNIT_M * 0.5),
		"lane_key_y_min": lane_key_of(y0 + GRID_UNIT_M * 0.5),
		"doors": doors.duplicate(),
		"exits": exits.duplicate(),
		"use_corner_l": bool(room.get("use_corner_l", true)),
	}
