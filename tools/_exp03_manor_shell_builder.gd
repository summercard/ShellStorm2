extends Node
## 远征03 公馆壳体铺装器：按房间功能铺「墙 + 地板」两件结构。
##
## ## 审美方案（本器唯一的设计判断，改这里就是改风格）
##
## 用光与材质区分「危险」与「安全」，而不是每间房一样：
##
##   · 深灰石材 + 无窗 → 战斗、Boss、陷阱（冷、封闭、看不清边界）
##   · 人字木地板 + 铅条窗 → 准备、撤离、宝箱、商店、枢纽（暖、有光、有归属感）
##
## 枢纽（hub）虽然是 COMBAT，但用木地板 + 窗 —— 多门交汇的大堂，与普通战斗房
## 在视觉上立刻分开。这是给玩家的方向感：亮的是通道，暗的是要打的地方。
##
## ## 门墙必须跟门位走
##
## `manor_wall_door` 洞口固定 2.2m 居中，只能摆在「本局门位所在的那一格」。
## 摆错就是把门堵死（实心件 `collision_owner: self` 带碰撞）。
## 复用键不含门位，所以文件名带门位指纹（见 `_portal_fingerprint`）。
##
## ## 覆盖判定
##
## 每面墙的**每一格**都放墙（门位格放门墙），地板**每一格**都放地砖 ——
## 这样 `_art_layer_coverage()` 才会判定"铺满"，程序化壳体才让位。
## 少一格就退回程序化，美术等于白做。

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel03_3D.tscn")
const CONTRACT := preload("res://src/world3d/RuntimeRoomArtSource.gd")
const MANOR := "res://assets/art/environments/tower_zones/expedition/runtime/common_components"

const WALL := MANOR + "/manor_wall_standard/env_manor_wall_standard_root_top3d.tscn"
const WALL_DOOR := MANOR + "/manor_wall_door/env_manor_wall_door_root_top3d.tscn"
const WALL_WINDOW := MANOR + "/manor_wall_window/env_manor_wall_window_root_top3d.tscn"
const FLOOR_WOOD := MANOR + "/manor_floor_wood/env_manor_floor_wood_root_top3d.tscn"
const FLOOR_STONE := MANOR + "/manor_floor_stone/env_manor_floor_stone_root_top3d.tscn"

const GRID := 5.0
const SEED := 77003244

## 房型 → 风格。键是 room_type，值含地板 prefab 与是否开窗。
##
## 为什么按 room_type 而不是 room_id：换种子后房间 id 不变但尺寸会变，
## 而"这间房是干什么用"才决定它该长什么样。
const STYLE_BY_TYPE := {
	# 危险 / 战斗：冷石，无窗
	"COMBAT": {"floor": FLOOR_STONE, "windows": false},
	"BOSS": {"floor": FLOOR_STONE, "windows": false},
	"TRAP": {"floor": FLOOR_STONE, "windows": false},
	# 功能 / 安全：暖木，开窗
	"UPGRADE": {"floor": FLOOR_WOOD, "windows": true},
	"EXTRACTION": {"floor": FLOOR_WOOD, "windows": false},
	"EVENT": {"floor": FLOOR_WOOD, "windows": true},
	"SCAVENGE": {"floor": FLOOR_WOOD, "windows": true},
	"MERCHANT": {"floor": FLOOR_WOOD, "windows": true},
	"SAFE_ROOM": {"floor": FLOOR_WOOD, "windows": false},
	"STAIR_LOBBY": {"floor": FLOOR_WOOD, "windows": false},
}

## 枢纽单独一条：虽然是 COMBAT，但要用"大堂"气质。
const HUB_IDS := ["hub_01", "hub_02"]

var _failures: Array[String] = []
var _written: Array[String] = []


func _ready() -> void:
	var tower := await _spawn()
	var rooms: Array = []
	for value in tower.get("_rooms") as Array:
		var room := value as DungeonRoom3D
		if room == null or not room.procedural_shell:
			continue
		if room.room_id.begins_with("cr") or room.room_id.begins_with("conn_"):
			continue
		rooms.append(room)
	rooms.sort_custom(func(a, b): return str(a.room_id) < str(b.room_id))
	print("BUILD_ROOMS %d" % rooms.size())

	for value in rooms:
		var room := value as DungeonRoom3D
		_build(room)
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
	var canvas := Node3D.new()
	canvas.name = "Room_" + room.room_id
	# 工坊靠这个 schema 认「已授权的美术场景」，不设就在列表里消失。
	canvas.set_meta("scene_builder_schema", "shellstorm2.component_scene.v1")
	canvas.set_meta("runtime_room_source_schema", CONTRACT.SCHEMA)
	canvas.set_meta("runtime_room_signature", str(descriptor["signature"]))
	# 直接存 Dictionary，**不要 JSON.stringify**：后者会变成单行字符串，
	# TSCN 序列化时把 `{` 转义成 `\"{\"`，而门禁 `extract_braced()` 是按未转义的
	# 括号配对找的 —— 结果是「字段存在却读不到」，看起来像缺字段。
	# 存 Dictionary 时 Godot 写成多行 `{ ... }`，与采集器（capture_runtime）一致。
	canvas.set_meta("runtime_room_geometry", descriptor["geometry"])
	canvas.set_meta("size_m", [dim.x, dim.y])
	canvas.set_meta("grid_unit_m", GRID)
	canvas.set_meta("level_id", "expedition_03")
	canvas.set_meta("room_id", room.room_id)
	canvas.set_meta("template_id", str(descriptor["template_id"]))
	canvas.set_meta("portal_fingerprint", str(descriptor["portal_fingerprint"]))
	canvas.set_meta("built_by", "manor_shell_builder")

	var art := Node3D.new()
	art.name = "ArtComponents"
	canvas.add_child(art)
	art.owner = canvas

	var style := _style_for(room)
	_floor_grid(art, canvas, dim, cols, rows, str(style["floor"]))
	var door_map := _door_cells(room, cols, rows)
	var wall_stats := _walls(art, canvas, dim, cols, rows, door_map, bool(style["windows"]))

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
	print("BUILD %-22s %-6s size=%.0fx%.0f floor=%-5s doors=%d windows=%d walls=%d"
		% [room.room_id, str(room.room_type), dim.x, dim.y,
			"stone" if str(style["floor"]).contains("stone") else "wood",
			int(door_map.get("_door_count", 0)), int(wall_stats.get("windows", 0)),
			int(wall_stats.get("total", 0))])


func _style_for(room: DungeonRoom3D) -> Dictionary:
	# 枢纽优先：多门交汇需要"大堂"气质，与普通战斗房分开。
	for hub in HUB_IDS:
		if room.room_id == hub:
			return {"floor": FLOOR_WOOD, "windows": true}
	var type_id := str(room.room_type)
	if STYLE_BY_TYPE.has(type_id):
		return STYLE_BY_TYPE[type_id]
	# 未知房型按"安全侧"处理：暖木无窗，至少不难看。
	return {"floor": FLOOR_WOOD, "windows": false}


## 把每个 side 上的门位换成「第几格」。
## lane 必须与某个格心精确对齐（<0.01）—— 对不齐说明这个种子把门放在了半格上，
## 那时 gate 会拒绝整面铺装（避免门墙错位），并报出来。
func _door_cells(room: DungeonRoom3D, cols: int, rows: int) -> Dictionary:
	var dim: Vector2 = room.call("get_dimensions")
	var cell_x := _cells(dim.x, cols)
	var cell_z := _cells(dim.y, rows)
	var result := {"north": [], "south": [], "west": [], "east": [], "_door_count": 0}
	# 同一面可能多门（EGT 枢纽同侧双门）。
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


func _floor_grid(art: Node3D, canvas: Node3D, dim: Vector2, cols: int, rows: int, prefab: String) -> void:
	var cell_x := _cells(dim.x, cols)
	var cell_z := _cells(dim.y, rows)
	for row in range(rows):
		for col in range(cols):
			_add(prefab, art, canvas, Vector3(cell_x[col], 0.0, cell_z[row]), 0.0,
				"Floor_%02d_%02d" % [col, row])


func _walls(art: Node3D, canvas: Node3D, dim: Vector2, cols: int, rows: int,
		door_map: Dictionary, windows: bool) -> Dictionary:
	var total := 0
	var window_count := 0
	var cell_x := _cells(dim.x, cols)
	var cell_z := _cells(dim.y, rows)
	# 每面：沿墙方向的格心列表 + 该面门位格 + 放置位置与朝向
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
		var window_indices: Array = []
		if windows:
			window_indices = _window_cells(cells, door_indices)
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


## 每面挑「关于房间中心对称、且两端都不是门位」的一对格子开窗，取最靠中心的那对。
## 对称是为了视觉平衡；靠中心是为了避开墙角的挤碰。
## 找不到对称对就退而取最近中心的单个非门位格；连这个都没有就不开窗。
func _window_cells(cells: Array, door_indices: Array) -> Array:
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


func _spawn() -> Node:
	var tower := SCENE.instantiate()
	tower.set("test_mode", true)
	tower.set("run_seed_override", SEED)
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


func _fail(message: String) -> void:
	_failures.append(message)
