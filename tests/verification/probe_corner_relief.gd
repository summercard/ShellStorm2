extends Node
## 只读探针：量「塔楼 A 套角件 L」两臂装饰面相对各自臂内面的凸出量。
##
## 为什么必须单独量：角件的整体 AABB 是 5.15×11.9×5.15，**两臂互相把对方的厚度轴
## 填满**，所以「拿 AABB 去减结构面 ±0.15」这种量法对角件完全失效（长臂的内面浮雕会被
## 短臂的 -5.0 臂长范围吞掉）。必须**分区取顶点**：只看长臂中段(x∈[1,4.5])的 min z、
## 只看短臂中段(z∈[-4.5,-1])的 max x，才量得到真正的浮雕凸出量。
##
## 运行：export APPDATA=I:/ss2_iso/corner_audit
##       $GODOT --headless --path . --scene res://tests/verification/probe_corner_relief.tscn

const P_CORNER := "res://assets/art/props/dungeon_3d/prp_corner_l_5m.tscn"
const P_TOWER_WALL := "res://assets/art/props/dungeon_3d/prp_tower_wall_solid_5m.tscn"
const P_BATTLE_WALL := "res://assets/art/environments/tower_zones/battle/runtime/common_components/wall_standard_5m/wall_standard_5m_root_top3d.tscn"
const STRUCT_HALF := 0.15


func _ready() -> void:
	_measure_corner()
	_measure_wall(P_TOWER_WALL, "tower A 套实墙")
	_measure_wall(P_BATTLE_WALL, "battle 通用墙")
	get_tree().quit(0)


func _measure_corner() -> void:
	print("========== tower A 套角件 L（ENV-TOWER-CORNER-L-5M） ==========")
	var scene := load(P_CORNER) as PackedScene
	if scene == null:
		print("  !! 加载失败")
		return
	var root := scene.instantiate() as Node3D
	add_child(root)
	var verts := _collect_vertices(root)
	print("  顶点总数 = %d" % verts.size())
	# 长臂：沿 +X，臂长 0..5；其**内面**（朝凹象限）是 z = −0.15。
	var long_min_z := INF
	var long_count := 0
	# 短臂：沿 −Z，臂长 −5..0；其**内面**（朝凹象限）是 x = +0.15。
	var short_max_x := -INF
	var short_count := 0
	for v in verts:
		if v.x >= 1.0 and v.x <= 4.5 and v.z >= -1.5 and v.z <= 1.5:
			long_count += 1
			if v.z < long_min_z:
				long_min_z = v.z
		if v.z <= -1.0 and v.z >= -4.5 and v.x >= -1.5 and v.x <= 1.5:
			short_count += 1
			if v.x > short_max_x:
				short_max_x = v.x
	print("  长臂中段(x∈[1,4.5]) 采样 %d 点 ⇒ min z = %+.4f m" % [long_count, long_min_z])
	print("  短臂中段(z∈[-4.5,-1]) 采样 %d 点 ⇒ max x = %+.4f m" % [short_count, short_max_x])
	print("  长臂装饰面相对内面(z=−0.15)凸出 = %+.1f mm" % ((-0.15 - long_min_z) * 1000.0))
	print("  短臂装饰面相对内面(x=+0.15)凸出 = %+.1f mm" % ((short_max_x - 0.15) * 1000.0))
	# 反向核对：臂的**外面**是否也有装饰（决定它对外侧是不是光板）。
	var long_max_z := -INF
	var short_min_x := INF
	for v in verts:
		if v.x >= 1.0 and v.x <= 4.5:
			long_max_z = maxf(long_max_z, v.z)
		if v.z <= -1.0 and v.z >= -4.5:
			short_min_x = minf(short_min_x, v.x)
	print("  长臂外面 max z = %+.4f m（结构面 +0.15 ⇒ 凸出 %+.1f mm）" % [
		long_max_z, (long_max_z - STRUCT_HALF) * 1000.0,
	])
	print("  短臂外面 min x = %+.4f m（结构面 −0.15 ⇒ 凸出 %+.1f mm）" % [
		short_min_x, (-STRUCT_HALF - short_min_x) * 1000.0,
	])
	root.queue_free()
	print("")


func _measure_wall(path: String, label: String) -> void:
	var scene := load(path) as PackedScene
	if scene == null:
		print("  !! %s 加载失败" % label)
		return
	var root := scene.instantiate() as Node3D
	add_child(root)
	var verts := _collect_vertices(root)
	var min_z := INF
	var max_z := -INF
	for v in verts:
		min_z = minf(min_z, v.z)
		max_z = maxf(max_z, v.z)
	print("========== %s ==========" % label)
	print("  顶点总数 = %d，Z 范围 [%+.4f, %+.4f]" % [verts.size(), min_z, max_z])
	print("  −Z 侧凸出 = %+.1f mm / +Z 侧凸出 = %+.1f mm" % [
		(-STRUCT_HALF - min_z) * 1000.0, (max_z - STRUCT_HALF) * 1000.0,
	])
	print("")
	root.queue_free()


## 把子树里所有 MeshInstance3D 的顶点收集到**该 MeshInstance 的父局部空间之外**的
## 统一坐标系 —— 这里统一用探针根（= 各 prefab 的装配空间）坐标。
func _collect_vertices(root: Node) -> Array:
	var out: Array = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for sub in node.get_children():
			stack.append(sub)
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var to_root: Transform3D = root.global_transform.affine_inverse() * mi.global_transform
		# 必须遍历**所有 surface**：塔楼 A 套的墙/角件是「结构板 + 装饰面」两三个 surf，
		# 只读 surface 0 会漏掉结构板、把 Z 范围量成 [+0.135, +0.3175]（实测踩过）。
		for surface_index in range(mi.mesh.get_surface_count()):
			var arrays := mi.mesh.surface_get_arrays(surface_index)
			if arrays.is_empty():
				continue
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for p in points:
				out.append(to_root * p)
	return out
