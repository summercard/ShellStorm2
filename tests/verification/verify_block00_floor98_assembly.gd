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
##   I. 办公室西墙的下行口 —— **按 98F 之下有没有层分流**：
##      · 有下层（DEEPEST_PLANNED_FLOOR < 98）：竖直边 side=west 且 seed gate 指向 97F；
##      · 98F 即塔底（== 98）：断言**一条下行竖边都没有**、无层种子门、`_floor_room_ids`
##        不含 97F，而 98↔99 上行竖边仍在（哨兵）。见 EXPECTED_ROOM_DOORS_AT_DEEPEST。
##   J. **和平区**（2026-09-20 主人要求）：四房门只做普通开关（无清房/钥匙/命运卡）、
##      不刷怪、门扇沿用 99F 基地滑升门 —— 真驱动进房后按运行时状态断言
##   K. **新游戏开场**（2026-09-20 主人要求）：全新存档第一次进场落进最里面那间
##      （主人的办公室 floor_01_exit），落点在房内、站在本层楼面、静止不下坠；
##      反向对照：同一 test_mode 下不强制开场分支时仍落 100F 天台出生点
##   L. **门一律普通门**（2026-09-21 主人要求）：四房水平门 + 98↔99 楼梯间门都挂
##      99F 基地那套普通交通门组件（E 开 / 走远自动关 / 不带任何条件）；楼梯间门
##      原「98F 大循环首门」封印整体停用，即使封印标志被强行置成「已封印」，
##      从 98F 侧仍能开门放行、不弹撤退二次确认
##
## 期望值来源：摆位源逐房计数、几何常量（GRID_UNIT_M=5、层高 12、门厅锚点）
## 与 RoomDoorLane 的门槽推导 —— 装配结果一律不硬编码。
## 打印 BLOCK00_ASSEMBLY_OK 表示全过；任一失败打印 BLOCK00_ASSEMBLY_FAILED。
##
## 反向对照（改坏会变红）：
##   · 把 DungeonRoom3D._build_shell 里 authored 分支注释掉 → B/C/E 全红；
##   · 把 _stair_lobby_visual_holes 的 authored 分支删掉 → H 红（退回 15×15 方格）；
##   · 把 Block00MasterOfficeLayout3D 的 exit_side 改回 "east" → A/I 红
##     （C 段门向也会红：不管哪种分支，办公室的门向表里都没有 "east" 以外的门，
##       西向那扇只由下行竖边追加）；
##   · 把 TowerDescent3D.DEEPEST_PLANNED_FLOOR 改回 85 → `_has_lower_floor` 翻真，
##     C 段自动回到「四房各两门」、I 段回到「竖边 side=west 且指 97F」——
##     即这条常量是**双向**受检的，两个方向都有断言盯着。
##   · 把 PEACEFUL_ZONE 改成 false → J 全红（门策略退回清房/钥匙/命运卡、
##     门扇退回塔楼 A 套、进房后按 COMBAT 公式刷出敌人）。
##   · 把 TowerFloorStage3D 的 support_keep_out_rects 消费（_stair_hole_grid_pieces）
##     去掉 → K 红（98F 西侧楼梯井洞口压进办公室，玩家在房内摔穿到 97F）。

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

## 和平区门扇 = 99F 基地滑升门（RoomDoor3D 把门扇包的 metadata/asset_id 记为 visual_asset_id）。
const BASE99_DOOR_LIFT_ASSET_ID := "ENV-BASE99-DOOR-LIFT-22X25"
## 对照：寻常战斗房/安全房用的塔楼 A 套门扇 —— 出现它即说明和平区分支没生效。
const TOWER_DOOR_LEAF_ASSET_ID := "ENV-TOWER-DOOR-LEAF-5M"

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

## ⚠️ 砍层模式（TowerDescent3D.DEEPEST_PLANNED_FLOOR == 98，98F 即最深层）下的门向。
##
## 办公室（floor_01_exit）的西向门**不是**摆位源给的装饰门，它**就是**下行口：
## `TowerDescent3D._append_next_arrival_shell()` 末尾那句
## `_declare_and_register_edge(exit, lower_entry, "vertical", side…)`
## 会把 side（plan 的 exit_side = "west"）追加进该房 record 的 doors。
## 所以「97F 不存在」⇒ 那句不执行 ⇒ 西向门与门墙一并消失，办公室只剩东向那扇。
## 这不是退化，是**预期结果**：此模式下 98F 是塔底，不该再有下行口。
##
## 反向对照：把 DEEPEST_PLANNED_FLOOR 调回 85 ⇒ `_has_lower_floor = true`，
## 本表不被使用，自动回到 EXPECTED_ROOM_DOORS 的口径（四房各两门 + I 段竖边）。
const EXPECTED_ROOM_DOORS_AT_DEEPEST := {
	"floor_01_entry": ["east", "west"],
	"floor_01_hub": ["east", "west"],
	"floor_01_main_02": ["east", "west"],
	"floor_01_exit": ["east"],
}

## 新游戏开场（2026-09-20 主人要求）：全新存档第一次进场落进 98F 四房链**最里面**
## 那间 —— 主人的办公室（运行时 id floor_01_exit），不再落 100F 天台。
const NEW_GAME_OPENING_ROOM_ID := "floor_01_exit"
## 反向对照：同一 test_mode 下不走开场分支时，必须仍是原天台出生点。
const ROOFTOP_SPAWN_WORLD := Vector3(-17.5, 0.05, 2.5)
## 「站在本层楼面」的判定容差。下层（97F）楼面在 −36，相差 12m，所以 0.5 足够区分
## 「站在 98F」与「摔穿楼板掉下去」，又不会被玩家胶囊的落点微差（≈0.03）误伤。
## ⚠️ 砍层模式下 97F 已不存在，摔穿就掉进虚空（仍由本容差判出）。
const FLOOR_STAND_TOL := 0.5

## L 段：普通门（2026-09-21 主人要求）
## 98↔99 楼梯间门 = 门厅东门 ↔ 99F 基地东门（竖直边）。
const STAIR_DOOR_OWNER_ROOM := "floor_01_entry"
const STAIR_DOOR_TARGET_ROOM := "facility"
## 99F 基地门那套普通交通门组件写在门上的标记名（SimpleTransitDoor3D.configure）。
const TRANSIT_COMPONENT_META := "simple_base_transit_v1"
## 站在门前多远按 E（组件 INTERACTION_DISTANCE_M = 3.4，这里取门内 1.6m）。
const PLAIN_DOOR_STAND_DISTANCE_M := 1.6
## 走远自动关：组件 AUTO_CLOSE_DISTANCE_M = 2.85 + AUTO_CLOSE_DELAY_S = 0.40
## + 门板 0.72s 行程，取 2.4s 留足余量。
const PLAIN_DOOR_FAR_AWAY_M := 9.0
const PLAIN_DOOR_AUTO_CLOSE_WAIT_S := 2.4

var _failures: Array[String] = []
var _checks := 0

## 「98F 之下还有没有层」—— 由运行时 `_floor_room_ids` 实测得出，不读常量：
## TowerDescent3D.DEEPEST_PLANNED_FLOOR 被砍到 98 时，97F 不再进 `_floor_room_ids`。
## C 段门向与 I 段下行边都以此分流（见 EXPECTED_ROOM_DOORS_AT_DEEPEST）。
var _has_lower_floor := false


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

	# 砍层分流：97F 在不在 `_floor_room_ids` 里，决定 C 段门向与 I 段下行边怎么断言。
	_has_lower_floor = floor_rooms.has(NEXT_FLOOR_INDEX)

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
	await _check_peaceful_zone(rooms, snapshots, tower)
	await _check_plain_doors(tower)
	await _check_new_game_opening(tower)

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
		var want_doors := (
			EXPECTED_ROOM_DOORS_AT_DEEPEST if not _has_lower_floor else EXPECTED_ROOM_DOORS
		).get(room_id, []) as Array
		want_doors = want_doors.duplicate()
		want_doors.sort()
		_check(
			doors == want_doors,
			"%s 门向=%s 期望 %s（%s）"
			% [
				room_id,
				str(doors),
				str(want_doors),
				"98F 为最深层，无下行口" if not _has_lower_floor else "98F 之下还有层，含下行口"
			]
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
	# 哨兵：边表为空时下面的「找不到」断言会空跑通过。
	if not _check(not declared.is_empty(), "哨兵：_declared_edges 为空，本节断言全空跑"):
		return

	if not _has_lower_floor:
		_check_deepest_floor_descent(tower, declared, exit_id)
		return

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


## I′. 砍层模式：98F 即塔底，**必须完全没有**从办公室出去的下行口。
##
## 断言方向与上一支相反 —— 上一支查「下行边在且指向 97F」，本支查「下行边一条都没有」，
## 两者都是正向断言，不存在「因为找不到所以放过」。若哪天 DEEPEST_PLANNED_FLOOR
## 被改回 85 而本支仍在跑，这里会立刻红（那时 _has_lower_floor 已为 true，不会进本支）。
func _check_deepest_floor_descent(tower: Node, declared: Array, exit_id: String) -> void:
	var vertical_total := 0
	var from_exit: Array[String] = []
	var from_stair_total := 0
	for value in declared:
		var declaration := value as Dictionary
		if str(declaration.get("kind", "")) != "vertical":
			continue
		vertical_total += 1
		var a := str(declaration.get("a", ""))
		var b := str(declaration.get("b", ""))
		if a == exit_id or b == exit_id:
			from_exit.append("%s→%s(side=%s)" % [a, b, str(declaration.get("side", ""))])
		# 反向对照哨兵：98↔99 楼梯间那条**上行**竖边必须还在，否则「竖边数为 0」
		# 这种断言连塔楼没建起来都能通过。
		if a == STAIR_DOOR_TARGET_ROOM or b == STAIR_DOOR_TARGET_ROOM:
			from_stair_total += 1

	_check(
		from_stair_total >= 1,
		"哨兵：98↔99 楼梯间竖边不见了（竖边总数 %d），本节断言无意义" % vertical_total
	)
	_check(
		from_exit.is_empty(),
		"98F 已是最深层，办公室 %s 仍有下行竖边：%s" % [exit_id, str(from_exit)]
	)
	var gate := tower.get("_floor_seed_gate_edges") as Dictionary
	var gate_hits: Array[String] = []
	for gate_key in gate.keys():
		if str(gate_key).contains(exit_id):
			gate_hits.append(str(gate_key))
	_check(gate_hits.is_empty(), "最深层仍登记了层种子门：%s" % str(gate_hits))
	var floor_rooms := tower.get("_floor_room_ids") as Dictionary
	_check(
		not floor_rooms.has(NEXT_FLOOR_INDEX),
		"_floor_room_ids 竟含 floor_index=%d（%s），砍层没生效"
		% [NEXT_FLOOR_INDEX, str(floor_rooms.get(NEXT_FLOOR_INDEX, []))]
	)
	# 平面口径不变：plan 仍声明 exit_side=west（摆位源的几何口径），只是没有下层可接。
	var snapshots := tower.get("_floor_plan_snapshots") as Dictionary
	var plan := snapshots.get(FLOOR_INDEX, {}) as Dictionary
	_check(
		str(plan.get("exit_side", "")) == "west",
		"最深层 plan exit_side=%s 期望仍为 west（摆位源口径不随砍层改）"
		% str(plan.get("exit_side", ""))
	)


## J. 和平区：门只做普通开关、区域不刷怪、门扇走 99F 基地滑升门。
##
## 「不刷怪」必须**真驱动进房**才算证据 —— `_alive_by_room` 与状态栏都是进房那一刻
## 在 `_spawn_room_enemies()` 里写的；只读 plan 数据什么都证明不了
## （改坏成刷怪时 plan 依然带 peaceful 标记）。
func _check_peaceful_zone(rooms: Dictionary, snapshots: Dictionary, tower: Node) -> void:
	print("\n---- J. 和平区：门普通开关 / 不刷怪 / 基地门扇 ----")
	var plan := snapshots.get(FLOOR_INDEX, {}) as Dictionary
	_check(
		bool(plan.get("authored_layout_peaceful", false)),
		"98F plan 未声明和平区（authored_layout_peaceful != true）"
	)
	var door_samples := 0
	var checked_rooms := 0
	for room_id_value in rooms.keys():
		var room_id := str(room_id_value)
		var room := rooms[room_id] as DungeonRoom3D
		checked_rooms += 1
		var snapshot := room.get_room_snapshot()
		_check(
			bool(snapshot.get("authored_layout_peaceful", false)),
			"房间 %s 未标和平区" % room_id
		)
		var door_snapshots := snapshot.get("door_snapshots", []) as Array
		_check(not door_snapshots.is_empty(), "房间 %s 没有任何门（门策略断言空跑）" % room_id)
		for value in door_snapshots:
			var door := value as Dictionary
			var direction := str(door.get("direction", ""))
			door_samples += 1
			_check(
				not bool(door.get("requires_clear", true)),
				"%s.%s 门仍要求清房（requires_clear=true）" % [room_id, direction]
			)
			_check(
				not bool(door.get("requires_key", true)),
				"%s.%s 门仍要求钥匙（requires_key=true）" % [room_id, direction]
			)
			_check(
				not bool(door.get("triggers_fate", true)),
				"%s.%s 门仍会弹命运卡（triggers_fate=true）" % [room_id, direction]
			)
			var leaf_id := str(door.get("visual_asset_id", ""))
			_check(
				leaf_id == BASE99_DOOR_LIFT_ASSET_ID,
				"%s.%s 门扇=%s 期望基地滑升门 %s（塔楼 A 套=%s 即分支没生效）"
				% [room_id, direction, leaf_id, BASE99_DOOR_LIFT_ASSET_ID, TOWER_DOOR_LEAF_ASSET_ID]
			)
	_check(
		checked_rooms == EXPECTED_ROOM_COUNT,
		"和平区房间样本=%d 期望 %d" % [checked_rooms, EXPECTED_ROOM_COUNT]
	)
	_check(door_samples > 0, "哨兵：门样本数为 0（门策略断言全是空跑）")

	var alive_by_room := tower.get("_alive_by_room") as Dictionary
	var spawned_rooms := tower.get("_spawned_rooms") as Dictionary
	var enemy_nodes_by_room := tower.get("_enemy_nodes_by_room") as Dictionary
	if not _check(alive_by_room != null, "取不到 _alive_by_room（不刷怪断言无法成立）"):
		return
	if not _check(enemy_nodes_by_room != null, "取不到 _enemy_nodes_by_room"):
		return
	for room_id_value in rooms.keys():
		var room_id := str(room_id_value)
		var room := rooms[room_id] as DungeonRoom3D
		# 首访标记要在进房**之前**读：进房会把它写掉，之后读不出来。
		var first_visit := not spawned_rooms.has(room_id)
		tower.call("force_enter_room_for_test", room_id)
		# 波次是延迟生成的（首波经 `_spawn_next_room_wave` 落到 `$ActiveEnemies`），
		# 只等一帧会读到「登记有敌人、节点还没入树」的中间态 —— 那样断言在
		# 改动前也照样绿，等于空跑。必须等够帧数。
		await _settle()
		# ⚠️ 不要数敌人节点：敌人挂 `$ActiveEnemies`，其存活由**流送**裁决
		# （`_update_room_streaming` 按玩家实际位置算，非 ACTIVE 即回收）。本探针
		# 不挪玩家（玩家人还在塔楼入口），98F 房恒非 ACTIVE ⇒ 节点数恒 0，
		# 那个断言在改动前后都绿，是假绿。
		# 有区分力的判据是**刷怪登记**（`_spawn_enemy_batch` 里写）与清房状态：
		# 改动前 `alive=3 / cleared=false`，改动后 `alive=0 / cleared=true`。
		var wave_queues := tower.get("_room_wave_queues") as Dictionary
		var pending := (wave_queues.get(room_id, []) as Array).size()
		print(
			"  [证据] %s type=%s 首访=%s 刷怪登记=%d 待刷波次=%d cleared=%s"
			% [room_id, room.room_type, str(first_visit), int(alive_by_room.get(room_id, 0)), pending, str(room.cleared)]
		)
		if room.room_type in ["COMBAT", "ELITE", "BOSS", "TRAP", "BASEMENT", "STORAGE"]:
			_check(first_visit, "敌意房 %s 进房前已非首访（不刷怪断言会空跑）" % room_id)
		_check(
			int(alive_by_room.get(room_id, 0)) == 0,
			"和平区房间 %s 刷怪登记=%d 期望 0（改动前为敌意房数量）"
			% [room_id, int(alive_by_room.get(room_id, 0))]
		)
		_check(pending == 0, "和平区房间 %s 仍有 %d 个待刷波次" % [room_id, pending])
		_check(room.cleared, "和平区房间 %s 进房后未放行（cleared=false，会锁住后续门）" % room_id)


## L. 区块00 的门一律普通门（2026-09-21 主人要求）。
##
## 「普通门」的口径 = 99F 基地两边那两扇门：挂**同一个** `SimpleTransitDoor3D`
## 组件（E 开、走远自动关），不看任何条件。98↔99 楼梯间门（`floor_01_entry` 东门
## ↔ 99F 基地东门）此前还带一套「98F 大循环首门」封印 —— 进 98F 后门在身后关闭、
## 从里面反向开门弹撤退二次确认。主人要求它也能自由开关，所以整套封印停用
## （`TowerDescent3D.INITIAL_LOOP_GATE_SEAL_ENABLED = false`）。
##
## 判据全是**运行时行为**，不读设计自述：
##   · 四房 6 扇水平门 + 楼梯间门都真的挂了普通交通门组件（meta 名逐值对上），
##     且门策略一律不看清房/钥匙/命运卡；
##   · **即使把封印标志强行置成「已封印」**，从 98F 侧开楼梯间门仍然成功、不弹
##     撤退弹窗、门板真的升起放行 —— 这条同时兜住「边开了门板不动、人过不去」
##     那个既有故障形态；
##   · 走远之后门真的自动关回去（组件 `_process` 在跑，不是只挂了个空组件）。
##
## 反向对照：
##   · `INITIAL_LOOP_GATE_SEAL_ENABLED` 置回 true → 第二组红；
##   · `_peaceful_plain_door_entries()` 从装配列表删掉 → 第一组红。
func _check_plain_doors(tower: Node) -> void:
	print("\n---- L. 区块00 门 = 普通门（E 开 / 走远自动关 / 楼梯间门不带条件）----")
	var room_by_id := tower.get("_room_by_id") as Dictionary
	var edge_kind := tower.get("_edge_kind_by_key") as Dictionary
	if not _check(
		room_by_id != null and edge_kind != null,
		"取不到 _room_by_id / _edge_kind_by_key（普通门断言无法成立）"
	):
		return

	# —— 1) 组件挂载 + 门策略：逐个门节点核 ——
	var plain_samples := 0
	var stair_door: RoomDoor3D = null
	var stair_owner: DungeonRoom3D = null
	for room_id_value in ROOM_ID_BY_AUTHORED.values():
		var room_id := str(room_id_value)
		var room := room_by_id.get(room_id) as DungeonRoom3D
		if not _check(room != null, "缺房间 %s（普通门断言无法成立）" % room_id):
			continue
		for side_value in room.door_targets.keys():
			var side := str(side_value)
			var target_id := str(room.door_targets[side_value])
			var edge := str(tower.call("_edge_key", room_id, target_id))
			var vertical := str(edge_kind.get(edge, "horizontal")) == "vertical"
			var is_stair_door := (
				room_id == STAIR_DOOR_OWNER_ROOM and target_id == STAIR_DOOR_TARGET_ROOM
			)
			var door := room.get_door_node(side)
			if not _check(door != null, "%s.%s 门为 null" % [room_id, side]):
				continue
			var snapshot := door.get_snapshot()
			_check(
				not bool(snapshot.get("requires_clear", true)),
				"%s.%s 门仍要求清房（requires_clear=true）" % [room_id, side]
			)
			_check(
				not bool(snapshot.get("requires_key", true)),
				"%s.%s 门仍要求钥匙（requires_key=true）" % [room_id, side]
			)
			_check(
				not bool(snapshot.get("triggers_fate", true)),
				"%s.%s 门仍会弹命运卡（triggers_fate=true）" % [room_id, side]
			)
			if vertical and not is_stair_door:
				# 98↔97 下行门是 FloorBundle 的原子提交门槛，不在本次「这个区域的门」
				# = 普通门 的范围内（它沿用楼梯到达/返回绑定）。
				continue
			plain_samples += 1
			_check(
				str(door.get_meta("transit_component", "")) == TRANSIT_COMPONENT_META,
				"%s.%s 没挂 99F 基地那套普通交通门组件（transit_component=%s）"
				% [room_id, side, str(door.get_meta("transit_component", "<无>"))]
			)
			_check(
				door.get_node_or_null("SimpleTransitDoor3D") != null,
				"%s.%s 门节点下没有 SimpleTransitDoor3D 子节点" % [room_id, side]
			)
			if is_stair_door:
				stair_door = door
				stair_owner = room
	_check(
		plain_samples == 7,
		"哨兵：普通门样本=%d 期望 7（四房 6 扇水平门 + 98↔99 楼梯间门）" % plain_samples
	)
	if not _check(
		stair_door != null and stair_owner != null,
		"没找到 98↔99 楼梯间门（%s ↔ %s）" % [STAIR_DOOR_OWNER_ROOM, STAIR_DOOR_TARGET_ROOM]
	):
		return

	# —— 2) 从 98F 侧开楼梯间门：封印标志被强行置成「已封印」也必须放行 ——
	# 正常流程里封印已整体停用（INITIAL_LOOP_GATE_SEAL_ENABLED=false），所以直接
	# 把运行时标志置 true 就是最坏情形：改动前这一下会弹撤退确认、门板纹丝不动。
	tower.call("force_enter_room_for_test", STAIR_DOOR_OWNER_ROOM)
	await _settle()
	tower.set("_initial_loop_gate_sealed", true)
	stair_door.set_open(false, true)
	await _settle()
	await _stand_near_door(tower, stair_owner, stair_door)
	var candidate := tower.get_interaction_candidate(tower.player) as Dictionary
	_check(
		not candidate.is_empty() and candidate.get("door") != null,
		"玩家站在楼梯间门前但拿不到门交互候选（E 交互链断了）"
	)
	var opened := (
		bool(tower.perform_interaction(tower.player, candidate)) if not candidate.is_empty() else false
	)
	await _settle()
	await get_tree().create_timer(1.0).timeout
	_check(opened, "从 98F 侧开楼梯间门失败（perform_interaction=false）")
	_check(
		tower.get("_initial_loop_retreat_overlay") == null,
		"从 98F 侧开楼梯间门弹出了撤退二次确认（封印没停用）"
	)
	_check(stair_door.is_open, "楼梯间门 is_open=false（边开了但门板没动）")
	_check(
		not bool(stair_door.get_snapshot().get("blocks_passage", true)),
		"楼梯间门仍 blocks_passage=true（门开着但碰撞没放行，人过不去）"
	)

	# —— 3) 走远自动关：与 99F 基地门同口径 ——
	var inward := stair_owner.global_position - stair_door.global_position
	inward.y = 0.0
	if inward.length() < 0.01:
		inward = Vector3.LEFT
	tower.player.global_position = (
		stair_door.global_position + inward.normalized() * PLAIN_DOOR_FAR_AWAY_M
	)
	tower.player.global_position.y = stair_owner.global_position.y + 0.05
	tower.player.velocity = Vector3.ZERO
	tower.call("_refresh_physical_location_authority", true)
	await _settle()
	await get_tree().create_timer(PLAIN_DOOR_AUTO_CLOSE_WAIT_S).timeout
	_check(
		not stair_door.is_open,
		"走远 %.1fm 并等 %.1fs 后楼梯间门没有自动关闭（组件 _process 没在跑）"
		% [PLAIN_DOOR_FAR_AWAY_M, PLAIN_DOOR_AUTO_CLOSE_WAIT_S]
	)
	_check(
		bool(stair_door.get_snapshot().get("blocks_passage", false)),
		"楼梯间门自动关闭后没有恢复阻挡"
	)
	tower.set("_initial_loop_gate_sealed", false)


## 把玩家摆到门前 1.6m（房内一侧）、贴本层楼面，并刷新物理位置归属。
## 与 `test_mode` 下的既有做法一致：只写玩家位置会读到未流送的旧归属。
func _stand_near_door(tower: Node, room: DungeonRoom3D, door: RoomDoor3D) -> void:
	if tower == null or room == null or door == null:
		return
	tower.player.global_position = room.global_position + Vector3(0.0, 0.05, 0.0)
	tower.player.velocity = Vector3.ZERO
	tower.call("_refresh_physical_location_authority", true)
	await _settle()
	var inward := room.global_position - door.global_position
	inward.y = 0.0
	if inward.length() < 0.01:
		inward = Vector3.LEFT
	tower.player.global_position = (
		door.global_position + inward.normalized() * PLAIN_DOOR_STAND_DISTANCE_M
	)
	tower.player.global_position.y = room.global_position.y + 0.05
	tower.player.velocity = Vector3.ZERO
	tower.call("_refresh_physical_location_authority", true)
	await _settle()


## K. 新游戏开场：全新存档第一次进场的落点。
## 判据全部是**运行时行为**，不读设计自述：
##   · 落点房 id == floor_01_exit（98F 四房链最里面那间 = 主人的办公室）；
##   · 玩家在房内（房间局部坐标落在足迹内）；
##   · 玩家站在**本层**楼面（世界 y ≈ 房间 y；楼下 97F 在 −36，相差 12m）；
##   · 再等 60 个物理帧仍不下坠 —— 这条同时兜住「房间楼板被楼梯井洞口打穿」
##     这类静默退化（见文件头反向对照）。
## 反向对照：同一 test_mode、不强制开场分支 ⇒ 必须仍落 100F 天台出生点，
## 证明本分支没有把常规进场路径一起改掉。
func _check_new_game_opening(previous: Node) -> void:
	print("\n---- K. 新游戏开场落进 98F 最里面的办公室 ----")
	# 先清掉主塔楼再开新的：两套玩家/房间注册会互相污染，时序也没法独立算。
	if previous != null and is_instance_valid(previous):
		remove_child(previous)
		previous.queue_free()
		await _settle()

	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	if not _check(scene != null, "开场塔楼场景加载失败"):
		return

	# —— 正向：强制走开场分支 ——
	var opening := scene.instantiate() as TowerDescent3D
	opening.test_mode = true
	opening.run_seed_override = SEED
	opening.force_new_game_opening_for_test = true
	add_child(opening)
	await _settle()

	var player := opening.player
	if not _check(player != null, "开场塔楼没有 player"):
		return
	var room := (opening.get("_room_by_id") as Dictionary).get(NEW_GAME_OPENING_ROOM_ID) as DungeonRoom3D
	if not _check(room != null, "开场塔楼缺房间 %s（98F 未提交或区块00 未接管）" % NEW_GAME_OPENING_ROOM_ID):
		return
	_check(
		str(opening.get("_current_room_id")) == NEW_GAME_OPENING_ROOM_ID,
		"开场落点房 id=%s 期望 %s" % [str(opening.get("_current_room_id")), NEW_GAME_OPENING_ROOM_ID]
	)
	_check(
		room.authored_layout_room_id == "master_office",
		"%s 不是主人的办公室（authored=%s）" % [NEW_GAME_OPENING_ROOM_ID, room.authored_layout_room_id]
	)
	var dimensions := room.get_dimensions()
	var local := room.to_local(player.global_position)
	_check(
		absf(local.x) <= dimensions.x * 0.5 + TOL and absf(local.z) <= dimensions.y * 0.5 + TOL,
		"开场玩家不在房内：local=%s dims=%s" % [str(local), str(dimensions)]
	)
	_check(
		absf(player.global_position.y - room.global_position.y) <= FLOOR_STAND_TOL,
		"开场玩家没站在 98F 楼面：y=%.3f 房 y=%.3f（差 > %.1f 说明摔穿了）"
		% [player.global_position.y, room.global_position.y, FLOOR_STAND_TOL]
	)
	# 静止判定：站着不动 60 物理帧，y 不许再掉。
	var y_before := player.global_position.y
	for index in range(60):
		await get_tree().physics_frame
	_check(
		absf(player.global_position.y - y_before) <= TOL,
		"开场玩家在房内持续下坠：%.3f → %.3f" % [y_before, player.global_position.y]
	)

	remove_child(opening)
	opening.queue_free()
	await _settle()

	# —— 反向对照：同一 test_mode，不强制分支 ⇒ 必须仍落天台 ——
	var rooftop := scene.instantiate() as TowerDescent3D
	rooftop.test_mode = true
	rooftop.run_seed_override = SEED
	add_child(rooftop)
	await _settle()
	_check(
		str(rooftop.get("_current_room_id")) == "start",
		"test_mode 反向对照：落点房 id=%s 期望 start（天台）" % str(rooftop.get("_current_room_id"))
	)
	var rooftop_player := rooftop.player
	if _check(rooftop_player != null, "反向对照塔楼没有 player"):
		_check(
			rooftop_player.global_position.distance_to(ROOFTOP_SPAWN_WORLD) <= FLOOR_STAND_TOL,
			"test_mode 反向对照：未落天台出生点 actual=%s expected=%s"
			% [str(rooftop_player.global_position), str(ROOFTOP_SPAWN_WORLD)]
		)
	remove_child(rooftop)
	rooftop.queue_free()
	await _settle()
