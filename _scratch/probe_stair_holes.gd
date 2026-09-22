extends Node
## 一次性勘察探针：**哪几个楼梯井真的在用**。
##
## 起因（2026-09-22）：主人要把 98F/99F 壳体缩到 100F 的 90×80 矩形，而 4 个楼梯井的
## 世界矩形里有 3 个伸在矩形外。判断「要不要处理它们」的前提是：现在实际有几个井在用。
##
## 判据三条（互为交叉验证）：
##   1. `_declared_edges` 里 kind=="vertical" 的边及其 side  —— 权威的「拓扑上连接了几对层」
##   2. 各层 stage 快照的 `stair_hole_sides`                  —— 该层楼板真的挖了哪几个洞
##   3. stage 子树里楼梯井节点（名字含 Stair）                —— 真的摆了哪几个井

const FLOOR_INDICES: Array[int] = [0, 1, 2]


func _ready() -> void:
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990321
	add_child(tower)
	for i in 6:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.35).timeout

	print("########## 1. 竖直边（拓扑：层与层之间真的连了几对）##########")
	var declared := tower.get("_declared_edges") as Array
	var vertical_count := 0
	for value in declared:
		var d := value as Dictionary
		if str(d.get("kind", "")) != "vertical":
			continue
		vertical_count += 1
		print("   %s → %s   side=%s   a_door=%s b_door=%s" % [
			str(d.get("a", "")), str(d.get("b", "")), str(d.get("side", "")),
			str(d.get("a_door_side", "")), str(d.get("b_door_side", "")),
		])
	print("   竖直边总数 = %d" % vertical_count)

	print("\n########## 2. 各层楼板实际挖掉哪几个楼梯井洞 ##########")
	var stages := tower.get("_floor_stages") as Dictionary
	for floor_index in FLOOR_INDICES:
		var stage := stages.get(floor_index) as Node3D
		if stage == null:
			print("   %dF: stage 缺失" % (100 - floor_index))
			continue
		var snap: Dictionary = stage.call("get_snapshot")
		var holes := snap.get("stair_hole_sides", []) as Array
		var gaps := snap.get("facade_gap_sides", []) as Array
		print("   %dF: stair_hole_sides=%s   facade_gap_sides=%s" % [
			100 - floor_index, str(holes), str(gaps),
		])

	print("\n########## 3. 实际摆在场景里的楼梯井节点 ##########")
	for floor_index in FLOOR_INDICES:
		var stage := stages.get(floor_index) as Node3D
		if stage == null:
			continue
		var names: Array[String] = []
		var stack: Array[Node] = [stage]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			for child in node.get_children():
				stack.append(child)
			var n := str(node.name)
			if n.contains("Stair") or n.contains("stair"):
				names.append(n)
		print("   %dF: %d 个楼梯井相关节点" % [100 - floor_index, names.size()])
		for n in names:
			print("        %s" % n)

	print("\n########## 4. 4 个井的世界矩形 vs 统一壳体矩形(100x80) ##########")
	var target := Rect2(-50.0, -35.0, 100.0, 80.0)
	var stage1 := stages.get(1) as Node3D
	for side in ["west", "east", "north", "south"]:
		var hole: Rect2 = stage1.call("_stair_hole_world_rect", side)
		var over: Array[String] = []
		if hole.position.x < target.position.x:
			over.append("西越 %.1f" % (target.position.x - hole.position.x))
		if hole.end.x > target.end.x:
			over.append("东越 %.1f" % (hole.end.x - target.end.x))
		if hole.position.y < target.position.y:
			over.append("北越 %.1f" % (target.position.y - hole.position.y))
		if hole.end.y > target.end.y:
			over.append("南越 %.1f" % (hole.end.y - target.end.y))
		print("   %-5s x[%6.1f,%6.1f] z[%6.1f,%6.1f]  %s" % [
			side, hole.position.x, hole.end.x, hole.position.y, hole.end.y,
			"在内" if over.is_empty() else "、".join(over),
		])

	print("\n########## 5. 各层 stage 的**全部**直接子节点包络（不过滤）##########")
	for floor_index in FLOOR_INDICES:
		var stage2 := stages.get(floor_index) as Node3D
		if stage2 == null:
			continue
		print("   %dF:" % (100 - floor_index))
		for child in stage2.get_children():
			var rect := _envelope(child)
			if rect.size.x <= 0.0 and rect.size.y <= 0.0:
				continue
			print("      %-36s x[%7.1f,%7.1f] z[%7.1f,%7.1f]  跨 %6.1f × %6.1f" % [
				str(child.name), rect.position.x, rect.end.x, rect.position.y, rect.end.y,
				rect.size.x, rect.size.y,
			])

	print("\n########## 6. 塔楼里（非 stage 下）的基地内容包络 ##########")
	var detail := tower.get_node_or_null("RuntimeDetail") as Node3D
	if detail == null:
		print("   RuntimeDetail 缺失")
	else:
		for child in detail.get_children():
			var rect2 := _envelope(child)
			if rect2.size.x <= 0.0 and rect2.size.y <= 0.0:
				continue
			print("      %-36s x[%7.1f,%7.1f] z[%7.1f,%7.1f]  跨 %6.1f × %6.1f" % [
				str(child.name), rect2.position.x, rect2.end.x, rect2.position.y, rect2.end.y,
				rect2.size.x, rect2.size.y,
			])

	print("\n########## 7. 逐层「房间」包络（功能内容的权威口径）##########")
	var rooms := tower.get("_rooms") as Array
	var by_floor := {}
	for value in rooms:
		var room := value as DungeonRoom3D
		if room == null:
			continue
		var fn := int(room.get_meta("floor_number", -1))
		if not by_floor.has(fn):
			by_floor[fn] = []
		(by_floor[fn] as Array).append(room)
	var keys := by_floor.keys()
	keys.sort()
	var target2 := Rect2(-50.0, -35.0, 100.0, 80.0)
	for fn_value in keys:
		var fn := int(fn_value)
		var list := by_floor[fn] as Array
		var min_x := INF
		var max_x := -INF
		var min_z := INF
		var max_z := -INF
		var labels: Array[String] = []
		for value in list:
			var room := value as DungeonRoom3D
			var dims := room.get_dimensions()
			var pos := room.global_position
			min_x = minf(min_x, pos.x - dims.x * 0.5)
			max_x = maxf(max_x, pos.x + dims.x * 0.5)
			min_z = minf(min_z, pos.z - dims.y * 0.5)
			max_z = maxf(max_z, pos.z + dims.y * 0.5)
			labels.append("%s(%s)" % [room.room_id, room.room_type])
		var fits := (
			min_x >= target2.position.x and max_x <= target2.end.x
			and min_z >= target2.position.y and max_z <= target2.end.y
		)
		print("   %dF: %d 间  包络 x[%.1f, %.1f] z[%.1f, %.1f]  跨 %.1f × %.1f m  %s" % [
			fn, list.size(), min_x, max_x, min_z, max_z, max_x - min_x, max_z - min_z,
			("装得下 90×80" if fits else "**装不下 90×80**"),
		])
		print("        %s" % ", ".join(labels))

	print("\nPROBE_STAIR_HOLES_DONE")
	get_tree().quit(0)


## 子树内全部可见网格的全局 AABB 并集，投影到 XZ。
func _envelope(root: Node) -> Rect2:
	var found := false
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		var mesh_node := node as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null or not mesh_node.visible:
			continue
		var aabb: AABB = mesh_node.global_transform * mesh_node.get_aabb()
		for corner in [
			Vector3(aabb.position.x, 0.0, aabb.position.z),
			Vector3(aabb.end.x, 0.0, aabb.position.z),
			Vector3(aabb.position.x, 0.0, aabb.end.z),
			Vector3(aabb.end.x, 0.0, aabb.end.z),
		]:
			found = true
			min_x = minf(min_x, corner.x)
			max_x = maxf(max_x, corner.x)
			min_z = minf(min_z, corner.z)
			max_z = maxf(max_z, corner.z)
	if not found:
		return Rect2()
	return Rect2(Vector2(min_x, min_z), Vector2(max_x - min_x, max_z - min_z))
