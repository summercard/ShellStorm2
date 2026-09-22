extends Node
## 探针：核对「99F 外墙」与「100F 天台外立面环」在运行时的**所有权与重合**关系。
##
## 起因（2026-09-22）：塔楼三层壳体平面统一为 100×80 后，99F 的普通外墙
## （prp_tower_wall_solid_5m）与天台立面环（prp_rooftop_facade_solid/window_5m）
## 落到同一圈轮廓、同一层高、同一厚度 —— 四面共面（z-fighting 闪面）。当时本探针
## 量出「99F 62 槽中 58 槽与天台立面环沿轴同位」，那组数字就是裁定的依据
## （原始输出存档在 _scratch/tower_facade/overlap_before.txt）。
##
## 业主裁定后的现状（本探针现在断言的目标）：
##   · 99F 外墙**整圈改用那套立面资源** —— 立面整批接管 99F 直段槽位；
##   · 天台那圈立面**整圈删除** —— 天台立面件数恒为 0。
## 于是「双套资源共面」不再可能：天台侧一件都没有，重合数必然归零。
##
## ⚠️ 不用 MultiMesh.get_instance_transform()：本项目 --headless（dummy 渲染驱动）下
## 回读一律 (0,0,0)。改用 stage 暴露的槽位表（脚本内 Array[Transform3D]，不经渲染
## 服务器）+ MeshInstance3D.global_transform * get_aabb()（网格数据）。

const FLOOR_ROOFTOP := 0
const FLOOR_FACILITY := 1
const SIDES: Array[String] = ["north", "south", "west", "east"]
## 沿轴坐标判「同槽位」的容差（m）。同一套 5m 网格应当逐值相等。
const ALONG_EPS := 0.05
## 判某槽位贴在哪条边上的容差（m）。边界线本身离矩形外皮 0.15~0.25m。
const BOUNDARY_EPS := 2.0

var _failures: Array[String] = []


func _ready() -> void:
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	if scene == null:
		print("PROBE_FAIL: TowerDescent3D.tscn 加载失败")
		get_tree().quit(1)
		return
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990321
	add_child(tower)
	await _settle()

	var stages: Dictionary = tower.get("_floor_stages")
	var rooftop := stages.get(FLOOR_ROOFTOP) as Node3D
	var facility := stages.get(FLOOR_FACILITY) as Node3D
	if rooftop == null or facility == null:
		print("PROBE_FAIL: 100F/99F stage 缺失 rooftop=%s facility=%s" % [str(rooftop), str(facility)])
		get_tree().quit(1)
		return

	_dump_stage(rooftop, "100F 天台")
	_dump_stage(facility, "99F 基地")
	_report_ownership(rooftop, facility)
	_dump_stairwell(tower)

	if _failures.is_empty():
		print("\nPROBE_OVERLAP_OK 双套资源共面已消除（天台立面 0 件、99F 自拥立面）")
	else:
		for failure in _failures:
			print("PROBE_OVERLAP_FAIL %s" % failure)
		print("\nPROBE_OVERLAP_DONE failures=%d" % _failures.size())
	print("\nPROBE_DONE")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _dump_stage(stage: Node3D, label: String) -> void:
	var s: Dictionary = stage.call("get_snapshot")
	print("\n########## %s (floor_index=%d) ##########" % [label, int(s.get("floor_index", -1))])
	print("  floor_kind=%s  stage.position=%s" % [str(s.get("floor_kind")), str(stage.position)])
	print("  outer_world_rect=%s  outer_grid_dimensions=%s" % [
		str(s.get("outer_world_rect")), str(s.get("outer_grid_dimensions"))
	])
	print("  outer_segment_count=%s  outer_straight_slot_count=%s  outer_corner_count=%s" % [
		str(s.get("outer_segment_count")), str(s.get("outer_straight_slot_count")),
		str(s.get("outer_corner_count"))
	])
	print("  外墙: height=%s thickness=%s" % [
		str(s.get("outer_wall_height")), str(s.get("outer_wall_thickness"))
	])
	print("  立面环: solid=%s window=%s slot=%s bottom_y=%s thickness=%s" % [
		str(s.get("outer_facade_solid_count")), str(s.get("outer_facade_window_count")),
		str(s.get("outer_facade_slot_count")), str(s.get("outer_facade_bottom_y")),
		str(s.get("outer_facade_thickness"))
	])
	print((
		"  立面让位: stair_hole_sides=%s（独立的 gap_spans/module_count/gap_sides 已随"
		+ "天台立面环一同删除，立面现在直接接管直段槽位）"
	) % [str(s.get("stair_hole_sides"))])
	_dump_direct_children(stage)
	_dump_meshes(stage, 1)
	_dump_collision(stage)


func _dump_direct_children(stage: Node3D) -> void:
	print("  -- 直接子节点 --")
	for child in stage.get_children():
		var line := "     %-40s %s" % [str(child.name), child.get_class()]
		var mmi := child as MultiMeshInstance3D
		if mmi != null and mmi.multimesh != null:
			var mesh_aabb := "null"
			if mmi.multimesh.mesh != null:
				mesh_aabb = str(mmi.multimesh.mesh.get_aabb())
			line += "  instances=%d mesh_aabb=%s" % [mmi.multimesh.instance_count, mesh_aabb]
		var mi := child as MeshInstance3D
		if mi != null and mi.mesh != null:
			line += "  aabb=%s" % str(mi.get_aabb())
		print(line)


## 递归列出所有 MeshInstance3D 的**世界** AABB —— 用于看角件/立面件到底落在哪。
func _dump_meshes(root: Node, depth: int) -> void:
	if depth > 4:
		return
	for child in root.get_children():
		var mi := child as MeshInstance3D
		if mi != null and mi.mesh != null and mi.visible:
			var aabb: AABB = mi.global_transform * mi.get_aabb()
			print("     %s%-34s x[%7.2f,%7.2f] y[%7.2f,%7.2f] z[%7.2f,%7.2f]" % [
				"    ".repeat(depth - 1), str(mi.name),
				aabb.position.x, aabb.end.x,
				aabb.position.y, aabb.end.y,
				aabb.position.z, aabb.end.z,
			])
		_dump_meshes(child, depth + 1)


func _dump_collision(stage: Node3D) -> void:
	print("  -- 碰撞代理 --")
	var hits := 0
	for child in stage.get_children():
		var body := child as StaticBody3D
		if body == null:
			continue
		hits += 1
		var line := "     %-32s camera_lower_wall=%s" % [
			str(body.name), str(body.get_meta("camera_lower_wall", false))
		]
		for sub in body.get_children():
			var cs := sub as CollisionShape3D
			if cs == null or cs.shape == null:
				continue
			var box := cs.shape as BoxShape3D
			if box != null:
				line += "  [pos=%s size=(%.2f,%.2f,%.2f)]" % [
					str(cs.position), box.size.x, box.size.y, box.size.z
				]
		print(line)
	if hits == 0:
		print("     （无）")


## 立面所有权核对（2026-09-22 裁定后）：99F 自拥立面、天台一件不留。
##
## 历史对照：改动前这里量的是「99F 普通外墙 vs 天台立面环」沿轴同位槽数（62 槽中 58 槽），
## 那是共面闪面的根因。现在天台立面件数恒为 0 ⇒ 同位槽数必然 0；同时 99F 的立面槽位
## 表与它自己的直段槽位表**逐条逐值相同**（立面接管直段，不是另起一圈）。
func _report_ownership(rooftop: Node3D, facility: Node3D) -> void:
	print("\n########## 立面所有权核对：99F 自拥 / 天台清零 ##########")
	var roof_snapshot: Dictionary = rooftop.call("get_snapshot")
	var fac_snapshot: Dictionary = facility.call("get_snapshot")
	var roof_rect: Rect2 = roof_snapshot.get("outer_world_rect", Rect2())
	var fac_rect: Rect2 = fac_snapshot.get("outer_world_rect", Rect2())
	print("100F outer_world_rect=%s  stage.position.y=%.2f" % [str(roof_rect), rooftop.position.y])
	print(" 99F outer_world_rect=%s  stage.position.y=%.2f" % [str(fac_rect), facility.position.y])
	print("轮廓相同 = %s" % ("是" if roof_rect.is_equal_approx(fac_rect) else "**否**"))

	var roof_facade_modules := int(roof_snapshot.get("outer_facade_module_count", -1))
	var fac_facade_modules := int(fac_snapshot.get("outer_facade_module_count", -1))
	print("立面件数：100F 天台=%d（应为 0：整圈删除）   99F=%d（应 >0：自拥立面）"
		% [roof_facade_modules, fac_facade_modules])
	_expect(roof_facade_modules == 0, "100F 天台仍有 %d 件立面" % roof_facade_modules)
	_expect(fac_facade_modules > 0, "99F 一件立面都没有")

	var fac_facade_slots := int(fac_snapshot.get("outer_facade_slot_count", -1))
	var fac_straight_slots := int(fac_snapshot.get("outer_straight_slot_count", -1))
	print("99F 槽位：立面=%d   直段=%d（应相等：立面整批接管直段）"
		% [fac_facade_slots, fac_straight_slots])
	_expect(
		fac_facade_slots == fac_straight_slots and fac_straight_slots > 0,
		"99F 立面槽位(%d) != 直段槽位(%d)" % [fac_facade_slots, fac_straight_slots]
	)
	# 99F 的普通墙批必须留空 —— 否则两套墙仍在同槽位共面（正是本次要消灭的现象）。
	var outer := facility.get("_outer_visual") as MultiMeshInstance3D
	var outer_instances := -1
	if outer != null and outer.multimesh != null:
		outer_instances = outer.multimesh.instance_count
	print("99F 普通墙批实例数=%d（应为 0：直段已整批交给立面批次）" % outer_instances)
	_expect(outer_instances == 0, "99F 普通墙批仍有 %d 个实例，会与立面共面" % outer_instances)

	var roof_facade := _slots_by_side(rooftop.call("get_outer_facade_slot_transforms"), roof_rect)
	var fac_facade := _slots_by_side(facility.call("get_outer_facade_slot_transforms"), fac_rect)
	var fac_wall := _slots_by_side(facility.call("get_outer_straight_slot_transforms"), fac_rect)
	var roof_total := 0
	var aligned_total := 0
	for side in SIDES:
		var roof_along: Array = roof_facade.get(side, [])
		var facade_along: Array = fac_facade.get(side, [])
		var wall_along: Array = fac_wall.get(side, [])
		var aligned := _count_aligned(facade_along, wall_along)
		roof_total += roof_along.size()
		aligned_total += aligned
		print("%-6s 天台立面=%2d 槽   99F立面=%2d 槽   99F直段=%2d 槽   立面∥直段同位=%2d 槽" % [
			side, roof_along.size(), facade_along.size(), wall_along.size(), aligned
		])
		print("        天台立面 along=%s" % _fmt(roof_along))
		print("        99F立面  along=%s" % _fmt(facade_along))
		_expect(
			roof_along.is_empty(),
			"100F 天台 %s 边仍残留 %d 个立面槽位" % [side, roof_along.size()]
		)
		_expect(
			aligned == wall_along.size() and not wall_along.is_empty(),
			"99F %s 边立面槽位与直段槽位沿轴同位 %d/%d（立面应逐条接管直段）"
				% [side, aligned, wall_along.size()]
		)
	print("合计：天台立面 %d 槽（历史值 66）⇒ 与 99F 的可重合槽数 0（历史值 58/62）" % roof_total)
	_expect(roof_total == 0, "天台立面环仍有 %d 个槽位" % roof_total)
	_expect(aligned_total > 0, "99F 立面与直段没有一个槽位同位（哨兵为 0 样本）")


## 统计 a 中有多少项在 b 中能找到沿轴同位（±ALONG_EPS）。
func _count_aligned(a: Array, b: Array) -> int:
	var count := 0
	for pb in b:
		for pa in a:
			if absf(float(pa) - float(pb)) <= ALONG_EPS:
				count += 1
				break
	return count


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


## 把槽位变换按「贴在哪条边」分组，返回 {side: Array[float]} 的沿轴坐标（已排序）。
func _slots_by_side(transforms: Array, rect: Rect2) -> Dictionary:
	var out := {}
	for side in SIDES:
		out[side] = [] as Array
	for value in transforms:
		var tr := value as Transform3D
		var p := tr.origin
		var near_z := absf(p.z - rect.position.y) <= absf(p.z - rect.end.y)
		if absf(p.z - rect.position.y) < BOUNDARY_EPS or absf(p.z - rect.end.y) < BOUNDARY_EPS:
			var side_name := "north" if near_z else "south"
			(out[side_name] as Array).append(p.x)
		else:
			var side_name := "west" if absf(p.x - rect.position.x) < absf(p.x - rect.end.x) else "east"
			(out[side_name] as Array).append(p.z)
	for side in SIDES:
		(out[side] as Array).sort()
	return out


func _fmt(values: Array) -> String:
	var parts: Array[String] = []
	for value in values:
		parts.append("%.2f" % float(value))
	return "[%s]" % ", ".join(parts)


func _dump_stairwell(tower: Node) -> void:
	print("\n########## 楼梯井封闭外壁（名字含 Stairwell / Enclosure）##########")
	var hits := 0
	for node in _walk(tower):
		var name_text := str(node.name)
		if name_text.find("Stairwell") < 0 and name_text.find("Enclosure") < 0:
			continue
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var aabb: AABB = mi.global_transform * mi.get_aabb()
		print("  %-48s x[%8.2f,%8.2f] z[%8.2f,%8.2f]" % [
			name_text, aabb.position.x, aabb.end.x, aabb.position.z, aabb.end.z
		])
		hits += 1
	print("  命中 %d 个" % hits)


func _walk(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		out.append(node)
		for child in node.get_children():
			stack.append(child)
	return out


func _settle() -> void:
	for i in 8:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.45).timeout
