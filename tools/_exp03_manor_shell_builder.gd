extends Node
## 远征03 公馆壳体铺装器：按「空间原型」给 17 间房铺墙 + 地板。
##
## ## 设计原则（本器唯一的设计判断，改这里就是改风格）
##
## **亮度 = 逃生希望，尺度 = 呼吸空间。**
##
## 一个人在公馆里转，靠两件事判断"这里危不危险"：光多不多、地方多大。
## 所以差异化不按 room_id 随机，也不靠贴花，而是用**光**和**尺度**两条轴：
##
##   小房 + 无窗  → 逼仄、压迫（25×25 战斗房，玩家只想快走）
##   中房 + 高窗  → 有光斑拉在地上，能读方向（30×40 / 40×30 战斗房）
##   大房 + 通窗  → 开阔、但空得能听见脚步（45×40 回廊）
##   枢纽       → 最亮 + 地板分区，唯一"可以停下"的地方
##   Boss       → 无窗 + 中央石台，把玩家逼到光下的舞台中央
##
## ## 三种地板，四种墙
##
## 地板不只"三选一"，还做**分区拼接**（全是现有 6 件资产，不需要新件）：
##
##   `full`        单材质满铺
##   `stone_ring`  外圈石 + 内心木 → 走道感，大堂用（石质沿廊围出木质中庭）
##   `wood_ring`   外圈木 + 内心石 → 舞台感，Boss 用（木质围廊包住中央石台）
##
## 墙有四种开窗节奏：
##
##   `blind`       只放实心墙（门位放门墙）—— 最暗
##   `pair`        每面挑对称一对开铅条窗 —— 有光斑，仍有墙垛节奏
##   `clerestory`  除门位及其两侧墙垛外全开窗 —— 近乎连续高窗，最亮
##   `single_side` 只有北面一对 —— 单向采光，明暗拉开，适合陈列
##
## ## 门墙必须跟门位走
##
## `manor_wall_door` 洞口固定 2.2m 居中，只能摆在「本局门位所在的那一格」。
## 摆错就是把门堵死（实心件带碰撞）。复用键不含门位，所以文件名带门位指纹
## （见 `RuntimeRoomArtSource.describe()` 的 `portal_fingerprint`）。
##
## ## 覆盖判定
##
## 每面墙的**每一格**都放墙（门位格放门墙），地板**每一格**都放地砖 ——
## 这样 `_art_layer_coverage()` 才会判定"铺满"，程序化壳体才让位。
## 少一格就退回程序化，美术等于白做。

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel03_3D.tscn")
const CONTRACT := preload("res://src/world3d/RuntimeRoomArtSource.gd")
## 原型表与逐格摆位的**唯一真源**。烘焙器不再自己维护一份 ——
## 两份表只要漂一格，烘焙文件名（用这里的指纹）就和运行时（用同一份）
## 对不上，表现是"刚烘焙完还是白盒"。
const MANOR_PLAN := preload("res://src/world3d/ManorShellPlan.gd")
const MANOR := "res://assets/art/environments/tower_zones/expedition/runtime/common_components"

const WALL := MANOR + "/manor_wall_standard/env_manor_wall_standard_root_top3d.tscn"
const WALL_DOOR := MANOR + "/manor_wall_door/env_manor_wall_door_root_top3d.tscn"
const WALL_WINDOW := MANOR + "/manor_wall_window/env_manor_wall_window_root_top3d.tscn"
const FLOOR_WOOD := MANOR + "/manor_floor_wood/env_manor_floor_wood_root_top3d.tscn"
const FLOOR_STONE := MANOR + "/manor_floor_stone/env_manor_floor_stone_root_top3d.tscn"
## `manor_floor_bath`（黑白瓷砖）**刻意不用**，虽然它在目录里标的是"黑白瓷砖地板5m"。
##
## 实测出图后量化过：按 5m 网格铺 2×2 后，中心区亮度 p05=205 / p50=217 / p95=218
## —— 95% 的像素挤在 205~218 这一窄条里，只剩零星黑点，**棋盘格没有出来**，
## 远处看就是一块白板。同批对比：木地板 p50=28、石地板 p50=16，都明显更暗。
##
## 成因在资产侧（UV 把 5m 铺面映射到色盘上一小块偏白区域，格纹被压成噪点），
## 不是打光能修的 —— 调暗只会得到"灰板"，格子依然没有。
## 已作为资产缺陷记录在 docs/v0.1/development/2026-10-31_expedition03_manor_shell_build.md，
## 修好资产前不要拿它铺地面。
const FLOOR_BATH := MANOR + "/manor_floor_bath/env_manor_floor_bath_root_top3d.tscn"

const GRID := 5.0
const SEED := 77003244

## 房型 → 原型。**不用 room_id 做键**：换种子后房间尺寸会变，
## 而"这间房是干什么用"才决定它该长什么样，这个跨种子稳定。
##
## `max_short_side`：房间短边不超过这个值时用"小"档（更暗、更封闭）。
## 这样同一房型的不同尺寸会自然分档，不需要为每间房写一条。
## 原型表已迁到 `src/world3d/ManorShellPlan.gd`（运行时与烘焙器共用）。
## **不要在这里重新加一份** —— 两份只要漂一格，文件名与运行时期望就对不上。

var _failures: Array[String] = []
var _written: Array[String] = []


func _ready() -> void:
	var tower := await _spawn()
	var only := ""
	var sweep := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.substr(7)
		elif arg == "--sweep":
			sweep = true
	if sweep:
		tower.queue_free()
		await get_tree().process_frame
		await _sweep_all_archetypes()
		return
	var rooms: Array = []
	for value in tower.get("_rooms") as Array:
		var room := value as DungeonRoom3D
		if room == null:
			continue
		# 走廊连接器不铺：它们是通行管道，不是可停留的房间。
		if room.room_id.begins_with("cr") or room.room_id.begins_with("conn_"):
			continue
		# **不再按 `procedural_shell` 过滤**：安全房（start）走的是
		# `procedural_shell=false` 分支 —— 那份静态场景会被「整个照常使用」，
		# 所以给它铺一份纯公馆件同样有效，而且正是工坊里要打开来编辑的那份。
		# 判据换成 `CONTRACT.supports()`：有门位声明 + 有静态布局，就能铺。
		# 铺装条件：有静态布局可写 + 不是 5m 模块壳房间。
		#
		# **不用 `CONTRACT.supports()`**：那条判据要求 `connection_ports` 里带
		# `door_width_m`，而运行时注入房（`*_inj1/2`、`reward_*`）的端口由注入器
		# 现场造，实测拿不到该字段 —— 用它过滤会把注入房整批漏掉，于是
		# `storage_*` / `trap_25x25` 这些只在注入房里出现的模板永远烘不出美术。
		if not CONTRACT.supports(room):
			if str(room.get("static_layout_scene_path")).is_empty():
				continue
			if bool(room.get("tower_module_shell")):
				continue
		if not only.is_empty() and room.room_id != only:
			continue
		rooms.append(room)
	rooms.sort_custom(func(a, b): return str(a.room_id) < str(b.room_id))
	print("BUILD_ROOMS %d" % rooms.size())

	for value in rooms:
		_build(value as DungeonRoom3D)
	tower.queue_free()
	await get_tree().process_frame

	print("BUILD_WRITTEN %d" % _written.size())
	for path in _written:
		print("  WROTE %s" % path.get_file())
	print("BUILD_%s failures=%d" % ["OK" if _failures.is_empty() else "FAILED", _failures.size()])
	for reason in _failures:
		printerr("BUILD_FAIL ", reason)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _build(room: DungeonRoom3D) -> void:
	var descriptor := CONTRACT.describe(room)
	var target := CONTRACT.art_path(str(room.get("static_layout_scene_path")), descriptor)
	if target.is_empty():
		_fail("%s: art_path 算不出来" % room.room_id)
		return
	var dim: Vector2 = room.call("get_dimensions")
	var cols := int(round(dim.x / GRID))
	var rows := int(round(dim.y / GRID))
	if cols <= 0 or rows <= 0:
		_fail("%s: 尺寸 %.1fx%.1f 不是 5m 整数倍" % [room.room_id, dim.x, dim.y])
		return
	var style := MANOR_PLAN.style_for(room, dim)

	var canvas := Node3D.new()
	canvas.name = "Room_" + room.room_id
	# 工坊靠这个 schema 认「已授权的美术场景」，不设就在列表里消失。
	canvas.set_meta("scene_builder_schema", "shellstorm2.component_scene.v1")
	canvas.set_meta("runtime_room_source_schema", CONTRACT.SCHEMA)
	canvas.set_meta("runtime_room_signature", str(descriptor["signature"]))
	# 直接存 Dictionary，**不要 JSON.stringify**：后者会变成单行字符串，
	# TSCN 序列化时把 `{` 转义成 `\"{\"`，而门禁 `extract_braced()` 是按未转义的
	# 括号配对找的 —— 结果是「字段存在却读不到」，看起来像缺字段。
	canvas.set_meta("runtime_room_geometry", descriptor["geometry"])
	canvas.set_meta("size_m", [dim.x, dim.y])
	canvas.set_meta("grid_unit_m", GRID)
	canvas.set_meta("level_id", "expedition_03")
	canvas.set_meta("room_id", room.room_id)
	canvas.set_meta("template_id", str(descriptor["template_id"]))
	canvas.set_meta("portal_fingerprint", str(descriptor["portal_fingerprint"]))
	canvas.set_meta("built_by", "manor_shell_builder")
	# 供验收与后续美术工序读的"设计意图"，避免看图猜这是哪种原型。
	canvas.set_meta("archetype", str(style["note"]))
	canvas.set_meta("floor_mode", str(style["floor"]))
	canvas.set_meta("window_mode", str(style["windows"]))

	var art := Node3D.new()
	art.name = "ArtComponents"
	canvas.add_child(art)
	art.owner = canvas

	var door_map := _door_cells(room, cols, rows)
	var floor_stats := _floor_grid(art, canvas, dim, cols, rows, style)
	var wall_stats := _walls(art, canvas, dim, cols, rows, door_map, str(style["windows"]))

	var packed := PackedScene.new()
	var error := packed.pack(canvas)
	if error != OK:
		_fail("%s: pack 失败 %s" % [room.room_id, error_string(error)])
		canvas.free()
		return
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	error = ResourceSaver.save(packed, target)
	canvas.free()
	if error != OK:
		_fail("%s: 保存失败 %s" % [room.room_id, error_string(error)])
		return
	_written.append(target)
	print("BUILD %-20s %-6s %-9s %-11s %-11s cells=%dx%d tiles=%d walls=%d(win=%d) doors=%d"
		% [room.room_id, str(room.room_type), str(style["note"]), str(style["floor"]),
			str(style["windows"]), cols, rows, int(floor_stats["total"]),
			int(wall_stats["total"]), int(wall_stats["windows"]),
			int(door_map.get("_door_count", 0))])


## 按「房型 + 短边」取原型 —— **已迁到 `ManorShellPlan.style_for()`**。
## 这里只保留一个转发，避免调用点判断两套名字。


## 把每个 side 上的门位换成「第几格」。
## lane 必须与某个格心精确对齐（<0.01）—— 对不齐说明这个种子把门放在了半格上，
## 那时该面不开窗（避免门墙错位），并报出来。
func _door_cells(room: DungeonRoom3D, cols: int, rows: int) -> Dictionary:
	var dim: Vector2 = room.call("get_dimensions")
	var cell_x := _cells(dim.x, cols)
	var cell_z := _cells(dim.y, rows)
	var result := {"north": [], "south": [], "west": [], "east": [], "_door_count": 0}
	# 同一面可能多门（hub 同侧双门）。
	for value in room.get("connection_ports"):
		var port := value as Dictionary
		var side := str(port.get("side", ""))
		if not result.has(side):
			continue
		var lane := float(port.get("lane_m", 0.0))
		var cells: Array = cell_x if side in ["north", "south"] else cell_z
		var found := -1
		for index in range(cells.size()):
			if absf(float(cells[index]) - lane) < 0.01:
				found = index
				break
		if found < 0:
			push_warning("壳铺装：%s 的 %s 面门位 %.2f 不在任何 5m 格心上，该面不用美术墙"
				% [room.room_id, side, lane])
			continue
		var list: Array = result[side]
		if not list.has(found):
			list.append(found)
			result["_door_count"] = int(result["_door_count"]) + 1
	for side in ["north", "south", "west", "east"]:
		var list: Array = result[side]
		list.sort()
	return result


func _cells(length: float, count: int) -> Array[float]:
	var out: Array[float] = []
	for index in range(count):
		out.append(-length * 0.5 + (float(index) + 0.5) * GRID)
	return out


## 铺地板。三种模式：
##   full        — 每格都用 `mat`
##   stone_ring  — 最外圈用 `ring`（石），内心用 `mat`（木）
##   wood_ring   — 最外圈用 `mat`（木），内心用 `ring`（石）
##
## 分区时**外圈恒为 1 格**：5×5 的房间外圈吃掉 1 格还剩 3×3 内心，仍然成立；
## 但 3×3 及更小的房间退化为满铺（外圈 = 全部，分区没有意义）。
func _floor_grid(art: Node3D, canvas: Node3D, dim: Vector2, cols: int, rows: int,
		style: Dictionary) -> Dictionary:
	var cell_x := _cells(dim.x, cols)
	var cell_z := _cells(dim.y, rows)
	var mode := str(style["floor"])
	var main_mat := str(style["mat"])
	var ring_mat := str(style.get("ring", main_mat))
	var stats := {"total": 0, "ring": 0, "core": 0}
	for row in range(rows):
		for col in range(cols):
			var prefab := main_mat
			var part := "core"
			if mode != "full" and cols >= 4 and rows >= 4:
				var is_ring := col == 0 or row == 0 or col == cols - 1 or row == rows - 1
				if is_ring:
					# stone_ring: 外圈石、内心木 → 外圈取 ring
					# wood_ring : 外圈木、内心石 → 外圈取 mat，内心取 ring
					prefab = ring_mat if mode == "stone_ring" else main_mat
					part = "ring"
				else:
					prefab = main_mat if mode == "stone_ring" else ring_mat
			elif mode != "full":
				# 太小的房间分区无意义，退化为满铺主材质。
				prefab = main_mat
			_add(prefab, art, canvas, Vector3(cell_x[col], 0.0, cell_z[row]), 0.0,
				"Floor_%02d_%02d" % [col, row])
			stats["total"] = int(stats["total"]) + 1
			stats[part] = int(stats[part]) + 1
	return stats


func _walls(art: Node3D, canvas: Node3D, dim: Vector2, cols: int, rows: int,
		door_map: Dictionary, window_mode: String) -> Dictionary:
	var total := 0
	var window_count := 0
	var cell_x := _cells(dim.x, cols)
	var cell_z := _cells(dim.y, rows)
	var sides := [
		{"side": "north", "cells": cell_x, "axis": "x", "at": -dim.y * 0.5, "yaw": 0.0},
		{"side": "south", "cells": cell_x, "axis": "x", "at": dim.y * 0.5, "yaw": 180.0},
		{"side": "west", "cells": cell_z, "axis": "z", "at": -dim.x * 0.5, "yaw": 90.0},
		{"side": "east", "cells": cell_z, "axis": "z", "at": dim.x * 0.5, "yaw": 90.0},
	]
	for spec in sides:
		var side := str(spec["side"])
		var cells: Array = spec["cells"]
		var at := float(spec["at"])
		var yaw := float(spec["yaw"])
		var along_x := str(spec["axis"]) == "x"
		var door_indices: Array = door_map.get(side, [])
		var window_indices: Array = _window_cells(cells, door_indices, window_mode, side)
		for index in range(cells.size()):
			var along := float(cells[index])
			var position := Vector3(along, 0.0, at) if along_x else Vector3(at, 0.0, along)
			var prefab := WALL
			var name := "Wall_%s_%02d" % [side, index]
			if door_indices.has(index):
				prefab = WALL_DOOR
				name = "DoorWall_%s_%02d" % [side, index]
			elif window_indices.has(index):
				prefab = WALL_WINDOW
				name = "WindowWall_%s_%02d" % [side, index]
				window_count += 1
			_add(prefab, art, canvas, position, yaw, name)
			total += 1
	return {"total": total, "windows": window_count}


## 决定这一面哪几格开窗。
##
## `pair`：挑「关于房间中心对称、且两端都不是门位」的一对格子，取最靠中心的那对。
##   对称是为了视觉平衡；靠中心是为了避开墙角的挤碰。
##
## `double_pair`：两对，形成"长窗廊"节奏。
##   **这是为大空间准备的手段** —— 45×40 这类 9 格长的墙面只开一对窗会显得空，
##   开满通窗又变成"玻璃幕墙"、失去墙垛。两对（4 窗）间距均匀，才是公馆长廊的做法。
##   与同尺寸枢纽的区分就落在窗数上：本档 16 窗，枢纽通窗 25 窗。
##
## `clerestory`：除门位、以及门位**相邻的墙垛**外全开。留一格墙垛是刻意的 ——
##   门两侧裸着通窗会像"玻璃幕墙接了个洞"，有墙垛才是公馆的门厅做法。
##
## `single_side`：只有北面给一对，其余全实心。单向采光把光压在一面，
##   明暗差最大，适合陈列（宝箱/事件房的视线引导）。
##
## `blind`：一格都不开。
func _window_cells(cells: Array, door_indices: Array, mode: String, side: String) -> Array:
	if mode == "blind" or cells.is_empty():
		return []
	if mode == "single_side":
		if side != "north":
			return []
		return _symmetric_pair(cells, door_indices)
	if mode == "double_pair":
		return _double_pair(cells, door_indices)
	if mode == "clerestory":
		var blocked := {}
		for index in door_indices:
			blocked[index] = true
			blocked[index - 1] = true
			blocked[index + 1] = true
		var out: Array = []
		for index in range(cells.size()):
			if blocked.has(index):
				continue
			out.append(index)
		# 全被挡住（例如 2 格宽的门廊）就退化成一对，至少有一线光。
		if out.is_empty():
			return _symmetric_pair(cells, door_indices)
		return out
	return _symmetric_pair(cells, door_indices)


## 两对对称窗：先按"到中心的距离"由近到远枚举对称对，再挑出**互不相邻**的两对。
##
## 必须互不相邻（`|i-j| > 1`）：相邻两格都开窗等于合成一个 10m 宽的洞，
## 那不是"长窗廊"，是"拆了半面墙"。
## 找不到两对就退回一对 —— 小房间（6 格宽）本来也只能容下一对。
func _double_pair(cells: Array, door_indices: Array) -> Array:
	var count := cells.size()
	var pairs: Array = []
	for i in range(count):
		for j in range(i + 1, count):
			if absf(float(cells[i]) + float(cells[j])) < 0.01:
				if door_indices.has(i) or door_indices.has(j):
					continue
				pairs.append({"first": i, "second": j, "dist": absf(float(cells[i]))})
	pairs.sort_custom(func(a, b): return float(a["dist"]) < float(b["dist"]))
	if pairs.size() < 2:
		return _symmetric_pair(cells, door_indices)
	var best: Array = []
	for pair in pairs:
		var pick: Array = [int(pair["first"]), int(pair["second"])]
		for other in pairs:
			if other == pair:
				continue
			# 内层对的跨度必须比外层小，否则两对会交叉或重叠
			if float(other["dist"]) >= float(pair["dist"]):
				continue
			var candidate: Array = [int(other["first"]), int(other["second"])]
			var disjoint := true
			for a in pick:
				for b in candidate:
					if absi(a - b) <= 1:
						disjoint = false
			if disjoint:
				best = pick + candidate
				best.sort()
				return best
	return _symmetric_pair(cells, door_indices)


func _symmetric_pair(cells: Array, door_indices: Array) -> Array:
	var count := cells.size()
	var pairs: Array = []
	for i in range(count):
		for j in range(i + 1, count):
			if absf(float(cells[i]) + float(cells[j])) < 0.01:
				pairs.append([i, j, absf(float(cells[i]))])
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
		var distance := absf(float(cells[index]))
		if distance < best_distance:
			best_distance = distance
			best = index
	return [best] if best >= 0 else []


func _add(prefab_path: String, parent: Node3D, canvas: Node3D, position: Vector3,
		yaw_degrees: float, node_name: String) -> void:
	var packed := load(prefab_path) as PackedScene
	if packed == null:
		_fail("加载不了 %s" % prefab_path)
		return
	var instance := packed.instantiate() as Node3D
	if instance == null:
		_fail("prefab 根不是 Node3D: %s" % prefab_path)
		return
	instance.name = node_name
	instance.position = position
	instance.rotation.y = deg_to_rad(yaw_degrees)
	parent.add_child(instance)
	# 不设 owner 就进不了 PackedScene —— 保存出来是空的。
	instance.owner = canvas


func _spawn(seed_override: int = -1) -> Node:
	var tower := SCENE.instantiate()
	tower.set("test_mode", true)
	tower.set("run_seed_override", SEED if seed_override < 0 else seed_override)
	add_child(tower)
	for _frame in 20:
		await get_tree().process_frame
	for value in tower.get("_rooms") as Array:
		var room := value as DungeonRoom3D
		if room != null:
			room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
			room.ensure_shell_built()
			room.ensure_detail_built()
	for _frame in 3:
		await get_tree().process_frame
	return tower


## 跨种子补齐：把所有 flow 模板下出现过的「原型组合」各铺一份。
##
## ## 为什么需要它
##
## 单种子只能看到那一条 flow 骨架抽到的房型。实测 24 个种子并集里还有
## `storage_25x25` / `storage_40x30` / `trap_25x25` / `scavenge_25x25` / `event_25x25`
## 五个模板从未被烘焙过 —— 玩家抽到就是白盒。这里把 24 个种子扫一遍，
## 每个 `(模板, 签名, 原型指纹)` 只铺一次（同键后写会覆盖前写，没有意义）。
##
## 门位由运行时按本局重算，所以"用哪个种子的门位烘焙"不影响最终画面。
const SWEEP_SEEDS := [
	77003244, 100990, 42, 123456, 7, 99, 2026, 31415, 55555, 808080,
	9173, 6060, 1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12, 13,
]


func _sweep_all_archetypes() -> void:
	var seen := {}
	var unknown_types := {}
	for seed_value in SWEEP_SEEDS:
		var tower := await _spawn(seed_value)
		for value in tower.get("_rooms") as Array:
			var room := value as DungeonRoom3D
			if room == null:
				continue
			if room.room_id.begins_with("cr") or room.room_id.begins_with("conn_"):
				continue
			if str(room.get("static_layout_scene_path")).is_empty():
				continue
			if bool(room.get("tower_module_shell")):
				continue
			var d := CONTRACT.describe(room)
			var style: Dictionary = d.get("style", {})
			if str(style.get("note", "")) == "未登记原型":
				unknown_types[str(room.room_type)] = true
			var key := "%s|%s|%s" % [
				str(d.get("template_id", "")),
				str(d.get("signature", "")).substr(0, 12),
				str(d.get("style_fingerprint", "")),
			]
			if seen.has(key):
				continue
			seen[key] = seed_value
			_build(room)
		tower.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	print("SWEEP_SEEDS %d  SWEEP_KEYS %d" % [SWEEP_SEEDS.size(), seen.size()])
	if not unknown_types.is_empty():
		var names: Array[String] = []
		for key in unknown_types.keys():
			names.append(str(key))
		names.sort()
		push_warning("ARCHETYPES 未登记这些 room_type，已按中性原型烘焙：%s" % ", ".join(names))
		print("SWEEP_UNKNOWN_TYPES %s" % ", ".join(names))
	print("BUILD_WRITTEN %d" % _written.size())
	print("BUILD_%s failures=%d" % ["OK" if _failures.is_empty() else "FAILED", _failures.size()])
	for reason in _failures:
		printerr("BUILD_FAIL ", reason)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _fail(message: String) -> void:
	_failures.append(message)
