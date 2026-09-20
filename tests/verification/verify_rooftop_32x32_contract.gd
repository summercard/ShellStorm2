extends Node
## 100层保留原16×16主区，只向西扩2格为18×16；其他三边、99层和普通层不动。

const ROOFTOP_TILE_COUNT_WITH_OPENINGS := 234
const ROOFTOP_WORLD_RECT := Rect2(-50.0, -35.0, 90.0, 80.0)
const WEST_STAIR_WORLD_RECT := Rect2(-45.0, 0.0, 15.0, 30.0)
## 天台女儿墙换成参考组件库 v002 派生件（0.50m 厚；2026-09-20 起按业主口径改为
## 总高 0.80m 的方案A 平整墙板）后，边界内缩由 0.15m 变 0.25m。
## ⚠️ 内缩口径只由**厚度**决定，所以改高度不动边界；但反过来说，改厚度必然动边界。
const WEST_PARAPET_X := -49.75
## 实体直段数 = 2×(17+15)：每边两端各让出 2.5m 转角件后比格数少一格。
const ROOFTOP_SEGMENT_COUNT := 64
## 四角各一件 2.5m 转角件。
const ROOFTOP_CORNER_COUNT := 4
## 2026-09-19：天台女儿墙直段改为「按种子随机分档」——intact + 三件破损变体
## （崩顶 / 贯穿 / 塌脚）。这三件在 Blender 里由 intact 网格程序化剔料派生，
## 包络与端头带与 intact 件逐位相同，因此可任意顺序对接。
## 下列常量是门禁侧的口径副本：破损比例区间（用户口径「约 1/4」）、
## 排布种子（与 TowerFloorStage3D.ROOFTOP_PARAPET_DAMAGE_SEED 同值）与变体清单。
const ROOFTOP_DAMAGE_RATIO_MIN := 0.15
const ROOFTOP_DAMAGE_RATIO_MAX := 0.35
const ROOFTOP_DAMAGE_PLAN_SEED := 20260919
const ROOFTOP_DAMAGE_VARIANT_KEYS: Array[String] = ["dmg_a", "dmg_b", "dmg_c"]
const ROOFTOP_DAMAGE_VARIANT_PATHS: Array[String] = [
	"res://assets/art/props/dungeon_3d/prp_rooftop_parapet_dmg_a_5m.tscn",
	"res://assets/art/props/dungeon_3d/prp_rooftop_parapet_dmg_b_5m.tscn",
	"res://assets/art/props/dungeon_3d/prp_rooftop_parapet_dmg_c_5m.tscn",
]
const TOWER_SCENE: PackedScene = preload("res://scenes/TowerDescent3D.tscn")


func _ready() -> void:
	var failures: Array[String] = []
	var rooftop := TowerFloorStage3D.new()
	rooftop.configure(0, "rooftop", ["west"])
	add_child(rooftop)
	var facility := TowerFloorStage3D.new()
	facility.configure(1, "facility", [])
	add_child(facility)
	var combat := TowerFloorStage3D.new()
	combat.configure(2, "combat", [])
	add_child(combat)
	var tower := TOWER_SCENE.instantiate() as TowerDescent3D
	if tower != null:
		tower.test_mode = true
		tower.run_seed_override = 100990
		add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame

	_verify_rooftop(rooftop, failures)
	_verify_facility(facility.get_snapshot(), failures)
	_verify_combat_floor(combat.get_snapshot(), failures)
	_verify_start_rooftop_shell(tower, failures)

	rooftop.queue_free()
	facility.queue_free()
	combat.queue_free()
	if tower != null:
		tower.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("ROOFTOP_WEST_EXPANSION_CONTRACT_PASS")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _verify_rooftop(rooftop: TowerFloorStage3D, failures: Array[String]) -> void:
	var snapshot := rooftop.get_snapshot()
	_expect((snapshot.get("grid_dimensions", Vector2i.ZERO) as Vector2i) == Vector2i(18, 16), "100层地板没有只向西扩成18×16格", failures)
	_expect((snapshot.get("map_dimensions", Vector2.ZERO) as Vector2).is_equal_approx(Vector2(90.0, 80.0)), "100层地板尺寸不是90m×80m", failures)
	_expect(int(snapshot.get("grid_count", -1)) == 18, "100层旧标量接口没有返回西向宽度18格", failures)
	_expect(is_equal_approx(float(snapshot.get("map_size", -1.0)), 90.0), "100层旧标量接口没有返回西向宽度90m", failures)
	_expect((snapshot.get("floor_world_rect", Rect2()) as Rect2).is_equal_approx(ROOFTOP_WORLD_RECT), "100层没有保持东南北边界并向西扩10m", failures)
	_expect(int(snapshot.get("tile_count", -1)) == ROOFTOP_TILE_COUNT_WITH_OPENINGS, "100层地砖数没有按18×16主面、36格基地开口和18格完整楼梯开口计算", failures)
	_expect((snapshot.get("outer_grid_dimensions", Vector2i.ZERO) as Vector2i) == Vector2i(18, 16), "100层围栏没有同步改为18×16轮廓", failures)
	_expect((snapshot.get("outer_map_dimensions", Vector2.ZERO) as Vector2).is_equal_approx(Vector2(90.0, 80.0)), "100层围栏尺寸不是90m×80m", failures)
	_expect(int(snapshot.get("outer_module_count", -1)) == 68, "100层围栏模块周长计数不是68", failures)
	_expect(
		int(snapshot.get("outer_segment_count", -1)) == ROOFTOP_SEGMENT_COUNT,
		"100层女儿墙实体直段数不是64（两角让位后每边少一段）",
		failures
	)
	_expect(
		int(snapshot.get("outer_corner_count", -1)) == ROOFTOP_CORNER_COUNT,
		"100层没有生成四件女儿墙转角件",
		failures
	)
	_expect(
		is_equal_approx(float(snapshot.get("outer_wall_thickness", -1.0)), 0.5),
		"100层女儿墙厚度不是组件库v002的0.50m",
		failures
	)
	_expect((snapshot.get("outer_world_rect", Rect2()) as Rect2).is_equal_approx(ROOFTOP_WORLD_RECT), "100层围栏没有与扩展地板共用轮廓", failures)
	_expect(
		is_equal_approx(
			float(snapshot.get("outer_wall_height", -1.0)), TowerFloorStage3D.ROOFTOP_PARAPET_HEIGHT
		),
		"100层女儿墙不是脚本口径的 %.2fm（快照实测 %.4f；2026-09-20 由 1.80m 改 0.80m）"
		% [
			TowerFloorStage3D.ROOFTOP_PARAPET_HEIGHT,
			float(snapshot.get("outer_wall_height", -1.0)),
		],
		failures
	)
	_expect(not bool(snapshot.get("uses_formal_rooftop_art", true)), "天台仍加载设施美术", failures)
	_expect(str(snapshot.get("formal_rooftop_art_version", "")) == "", "天台设施版本应为空", failures)
	_expect(int(snapshot.get("formal_rooftop_art_blocker_count", -1)) == 0, "天台残留设施阻挡", failures)
	var facilities := rooftop.find_child("FormalRooftopFacilities*", false, false) as Node3D
	_expect(facilities == null, "100层Stage残留设施实例", failures)
	var outer := rooftop.get("_outer_visual") as MultiMeshInstance3D
	_expect(outer != null and outer.multimesh != null, "100层围栏MultiMesh缺失", failures)
	_expect(outer != null and outer.visible, "100层原生围栏被设施导入隐藏", failures)
	var floor_light := rooftop.get("_floor_visual_light") as MultiMeshInstance3D
	var floor_dark := rooftop.get("_floor_visual_dark") as MultiMeshInstance3D
	_expect(floor_light != null and floor_light.visible, "100层原生浅色地砖被设施导入隐藏", failures)
	_expect(floor_dark != null and floor_dark.visible, "100层原生深色地砖被设施导入隐藏", failures)
	if outer != null and outer.multimesh != null:
		# 不变量：被跳过的直段数 == 补位的门洞墙件数（缺口宽度由两者共同决定）。
		#
		# 2026-09-20：西侧楼梯口整体在轮廓**内部**（离西墙 5m 净距），「楼梯口 = 外墙
		# 门洞」这条旧假设对天台不成立 —— 它只会在西墙留下一段带 2m 门洞的**系统
		# 占位矮墙**，从里看就是没连起来的栏杆缺口（用户报的问题）。现在天台外墙
		# 连成整圈：门洞件 0 件、直段槽位 64/64。判据仍写成「64 - 门洞件数」这条
		# 关系式，是为了让它在普通层仍成立。
		var doorway_walls := 0
		for child in rooftop.get_children():
			if child.name.begins_with("ParapetDoorWall_"):
				doorway_walls += 1
		_expect(
			doorway_walls == 0,
			"100层西侧仍有 %d 件系统占位门洞矮墙，外墙没连成整圈" % doorway_walls,
			failures
		)
		_expect(
			int(snapshot.get("outer_doorway_wall_count", -1)) == doorway_walls,
			"100层快照的门洞矮墙计数与实测不符",
			failures
		)
		# 2026-09-19：直段可视件改为「按种子随机分档」——intact + 崩顶/贯穿/塌脚三件
		# 破损变体各占一个 MultiMesh 批次，所以「实体直段数」不再等于 _outer_visual
		# 单个 MultiMesh 的实例数。真源改为**槽位表**：破损只换外观、不增删槽位，
		# 因此槽位总数必须等于「64 段 - 门洞补位墙」。四批次之和 == 槽位表
		# 由 _verify_rooftop_parapet_damage() 逐项对账。
		var slot_count := int(rooftop.call("get_outer_straight_slot_count"))
		_expect(
			slot_count == ROOFTOP_SEGMENT_COUNT - doorway_walls,
			"100层女儿墙直段槽位数(%d)与「64段-门洞补位墙%d件」不符"
				% [slot_count, doorway_walls],
			failures
		)
		_verify_rooftop_parapet_damage(rooftop, slot_count, failures)
	# 西侧不再有门洞矮墙，改为断言「整圈 64 段槽位无缺口」——
	# 旧写法只测门洞墙的位置，封口后没有对象可测，必须换成对整圈的断言，
	# 否则这条覆盖判据会静默退化成 0 样本。
	var west_slot_zs: Array[float] = []
	for slot_transform in rooftop.call("get_outer_straight_slot_transforms"):
		var slot := slot_transform as Transform3D
		if is_equal_approx(slot.origin.x, WEST_PARAPET_X):
			west_slot_zs.append(slot.origin.z)
	west_slot_zs.sort()
	_expect(
		west_slot_zs.size() == 15,
		"100层西侧直段不是15段（整圈封口后应为 80m/5m 减两角让位）实际 %d"
			% west_slot_zs.size(),
		failures
	)
	for index in range(west_slot_zs.size() - 1):
		_expect(
			is_equal_approx(west_slot_zs[index + 1] - west_slot_zs[index], 5.0),
			"100层西侧直段之间有缺口：z=%.2f → z=%.2f"
				% [west_slot_zs[index], west_slot_zs[index + 1]],
			failures
		)
	_expect(
		rooftop.find_child("ParapetDoorWall_West*", false, false) == null,
		"100层西侧仍残留系统占位矮墙 ParapetDoorWall_West*",
		failures
	)
	# 四角必须是 2.5m 转角件，而不是继续让两根直段在角上交叉。
	# 期望位置 = 该角 2.5m 让位区中心；朝向按俯视逆时针 0 → PI/2 → PI → 3PI/2。
	var corner_expectations := {
		"SW": {"position": Vector3(-48.75, 0.0, 43.75), "rotation_y": 0.0},
		"SE": {"position": Vector3(38.75, 0.0, 43.75), "rotation_y": PI * 0.5},
		"NE": {"position": Vector3(38.75, 0.0, -33.75), "rotation_y": PI},
		"NW": {"position": Vector3(-48.75, 0.0, -33.75), "rotation_y": PI * 1.5},
	}
	for corner_name in corner_expectations.keys():
		var expectation := corner_expectations[corner_name] as Dictionary
		var corner_found := rooftop.find_child(
			"RooftopOuterCorner_%s" % corner_name, false, false
		) as Node3D
		_expect(corner_found != null, "100层%s角缺少女儿墙转角件" % corner_name, failures)
		if corner_found == null:
			continue
		_expect(
			str(corner_found.get_meta("asset_id", "")) == "ENV-ROOFTOP-REF-PARAPET-OUTER",
			"100层%s角转角件资产ID不符" % corner_name,
			failures
		)
		_expect(
			bool(corner_found.get_meta("visual_only", false)),
			"100层%s角转角件不是纯视觉件" % corner_name,
			failures
		)
		_expect(
			corner_found.position.is_equal_approx(expectation["position"] as Vector3),
			"100层%s角转角件没有落在2.5m让位区中心：实际%s" % [corner_name, corner_found.position],
			failures
		)
		_expect_angle(
			corner_found.rotation.y,
			float(expectation["rotation_y"]),
			"100层%s角转角件朝向不对：实际%.4f" % [corner_name, corner_found.rotation.y],
			failures
		)
	var west_collision := rooftop.find_child("OuterBoundaryCollision_West", false, false) as StaticBody3D
	_expect(west_collision != null, "100层西侧边界碰撞缺失", failures)
	if west_collision != null:
		var west_shapes := 0
		for child in west_collision.get_children():
			if child is CollisionShape3D:
				west_shapes += 1
				var collision := child as CollisionShape3D
				var shape := collision.shape as BoxShape3D
				_expect(is_equal_approx(collision.position.x, WEST_PARAPET_X), "100层西侧碰撞没有随围栏移动", failures)
				if shape != null:
					var collision_east_edge := collision.position.x + shape.size.x * 0.5
					_expect(collision_east_edge < WEST_STAIR_WORLD_RECT.position.x, "100层西侧碰撞仍侵入楼梯外廓", failures)
					# 封口后西侧碰撞必须是**一整条**（旧代码在楼梯口处切成两段、中间留 10m 缝）。
					_expect(
						is_equal_approx(shape.size.z, ROOFTOP_WORLD_RECT.size.y),
						"100层西侧碰撞未覆盖全长，仍留缺口：size.z=%.2f 期望 %.2f"
							% [shape.size.z, ROOFTOP_WORLD_RECT.size.y],
						failures
					)
		_expect(west_shapes == 1, "100层西侧碰撞不是一整条（实际 %d 段，仍按门洞切分）" % west_shapes, failures)
	# 2026-09-20 新增：天台外立面环（= 从边缘往下看到的那层「99 层外墙」）。
	# 判据只认「计划 == 摆放 + 几何口径」，不认某个具体件数：
	#   1. 快照里的立面件数与两个批次 MultiMesh 的实测实例数逐档相等（防空摆）；
	#   2. 环件数 == 2×(18+16)=68（整格铺满一圈：x 向 18 件、z 向 16 件）；
	#   3. 底面标高 = -12.0（低一整层）、厚度 = 0.30m，且与女儿墙外皮共面。
	_verify_rooftop_facade(rooftop, snapshot, failures)


## 天台外立面环的运行时对账。
##
## 用户口径：「99 楼外墙在天台周边调用，围起来」——即从天台边缘往下不该是空的。
## 本函数把这句话落成可实测的不变量，并留一条**防假绿哨兵**（件数为 0 时直接报错，
## 否则「计划==摆放」会两边同为 0 而恒真）。
func _verify_rooftop_facade(
	rooftop: TowerFloorStage3D, snapshot: Dictionary, failures: Array[String]
) -> void:
	var planned_solid := int(snapshot.get("outer_facade_solid_count", -1))
	var planned_window := int(snapshot.get("outer_facade_window_count", -1))
	var batches := snapshot.get("outer_facade_batch_counts", {}) as Dictionary
	var actual_solid := int(batches.get("solid", -1))
	var actual_window := int(batches.get("window", -1))
	var ring_total := planned_solid + planned_window
	print(
		"    [外立面环] plan solid=%d window=%d total=%d | actual solid=%d window=%d"
		% [planned_solid, planned_window, ring_total, actual_solid, actual_window]
	)
	# 哨兵：0 样本会让下面所有「相等」判据恒真 —— 必须先确认真摆了件。
	_expect(
		ring_total > 0,
		"100层外立面环一件都没有（立面未接线，或哨兵为 0 样本）",
		failures
	)
	_expect(planned_solid > 0, "100层外立面没有实墙件", failures)
	_expect(planned_window > 0, "100层外立面没有窗墙件", failures)
	_expect(
		planned_solid == actual_solid and planned_window == actual_window,
		"100层外立面计划(solid=%d/window=%d)与实际批次实例数(solid=%d/window=%d)不符"
			% [planned_solid, planned_window, actual_solid, actual_window],
		failures
	)
	# 整格铺满一圈：x 向 18 件、z 向 16 件，两侧各一遍，共 68 件。
	var expected_ring := 2 * (ROOFTOP_WORLD_RECT.size.x + ROOFTOP_WORLD_RECT.size.y) / 5.0
	_expect(
		ring_total == int(expected_ring),
		"100层外立面环件数不是整格满铺的 %d 件（实际 %d）" % [int(expected_ring), ring_total],
		failures
	)
	_expect(
		is_equal_approx(float(snapshot.get("outer_facade_bottom_y", 0.0)), -12.0),
		"100层外立面底面标高不是 -12.0（应比女儿墙低一整层）",
		failures
	)
	_expect(
		is_equal_approx(float(snapshot.get("outer_facade_thickness", 0.0)), 0.30),
		"100层外立面厚度不是组件库v002的0.30m",
		failures
	)
	# 两个批次必须是 MultiMesh 且可见；网格自带 PaletteUV（无材质覆盖）。
	for pair in [
		{"key": "solid", "node": rooftop.get("_rooftop_facade_solid_visual")},
		{"key": "window", "node": rooftop.get("_rooftop_facade_window_visual")},
	]:
		var node := pair["node"] as MultiMeshInstance3D
		var label := str(pair["key"])
		_expect(
			node != null and node.multimesh != null and node.multimesh.mesh != null,
			"100层外立面 %s 批次不是带网格的 MultiMeshInstance3D" % label,
			failures
		)
		if node == null:
			continue
		_expect(node.visible, "100层外立面 %s 批次被隐藏（边缘往下会露空洞）" % label, failures)
		_expect(
			node.material_override == null,
			"100层外立面 %s 批次被套了材质覆盖，PaletteUV 会被盖掉" % label,
			failures
		)
		if node.multimesh != null and node.multimesh.mesh != null:
			var aabb := node.multimesh.mesh.get_aabb()
			_expect(
				is_equal_approx(aabb.position.y, 0.0) and is_equal_approx(aabb.size.y, 11.9),
				"100层外立面 %s 件不是「底面中心原点 + 11.90m 可视高」：%s"
					% [label, str(aabb)],
				failures
			)
	# 环的四边碰撞代理：每边一个 body，代理盒厚 0.30m、高 12m。
	var facade_sides := ["North", "South", "West", "East"]
	for side in facade_sides:
		var body := rooftop.find_child("FacadeBoundaryCollision_%s" % side, false, false) as StaticBody3D
		_expect(body != null, "100层外立面 %s 侧碰撞代理缺失" % side, failures)
		if body == null:
			continue
		var shapes := 0
		for child in body.get_children():
			if child is not CollisionShape3D:
				continue
			shapes += 1
			var shape := (child as CollisionShape3D).shape as BoxShape3D
			if shape == null:
				continue
			var thickness: float = (
				shape.size.x if side in ["West", "East"] else shape.size.z
			)
			_expect(
				is_equal_approx(thickness, 0.30),
				"100层外立面 %s 侧碰撞厚度不是 0.30m（实际 %.3f）" % [side, thickness],
				failures
			)
			_expect(
				is_equal_approx(shape.size.y, 12.0),
				"100层外立面 %s 侧碰撞高度不是一整层 12m（实际 %.3f）" % [side, shape.size.y],
				failures
			)
		_expect(shapes == 1, "100层外立面 %s 侧碰撞不是一整条（实际 %d 段）" % [side, shapes], failures)
	# 99F/普通层不得有立面环（否则会凭空多出一圈墙）。
	# add_child() 会同步触发 _ready()（即整套装配），所以这里不需要 await；
	# 保持本函数同步，避免协程被当普通函数调用时后半段断言根本不参与判定。
	var facility := TowerFloorStage3D.new()
	facility.configure(1, "facility", [])
	add_child(facility)
	var combat := TowerFloorStage3D.new()
	combat.configure(2, "combat", [])
	add_child(combat)
	for stage in [facility, combat] as Array[TowerFloorStage3D]:
		var stage_snapshot: Dictionary = stage.get_snapshot()
		_expect(
			int(stage_snapshot.get("outer_facade_module_count", -1)) == 0,
			"非天台层(%s)被误加外立面环" % str(stage_snapshot.get("floor_kind", "")),
			failures
		)
		_expect(
			stage.get("_rooftop_facade_solid_visual") == null
				and stage.get("_rooftop_facade_window_visual") == null,
			"非天台层(%s)被误加外立面批次节点" % str(stage_snapshot.get("floor_kind", "")),
			failures
		)
		_expect(
			stage.find_child("FacadeBoundaryCollision_*", false, false) == null,
			"非天台层(%s)被误加外立面碰撞" % str(stage_snapshot.get("floor_kind", "")),
			failures
		)
	facility.queue_free()
	combat.queue_free()


func _verify_facility(snapshot: Dictionary, failures: Array[String]) -> void:
	_expect(int(snapshot.get("grid_count", -1)) == 50, "99层地板被错误缩小", failures)
	_expect(is_equal_approx(float(snapshot.get("map_size", -1.0)), 250.0), "99层地板边长被错误修改", failures)
	_expect(int(snapshot.get("outer_grid_count", -1)) == 32, "99层外墙被意外缩小", failures)
	_expect(is_equal_approx(float(snapshot.get("outer_map_size", -1.0)), 160.0), "99层外墙边长被意外改变", failures)
	_expect(is_equal_approx(float(snapshot.get("outer_wall_height", -1.0)), 12.0), "99层外墙不是12米", failures)


func _verify_combat_floor(snapshot: Dictionary, failures: Array[String]) -> void:
	_expect(int(snapshot.get("grid_count", -1)) == 50, "普通楼层地板被错误缩小", failures)
	_expect(is_equal_approx(float(snapshot.get("map_size", -1.0)), 250.0), "普通楼层地板边长被错误修改", failures)
	_expect(int(snapshot.get("outer_grid_count", -1)) == 50, "普通楼层外墙被错误收缩", failures)
	_expect(is_equal_approx(float(snapshot.get("outer_map_size", -1.0)), 250.0), "普通楼层外墙边长被错误修改", failures)


func _verify_start_rooftop_shell(tower: TowerDescent3D, failures: Array[String]) -> void:
	_expect(tower != null, "正式塔楼场景无法实例化", failures)
	if tower == null:
		return
	var room_by_id := tower.get("_room_by_id") as Dictionary
	var rooftop_room := room_by_id.get("start") as DungeonRoom3D
	_expect(rooftop_room != null, "100层start房间缺失", failures)
	if rooftop_room == null:
		return
	rooftop_room.ensure_shell_built()
	var snapshot := rooftop_room.get_room_snapshot()
	var open_directions := snapshot.get("open_wall_directions", []) as Array
	for direction in ["north", "south", "east"]:
		_expect(direction in open_directions, "100层start仍未开放%s侧旧房间墙" % direction, failures)
	_expect(
		_count_nodes_with_asset_id(rooftop_room, "ENV-TOWER-WALL-SOLID-5M") == 0,
		"100层start仍生成65米旧房间墙视觉",
		failures
	)
	_expect(
		_count_nodes_with_suffix(rooftop_room, "_Run") == 0,
		"100层start仍生成65米旧房间墙碰撞",
		failures
	)
	_expect(
		_count_nodes_with_asset_id(rooftop_room, "ENV-TOWER-WALL-DOOR-5M") == 1,
		"移除旧房间墙时误删或重复生成了西侧5米门洞墙",
		failures
	)
	_expect(
		rooftop_room.get_door_node("west") != null,
		"移除旧房间墙时误删了100层西侧楼梯门",
		failures
	)


func _count_nodes_with_asset_id(root: Node, asset_id: String) -> int:
	var count := 1 if str(root.get_meta("asset_id", "")) == asset_id else 0
	for child in root.get_children():
		count += _count_nodes_with_asset_id(child, asset_id)
	return count


func _count_nodes_with_suffix(root: Node, suffix: String) -> int:
	var count := 1 if root.name.ends_with(suffix) else 0
	for child in root.get_children():
		count += _count_nodes_with_suffix(child, suffix)
	return count


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


## 角度比较先 wrap 到 (-PI, PI]，避免 3PI/2 这类值因浮点误差误报。
func _expect_angle(actual: float, expected: float, message: String, failures: Array[String]) -> void:
	if not is_equal_approx(wrapf(actual - expected, -PI, PI), 0.0):
		failures.append(message)


## 天台女儿墙「按种子随机破损」的运行时对账（2026-09-19 新增）。
##
## 用户要求：Blender 里做 3 个「能接起来」的破损变种，导入成 prefab 后**随机排列外墙**。
## 本函数把这句话落成可实测的不变量：
##   1. 破损只换外观：四批次件数之和 == 直段槽位总数（槽位没被增删）；
##   2. 计划 == 摆放：各批次 MultiMesh 的实测实例数逐档等于计划数，且四档都 >0
##      （防「三件资产躺在仓库里没被用」）；
##   3. 比例符合口径：总受损率 ∈ [0.15, 0.35]，且破损批次网格包络与 intact 件逐值
##      相同（「能接起来」的运行时证据）；
##   4. 排布可复现且真的随机：把「实际槽位 + 实际种子」重算一遍必须得到与运行时
##      完全相同的计划；同种子两次同结果、换种子必换结果、非天台层整批完好。
func _verify_rooftop_parapet_damage(
	rooftop: TowerFloorStage3D, slot_count: int, failures: Array[String]
) -> void:
	var seed_value := int(rooftop.get("_outer_damage_seed"))
	var damage_nodes: Array = rooftop.get("_outer_damage_visual")
	var batch_counts: Dictionary = rooftop.call("_outer_damage_batch_counts")
	var planned: Dictionary = rooftop.call("get_outer_damage_counts")
	var intact_count := int(batch_counts.get("intact", -1))
	var damaged := 0
	for key in ROOFTOP_DAMAGE_VARIANT_KEYS:
		damaged += int(batch_counts.get(key, -1))
	var ratio := float(damaged) / float(slot_count) if slot_count > 0 else 0.0
	print(
		"    [破损排布] seed=%d slots=%d intact=%d dmg_a=%d dmg_b=%d dmg_c=%d damaged=%d ratio=%.4f"
		% [
			seed_value,
			slot_count,
			intact_count,
			int(batch_counts.get("dmg_a", -1)),
			int(batch_counts.get("dmg_b", -1)),
			int(batch_counts.get("dmg_c", -1)),
			damaged,
			ratio,
		]
	)
	# 哨兵：四批次全为 0 时，下面的「求和 == 槽位数」只会退化成 0 == 0 之外的假绿，
	# 而「计划 == 摆放」会两边同为 0 而恒真 —— 必须先确认真摆了件。
	_expect(damaged > 0, "100层没有任何破损直段（破损未接线，或哨兵为 0 样本）", failures)
	_expect(intact_count > 0, "100层完好直段批次为空", failures)
	_expect(
		intact_count + damaged == slot_count,
		"四批次件数之和(%d) != 直段槽位数(%d)：破损增删了槽位"
			% [intact_count + damaged, slot_count],
		failures
	)
	var all_keys: Array = ["intact"]
	all_keys.append_array(ROOFTOP_DAMAGE_VARIANT_KEYS)
	for key in all_keys:
		_expect(
			int(planned.get(key, -1)) == int(batch_counts.get(key, -1)),
			"100层破损计划数(%s=%d)与实际批次实例数(%d)不符"
				% [key, int(planned.get(key, -1)), int(batch_counts.get(key, -1))],
			failures
		)
		_expect(int(batch_counts.get(key, 0)) > 0, "100层 %s 档一件都没摆上" % key, failures)
	_expect(
		ratio >= ROOFTOP_DAMAGE_RATIO_MIN and ratio <= ROOFTOP_DAMAGE_RATIO_MAX,
		"100层破损比例 %.4f 不在 [%.2f, %.2f]（用户口径约 1/4）"
			% [ratio, ROOFTOP_DAMAGE_RATIO_MIN, ROOFTOP_DAMAGE_RATIO_MAX],
		failures
	)
	_expect(
		damage_nodes.size() == ROOFTOP_DAMAGE_VARIANT_KEYS.size(),
		"100层破损批次不是 %d 个（实际 %d）" % [ROOFTOP_DAMAGE_VARIANT_KEYS.size(), damage_nodes.size()],
		failures
	)
	var outer := rooftop.get("_outer_visual") as MultiMeshInstance3D
	if outer == null or outer.multimesh == null or outer.multimesh.mesh == null:
		_expect(false, "100层完好批次 MultiMesh 缺失，无法核对包络", failures)
		return
	var intact_aabb := outer.multimesh.mesh.get_aabb()
	for index in range(damage_nodes.size()):
		var node := damage_nodes[index] as MultiMeshInstance3D
		if node == null or node.multimesh == null or node.multimesh.mesh == null:
			_expect(false, "100层破损批次 %d 不是 MultiMeshInstance3D 或缺网格" % index, failures)
			continue
		_expect(node.visible, "100层破损批次 %d 被隐藏（破损位置会露出空洞）" % index, failures)
		var variant_aabb := node.multimesh.mesh.get_aabb()
		_expect(
			variant_aabb.is_equal_approx(intact_aabb),
			"100层破损件 %s 包络 %s != intact 件 %s（会导致接头错台）"
				% [ROOFTOP_DAMAGE_VARIANT_KEYS[index], str(variant_aabb), str(intact_aabb)],
			failures
		)
	# 用「实际槽位 + 实际种子」重算计划：这条同时盯住「种子有没有接线」与
	# 「运行时用的槽位顺序是否与算法假定的顺序一致」。
	var live_slots: Array = rooftop.call("get_outer_straight_slot_transforms")
	var recomputed: Dictionary = (
		TowerFloorStage3D.split_outer_parapet_damage(live_slots, seed_value, true)["counts"]
	)
	_expect(
		planned == recomputed,
		"100层实际排布 %s 与按种子重算的计划 %s 不符" % [str(planned), str(recomputed)],
		failures
	)
	# 纯函数三条对照（不建第二个 stage，避免再铺一层地砖）：
	#   同种子必同结果 / 换种子必换结果 / 非天台层整批完好。
	var probe: Array = []
	for index in range(slot_count):
		probe.append(Transform3D(Basis.IDENTITY, Vector3(5.0 * float(index), 0.0, 0.0)))
	var plan_a: Dictionary = TowerFloorStage3D.split_outer_parapet_damage(probe, ROOFTOP_DAMAGE_PLAN_SEED, true)["counts"]
	var plan_b: Dictionary = TowerFloorStage3D.split_outer_parapet_damage(probe, ROOFTOP_DAMAGE_PLAN_SEED, true)["counts"]
	var plan_c: Dictionary = TowerFloorStage3D.split_outer_parapet_damage(probe, ROOFTOP_DAMAGE_PLAN_SEED + 1, true)["counts"]
	var plan_off: Dictionary = TowerFloorStage3D.split_outer_parapet_damage(probe, ROOFTOP_DAMAGE_PLAN_SEED, false)["counts"]
	_expect(plan_a == plan_b, "同种子两次排布结果不同（排布不可复现）", failures)
	_expect(plan_a != plan_c, "换种子排布结果没变（种子没接线，随机写成了常量）", failures)
	_expect(
		int(plan_off.get("intact", -1)) == slot_count,
		"非天台层应整批完好，实际 intact=%d / slots=%d" % [int(plan_off.get("intact", -1)), slot_count],
		failures
	)
	# 变体 prefab 必须真能加载（防「路径写错但件数为 0 时静默跳过」）。
	for path in ROOFTOP_DAMAGE_VARIANT_PATHS:
		_expect(
			ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) != null,
			"破损变体 prefab 加载失败：%s" % path,
			failures
		)
