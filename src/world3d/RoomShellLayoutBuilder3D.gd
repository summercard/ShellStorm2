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
##     ①.5 **门让位于角件**（轮廓房新增）：L 件是 5m 实体件，若它的某条 arm lane 上
##     正好开门（门洞跨 [lane−2.5, lane+2.5]），两者物理重叠。**门位是运行时契约
##     （`derive_ports` → `_plan_room_layout`），不能动**，所以让**角件**整件让位：
##     记进 `corners_dropped`（`provided_by = "door_lane"`），不放 L 件。
##     判据是**全区块**的门/出口 lane（邻房的臂占掉本房门 lane 时同样让位）。
##     该角的两条墙随后由各自 lane 上的普通墙/门墙补齐（被顶掉的角件不预留 lane，
##     规则同 ①），角落不会留缺口 —— 只是门紧贴角落。
##  ② **L 臂 lane 预留居中**：只按**留下的**角件预留。每个角件占 2 个 lane，
##     各是「紧邻角点的那一个」（角点 ±2.5）；被臂占掉的 lane 谁都不能放墙。
##     邻房的臂也会占掉本房的 lane（区块00 走廊西墙 y=−2.5 / 7.5 两个 lane 无墙，
##     因为那两段是会议室 SE / NE 的臂）。
##  ③ **共面 lane 归属在后**：同一 `(常量轴, 常量坐标, lane_key)` 全局只出一个实例，
##     先声明者拥有；任一侧声明了门/出口则该 lane 是门洞（覆盖实墙）。
##     门/出口**只认该侧包围盒外边那一段**（见 `_room_port_lane_key_sets` 头注释）。
## 地砖按 `(i + j) % 2` 交替取 c01 / c02（棋盘格），与区块00 摆位源 49 块里
## c01=25 / c02=24 的实测计数一致。命名 `R` = y 索引 + 1、`C` = x 索引 + 1（行 / 列）。
##
## —— 坐标契约（照搬 Block00MasterOfficeLayout3D，别重新推导）——
## Blender Z-up：X = 东、Y = 北、**南 = −Y**；`world.x = bx`、`world.z = −by`、
## `rotation.y = rotation_z_deg`（同号）。`position_m` 直接给 Blender 世界坐标，运行时只做
## `local = (bx − cx, y, −(by − cy))` —— 见 `to_runtime_instances()`。
## 边界命名：south = bounds_y 小端、north = 大端、west = bounds_x 小端、east = 大端。
##
## —— 非矩形外轮廓（可选，2026-09-25 加）——
## 房间可带 `footprint_vertices_m`（模板 `variant_footprints.<variant>.vertices_m`），
## **口径是模板自有坐标系** `frame = "bbox_nw_x_east_y_south"`：
## 顶点以**包围盒西北角**为原点、x 向东为正、y 向**南**为正。换算到 Blender 世界：
##   `bx = bounds_x_m[0] + vx`、`by = bounds_y_m[1] − vy`
## 缺省（矩形房）= 包围盒本身。带轮廓时：
##   · **墙**：不再沿包围盒四边铺，而是沿多边形**边界**逐边铺 —— 凹口处的包围盒边
##     本来就不是房间边界（那里没有墙），凹口自身的两条边则新增为墙。
##   · **L 角件**：只放**凸角**（单象限占位）；凹角两侧的墙自然相接，不放 L 件
##     （通用件里没有内角件）。
##   · **地砖**：只铺**格心落在多边形内**的格子（凹口不铺砖）—— 与墙同源，
##     所以「墙跟着地面走」在矩形房上是恒等式，在轮廓房上才是有内容的约束。
## 三条全局规则、lane 归属模型、坐标换算全部**不变**；矩形房的输出逐字节不变
## （缺省轮廓的顶点序取 SW → SE → NE → NW，与旧 `_corner_records` 的迭代序一致）。

const GRID_UNIT_M := 5.0
## 门位与 lane 中心的容差。门位必须**正好落在某个可用 lane 中心**上，否则报错。
const DOOR_OFFSET_TOLERANCE_M := 0.01
## 外轮廓真源坐标系的唯一合法值（见头注释「非矩形外轮廓」）。
const FOOTPRINT_FRAME := "bbox_nw_x_east_y_south"
## 凸/凹判定与「房内在哪一侧」的探针距离。所有边界段都 ≥5m，1m 偏移恒落在严格内/外。
const PROBE_OFFSET_M := 1.0

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
##   "footprint_vertices_m": [[vx, vy]],   # 可选：非矩形外轮廓，模板坐标系（口径见头注释）
##   "footprint_frame": String,            # 可选：必须等于 FOOTPRINT_FRAME
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

	# ①.5 门让位于角件（轮廓房必须；矩形房无此情形则逐字节不变）：
	# 门位是运行时契约（`derive_ports` → `_plan_room_layout`），不能动；
	# L 件是 5m 实体件，臂与本房/邻房的门洞物理重叠 ⇒ 让**角件**整件让位。
	# 全局判据：角件任一条臂的 lane 落在**任一房**的门/出口 lane 上即 drop
	# （邻房的臂也会占掉本房的 lane，所以不能只看本房）。
	# 被顶掉的角件不预留 lane（规则同 ①），该 lane 由门墙/普墙照常补齐。
	var door_lane_keys := port_lane_key_set(normalized)
	var surviving_corners: Array = []
	for value in kept_corners:
		var record := value as Dictionary
		var conflicted := false
		for arm_value in record["arms"]:
			var arm := arm_value as Dictionary
			if door_lane_keys.has(_lane_key_str(
				str(arm["axis"]), float(arm["line_m"]), int(arm["lane_key"])
			)):
				conflicted = true
				break
		if not conflicted:
			surviving_corners.append(record)
			continue
		dropped_corners.append({
			"room_id": str(record["room_id"]),
			"corner_id": str(record["corner_id"]),
			"point_m": [float(record["point_x"]), float(record["point_y"])],
			"provided_by": "door_lane",
		})
	kept_corners = surviving_corners

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

	# ③ 逐房逐**轮廓边界段**声明 lane 归属（含门/出口标记），全局按 lane 合并去重。
	# 矩形房每条侧边恰好一段（与旧「四边」写法逐字节等价）；轮廓房可能一段、多段或零段
	# （零段 = 该侧整条包围盒边都在凹口里，本来就没有墙）。
	# 门位按**侧**判「有没有落上」（不是按段）：同一侧可能有多段，门落在其中一段上即合法。
	var lane_claims: Dictionary = {}
	for room in normalized:
		var room_id := str(room["room_id"])
		var edges_by_side: Dictionary = room["_boundary_edges_by_side"]
		# 门/出口的合法 lane **只认该侧包围盒外边段**（轮廓房同一侧可能有凹口段/内墙段，
		# 同一个门偏移会在多段上同时命中 ⇒ lane 被重复计入、共享墙翻倍）。
		# 凹口恒在包围盒内部 ⇒ 那里没有任何邻房 ⇒ 门落上去就是开向虚空，必须拒绝。
		var port_sets := _room_port_lane_key_sets(room)
		var door_lane_set: Dictionary = port_sets["door"]
		var exit_lane_set: Dictionary = port_sets["exit"]
		for side in SIDE_ORDER:
			var door_offset: Variant = room["doors"].get(side, null)
			var exit_offset: Variant = room["exits"].get(side, null)
			var door_found := false
			var exit_found := false
			for edge_value in edges_by_side.get(side, []):
				var edge := edge_value as Dictionary
				var line_m := float(edge["line_m"])
				var keys := edge_lane_keys(float(edge["span_min_m"]), float(edge["span_max_m"]))
				for lane_key in keys:
					var center := lane_center_of(lane_key)
					var lane_str := _lane_key_str(str(edge["axis"]), line_m, lane_key)
					var is_door := door_lane_set.has(lane_str)
					var is_exit := exit_lane_set.has(lane_str)
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
							"rotation_z_deg": float(edge["rotation_z_deg"]),
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
			# 门位必须落在本侧**某一段边界**的 lane 上。轮廓房里门位正好开在凹口上时，
			# 本侧一段都没扫到它 ⇒ door_found 仍是 false ⇒ 在这里报错，
			# 由调用方放弃接管（宁可不给轮廓壳，也不给一扇开在空处的门）。
			if door_offset != null and not door_found:
				errors.append("door_offset_off_lane:%s.%s=%s" % [room_id, side, str(door_offset)])
			if exit_offset != null and not exit_found:
				errors.append("exit_offset_off_lane:%s.%s=%s" % [room_id, side, str(exit_offset)])

	# ④ 出实例。
	var instances: Array = []
	var corner_id_uses: Dictionary = {}
	for value in kept_corners:
		var record := value as Dictionary
		var room_id := str(record["room_id"])
		var corner_id := str(record["corner_id"])
		# 轮廓房里同一房可能有两处凸角映射到同一个四向 id（如 L 形走廊的 SE 出现两次）：
		# 加后缀保 instance_id 唯一；矩形房恒不冲突 ⇒ id 逐字节不变。
		var base_id := "CORNER_%s_%s" % [room_id.to_upper(), corner_id]
		var instance_id := base_id
		var use_index := int(corner_id_uses.get(base_id, 0))
		corner_id_uses[base_id] = use_index + 1
		if use_index > 0:
			instance_id = "%s_%d" % [base_id, use_index + 1]
		instances.append({
			"instance_id": instance_id,
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
		var polygon: PackedVector2Array = room["footprint_m"]
		for i in range(int(room["lanes_x"])):
			for j in range(int(room["lanes_y"])):
				var cell_center := Vector2(
					lane_center_of(int(room["lane_key_x_min"]) + i),
					lane_center_of(int(room["lane_key_y_min"]) + j)
				)
				# 轮廓房：凹口不铺砖（格心落在多边形外）。矩形房恒为真 ⇒ 逐字节不变。
				if not point_in_polygon(cell_center, polygon):
					continue
				var is_c01 := (i + j) % 2 == 0
				instances.append({
					"instance_id": "FLOOR_%s_R%02d_C%02d" % [room_id.to_upper(), j + 1, i + 1],
					"package": PACKAGE_FLOOR_TILE_C01 if is_c01 else PACKAGE_FLOOR_TILE_C02,
					"position_m": [cell_center.x, cell_center.y, 0.0],
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


## 某侧**包围盒外边**所在的常量轴坐标（门/出口的唯一合法墙平面）。
## 矩形房四边就是这个值；轮廓房凹口段/内墙段的 line 不等于它。
static func _side_bound_line(room: Dictionary, side: String) -> float:
	var bounds_x := room["bounds_x_m"] as Array
	var bounds_y := room["bounds_y_m"] as Array
	match side:
		"south":
			return float(bounds_y[0])
		"north":
			return float(bounds_y[1])
		"west":
			return float(bounds_x[0])
		_:
			return float(bounds_x[1])


## 某房某侧的包围盒外边**边界段**；该侧外边整条都在凹口里时返回 `null`。
static func _bound_outer_edge(room: Dictionary, side: String) -> Variant:
	var line := _side_bound_line(room, side)
	var segments: Array = (room["_boundary_edges_by_side"] as Dictionary).get(side, [])
	for edge_value in segments:
		var edge := edge_value as Dictionary
		if is_equal_approx(float(edge["line_m"]), line):
			return edge
	return null


## 某房**包围盒外边段**上真正存在的门 / 出口 lane：
## `{"door": {lane_str: true}, "exit": {lane_str: true}}`。
## 这是「门/出口合法落点」的**唯一判据**，build_block() 与生成器的轮廓兼容性检查共用它。
##
## 为什么只认包围盒外边段：轮廓房的凹口**恒在包围盒内部**，而房间按包围盒摆放、
## 互不重叠 ⇒ 凹口区域里不可能有邻房、也不可能在别的房间内部 ⇒ 恒为空洞。
## 门落在凹口段（或凹口对面的内墙段）上就是开向虚空。同一侧多条平行段上
## 同一个门偏移会同时命中 ⇒ lane 被重复计入、共享墙翻倍（实测 14 件门墙 vs 12 条边）。
static func _room_port_lane_key_sets(room: Dictionary) -> Dictionary:
	var sets := {"door": {}, "exit": {}}
	for side in SIDE_ORDER:
		var edge_value: Variant = _bound_outer_edge(room, side)
		if edge_value == null:
			continue
		var edge := edge_value as Dictionary
		for kind in ["door", "exit"]:
			var offset: Variant = (room["%ss" % kind] as Dictionary).get(side, null)
			if offset == null:
				continue
			var lane_keys := edge_lane_keys(float(edge["span_min_m"]), float(edge["span_max_m"]))
			for lane_key in lane_keys:
				if absf(lane_center_of(lane_key) - float(offset)) <= DOOR_OFFSET_TOLERANCE_M:
					(sets[kind] as Dictionary)[_lane_key_str(
						str(edge["axis"]), float(edge["line_m"]), lane_key
					)] = true
	return sets


## 全区块的门/出口 lane 集合（`lane_str → true`）。「①.5 门让位于角件」的判据，
## 以及生成器「轮廓与门位是否兼容」的判据，都取自它。
static func port_lane_key_set(rooms: Array) -> Dictionary:
	var keys: Dictionary = {}
	for value in rooms:
		if not (value is Dictionary):
			continue
		var sets := _room_port_lane_key_sets(value as Dictionary)
		for kind in ["door", "exit"]:
			for lane_key in (sets[kind] as Dictionary).keys():
				keys[lane_key] = true
	return keys


## 该外轮廓能否承接这些门 / 出口（生成器侧判据：不兼容就换变体 / 退矩形）。
##
## `true` 的条件与 `build_block()` 完全同源 —— 每个有门/出口的侧，其偏移都必须落在
## 该侧**包围盒外边段**上某个 lane 的中心（同一条 lane 公式、同一个容差）。
## 轮廓非法（越界 / 不在 5m 格线 / 自交）时同样返回 `false`。
##
## 为什么由生成器先筛、而不是让 build_block() 报错：一处不兼容会让**整层**放弃接管
## （回到程序化壳体），那是把局部冲突放大成全图回退。生成器有模板池，可以换个变体。
static func footprint_accepts_ports(
	footprint_vertices_m: Array,
	footprint_frame: String,
	bounds_x_m: Array,
	bounds_y_m: Array,
	doors: Dictionary,
	exits: Dictionary
) -> bool:
	var errors: Array[String] = []
	var x0 := minf(float(bounds_x_m[0]), float(bounds_x_m[1]))
	var x1 := maxf(float(bounds_x_m[0]), float(bounds_x_m[1]))
	var y0 := minf(float(bounds_y_m[0]), float(bounds_y_m[1]))
	var y1 := maxf(float(bounds_y_m[0]), float(bounds_y_m[1]))
	var polygon := normalize_footprint(
		{
			"footprint_vertices_m": footprint_vertices_m,
			"footprint_frame": footprint_frame,
		},
		x0, x1, y0, y1, "footprint_probe", errors
	)
	if polygon.is_empty():
		return false
	var probe_room := {
		"bounds_x_m": [x0, x1],
		"bounds_y_m": [y0, y1],
		"doors": doors,
		"exits": exits,
		"_boundary_edges_by_side": boundary_edges(polygon),
	}
	for kind in ["door", "exit"]:
		for side in (probe_room["%ss" % kind] as Dictionary).keys():
			if not _side_has_port_lane(probe_room, kind, str(side)):
				return false
	return true


## 该侧的门（或出口）是否找到了合法 lane。
static func _side_has_port_lane(probe_room: Dictionary, kind: String, side: String) -> bool:
	var ports: Dictionary = probe_room["%ss" % kind]
	if not ports.has(side):
		return false
	var edge_value: Variant = _bound_outer_edge(probe_room, side)
	if edge_value == null:
		return false
	var offset := float(ports[side])
	var edge := edge_value as Dictionary
	for lane_key in edge_lane_keys(float(edge["span_min_m"]), float(edge["span_max_m"])):
		if absf(lane_center_of(lane_key) - offset) <= DOOR_OFFSET_TOLERANCE_M:
			return true
	return false


## —— 非矩形外轮廓的几何原语（纯函数，公开给探针独立复核）——

## 多边形有向面积（鞋带公式）。>0 = 逆时针（在 `bx` 东 / `by` 北 的右手系里）。
static func polygon_signed_area(polygon: PackedVector2Array) -> float:
	var total := 0.0
	var count := polygon.size()
	if count < 3:
		return 0.0
	for index in range(count):
		var a := polygon[index]
		var b := polygon[(index + 1) % count]
		total += a.x * b.y - b.x * a.y
	return total * 0.5


## 点在多边形内（奇偶射线法）。只用于**严格内/外**的探针点与格心，
## 边界上的点不在契约内（房界恒落格线，格心与探针都恒不在边界上）。
static func point_in_polygon(point: Vector2, polygon: PackedVector2Array) -> bool:
	var count := polygon.size()
	if count < 3:
		return false
	var inside := false
	var previous := count - 1
	for index in range(count):
		var a := polygon[index]
		var b := polygon[previous]
		if (a.y > point.y) != (b.y > point.y):
			var ratio := (point.y - a.y) / (b.y - a.y)
			if point.x < a.x + ratio * (b.x - a.x):
				inside = not inside
		previous = index
	return inside


## 多边形外轮廓 → 边界段，**按 SIDE_ORDER 分组的字典** `{side: [edge...]}`，
## 组内按 `span_min_m` 升序。每段：`{axis, line_m, span_min_m, span_max_m, side, rotation_z_deg}`。
##
## `side` 由「房内在墙的哪一侧」定出（探针法），**不是按包围盒猜**：
##   竖直段 x = X：房内在 +x ⇒ 该墙是房间的 west 侧；在 −x ⇒ east。
##   水平段 y = Y：房内在 +y ⇒ south；在 −y ⇒ north。
## 矩形房上这与旧 `edge_geometry()` 的四边口径逐字一致；轮廓房上凹口两侧的边
## 会被正确地判成「房间在凹口对面」，于是墙朝向也跟着对。
static func boundary_edges(polygon: PackedVector2Array) -> Dictionary:
	var by_side: Dictionary = {}
	for side in SIDE_ORDER:
		by_side[side] = []
	var count := polygon.size()
	for index in range(count):
		var a := polygon[index]
		var b := polygon[(index + 1) % count]
		var edge: Dictionary = {}
		var probe_minus: Vector2 = Vector2.ZERO
		var probe_plus: Vector2 = Vector2.ZERO
		if is_equal_approx(a.x, b.x):
			edge = {
				"axis": "x", "line_m": a.x,
				"span_min_m": minf(a.y, b.y), "span_max_m": maxf(a.y, b.y),
			}
			probe_minus = Vector2(a.x - PROBE_OFFSET_M, (a.y + b.y) * 0.5)
			probe_plus = Vector2(a.x + PROBE_OFFSET_M, (a.y + b.y) * 0.5)
		elif is_equal_approx(a.y, b.y):
			edge = {
				"axis": "y", "line_m": a.y,
				"span_min_m": minf(a.x, b.x), "span_max_m": maxf(a.x, b.x),
			}
			probe_minus = Vector2((a.x + b.x) * 0.5, a.y - PROBE_OFFSET_M)
			probe_plus = Vector2((a.x + b.x) * 0.5, a.y + PROBE_OFFSET_M)
		else:
			continue
		var side := ""
		if point_in_polygon(probe_minus, polygon):
			side = "east" if str(edge["axis"]) == "x" else "north"
		elif point_in_polygon(probe_plus, polygon):
			side = "west" if str(edge["axis"]) == "x" else "south"
		if side.is_empty():
			continue
		edge["side"] = side
		edge["rotation_z_deg"] = float(FACE_IN_ROTATION_DEG[side])
		(by_side[side] as Array).append(edge)
	for side in SIDE_ORDER:
		var segments := by_side[side] as Array
		segments.sort_custom(_boundary_edge_sort_less)
	return by_side


static func _boundary_edge_sort_less(a: Variant, b: Variant) -> bool:
	return float((a as Dictionary)["span_min_m"]) < float((b as Dictionary)["span_min_m"])


## 把 `{side: [edge...]}` 摊平成 SIDE_ORDER 顺序的列表（`_side_for_room` 用）。
static func flatten_boundary_edges(by_side: Dictionary) -> Array:
	var flat: Array = []
	for side in SIDE_ORDER:
		flat.append_array(by_side.get(side, []))
	return flat


## 显式外轮廓（模板坐标系）→ Blender 世界多边形；缺省 = 包围盒矩形。
## 校验不通过时 append 到 `errors` 并返回空 `PackedVector2Array` ⇒ `_normalize_room()`
## 返回空 ⇒ `build_block()` 报错 ⇒ 调用方放弃接管（不静默给半个壳）。
static func normalize_footprint(
	room: Dictionary, x0: float, x1: float, y0: float, y1: float,
	room_id: String, errors: Array[String]
) -> PackedVector2Array:
	var width := x1 - x0
	var depth := y1 - y0
	var polygon := PackedVector2Array()
	var raw: Variant = room.get("footprint_vertices_m", null)
	if raw == null:
		polygon.append(Vector2(x0, y0))
		polygon.append(Vector2(x1, y0))
		polygon.append(Vector2(x1, y1))
		polygon.append(Vector2(x0, y1))
		return polygon
	var frame := str(room.get("footprint_frame", FOOTPRINT_FRAME))
	if frame != FOOTPRINT_FRAME:
		errors.append("footprint_unknown_frame:%s:%s" % [room_id, frame])
		return PackedVector2Array()
	if not (raw is Array):
		errors.append("footprint_malformed:%s" % room_id)
		return PackedVector2Array()
	var vertices := raw as Array
	if vertices.size() < 4:
		errors.append("footprint_too_few_vertices:%s" % room_id)
		return PackedVector2Array()
	for index in range(vertices.size()):
		var pair_value: Variant = vertices[index]
		if not (pair_value is Array) or (pair_value as Array).size() != 2:
			errors.append("footprint_malformed:%s:%d" % [room_id, index])
			return PackedVector2Array()
		var pair := pair_value as Array
		var vx := float(pair[0])
		var vy := float(pair[1])
		if vx < -DOOR_OFFSET_TOLERANCE_M or vx > width + DOOR_OFFSET_TOLERANCE_M:
			errors.append("footprint_vertex_outside_bounds:%s:%d" % [room_id, index])
			return PackedVector2Array()
		if vy < -DOOR_OFFSET_TOLERANCE_M or vy > depth + DOOR_OFFSET_TOLERANCE_M:
			errors.append("footprint_vertex_outside_bounds:%s:%d" % [room_id, index])
			return PackedVector2Array()
		# 模板坐标系（y 向南）→ Blender 世界（X 东 / Y 北）：`bx = x0 + vx`、`by = y1 − vy`。
		var bx := x0 + vx
		var by := y1 - vy
		for coordinate in [bx, by]:
			if not is_zero_approx(fmod(absf(coordinate), GRID_UNIT_M)):
				errors.append("footprint_vertex_off_grid:%s:%d" % [room_id, index])
				return PackedVector2Array()
		polygon.append(Vector2(bx, by))
	if not _footprint_shape_valid(polygon, room_id, errors):
		return PackedVector2Array()
	return polygon


## 轴对齐 + 边不为零长 + 面积非零 + 不自交（含相触/捏点）。
static func _footprint_shape_valid(
	polygon: PackedVector2Array, room_id: String, errors: Array[String]
) -> bool:
	var count := polygon.size()
	for index in range(count):
		var a := polygon[index]
		var b := polygon[(index + 1) % count]
		if is_equal_approx(a.x, b.x) and is_equal_approx(a.y, b.y):
			errors.append("footprint_zero_length_edge:%s:%d" % [room_id, index])
			return false
		if not (is_equal_approx(a.x, b.x) or is_equal_approx(a.y, b.y)):
			errors.append("footprint_edge_not_axis_aligned:%s:%d" % [room_id, index])
			return false
	if is_zero_approx(polygon_signed_area(polygon)):
		errors.append("footprint_zero_area:%s" % room_id)
		return false
	for first in range(count):
		for second in range(first + 1, count):
			if (
				(second + 1) % count == first
				or (first + 1) % count == second
			):
				continue
			if _axis_aligned_segments_touch(
				polygon[first], polygon[(first + 1) % count],
				polygon[second], polygon[(second + 1) % count]
			):
				errors.append("footprint_self_intersection:%s:%d,%d" % [room_id, first, second])
				return false
	return true


## 轴对齐线段是否相触（AABB 相交判据在两个轴向上同时成立即相触）。
static func _axis_aligned_segments_touch(
	a1: Vector2, a2: Vector2, b1: Vector2, b2: Vector2
) -> bool:
	return (
		minf(a1.x, a2.x) <= maxf(b1.x, b2.x)
		and minf(b1.x, b2.x) <= maxf(a1.x, a2.x)
		and minf(a1.y, a2.y) <= maxf(b1.y, b2.y)
		and minf(b1.y, b2.y) <= maxf(a1.y, a2.y)
	)


## 每个（房间, **凸角**）一条记录，含它若成立会占掉的两条 lane。
## 轮廓房按多边形顶点迭代：顶点序即遍历序，矩形房的缺省轮廓顶点序取 SW → SE → NE → NW，
## 与旧实现（CORNER_IDS 表序）逐字节一致。
## 凹角**不出记录** —— 两条墙自身相接，不需要 L 件（通用件里没有内角件），
## 也不预留 lane（否则会误占邻房在同一个 lane 上的合法墙）。
static func _corner_records(rooms: Array) -> Array:
	var records: Array = []
	for room in rooms:
		if not bool(room["use_corner_l"]):
			continue
		var room_id := str(room["room_id"])
		var polygon: PackedVector2Array = room["footprint_m"]
		var count := polygon.size()
		var area_sign := signf(polygon_signed_area(polygon))
		for index in range(count):
			var previous := polygon[(index + count - 1) % count]
			var point := polygon[index]
			var following := polygon[(index + 1) % count]
			var e_in := point - previous
			var e_out := following - point
			if e_in.x * e_out.y - e_in.y * e_out.x == 0.0:
				continue
			# 房内在哪一个象限：**恰好一个**候选探针落在多边形内才是凸角。
			# 0 个象限 ⇒ 退化构型；**≥2 个象限 ⇒ 凹角**（内角 270°，三个象限在内）。
			# 两者都不放 L 件、也不预留 lane —— 通用件里没有内角件，硬放会得到
			# 一个朝向错误的 L 件，并且把凹口两侧的合法墙 lane 全部占掉。
			var inside_count := 0
			var dir_x := 0.0
			var dir_y := 0.0
			for sign_x in [-1.0, 1.0]:
				for sign_y in [-1.0, 1.0]:
					var probe := point + Vector2(sign_x, sign_y) * PROBE_OFFSET_M
					if point_in_polygon(probe, polygon):
						inside_count += 1
						dir_x = sign_x
						dir_y = sign_y
			if inside_count != 1:
				continue
			var corner_id := "SW"
			if dir_x < 0.0:
				corner_id = "SE" if dir_y > 0.0 else "NE"
			elif dir_y < 0.0:
				corner_id = "NW"
			# 臂 1：平面 x = point.x，沿 y 朝房内，占「紧邻角点的那一个 lane」。
			var arm_y_key := lane_key_of(point.y + dir_y * GRID_UNIT_M * 0.5)
			# 臂 2：平面 y = point.y，沿 x 朝房内，占「紧邻角点的那一个 lane」。
			var arm_x_key := lane_key_of(point.x + dir_x * GRID_UNIT_M * 0.5)
			records.append({
				"room_id": room_id,
				"corner_id": corner_id,
				"point_x": point.x,
				"point_y": point.y,
				"rotation_z_deg": float(CORNER_ROTATION_DEG[corner_id]),
				"arms": [
					{"axis": "x", "line_m": point.x, "lane_key": arm_y_key},
					{"axis": "y", "line_m": point.y, "lane_key": arm_x_key},
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
## 与 `boundary_edges()` 同源：矩形房每个平面恰一段（结果与旧「按四边比」一致），
## 轮廓房同一平面可能有多段、也可能一段都没有。
static func _side_for_room(axis: String, line_m: float, room_id: String, rooms: Array) -> String:
	for value in rooms:
		var room := value as Dictionary
		if str(room["room_id"]) != room_id:
			continue
		for edge_value in room["_boundary_edges"]:
			var edge := edge_value as Dictionary
			if (
				str(edge["axis"]) == axis
				and is_equal_approx(float(edge["line_m"]), line_m)
			):
				return str(edge["side"])
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
	var polygon := normalize_footprint(room, x0, x1, y0, y1, room_id, errors)
	if polygon.is_empty():
		return {}
	var edges_by_side := boundary_edges(polygon)
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
		"footprint_m": polygon,
		"footprint_is_rect": polygon.size() == 4,
		"_boundary_edges_by_side": edges_by_side,
		"_boundary_edges": flatten_boundary_edges(edges_by_side),
	}
