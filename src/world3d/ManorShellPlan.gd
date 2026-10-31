extends RefCounted
## 远征03 公馆壳体配方：给定房间（空间原型 + **本局门位**），算出「每一格放什么」。
##
## ## 为什么要有这个文件
##
## 2026-10-31 之前，"按原型铺墙地板"的逻辑只活在烘焙器 `tools/_exp03_manor_shell_builder.gd`
## 里。烘焙器按**烘焙那一局**的门位算出每面墙的实墙/窗/门序列，把结果连同门位指纹
## 写进文件名。于是复用键随门位漂移 —— 实测跨 5 个种子，按门位命中只有 1.4/17。
##
## 业主 2026-10-31 定方向：「美术包装按固定房间进行，包装完就应该在游戏内呈现」。
## 因此墙体与地砖改为**运行时按本局门位生成**，烘焙文件只承载装饰陈设。
## 本文件就是那份配方：**只算不建**，烘焙器与运行时调同一套函数，逐格结果必然一致。
##
## ## 设计原则（改这里就是改风格）
##
## **亮度 = 逃生希望，尺度 = 呼吸空间。** 差异化不按 room_id 随机、不靠贴花，
## 只用「光」和「尺度」两条轴：
##
##   小房 + 无窗  → 逼仄、压迫（25×25 战斗房，玩家只想快走）
##   中房 + 成对窗 → 有光斑拉在地上，能读方向（30×40 / 40×30）
##   大房 + 两对窗 → 开阔但空得能听见脚步（45×40 回廊）
##   枢纽        → 最亮 + 地板分区，唯一"可以停下"的地方
##   Boss        → 无窗 + 中央石台，把玩家逼到光下的舞台中央

const GRID := 5.0

const MANOR := "res://assets/art/environments/tower_zones/expedition/runtime/common_components"
const WALL := MANOR + "/manor_wall_standard/env_manor_wall_standard_root_top3d.tscn"
const WALL_DOOR := MANOR + "/manor_wall_door/env_manor_wall_door_root_top3d.tscn"
const WALL_WINDOW := MANOR + "/manor_wall_window/env_manor_wall_window_root_top3d.tscn"
const FLOOR_WOOD := MANOR + "/manor_floor_wood/env_manor_floor_wood_root_top3d.tscn"
const FLOOR_STONE := MANOR + "/manor_floor_stone/env_manor_floor_stone_root_top3d.tscn"

## `manor_floor_bath`（黑白瓷砖）**刻意不用**：实测铺 2×2 后中心区亮度
## p05=205 / p50=217 / p95=218，95% 像素挤在 205~218 —— 棋盘格被 UV 压成噪点，
## 远处就是一块白板。同批对比木地板 p50=28、石地板 p50=16。资产侧缺陷，修好前不要拿来铺地面。
const FLOOR_BATH := MANOR + "/manor_floor_bath/env_manor_floor_bath_root_top3d.tscn"

## 房型 → 原型。**不用 room_id 做键**（除枢纽特判）：换种子后房间尺寸会变，
## 而"这间房是干什么用"跨种子稳定。
## `max_short_side`：短边不超过该值用"小"档 —— 压迫感取决于最窄那一维。
const ARCHETYPES := {
	"COMBAT": {
		"small": {"floor": "full", "mat": FLOOR_STONE, "windows": "blind", "note": "逼仄空厅"},
		"mid": {"floor": "full", "mat": FLOOR_STONE, "windows": "pair", "note": "中庭回廊"},
		"large": {"floor": "full", "mat": FLOOR_STONE, "windows": "double_pair", "note": "大回廊"},
		"max_short_side": {"small": 25.0, "mid": 30.0},
	},
	"BOSS": {"floor": "wood_ring", "mat": FLOOR_WOOD, "ring": FLOOR_STONE, "windows": "blind", "note": "王座间"},
	"TRAP": {"floor": "full", "mat": FLOOR_STONE, "windows": "blind", "note": "陷阱厅"},
	"UPGRADE": {"floor": "full", "mat": FLOOR_WOOD, "windows": "pair", "note": "更衣前厅"},
	"MERCHANT": {"floor": "full", "mat": FLOOR_WOOD, "windows": "pair", "note": "铺面"},
	"EVENT": {"floor": "full", "mat": FLOOR_WOOD, "windows": "single_side", "note": "陈列室"},
	"SCAVENGE": {"floor": "stone_ring", "mat": FLOOR_WOOD, "ring": FLOOR_STONE, "windows": "pair", "note": "操作间"},
	"EXTRACTION": {"floor": "full", "mat": FLOOR_WOOD, "windows": "blind", "note": "撤离舱"},
	"SAFE_ROOM": {"floor": "full", "mat": FLOOR_WOOD, "windows": "blind", "note": "安全屋"},
	"STAIR_LOBBY": {"floor": "full", "mat": FLOOR_WOOD, "windows": "blind", "note": "楼梯厅"},
	# 2026-10-31 补：存档房（`STORAGE`）此前不在表里，`reward_*` 抽到该类型时拿不到原型，
	# 即使复用键改对了也命不中。按"仓库"语义取暗一点的中性色 —— 无窗 + 石地。
	"STORAGE": {"floor": "full", "mat": FLOOR_STONE, "windows": "blind", "note": "储藏间"},
}

## 枢纽：room_type 是 COMBAT，但多门交汇要"大堂"气质 —— 单独一条，
## 与同尺寸的普通战斗房必须一眼分开。手段是地板分区（石沿廊 + 木中庭）+ 通窗。
const HUB_IDS := ["hub_01", "hub_02"]


## 取本房的空间原型。**纯函数**：只读 room_id / room_type / 尺寸，零随机。
## 所以它算出来的东西跨种子稳定，是可以进复用键的维度。
static func style_for(room: Node, dim: Vector2) -> Dictionary:
	var room_id := str(room.get("room_id"))
	for hub in HUB_IDS:
		if room_id == hub:
			return {
				"floor": "stone_ring", "mat": FLOOR_WOOD, "ring": FLOOR_STONE,
				"windows": "clerestory", "note": "大堂",
			}
	var type_id := str(room.get("room_type"))
	var entry: Variant = ARCHETYPES.get(type_id)
	if entry is Dictionary and (entry as Dictionary).has("small"):
		var short_side := minf(dim.x, dim.y)
		var tiers: Dictionary = (entry as Dictionary)["max_short_side"]
		if short_side <= float(tiers["small"]):
			return ((entry as Dictionary)["small"] as Dictionary).duplicate()
		if short_side <= float(tiers["mid"]):
			return ((entry as Dictionary)["mid"] as Dictionary).duplicate()
		return ((entry as Dictionary)["large"] as Dictionary).duplicate()
	if entry is Dictionary:
		return (entry as Dictionary).duplicate()
	# 未登记的类型：退回"暗 + 石"的中性原型，并在调用侧留痕（不要静默出白房间）。
	return {"floor": "full", "mat": FLOOR_STONE, "windows": "blind", "note": "未登记原型"}


static func has_archetype(type_id: String) -> bool:
	return ARCHETYPES.has(type_id)


## 原型的可读标签，例如 `大堂/clerestory/stone_ring`。诊断与元数据用。
static func style_label(style: Dictionary) -> String:
	return "%s/%s/%s" % [
		str(style.get("note", "?")), str(style.get("windows", "?")), str(style.get("floor", "?")),
	]


## 原型的**复用指纹** —— 取代原先的「门位指纹」进文件名。
##
## 进指纹的是所有会改变画面的量：原型名、窗模式、地板模式、主材质、环材质。
## **门位刻意不进**：门位每局都变，进了就等于美术只对一局有效（这是 2026-10-31
## 那次"验收全绿但游戏里是白盒"的根因）。
static func style_fingerprint(style: Dictionary) -> String:
	var raw := "%s|%s|%s|%s|%s" % [
		str(style.get("note", "")),
		str(style.get("windows", "")),
		str(style.get("floor", "")),
		str(style.get("mat", "")).get_file(),
		str(style.get("ring", "")).get_file(),
	]
	return raw.sha256_text().substr(0, 6)


## 每一格的沿墙坐标（格心）。`count` 由尺寸 / GRID 四舍五入得出。
static func cells(length: float, count: int) -> Array[float]:
	var out: Array[float] = []
	for index in range(count):
		out.append(-length * 0.5 + (float(index) + 0.5) * GRID)
	return out


## 本局门位 → 每面墙「哪几格要开门」。
## 同一面可能多门（枢纽实测有），所以是数组不是单值。
##
## 门位不在格心时该面**不放门墙**并告警 —— 门墙洞口固定 2.2m 居中，
## 摆偏就是把门堵死。实测远征03 的 24 个门位无一例外都落在格心。
static func door_cells(connection_ports: Array, dim: Vector2) -> Dictionary:
	var cols := int(round(dim.x / GRID))
	var rows := int(round(dim.y / GRID))
	var cell_x := cells(dim.x, cols)
	var cell_z := cells(dim.y, rows)
	var result := {"north": [], "south": [], "west": [], "east": [], "_door_count": 0,
		"_offgrid": []}
	for value in connection_ports:
		var port := value as Dictionary
		var side := str(port.get("side", ""))
		if not result.has(side):
			continue
		var lane := float(port.get("lane_m", 0.0))
		var list_cells: Array = cell_x if side in ["north", "south"] else cell_z
		var found := -1
		for index in range(list_cells.size()):
			if absf(float(list_cells[index]) - lane) < 0.01:
				found = index
				break
		if found < 0:
			(result["_offgrid"] as Array).append("%s@%.2f" % [side, lane])
			continue
		var list: Array = result[side]
		if not list.has(found):
			list.append(found)
			result["_door_count"] = int(result["_door_count"]) + 1
	for side in ["north", "south", "west", "east"]:
		(result[side] as Array).sort()
	return result


## 决定这一面哪几格开窗。**输入含门位**，所以窗位会随门位变 ——
## 这正是它不能烘焙进文件、必须运行时算的原因。
##
##   pair        对称一对，最靠中心
##   double_pair 两对互不相邻（相邻两格等于合成 10m 大洞，不是窗廊）
##   clerestory  除门位及其两侧墙垛外全开
##   single_side 只有北面一对
##   blind       一格不开
static func window_cells(cell_list: Array, door_indices: Array, mode: String, side: String) -> Array:
	if mode == "blind" or cell_list.is_empty():
		return []
	if mode == "single_side":
		if side != "north":
			return []
		return _symmetric_pair(cell_list, door_indices)
	if mode == "double_pair":
		return _double_pair(cell_list, door_indices)
	if mode == "clerestory":
		var blocked := {}
		for index in door_indices:
			blocked[index] = true
			blocked[index - 1] = true
			blocked[index + 1] = true
		var out: Array = []
		for index in range(cell_list.size()):
			if blocked.has(index):
				continue
			out.append(index)
		# 全被挡住（例如 2 格宽门廊）就退化成一对，至少留一线光。
		if out.is_empty():
			return _symmetric_pair(cell_list, door_indices)
		return out
	return _symmetric_pair(cell_list, door_indices)


static func _double_pair(cell_list: Array, door_indices: Array) -> Array:
	var count := cell_list.size()
	var pairs: Array = []
	for i in range(count):
		for j in range(i + 1, count):
			if absf(float(cell_list[i]) + float(cell_list[j])) < 0.01:
				if door_indices.has(i) or door_indices.has(j):
					continue
				pairs.append({"first": i, "second": j, "dist": absf(float(cell_list[i]))})
	pairs.sort_custom(func(a, b): return float(a["dist"]) < float(b["dist"]))
	if pairs.size() < 2:
		return _symmetric_pair(cell_list, door_indices)
	for pair in pairs:
		var pick: Array = [int(pair["first"]), int(pair["second"])]
		for other in pairs:
			if other == pair:
				continue
			# 内层对的跨度必须比外层小，否则两对会交叉或重叠。
			if float(other["dist"]) >= float(pair["dist"]):
				continue
			var candidate: Array = [int(other["first"]), int(other["second"])]
			var disjoint := true
			for a in pick:
				for b in candidate:
					if absi(int(a) - int(b)) <= 1:
						disjoint = false
			if disjoint:
				var best: Array = pick + candidate
				best.sort()
				return best
	return _symmetric_pair(cell_list, door_indices)


static func _symmetric_pair(cell_list: Array, door_indices: Array) -> Array:
	var count := cell_list.size()
	var pairs: Array = []
	for i in range(count):
		for j in range(i + 1, count):
			if absf(float(cell_list[i]) + float(cell_list[j])) < 0.01:
				pairs.append([i, j, absf(float(cell_list[i]))])
	pairs.sort_custom(func(a, b): return float(a[2]) < float(b[2]))
	for pair in pairs:
		var first := int(pair[0])
		var second := int(pair[1])
		if not door_indices.has(first) and not door_indices.has(second):
			return [first, second]
	var best := -1
	var best_distance := 1e9
	for index in range(count):
		if door_indices.has(index):
			continue
		var distance := absf(float(cell_list[index]))
		if distance < best_distance:
			best_distance = distance
			best = index
	return [best] if best >= 0 else []


## 地板配方。返回 `[{prefab, position, name, part}]`。
##   full        单材质满铺
##   stone_ring  外圈石 + 内心木（走道感，大堂用）
##   wood_ring   外圈木 + 内心石（舞台感，Boss 用）
## 分区时外圈恒为 1 格；3×3 及更小的房间退化为满铺（分区没有意义）。
static func floor_plan(dim: Vector2, style: Dictionary) -> Array[Dictionary]:
	var cols := int(round(dim.x / GRID))
	var rows := int(round(dim.y / GRID))
	var cell_x := cells(dim.x, cols)
	var cell_z := cells(dim.y, rows)
	var mode := str(style.get("floor", "full"))
	var main_mat := str(style.get("mat", FLOOR_WOOD))
	var ring_mat := str(style.get("ring", main_mat))
	var out: Array[Dictionary] = []
	for row in range(rows):
		for col in range(cols):
			var prefab := main_mat
			var part := "core"
			if mode != "full" and cols >= 4 and rows >= 4:
				var is_ring := col == 0 or row == 0 or col == cols - 1 or row == rows - 1
				if is_ring:
					prefab = ring_mat if mode == "stone_ring" else main_mat
					part = "ring"
				else:
					prefab = main_mat if mode == "stone_ring" else ring_mat
			elif mode != "full":
				prefab = main_mat
			out.append({
				"prefab": prefab,
				"position": Vector3(cell_x[col], 0.0, cell_z[row]),
				"name": "Floor_%02d_%02d" % [col, row],
				"part": part,
			})
	return out


## 墙面配方。每面**每一格**都放墙（门位格放门墙），返回 `[{prefab, position, yaw, name}]`。
## 少一格，`_art_layer_coverage()` 就判"没铺满"。
static func wall_plan(dim: Vector2, door_map: Dictionary, window_mode: String) -> Array[Dictionary]:
	var cols := int(round(dim.x / GRID))
	var rows := int(round(dim.y / GRID))
	var cell_x := cells(dim.x, cols)
	var cell_z := cells(dim.y, rows)
	var sides := [
		{"side": "north", "cells": cell_x, "axis": "x", "at": -dim.y * 0.5, "yaw": 0.0},
		{"side": "south", "cells": cell_x, "axis": "x", "at": dim.y * 0.5, "yaw": 180.0},
		{"side": "west", "cells": cell_z, "axis": "z", "at": -dim.x * 0.5, "yaw": 90.0},
		{"side": "east", "cells": cell_z, "axis": "z", "at": dim.x * 0.5, "yaw": 90.0},
	]
	var out: Array[Dictionary] = []
	for spec in sides:
		var side := str(spec["side"])
		var cell_list: Array = spec["cells"]
		var at := float(spec["at"])
		var yaw := float(spec["yaw"])
		var along_x := str(spec["axis"]) == "x"
		var door_indices: Array = door_map.get(side, [])
		var window_indices: Array = window_cells(cell_list, door_indices, window_mode, side)
		for index in range(cell_list.size()):
			var along := float(cell_list[index])
			var position := Vector3(along, 0.0, at) if along_x else Vector3(at, 0.0, along)
			var prefab := WALL
			var node_name := "Wall_%s_%02d" % [side, index]
			if door_indices.has(index):
				prefab = WALL_DOOR
				node_name = "DoorWall_%s_%02d" % [side, index]
			elif window_indices.has(index):
				prefab = WALL_WINDOW
				node_name = "WindowWall_%s_%02d" % [side, index]
			out.append({
				"prefab": prefab, "position": position, "yaw": yaw, "name": node_name,
			})
	return out


## 把配方实例化到 `parent` 下。返回建出的件数。
## `owner_node` 非空时写 owner（烘焙器需要，否则存不进 PackedScene）；运行时传 null。
static func instantiate_plan(plan: Array, parent: Node3D, owner_node: Node = null) -> int:
	var built := 0
	for item in plan:
		var entry := item as Dictionary
		var packed := load(str(entry.get("prefab", ""))) as PackedScene
		if packed == null:
			push_warning("[ManorShellPlan] 加载不了 %s" % str(entry.get("prefab", "")))
			continue
		var instance := packed.instantiate() as Node3D
		if instance == null:
			continue
		instance.name = str(entry.get("name", "Part"))
		instance.position = entry.get("position", Vector3.ZERO) as Vector3
		instance.rotation.y = deg_to_rad(float(entry.get("yaw", 0.0)))
		parent.add_child(instance)
		if owner_node != null:
			instance.owner = owner_node
		built += 1
	return built
