class_name EgtPlanBridge
extends RefCounted
## EGT 组装器房间表 → `RoomShellLayoutBuilder3D.build_block()` 区块输入。
##
## ## 为什么需要这一层
##
## 两侧的坐标系与契约不一样，**不能直接对接**：
##
## | | 组装器 `EgtFlowAssembler` | 壳体组合器 `build_block()` |
## |---|---|---|
## | 坐标 | 平面坐标，`center` + `size`，y 向南 | Blender 世界坐标，`bounds_x/y_m`，y 向北 |
## | 门 | `ports = {side: [相对中心的 lane 偏移]}` | `doors = {side: 沿墙轴的**绝对**坐标}` |
## | 走廊 | `connections` 里一条 `kind: "corridor"` | 不存在 —— 走廊必须是**房间** |
## | 格线 | 不保证落 5m 格线 | 硬要求：bounds 落在 5m 格线、门落在 lane 中心 |
##
## 这一层只做**换算与补齐**，不重新布局、不改拓扑。
##
## ## 三条换算规则（都实测过，不是推导）
##
## ① **全局平移 +2.5m**。组装器的对齐公式 `b.y = a.y + lane_a - lane_b` 让所有
##   房间中心的同余类由尺寸奇偶决定，实测 263 间房 × 4 条边 = **1052 条边界**
##   全部落在 `5k + 2.5`。整体平移 (2.5, 2.5) 后**全部落回 5m 格线**，
##   同时 526 个门点**全部正好落在 lane 中心 `5k + 2.5`** —— 两个条件同时成立，
##   所以只需要一个常量平移，不需要逐房吸附。
##
## ② **走廊补成房间**。组装器把 gap 5~30m 的连接记成 `kind: "corridor"`，
##   但壳体组合器只认房间 —— 不补这一段，玩家就得跨过一片虚空。
##   原文也说实际地图比 flow 图多出"奇怪的走廊房间"（Boris 第 13 行）。
##   直走廊 = 5m 宽矩形；两门横向错开时 = **两段直走廊在拐角处共墙 + 各开一门**，
##   不是一整段斜拉、也不是单块凹多边形 —— 前者墙不轴对齐，后者的顶点绕向
##   写反一次就会让**整块**退回程序化壳体（见 `_l_pieces()`）。
##
## ③ **同侧多门给数组**。526 个门侧里有 2 个是同侧双门，丢一扇就是一个假墙。
##
## ## 用法
## ```gdscript
## var result := EgtFlowAssembler.assemble_flow(flow, templates, {}, seed)
## var bridged := EgtPlanBridge.to_block(result)
## var block := RoomShellLayoutBuilder3D.build_block(bridged["block"])
## ```

const BUILDER := preload("res://src/world3d/RoomShellLayoutBuilder3D.gd")
const LANE := preload("res://src/map/RoomDoorLane.gd")

const GRID_UNIT_M := 5.0
## 门槽中心相对格线的偏移（`lane_center_of(k) = 5k + 2.5`）。
const LANE_HALF_M := 2.5
## 走廊净宽。原文"窄长走廊"，5m 正好一格。
const CORRIDOR_WIDTH_M := 5.0
const EPS := 0.01
const SIDE_ORDER: Array[String] = ["north", "south", "west", "east"]


# ── 对外入口 ────────────────────────────────────────────────────────────────
## 组装结果 → 壳体区块输入。
##
## 返回：
## ```
## {
##   "block": [ 房间字典 … ],              # 可直接喂 build_block()
##   "corridor_ids": [String],             # 补出来的走廊房 id（不是 flow 里的节点）
##   "room_meta": {room_id: {kind, template_id, is_corridor}},
##   "errors": [String],
##   "stats": {room_count, corridor_count, gate_count, straight, l_shape},
## }
## ```
static func to_block(result: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var rooms: Array = result.get("rooms", []) as Array
	if rooms.is_empty():
		return {"block": [], "corridor_ids": [], "room_meta": {}, "errors": ["no_rooms"],
			"stats": {}}

	var shift := _grid_shift(rooms, errors)
	# 门槽必须先盖章再补走廊：走廊的两端是**门的位置**，门一动走廊就得跟着动。
	var stamp := _stamp_ports(result, errors)
	var block: Array = []
	var room_meta := {}
	var room_by_id := {}
	for value in rooms:
		var room := value as Dictionary
		var room_id := str(room.get("node_id", ""))
		var record := _room_record(room, shift, stamp["ports"], errors)
		if record.is_empty():
			continue
		block.append(record)
		room_by_id[room_id] = room
		room_meta[room_id] = {
			"kind": str(room.get("kind", "")),
			"template_id": str(room.get("template_id", "")),
			"is_corridor": false,
		}

	var corridor_ids: Array[String] = []
	var corridor_stats := {"straight": 0, "l_shape": 0}
	# 用 `corridors` 而不是 `connections`：前者是组装器**已整理好**的走廊清单
	# （`from_node/to_node/from_side/from_lane/...`），后者是内部结构（`a_id/b_id/...`）。
	var corridors := _corridor_rooms(room_by_id, result.get("corridors", []) as Array,
		shift, errors, corridor_stats, stamp["pairs"])
	for value in corridors:
		var record := value as Dictionary
		block.append(record)
		corridor_ids.append(str(record["room_id"]))
		room_meta[str(record["room_id"])] = {
			"kind": "CORRIDOR_ROOM", "template_id": "", "is_corridor": true,
		}

	_overlap_report(block, errors)

	var gate_count := 0
	for value in block:
		var record := value as Dictionary
		for side_value in (record["doors"] as Dictionary).keys():
			gate_count += BUILDER._port_offsets((record["doors"] as Dictionary)[side_value]).size()

	return {
		"block": block,
		"corridor_ids": corridor_ids,
		"room_meta": room_meta,
		"errors": errors,
		"stats": {
			"room_count": rooms.size(),
			"corridor_count": corridors.size(),
			"gate_count": gate_count,
			"stamped_ok": int(stamp.get("stamped_ok", 0)),
			"stamped_fallback": int(stamp.get("stamped_fallback", 0)),
			"straight": int(corridor_stats["straight"]),
			"l_shape": int(corridor_stats["l_shape"]),
			"shift": [shift.x, shift.y],
		},
	}


# ── ⓪ 门槽盖章 ──────────────────────────────────────────────────────────────
## 把组装器算出的门槽**统一换成** `RoomDoorLane.port_pair()` 的结果。
##
## ## 为什么必须盖章
##
## 组装器和本工程的其余四个消费方用的不是同一条门槽算法：
##
## | 谁 | 语义 | 结果 |
## |---|---|---|
## | 组装器 `_aligned_center()` | **先选门槽，再由门槽反推位置** | 门槽可以选靠墙的 |
## | `RoomDoorLane.port_pair()` | **先有位置，再反算共享门槽** | 取离两房中心最近的共享槽 |
##
## 实测 758 条连接：**`side` 100% 一致，`lane` 只有 18.6% 一致** —— 两者都是合法解，
## 只是选的那个槽不同。而 `LevelPlanValidator._validate_port_derivation()` 会逐条比对
## 设计源 `ports` 与 `port_pair()` 的派生值，不一致就报 `port_derivation_mismatch`。
##
## 若把组装器的门槽直接写进设计源，校验器会红掉 81% 的门；若改用 `port_pair()`，
## 校验器绿了但组装器的布局没被采用。**唯一不牺牲任何一方的做法就是盖章**：
## 布局位置由组装器决定（它才管拓扑和形状），门槽一律以本工程唯一实现为准。
##
## 盖章代价为零：实测 758/758 条连接在盖章后两侧门点仍然重合（`direct` 门距 0、
## `corridor` 长度盖得住）—— 因为门槽换成的是**同一面墙上的另一条合法共享槽**，
## 房间位置不需要动。
##
## 盖章后仍要做两件事：① 门槽必须是该墙上的合法槽；② 同一房间同一面墙不能有两扇门
## 落到同一个槽（那会变成一扇门 + 一个假墙洞）。
static func _stamp_ports(result: Dictionary, errors: Array[String]) -> Dictionary:
	var by_id := {}
	for value in result.get("rooms", []) as Array:
		var room := value as Dictionary
		by_id[str(room.get("node_id", ""))] = room
	var ports := {}
	var pairs := {}
	var stamped_ok := 0
	var stamped_fallback := 0
	for value in result.get("connections", []) as Array:
		var conn := value as Dictionary
		var a_id := str(conn["a_id"])
		var b_id := str(conn["b_id"])
		if not (by_id.has(a_id) and by_id.has(b_id)):
			errors.append("stamp_unknown_room:%s-%s" % [a_id, b_id])
			continue
		var room_a := by_id[a_id] as Dictionary
		var room_b := by_id[b_id] as Dictionary
		var pair := LANE.port_pair(room_a["center"] as Vector2, room_a["size"] as Vector2,
			room_b["center"] as Vector2, room_b["size"] as Vector2)
		var chosen := pair
		# **保守盖章**：`port_pair()` 的 `b_lane` 是「共享绝对坐标 − b 的轴中心」，
		# 而共享坐标取自 a 侧的候选槽。两墙不等长时（a 25m / b 45m），减出来的
		# b_lane 落在 b 的合法槽之外 —— 实测这正是 13/120 局报 `stamp_lane_illegal` 的来源。
		# 所以只有两侧都合法才采纳它的值；否则保留组装器原槽（原槽一定合法，
		# 它是从模板 `wall_lane_table` 里选的，`build_block()` 之前已经验过）。
		if not (_lane_is_legal(room_a, str(pair["a_side"]), float(pair["a_lane"]))
				and _lane_is_legal(room_b, str(pair["b_side"]), float(pair["b_lane"]))):
			chosen = {
				"a_side": str(conn["a_side"]), "a_lane": float(conn["a_lane"]),
				"b_side": str(conn["b_side"]), "b_lane": float(conn["b_lane"]),
			}
			stamped_fallback += 1
		else:
			stamped_ok += 1
		pairs[_edge_key(a_id, b_id)] = chosen
		_add_port(ports, a_id, str(chosen["a_side"]), float(chosen["a_lane"]), errors)
		_add_port(ports, b_id, str(chosen["b_side"]), float(chosen["b_lane"]), errors)

	# ① 门槽合法 + ② 同侧不撞槽。两件事都只能在这里做：`port_pair()` 只保证
	# 「是本侧候选池里的一个」，不保证「与另外几条连接不撞」。
	for room_id in ports.keys():
		var room_value: Variant = by_id.get(room_id, null)
		if room_value == null:
			continue
		var size := (room_value as Dictionary)["size"] as Vector2
		var side_map: Dictionary = ports[room_id]
		for side_value in side_map.keys():
			var side := str(side_value)
			var wall_length := size.x if side in ["north", "south"] else size.y
			var legal := LANE.lane_offsets(wall_length)
			var seen: Array = []
			for lane_value in side_map[side] as Array:
				var lane := float(lane_value)
				var matched := false
				for offset in legal:
					if absf(float(offset) - lane) < 0.005:
						matched = true
						break
				if not matched:
					var dbg := []
					for pv in pairs.values():
						var pd := pv as Dictionary
						if str(pd.get("a_side","")) == side and absf(float(pd.get("a_lane",0.0)) - lane) < 0.005:
							dbg.append("A wl=%.0f" % float(pd.get("a_wall_length",0.0)))
						if str(pd.get("b_side","")) == side and absf(float(pd.get("b_lane",0.0)) - lane) < 0.005:
							dbg.append("B wl=%.0f" % float(pd.get("b_wall_length",0.0)))
					errors.append("stamp_lane_illegal:%s.%s=%.1f (墙长 %.0f) dbg=%s" % [
						room_id, side, lane, wall_length, str(dbg)])
				if seen.has(lane):
					errors.append("stamp_lane_collision:%s.%s=%.1f" % [room_id, side, lane])
				seen.append(lane)
			side_map[side] = seen
	return {"ports": ports, "pairs": pairs,
		"stamped_ok": stamped_ok, "stamped_fallback": stamped_fallback}


## 这个门槽是不是该房该墙上的合法槽（首尾各留一格，`RoomDoorLane.lane_offsets()`）。
static func _lane_is_legal(room: Dictionary, side: String, lane: float) -> bool:
	if side not in ["north", "south", "east", "west"]:
		return false
	var size := room["size"] as Vector2
	var wall_length := size.x if side in ["north", "south"] else size.y
	for offset in LANE.lane_offsets(wall_length):
		if absf(float(offset) - lane) < 0.005:
			return true
	return false


static func _add_port(ports: Dictionary, room_id: String, side: String, lane: float,
		errors: Array[String]) -> void:
	if not ports.has(room_id):
		ports[room_id] = {}
	var side_map: Dictionary = ports[room_id]
	if not side_map.has(side):
		side_map[side] = []
	(side_map[side] as Array).append(lane)


static func _edge_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]


# ── ① 全局平移 ──────────────────────────────────────────────────────────────## 让全体房间边界落回 5m 格线所需的平移量（对全部房间必须是同一个，否则报错）。
static func _grid_shift(rooms: Array, errors: Array[String]) -> Vector2:
	var first := rooms[0] as Dictionary
	var center := first["center"] as Vector2
	var size := first["size"] as Vector2
	var dx := fposmod(-(center.x - size.x * 0.5), GRID_UNIT_M)
	var dy := fposmod(-(center.y - size.y * 0.5), GRID_UNIT_M)
	for value in rooms:
		var room := value as Dictionary
		var c := room["center"] as Vector2
		var s := room["size"] as Vector2
		for axis in ["x", "y"]:
			var low := (c.x if axis == "x" else c.y) - (s.x if axis == "x" else s.y) * 0.5
			var delta := (dx if axis == "x" else dy)
			if not _on_grid(low + delta):
				errors.append("grid_misaligned:%s:%s=%.3f(+%.1f)" % [
					str(room.get("node_id", "")), axis, low, delta])
	return Vector2(dx, dy)


static func _on_grid(value: float) -> bool:
	return absf(fposmod(value, GRID_UNIT_M)) < EPS or \
		absf(fposmod(value, GRID_UNIT_M) - GRID_UNIT_M) < EPS


# ── ② 房间 → 区块记录 ───────────────────────────────────────────────────────
## 平面坐标 → Blender 世界坐标：`bx = px`、`by = −py`（planar y 向南、Blender y 向北）。
static func _room_record(room: Dictionary, shift: Vector2, stamped_ports: Dictionary,
		errors: Array[String]) -> Dictionary:
	var room_id := str(room.get("node_id", ""))
	var center := (room["center"] as Vector2) + shift
	var size := room["size"] as Vector2
	if size.x < GRID_UNIT_M or size.y < GRID_UNIT_M:
		errors.append("room_too_small:%s" % room_id)
		return {}
	var bx := center.x
	var by := -center.y
	var bounds_x := [bx - size.x * 0.5, bx + size.x * 0.5]
	var bounds_y := [by - size.y * 0.5, by + size.y * 0.5]

	var doors := {}
	# 端口取盖章后的那一份（`_stamp_ports()`），**不读** `room["ports"]`
	# —— 后者是组装器自己选的槽，与本工程其余四个消费方不是同一条算法。
	var ports: Dictionary = stamped_ports.get(room_id, {})
	for side in SIDE_ORDER:
		if not ports.has(side):
			continue
		var absolute: Array = []
		for lane_value in ports[side] as Array:
			var lane := float(lane_value)
			# north/south 墙的沿墙轴是 bx（planar x，无镜像）；
			# west/east 墙的沿墙轴是 by（planar y 取负，故是减）。
			absolute.append(bx + lane if side in ["north", "south"] else by - lane)
		if absolute.is_empty():
			continue
		doors[side] = absolute if absolute.size() > 1 else absolute[0]

	return {
		"room_id": room_id,
		"bounds_x_m": bounds_x,
		"bounds_y_m": bounds_y,
		"doors": doors,
		"exits": {},
		# 5m 宽的单 lane 房没有角落可放 L 件（L 件占 2 条臂）。
		"use_corner_l": size.x > GRID_UNIT_M + EPS and size.y > GRID_UNIT_M + EPS,
	}


# ── ③ 走廊成房 ──────────────────────────────────────────────────────────────
## 门点的 Blender 世界坐标。
static func _gate(room: Dictionary, side: String, lane: float, shift: Vector2) -> Vector2:
	var center := (room["center"] as Vector2) + shift
	var size := room["size"] as Vector2
	var bx := center.x
	var by := -center.y
	match side:
		"north":
			return Vector2(bx + lane, by + size.y * 0.5)
		"south":
			return Vector2(bx + lane, by - size.y * 0.5)
		"west":
			return Vector2(bx - size.x * 0.5, by - lane)
		_:
			return Vector2(bx + size.x * 0.5, by - lane)


static func _corridor_rooms(room_by_id: Dictionary, connections: Array, shift: Vector2,
		errors: Array[String], stats: Dictionary, pairs: Dictionary) -> Array:
	var out: Array = []
	var index := 0
	for value in connections:
		var conn := value as Dictionary
		var a_id := str(conn["from_node"])
		var b_id := str(conn["to_node"])
		if not (room_by_id.has(a_id) and room_by_id.has(b_id)):
			errors.append("corridor_unknown_room:%s-%s" % [a_id, b_id])
			continue
		# 走廊两端必须用**盖章后的门**：走廊是按门的位置长出来的，用组装器原来的
		# 门槽会让走廊端点与房间实际门洞错开半个格 —— 图上就是门槛悬空。
		var pair: Dictionary = pairs.get(_edge_key(a_id, b_id), {})
		if pair.is_empty():
			errors.append("corridor_without_pair:%s-%s" % [a_id, b_id])
			continue
		var ga := _gate(room_by_id[a_id] as Dictionary, str(pair["a_side"]),
			float(pair["a_lane"]), shift)
		var gb := _gate(room_by_id[b_id] as Dictionary, str(pair["b_side"]),
			float(pair["b_lane"]), shift)
		var pieces := _corridor_pieces("cr%02d_%s_%s" % [index, a_id, b_id],
			str(pair["a_side"]), ga, gb, errors)
		index += 1
		if pieces.is_empty():
			continue
		var bucket := "straight" if pieces.size() == 1 else "l_shape"
		stats[bucket] = int(stats[bucket]) + 1
		out.append_array(pieces)
	return out


## 一条走廊 → 1 段（直）或 2 段（横向错开，L 形）。
##
## `a_side` 决定行进轴：east/west → 沿 bx；north/south → 沿 by。
static func _corridor_pieces(base_id: String, a_side: String, ga: Vector2, gb: Vector2,
		errors: Array[String]) -> Array:
	var along_x := a_side in ["east", "west"]
	if absf((gb.x - ga.x) if along_x else (gb.y - ga.y)) < EPS:
		errors.append("corridor_zero_length:%s" % base_id)
		return []
	var lateral := (gb.y - ga.y) if along_x else (gb.x - ga.x)
	if absf(lateral) < EPS:
		return [_straight_piece(base_id, along_x, ga, gb)]
	if not _on_grid(absf(lateral)):
		errors.append("corridor_lateral_off_grid:%s:%.3f" % [base_id, lateral])
		return []
	return _l_pieces(base_id, along_x, ga, gb)


## 直走廊：横向与两门同轴，一段矩形就够。
static func _straight_piece(piece_id: String, along_x: bool, ga: Vector2,
		gb: Vector2) -> Dictionary:
	var half := CORRIDOR_WIDTH_M * 0.5
	var doors := {}
	if along_x:
		var min_x := minf(ga.x, gb.x)
		var max_x := maxf(ga.x, gb.x)
		doors["west" if ga.x < gb.x else "east"] = ga.y
		doors["east" if ga.x < gb.x else "west"] = gb.y
		return _piece(piece_id, [min_x, max_x], [ga.y - half, ga.y + half], doors)
	var min_y := minf(ga.y, gb.y)
	var max_y := maxf(ga.y, gb.y)
	doors["south" if ga.y < gb.y else "north"] = ga.x
	doors["north" if ga.y < gb.y else "south"] = gb.x
	return _piece(piece_id, [ga.x - half, ga.x + half], [min_y, max_y], doors)


## L 形：拆成两段直走廊，在拐角处**共墙并各开一门**。
##
## 为什么不做单个多边形房：凹角多边形的顶点序与绕向极易写反（写反了 builder 会判
## 轮廓非法并让**整块**退回程序化壳体），而两段矩形 + 拐角门洞在几何上等价于通行的
## L 形，且完全走已验证的直走廊路径。真实建筑里走廊转弯处本来也常有一道门。
static func _l_pieces(base_id: String, along_x: bool, ga: Vector2, gb: Vector2) -> Array:
	var half := CORRIDOR_WIDTH_M * 0.5
	var sign_along := 1.0 if ((gb.x if along_x else gb.y) > (ga.x if along_x else ga.y)) else -1.0
	var sign_lateral := 1.0 if ((gb.y if along_x else gb.x) > (ga.y if along_x else ga.x)) else -1.0
	# 拐角门所在的 lane：贴着 b 那一格的中心。
	var corner_lane := (gb.x - half * sign_along) if along_x else (gb.y - half * sign_along)
	if along_x:
		# 段 1：从 a 的门沿 bx 走到 b 的墙线，横向保持 a 的 lane。
		var seg_a := _piece(base_id + "_a",
			[minf(ga.x, gb.x), maxf(ga.x, gb.x)],
			[ga.y - half, ga.y + half],
			{
				("west" if sign_along > 0 else "east"): ga.y,
				("north" if sign_lateral > 0 else "south"): corner_lane,
			})
		# 段 2：贴 b 的墙，从段 1 的边一直伸到 b 的门 lane。
		var y_low := (ga.y + half) if sign_lateral > 0 else (gb.y - half)
		var y_high := (gb.y + half) if sign_lateral > 0 else (ga.y - half)
		var seg_b := _piece(base_id + "_b",
			[minf(gb.x, gb.x - CORRIDOR_WIDTH_M * sign_along),
				maxf(gb.x, gb.x - CORRIDOR_WIDTH_M * sign_along)],
			[y_low, y_high],
			{
				("south" if sign_lateral > 0 else "north"): corner_lane,
				("east" if sign_along > 0 else "west"): gb.y,
			})
		return [seg_a, seg_b]
	var seg_a_y := _piece(base_id + "_a",
		[ga.x - half, ga.x + half],
		[minf(ga.y, gb.y), maxf(ga.y, gb.y)],
		{
			("south" if sign_along > 0 else "north"): ga.x,
			("east" if sign_lateral > 0 else "west"): corner_lane,
		})
	var x_low := (ga.x + half) if sign_lateral > 0 else (gb.x - half)
	var x_high := (gb.x + half) if sign_lateral > 0 else (ga.x - half)
	var seg_b_y := _piece(base_id + "_b",
		[x_low, x_high],
		[minf(gb.y, gb.y - CORRIDOR_WIDTH_M * sign_along),
			maxf(gb.y, gb.y - CORRIDOR_WIDTH_M * sign_along)],
		{
			("west" if sign_lateral > 0 else "east"): corner_lane,
			("north" if sign_along > 0 else "south"): gb.x,
		})
	return [seg_a_y, seg_b_y]


static func _piece(piece_id: String, bounds_x: Array, bounds_y: Array,
		doors: Dictionary) -> Dictionary:
	return {
		"room_id": piece_id,
		"bounds_x_m": bounds_x,
		"bounds_y_m": bounds_y,
		"doors": doors,
		"exits": {},
		# 5m 宽的单 lane 房没有角落可放 L 件（L 件占 2 条臂）。
		"use_corner_l": false,
	}



## 两两求矩形包围盒交集 —— 走廊常从别的房间边上擦过，重叠了就是穿模。
## 共墙贴合（交集面积为 0）不算重叠。
static func _overlap_report(block: Array, errors: Array[String]) -> void:
	for i in range(block.size()):
		var a := block[i] as Dictionary
		var ax := a["bounds_x_m"] as Array
		var ay := a["bounds_y_m"] as Array
		for j in range(i + 1, block.size()):
			var b := block[j] as Dictionary
			var bx := b["bounds_x_m"] as Array
			var by := b["bounds_y_m"] as Array
			var w := minf(float(ax[1]), float(bx[1])) - maxf(float(ax[0]), float(bx[0]))
			var h := minf(float(ay[1]), float(by[1])) - maxf(float(ay[0]), float(by[0]))
			if w > EPS and h > EPS:
				errors.append("room_overlap:%s/%s:%.1fx%.1f" % [
					str(a["room_id"]), str(b["room_id"]), w, h])
