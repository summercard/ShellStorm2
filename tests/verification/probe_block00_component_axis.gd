extends Node
## 探针：实测「战局通用组件」在 Godot 里的**局部朝向**与包络，用来把 Block 00 的
## Blender 布局坐标/旋转映射到 Godot 时钉死符号。两套候选：
##   (A) position = (bx, ·, +by)  且 rotation.y = rot_z
##   (B) position = (bx, ·, -by)  且 rotation.y = rot_z
## 二者互为镜像；只有实测「组件装饰面朝哪一侧」才能判定哪一套让壁板朝房内。
## 只读 prefab 的 mesh 包络与 metadata，不改动任何文件。

const WALL := "res://assets/art/environments/tower_zones/battle/runtime/common_components/wall_standard_5m/wall_standard_5m_root_top3d.tscn"
const DOORWALL := "res://assets/art/environments/tower_zones/battle/runtime/common_components/wall_door_5m/wall_door_5m_root_top3d.tscn"
const CORNER := "res://assets/art/props/dungeon_3d/prp_corner_l_5m.tscn"
const TILE_C01 := "res://assets/art/environments/tower_zones/battle/runtime/common_components/floor_tile_5m/floor_tile_r01_c01_root_top3d.tscn"
const TILE_C02 := "res://assets/art/environments/tower_zones/battle/runtime/common_components/floor_tile_5m/floor_tile_r01_c02_root_top3d.tscn"


func _ready() -> void:
	for path in [WALL, DOORWALL, CORNER, TILE_C01, TILE_C02]:
		_report(path)
	# 关键：把「装饰件」（带色盘材质的 mesh）与「结构件」分开量。
	# 装饰件的横向质心方向 = 装饰面朝向。
	_report_decoration_side(WALL)
	_report_decoration_side(DOORWALL)
	_report_decoration_side(CORNER)
	print("\nPROBE_DONE")
	get_tree().quit(0)


func _report(path: String) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		print("!! 加载失败 %s" % path)
		return
	var root := packed.instantiate() as Node3D
	add_child(root)
	print("\n===== %s =====" % path.get_file())
	for key in ["asset_id", "origin_contract", "forward_axis", "bounds_size_m",
			"snap_to_walk_plane_offset_m", "visual_node_name", "runtime_collision_note"]:
		if root.has_meta(key):
			print("   meta %-28s = %s" % [key, str(root.get_meta(key))])
	print("   全可见网格累积 AABB(root 空间) = %s" % str(_accumulated_aabb(root)))
	print("   子节点:")
	_dump_tree(root, "      ")
	root.queue_free()


func _dump_tree(node: Node, indent: String) -> void:
	for child in node.get_children():
		var extra := ""
		var mi := child as MeshInstance3D
		if mi != null:
			var visible := "vis" if mi.visible else "HID"
			extra = " [%s] aabb=%s" % [visible, str(mi.mesh.get_aabb()) if mi.mesh != null else "<null>"]
		elif child is CollisionShape3D:
			extra = " [COLLISION]"
		elif child is StaticBody3D:
			extra = " [STATICBODY]"
		print("%s%s%s" % [indent, child.name, extra])
		_dump_tree(child, indent + "  ")


const _SIDE_TOLERANCE := 0.02


func _report_decoration_side(path: String) -> void:
	var packed := load(path) as PackedScene
	var root := packed.instantiate() as Node3D
	add_child(root)
	# 装饰面判据：在 ±Z 两端各取「距原点最远的可见网格面」，比较哪一侧更外扩。
	# 组件原点在墙结构中心平面，装饰装甲只贴一侧 ⇒ 外扩更多的那侧就是装饰面。
	var min_z := INF
	var max_z := -INF
	var min_y := INF
	var max_y := -INF
	var min_x := INF
	var max_x := -INF
	for value in root.find_children("*", "MeshInstance3D", true, false):
		var mi := value as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.visible:
			continue
		var xf := _transform_between(root, mi)
		var box := mi.mesh.get_aabb()
		for i in 8:
			var corner := box.position + Vector3(
				box.size.x * float(i & 1),
				box.size.y * float((i >> 1) & 1),
				box.size.z * float((i >> 2) & 1)
			)
			var p := xf * corner
			min_z = minf(min_z, p.z)
			max_z = maxf(max_z, p.z)
			min_y = minf(min_y, p.y)
			max_y = maxf(max_y, p.y)
			min_x = minf(min_x, p.x)
			max_x = maxf(max_x, p.x)
	var side := "?"
	if absf(min_z) > absf(max_z) + _SIDE_TOLERANCE:
		side = "-Z"
	elif absf(max_z) > absf(min_z) + _SIDE_TOLERANCE:
		side = "+Z"
	print("   [朝向] %s 装饰外扩 z=[%.3f, %.3f] ⇒ 装饰面朝 %s" % [
		path.get_file(), min_z, max_z, side,
	])
	print("         x=[%.3f, %.3f] y=[%.3f, %.3f]" % [min_x, max_x, min_y, max_y])
	root.queue_free()


func _accumulated_aabb(root: Node3D) -> AABB:
	var acc: Array = [AABB(), false]
	_acc(root, Transform3D.IDENTITY, acc)
	return acc[0] as AABB


func _acc(node: Node, xf: Transform3D, acc: Array) -> void:
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh != null and mi.visible:
		var box := _transformed_aabb(mi.mesh.get_aabb(), xf)
		acc[0] = box if not bool(acc[1]) else (acc[0] as AABB).merge(box)
		acc[1] = true
	for child in node.get_children():
		var as_3d := child as Node3D
		_acc(child, xf * as_3d.transform if as_3d != null else xf, acc)


func _transformed_aabb(box: AABB, xf: Transform3D) -> AABB:
	var result := AABB(xf * box.position, Vector3.ZERO)
	for i in 8:
		result = result.expand(xf * (box.position + Vector3(
			box.size.x * float(i & 1),
			box.size.y * float((i >> 1) & 1),
			box.size.z * float((i >> 2) & 1)
		)))
	return result


func _transform_between(root: Node, node: Node) -> Transform3D:
	var chain: Array[Node3D] = []
	var cursor := node
	while cursor != null and cursor != root:
		var as_3d := cursor as Node3D
		if as_3d == null:
			break
		chain.append(as_3d)
		cursor = cursor.get_parent()
	var xf := Transform3D.IDENTITY
	for index in range(chain.size() - 1, -1, -1):
		xf = xf * chain[index].transform
	return xf
