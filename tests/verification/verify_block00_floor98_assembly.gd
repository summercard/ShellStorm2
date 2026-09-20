extends Node
## 验收探针：区块00「主人的办公室」在塔楼 98F 的**运行时装配**。
##
## 区块00 是「拿现有 5m 通用组件直接把整层拼出来」，不走数据驱动生成器：
## Blender 摆位源（block_00_master_office_layout_v002.layout.json）→ 运行时壳体。
## 本探针在 headless 下真跑一次 98F 的 FloorBundle，只读运行时节点树与元数据，
## 逐项断言**装配结果**，而不是设计意图或摆位源自述：
##
##   A. 98F plan 被区块00 接管（authored_layout / 四房 / planar_z_shift / exit_side=west）
##   B. 四间房都走授权壳体路径（DungeonRoom3D._build_authored_layout_shell）
##   C. 组件计数 == 摆位源逐房计数；总量 11 L 件 / 27 墙（含提升门墙）/ 49 地砖
##   D. 门厅东门世界坐标 (35,−24,2.5) —— 99→98 楼梯下端必须落在这里
##   E. 共墙 lane 守恒：全场无两块墙件 / 两个 L 件 / 两块地砖落在同一世界位置
##   F. 地砖内嵌静态碰撞全关（承重归 TowerFloorStage3D）
##   G. 委托门（墙归邻房的那一侧）面板已隐藏、门节点与交互仍在
##   H. 楼层台座按四房**真实足迹**挖洞（不是 15×15 方格）
##   I. 下行走办公室西墙：竖直边 side=west 且 seed gate 指向 97F
##
## 期望值来源：摆位源逐房计数、几何常量（GRID_UNIT_M=5、层高 12、门厅锚点）
## 与 RoomDoorLane 的门槽推导 —— 装配结果一律不硬编码。
## 打印 BLOCK00_ASSEMBLY_OK 表示全过；任一失败打印 BLOCK00_ASSEMBLY_FAILED。
##
## 反向对照（改坏会变红）：
##   · 把 DungeonRoom3D._build_shell 里 authored 分支注释掉 → B/C/E 全红；
##   · 把 _stair_lobby_visual_holes 的 authored 分支删掉 → H 红（退回 15×15 方格）；
##   · 把 Block00MasterOfficeLayout3D 的 exit_side 改回 "east" → A/I 红。

const FLOOR_INDEX := 2
const FLOOR_NUMBER := 98
const NEXT_FLOOR_INDEX := 3
const SEED := 990098
const TOL := 0.05

const BLOCK00_LAYOUT_ASSET_ID := "ENV-BATTLE-BLOCK00-ART-LAYOUT-3D"
const BLOCK00_LAYOUT_VERSION := "v002"
## 摆位源组件 ID → 运行时使用的组件包（与 DungeonRoom3D 的映射表同源）。
const FLOOR_TILE_COMPONENT_IDS: Array[String] = [
	"ENV-BATTLE-COMMON-FLOOR-TILE-R01-C01",
	"ENV-BATTLE-COMMON-FLOOR-TILE-R01-C02",
]

## 门厅 = 原 98F 入口安全房（15×15 @ planar(27.5, 2.5)），区块00 必须逐值命中。
const EXPECTED_ENTRY_PLANAR := Vector2(27.5, 2.5)
const EXPECTED_ENTRY_DIMS := Vector2(15.0, 15.0)
## 99→98 楼梯下端落点 = 门厅东墙中心（由入口房锚点推出，不是抄来的数字）。
const EXPECTED_ENTRY_EAST_DOOR_WORLD := Vector3(35.0, -24.0, 2.5)
## 平面 z 平移量 = 摆位源块内原点 → 塔楼 98F 平面的那 5m 落差。
const EXPECTED_PLANAR_Z_SHIFT := 5.0

const EXPECTED_TOTAL_CORNER_L := 11
const EXPECTED_TOTAL_WALLS := 27
const EXPECTED_TOTAL_TILES := 49
const EXPECTED_ROOM_COUNT := 4

## 摆位源房间 → 运行时房间 id（沿用原 98F 规划同名键，存档 room_progress 不受换拓扑影响）。
const ROOM_ID_BY_AUTHORED := {
	"lobby": "floor_01_entry",
	"corridor": "floor_01_hub",
	"meeting_room": "floor_01_main_02",
	"master_office": "floor_01_exit",
}
## 各房应有门向：东西贯通链（门厅→走廊→会议室→办公室）+ 门厅东上行 + 办公室西下行。
const EXPECTED_ROOM_DOORS := {
	"floor_01_entry": ["east", "west"],
	"floor_01_hub": ["east", "west"],
	"floor_01_main_02": ["east", "west"],
	"floor_01_exit": ["east", "west"],
}
## 共墙 lane 归属模型（摆位源 placement_model「同一 lane 全局只出一个实例」）下，
## 「墙归邻房、本房不重复建门墙」的门侧 —— 这是契约，不是推导结果：
##   lobby.west(x=20)  归 corridor.east
##   meeting_room.east(x=15) 归 corridor.west
##   master_office.east(x=−25) 归 meeting_room.west
const EXPECTED_DELEGATED_DOOR_SIDES := {
	"floor_01_entry": ["west"],
	"floor_01_hub": [],
	"floor_01_main_02": ["east"],
	"floor_01_exit": ["east"],
}

var _failures: Array[String] = []
var _checks := 0


func _ready() -> void:
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	if scene == null:
		_finish("TowerDescent3D.tscn 加载失败")
		return
	var tower := scene.instantiate() as TowerDescent3D
	if tower == null:
		_finish("场景根节点不是 TowerDescent3D")
		return
	tower.test_mode = true
	tower.run_seed_override = SEED
	add_child(tower)
	await _settle()

	var committed := tower.generate_through_floor_for_test(FLOOR_NUMBER)
	await _settle()
	_check(committed, "generate_through_floor_for_test(%d) 返回 false" % FLOOR_NUMBER)

	# 探针前置哨兵：拿不到塔楼内部字典说明环境变了，后面的断言全无意义。
	var snapshots := tower.get("_floor_plan_snapshots") as Dictionary
	var records_by_id := tower.get("_records") as Array
	var room_by_id := tower.get("_room_by_id") as Dictionary
	var floor_rooms := tower.get("_floor_room_ids") as Dictionary
	_check(snapshots != null, "取不到 _floor_plan_snapshots")
	_check(room_by_id != null and not room_by_id.is_empty(), "取不到 _room_by_id（0 个房间）")
	_check(records_by_id != null and not records_by_id.is_empty(), "取不到 _records（0 条记录）")
	if snapshots == null or room_by_id == null or records_by_id == null:
		_finish("塔楼内部状态不可读")
		return

	var rooms := _collect_block00_rooms(room_by_id, floor_rooms)
	_check(
		rooms.size() == EXPECTED_ROOM_COUNT,
		"98F 房间数应为 %d，实得 %d（%s）"
		% [EXPECTED_ROOM_COUNT, rooms.size(), str(rooms.keys())]
	)

	_check_plan(snapshots)
	_check_shells(rooms)
	_check_anchor_door(rooms)
	_check_lane_conservation(rooms)
	_check_floor_tile_collision(rooms)
	_check_stage_holes(tower)
	_check_descent_side(tower)

	_finish("")


func _finish(error_head: String) -> void:
	print("\n########## BLOCK00 98F 装配验收 ##########")
	print("-- 断言数 = %d，失败数 = %d" % [_checks, _failures.size()])
	if not error_head.is_empty():
		print("-- 前置错误: %s" % error_head)
	for message in _failures:
		print("-- FAIL: %s" % message)
	if _failures.is_empty() and error_head.is_empty():
		print("BLOCK00_ASSEMBLY_OK checks=%d" % _checks)
		get_tree().quit(0)
		return
	print("BLOCK00_ASSEMBLY_FAILED failures=%d" % (_failures.size() + (0 if error_head.is_empty() else 1)))
	get_tree().quit(1)


func _settle() -> void:
	for i in 6:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.35).timeout


func _check(condition: bool, message: String) -> bool:
	_checks += 1
	if condition:
		return true
	_failures.append(message)
	print("  [FAIL] %s" % message)
	return false


func _check_float(actual: float, expected: float, message: String) -> bool:
	return _check(
		absf(actual - expected) <= TOL,
		"%s (actual=%s expected=%s)" % [message, str(actual), str(expected)]
	)


func _check_vec3(actual: Vector3, expected: Vector3, message: String) -> bool:
	return _check(
		actual.distance_to(expected) <= TOL,
		"%s (actual=%s expected=%s)" % [message, str(actual), str(expected)]
	)


## 98F 的四间区块00 房间（按运行时房间 id）。只认「授权壳体」标记，防止
## 生成器房表被误当成区块00 而假绿。
func _collect_block00_rooms(room_by_id: Dictionary, floor_rooms: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for room_id_value in floor_rooms.get(FLOOR_INDEX, []):
		var room_id := str(room_id_value)
		var room := room_by_id.get(room_id) as DungeonRoom3D
		if room == null:
			continue
		if not room.authored_layout_shell:
			continue
		result[room_id] = room
	return result


func _check_plan(snapshots: Dictionary) -> void:
	print("\n---- A. 98F plan 被区块00 接管 ----")
	var plan := snapshots.get(FLOOR_INDEX, {}) as Dictionary
	if not _check(not plan.is_empty(), "98F 无 plan snapshot"):
		return
	_check(
		bool(plan.get("authored_layout", false)),
		"98F plan 未被区块00 接管（authored_layout != true）"
	)
	_check(
		str(plan.get("authored_layout_asset_id", "")) == BLOCK00_LAYOUT_ASSET_ID,
		"plan authored_layout_asset_id=%s 期望 %s"
		% [str(plan.get("authored_layout_asset_id", "")), BLOCK00_LAYOUT_ASSET_ID]
	)
	_check(
		str(plan.get("authored_layout_version", "")) == BLOCK00_LAYOUT_VERSION,
		"plan authored_layout_version=%s 期望 %s"
		% [str(plan.get("authored_layout_version", "")), BLOCK00_LAYOUT_VERSION]
	)
	_check_float(
		float(plan.get("authored_layout_planar_z_shift_m", -999.0)),
		EXPECTED_PLANAR_Z_SHIFT,
		"平面 z 平移量（摆位源块内原点 → 98F 平面）"
	)
	_check(
		str(plan.get("exit_side", "")) == "west",
		"98F exit_side=%s 期望 west（下行走办公室西墙）" % str(plan.get("exit_side", ""))
	)
	# 房间 id 必须沿用原 98F 同名键，否则存档 room_progress / 到达门事务会错位。
	var specs := plan.get("rooms", []) as Array
	_check(specs.size() == EXPECTED_ROOM_COUNT, "plan 房间数=%d 期望 %d" % [specs.size(), EXPECTED_ROOM_COUNT])
	var ids: Array[String] = []
	for value in specs:
		ids.append(str((value as Dictionary).get("id", "")))
	for room_id in ROOM_ID_BY_AUTHORED.values():
		_check(str(room_id) in ids, "plan 缺房间 id=%s（存档键必须沿用）" % str(room_id))
	var entry_spec := _spec_by_key(specs, "entry")
	_check(
		(entry_spec.get("position", Vector2.ZERO) as Vector2).is_equal_approx(EXPECTED_ENTRY_PLANAR),
		"门厅落位=%s 期望 %s（99→98 楼梯下端锚点不可动）"
		% [str(entry_spec.get("position", Vector2.ZERO)), str(EXPECTED_ENTRY_PLANAR)]
	)
	_check(
		(entry_spec.get("dimensions", Vector2.ZERO) as Vector2).is_equal_approx(EXPECTED_ENTRY_DIMS),
		"门厅尺寸=%s 期望 %s" % [str(entry_spec.get("dimensions", Vector2.ZERO)), str(EXPECTED_ENTRY_DIMS)]
	)


func _spec_by_key(specs: Array, key: String) -> Dictionary:
	for value in specs:
		var spec := value as Dictionary
		if str(spec.get("key", "")) == key:
			return spec
	return {}


func _check_shells(rooms: Dictionary) -> void:
	print("\n---- B/C. 授权壳体 + 组件计数 ----")
	var manifest := Block00MasterOfficeLayout3D.load_manifest()
	if not _check(not manifest.is_empty(), "区块00 摆位源加载失败"):
		return
	var manifest_errors := Block00MasterOfficeLayout3D.validate_manifest(manifest)
	_check(manifest_errors.is_empty(), "摆位源自检失败: %s" % str(manifest_errors))
	var expected := _expected_roles_by_room(manifest)

	var total_corner := 0
	var total_solid := 0
	var total_door_wall := 0
	var total_tile := 0
	var total_doors := 0
	var total_delegated := 0
	for authored_id_value in ROOM_ID_BY_AUTHORED.keys():
		var authored_id := str(authored_id_value)
		var room_id := str(ROOM_ID_BY_AUTHORED[authored_id])
		var room := rooms.get(room_id) as DungeonRoom3D
		if not _check(room != null, "缺房间 %s（%s）" % [room_id, authored_id]):
			continue
		# B. 走的是授权壳体路径，且资产身份对上。
		_check(room.authored_layout_shell, "%s 未走授权壳体（authored_layout_shell=false）" % room_id)
		_check(
			bool(room.get_meta("authored_layout_shell", false)),
			"%s 缺 authored_layout_shell 元数据（壳体可能没建）" % room_id
		)
		_check(
			str(room.get_meta("authored_layout_asset_id", "")) == BLOCK00_LAYOUT_ASSET_ID,
			"%s 资产 ID=%s 期望 %s"
			% [room_id, str(room.get_meta("authored_layout_asset_id", "")), BLOCK00_LAYOUT_ASSET_ID]
		)
		_check(
			str(room.authored_layout_room_id) == authored_id,
			"%s authored_room_id=%s 期望 %s" % [room_id, str(room.authored_layout_room_id), authored_id]
		)
		_check(
			(room.get_meta("authored_layout_unresolved_instances", []) as Array).is_empty(),
			"%s 有组件无法解析：%s" % [room_id, str(room.get_meta("authored_layout_unresolved_instances", []))]
		)

		# C. 运行时计数 vs 摆位源计数。
		var want := expected.get(authored_id, {}) as Dictionary
		var want_corner := int(want.get("corner_l", 0))
		var want_wall := int(want.get("solid_wall", 0)) + int(want.get("door_wall", 0))
		var want_tile := int(want.get("floor_tile", 0))
		var got_corner := int(room.get_meta("authored_layout_corner_count", -1))
		var got_solid := int(room.get_meta("authored_layout_solid_wall_count", -1))
		var got_door_wall := int(room.get_meta("authored_layout_door_wall_count", -1))
		var got_tile := int(room.get_meta("authored_layout_floor_tile_count", -1))
		_check(
			got_corner == want_corner,
			"%s L 角件=%d 期望 %d" % [room_id, got_corner, want_corner]
		)
		_check(
			got_tile == want_tile,
			"%s 地砖=%d 期望 %d" % [room_id, got_tile, want_tile]
		)
		# 门墙会「提升」：摆位源里坐在门槽上的实墙运行时会换成门墙，
		# 所以只有「墙件总量」是稳定口径。
		_check(
			got_solid + got_door_wall == want_wall,
			"%s 墙件总量=%d 期望 %d（solid=%d door_wall=%d）"
			% [room_id, got_solid + got_door_wall, want_wall, got_solid, got_door_wall]
		)
		_check(
			got_door_wall >= int(want.get("door_wall", 0)),
			"%s 门墙=%d 少于摆位源声明的 %d" % [room_id, got_door_wall, int(want.get("door_wall", 0))]
		)

		# 门向 + 委托门集合（共墙 lane 归属）。
		var doors := room.doors.duplicate()
		doors.sort()
		var want_doors := (EXPECTED_ROOM_DOORS.get(room_id, []) as Array).duplicate()
		want_doors.sort()
		_check(
			doors == want_doors,
			"%s 门向=%s 期望 %s" % [room_id, str(doors), str(want_doors)]
		)
		var delegated := (room.get_meta("authored_layout_delegated_door_sides", []) as Array).duplicate()
		delegated.sort()
		var want_delegated := (EXPECTED_DELEGATED_DOOR_SIDES.get(room_id, []) as Array).duplicate()
		want_delegated.sort()
		_check(
			delegated == want_delegated,
			"%s 委托门侧=%s 期望 %s（共墙 lane 归属）" % [room_id, str(delegated), str(want_delegated)]
		)
		total_doors += doors.size()
		total_delegated += delegated.size()

		total_corner += got_corner
		total_solid += got_solid
		total_door_wall += got_door_wall
		total_tile += got_tile

	_check(total_tile > 0 and total_corner > 0, "哨兵：组件样本数为 0（计数断言全是空跑）")
	_check(
		total_corner == EXPECTED_TOTAL_CORNER_L,
		"全场 L 角件=%d 期望 %d（共墙角件必须复用，不得重复）"
		% [total_corner, EXPECTED_TOTAL_CORNER_L]
	)
	_check(
		total_solid + total_door_wall == EXPECTED_TOTAL_WALLS,
		"全场墙件=%d 期望 %d" % [total_solid + total_door_wall, EXPECTED_TOTAL_WALLS]
	)
	_check(
		total_tile == EXPECTED_TOTAL_TILES,
		"全场地砖=%d 期望 %d" % [total_tile, EXPECTED_TOTAL_TILES]
	)
	# 每扇**未委派**的门都必须有一条门墙承接门洞（几何与门槽校验都查不出的隐形契约）。
	_check(
		total_door_wall == total_doors - total_delegated,
		"门墙数=%d 应等于「全场门数 %d − 委托门数 %d」"
		% [total_door_wall, total_doors, total_delegated]
	)


func _expected_roles_by_room(manifest: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for value in manifest.get("instances", []):
		var instance := value as Dictionary
		var role := str(instance.get("slot_role", ""))
		if role == "door_leaf_preview":
			continue
		var room_id := str(instance.get("room_id", ""))
		if not result.has(room_id):
			result[room_id] = {}
		var bucket := result[room_id] as Dictionary
		bucket[role] = int(bucket.get(role, 0)) + 1
	return result


func _check_anchor_door(rooms: Dictionary) -> void:
	print("\n---- D. 门厅东门 = 99→98 楼梯下端落点 ----")
	var entry := rooms.get("floor_01_entry") as DungeonRoom3D
	if not _check(entry != null, "缺门厅 floor_01_entry"):
		return
	# 东门目标应在场（99F 基地），否则门节点不会生成。
	var east_target := str(entry.door_targets.get("east", ""))
	_check(not east_target.is_empty(), "门厅东门没有目标房间 id")
	var east_door := entry.get_door_node("east")
	if _check(east_door != null, "门厅缺东门节点"):
		_check_vec3(
			east_door.global_position,
			EXPECTED_ENTRY_EAST_DOOR_WORLD,
			"门厅东门世界坐标（楼梯下端落点）"
		)
	var east_meta := entry.get_meta("room_door_world_east", Vector3.INF) as Vector3
	_check_vec3(east_meta, EXPECTED_ENTRY_EAST_DOOR_WORLD, "门厅 room_door_world_east 元数据")
	_check_float(
		float(entry.get_meta("tower_wall_door_offset_east", 99.0)),
		0.0,
		"门厅东墙门槽偏移（15m 墙只有一个合法槽 = 0）"
	)


func _check_lane_conservation(rooms: Dictionary) -> void:
	print("\n---- E. 共墙 lane 守恒（同一位置不得出两件）----")
	var wall_keys: Dictionary = {}
	var corner_keys: Dictionary = {}
	var tile_keys: Dictionary = {}
	var wall_samples := 0
	var corner_samples := 0
	var tile_samples := 0
	for room_id_value in rooms.keys():
		var room_id := str(room_id_value)
		var room := rooms[room_id] as DungeonRoom3D
		for value in room.find_children("*", "Node3D", true, false):
			var node := value as Node3D
			if node == null:
				continue
			if node.has_meta("tower_wall_direction"):
				wall_samples += 1
				_accumulate_lane_key(
					wall_keys, room_id, node, "墙件 dir=%s" % str(node.get_meta("tower_wall_direction"))
				)
			elif node.has_meta("tower_wall_corner"):
				corner_samples += 1
				_accumulate_lane_key(
					corner_keys, room_id, node, "L 角件 %s" % str(node.get_meta("tower_wall_corner"))
				)
			elif node.has_meta("walk_plane_snap_y"):
				tile_samples += 1
				_accumulate_lane_key(tile_keys, room_id, node, "地砖")
	_check(wall_samples > 0, "哨兵：全场 0 件墙样本（lane 守恒断言空跑）")
	_check(corner_samples > 0, "哨兵：全场 0 件 L 角样本")
	_check(tile_samples > 0, "哨兵：全场 0 块地砖样本")
	print("   样本数 wall=%d corner=%d tile=%d" % [wall_samples, corner_samples, tile_samples])


## 一件组件在某个世界位置只允许出现一次。共墙双墙 / 双角件 / 双地砖都会在这里现形。
func _accumulate_lane_key(
	keys: Dictionary, room_id: String, node: Node3D, label: String
) -> void:
	var world := node.global_position
	var key := "%s|%.2f|%.2f" % [label, world.x, world.z]
	if keys.has(key):
		_check(
			false,
			"lane 冲突：%s 在 %s 与 %s 各出一件（共墙应只归声明它的房间，同房也不得重复实例）"
			% [key, str(keys[key]), room_id]
		)
		return
	keys[key] = room_id


func _check_floor_tile_collision(rooms: Dictionary) -> void:
	print("\n---- F. 地砖内嵌静态碰撞全关（承重归 TowerFloorStage3D）----")
	var tiles := 0
	var bodies := 0
	var live_bodies: Array[String] = []
	var live_shapes: Array[String] = []
	for room_id_value in rooms.keys():
		var room_id := str(room_id_value)
		var room := rooms[room_id] as DungeonRoom3D
		for value in room.find_children("*", "Node3D", true, false):
			var tile := value as Node3D
			if tile == null or not tile.has_meta("walk_plane_snap_y"):
				continue
			var component_id := str(tile.get_meta("authored_component_id", ""))
			if component_id not in FLOOR_TILE_COMPONENT_IDS:
				continue
			tiles += 1
			for body_value in tile.find_children("*", "StaticBody3D", true, false):
				var body := body_value as StaticBody3D
				if body == null:
					continue
				bodies += 1
				if body.collision_layer != 0:
					live_bodies.append("%s/%s layer=%d" % [room_id, str(body.name), body.collision_layer])
				for shape_value in body.find_children("*", "CollisionShape3D", true, false):
					var shape := shape_value as CollisionShape3D
					if shape != null and not shape.disabled:
						live_shapes.append("%s/%s" % [room_id, str(shape.name)])
	_check(tiles > 0, "哨兵：0 块地砖样本（碰撞去重断言空跑）")
	_check(live_bodies.is_empty(), "地砖内嵌静态碰撞未关：%s" % str(live_bodies))
	_check(live_shapes.is_empty(), "地砖内嵌碰撞形状未禁用：%s" % str(live_shapes))
	print("   样本数 tile=%d 内嵌 StaticBody=%d" % [tiles, bodies])


func _check_stage_holes(tower: Node) -> void:
	print("\n---- H. 楼层台座按四房真实足迹挖洞 ----")
	var stages := tower.get("_floor_stages") as Dictionary
	var stage := stages.get(FLOOR_INDEX) as Node3D
	if not _check(stage != null, "98F 无 floor stage"):
		return
	_check(
		int(stage.get_meta("floor_number", -1)) == FLOOR_NUMBER,
		"stage floor_number=%s 期望 %d" % [str(stage.get_meta("floor_number", -1)), FLOOR_NUMBER]
	)
	var holes := stage.get("additional_visual_holes") as Array
	if not _check(holes != null, "stage 取不到 additional_visual_holes"):
		return
	# 期望 = 四房真实足迹（位置/尺寸取自 plan，与拼装用的同一个房间表）。
	var snapshots := tower.get("_floor_plan_snapshots") as Dictionary
	var plan := snapshots.get(FLOOR_INDEX, {}) as Dictionary
	var expected_holes: Array[Rect2] = []
	for value in plan.get("rooms", []):
		var spec := value as Dictionary
		if not bool(spec.get("authored_layout_shell", false)):
			continue
		var position := spec.get("position", Vector2.ZERO) as Vector2
		var dimensions := spec.get("dimensions", Vector2.ZERO) as Vector2
		expected_holes.append(Rect2(position - dimensions * 0.5, dimensions))
	_check(
		holes.size() == expected_holes.size(),
		"台座挖洞数=%d 期望 %d（授权房按真实足迹挖，不叠加 15×15 方格）"
		% [holes.size(), expected_holes.size()]
	)
	for expected_rect in expected_holes:
		var matched := false
		for hole_value in holes:
			var hole := hole_value as Rect2
			if (
				absf(hole.position.x - expected_rect.position.x) <= TOL
				and absf(hole.position.y - expected_rect.position.y) <= TOL
				and absf(hole.size.x - expected_rect.size.x) <= TOL
				and absf(hole.size.y - expected_rect.size.y) <= TOL
			):
				matched = true
				break
		_check(matched, "台座缺 %s 的挖洞" % str(expected_rect))
	# 承重不能跟着被挖空：楼板碰撞矩形必须仍然铺着。
	_check(
		int(stage.get("_support_rect_count")) > 0,
		"台座 _support_rect_count=0（挖洞把承重也挖没了）"
	)


func _check_descent_side(tower: Node) -> void:
	print("\n---- I. 下行走办公室西墙 ----")
	var declared := tower.get("_declared_edges") as Array
	var exit_id := str(ROOM_ID_BY_AUTHORED["master_office"])
	var found := false
	for value in declared:
		var declaration := value as Dictionary
		if str(declaration.get("kind", "")) != "vertical":
			continue
		var a := str(declaration.get("a", ""))
		var b := str(declaration.get("b", ""))
		if a != exit_id and b != exit_id:
			continue
		found = true
		_check(
			str(declaration.get("side", "")) == "west",
			"98F 下行竖直边 side=%s 期望 west（办公室西墙）" % str(declaration.get("side", ""))
		)
		_check(a == exit_id, "竖直边 a 端=%s 期望 %s（上层出口房）" % [a, exit_id])
		var lower_id := b
		var gate := tower.get("_floor_seed_gate_edges") as Dictionary
		var gate_found := false
		for gate_key in gate.keys():
			if str(gate_key).contains(lower_id) or str(gate_key).contains(exit_id):
				gate_found = true
				_check(
					int(gate[gate_key]) == NEXT_FLOOR_INDEX,
					"seed gate 指层=%d 期望 %d" % [int(gate[gate_key]), NEXT_FLOOR_INDEX]
				)
		_check(gate_found, "下行竖直边没有登记 seed gate")
		var floor_rooms := tower.get("_floor_room_ids") as Dictionary
		_check(
			lower_id in (floor_rooms.get(NEXT_FLOOR_INDEX, []) as Array),
			"下层（floor_index=%d）没有到达房 %s" % [NEXT_FLOOR_INDEX, lower_id]
		)
	_check(found, "未找到 98F 出口房 %s 的竖直下行边" % exit_id)
