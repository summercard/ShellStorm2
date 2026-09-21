extends Node

## 99F 剩余设施布局探针 v2
##
## 目的：量出「父场景 45 个顶层子节点在当前 .tscn 下，游戏里实际装配到哪」。
## 只做事实采集，不下结论。
##
## 两处上一版踩到的坑，这一版已避开：
##   1) 脱离场景树时 Node3D.global_transform **不级联父链** —— 改为手工沿父链累乘；
##   2) 手工累乘时若在 top-level 节点处提前 break，会**漏掉该节点自身的 T** ——
##      本版把 T 一起乘进去，并在 FOCUS 子树里逐层打印世界原点，可直接看出
##      「包装包根节点的 pivot」和「几何落点」是否分离。
##
## 不 add_child 进树：各 facility 包装包挂 BaseFacility3D.gd，进树会跑 _ready 并依赖 autoload。

const SCENE_PATH := "res://assets/art/environments/base_facility_3d/runtime/env_base99_remaining_facilities/env_base99_remaining_facilities_root_top3d.tscn"

# 需要逐层展开的节点（5 个 facility 包装包 + 1 个普通包对照）
const FOCUS := [
	"42_双屏电脑完整工位_资产包",
	"36_墨绿三人休闲沙发_资产包",
	"45_MEDICAL医疗柜_资产包",
	"47_窄型电池柜_资产包",
	"49_武器工作台与弹药附件_资产包",
	"58_空气压缩机_资产包",
	"54_蓄电池组_资产包",
]


func _ready() -> void:
	_rotation_serialization_check()

	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		print("PROBE_FAIL\t无法加载场景")
		get_tree().quit(1)
		return
	var scene_root := packed.instantiate() as Node3D
	print("PROBE_ROOT\t%s\tchildren=%d" % [scene_root.name, scene_root.get_child_count()])

	for child in scene_root.get_children():
		if not (child is Node3D):
			print("ROW\t%s\t(非 Node3D: %s)" % [child.name, child.get_class()])
			continue
		var node := child as Node3D
		var bounds := _mesh_aabb(node)
		var mesh_count := node.find_children("*", "MeshInstance3D", true, false).size()
		print("ROW\t%s\tT=%s\tyaw=%.3f\tcenter=%s\tsize=%s\tmeshes=%d" % [
			node.name,
			_v(node.transform.origin),
			node.rotation_degrees.y,
			_v(bounds.get_center()) if mesh_count > 0 else "n/a",
			_v(bounds.size) if mesh_count > 0 else "n/a",
			mesh_count,
		])

	# 自嵌套同名子节点扫描（**递归**，不只扫直接子节点）：
	# 节点名与任一祖先同名 ⇒ 同一资产多出一份。
	# 这类节点不会被顶层 ROW 循环单独列出，只能靠显式扫描才能发现。
	# 口径：一律用 _aabb_world（从 scene_root 起链）取世界空间 AABB。
	# 另：DUP_OWN 只对顶层节点算，取「除同名子节点以外的直接子树并集」＝原件自持几何。
	var dup_root := scene_root as Node3D
	var dup_total := _scan_dups(dup_root, dup_root, [], dup_root, 0)
	print("DUP_TOTAL\t%d" % dup_total)
	for child in scene_root.get_children():
		if not (child is Node3D):
			continue
		var own := AABB()
		var found := false
		for sub in child.get_children():
			if sub.name == child.name:
				continue
			var b2 := _aabb_world(dup_root, sub)
			if b2.size == Vector3.ZERO:
				continue
			own = b2 if not found else own.merge(b2)
			found = true
		if found:
			print("DUP_OWN\t%s\tworld_center=%s\tworld_size=%s" % [
				child.name, _v(own.get_center()), _v(own.size)])

	for focus_name in FOCUS:
		var target := scene_root.get_node_or_null(NodePath(str(focus_name))) as Node3D
		if target == null:
			print("FOCUS_MISS\t%s" % focus_name)
			continue
		print("FOCUS\t%s" % focus_name)
		_subtree(target, target, 0)
	get_tree().quit(0)


func _subtree(node: Node, top: Node3D, depth: int) -> void:
	if depth > 6:
		return
	var pad := "  ".repeat(depth)
	var info := ""
	if node is Node3D:
		var n3 := node as Node3D
		var world := _chain_transform(top, n3).origin
		info = "\tlocal=%s\tworld=%s\trot_deg=%s" % [
			_v(n3.transform.origin), _v(world), _v(n3.rotation_degrees)]
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var mi := node as MeshInstance3D
			info += "\tmesh_aabb_center=%s" % _v((_chain_transform(top, mi) * mi.mesh.get_aabb()).get_center())
	print("NODE\t%s%s\t%s%s" % [pad, node.name, node.get_class(), info])
	for sub in node.get_children():
		_subtree(sub, top, depth + 1)


func _rotation_serialization_check() -> void:
	# 反证 Godot 的旋转序列化方向，避免靠公式推断轴向符号。
	for deg in [90.0, -90.0, 17.21]:
		var n := Node3D.new()
		n.rotation_degrees = Vector3(0.0, deg, 0.0)
		print("ROTCHECK\tdeg=%.3f\tbasis_x=%s\tbasis_z=%s\troundtrip=%.3f" % [
			deg, _v(n.transform.basis.x), _v(n.transform.basis.z), n.rotation_degrees.y])
		n.free()


func _v(value: Variant) -> String:
	if value is Vector3:
		var v := value as Vector3
		return "(%.4f, %.4f, %.4f)" % [v.x, v.y, v.z]
	return str(value)


## 递归扫描「节点名 == 任一祖先名」的实例，逐份打印。返回份数。
## 每份同时给三个量，别混：
##   world_center/world_size  = **该份自身**几何的世界 AABB（排除同名的更深份）
##   subtree_center/size      = 含更深份的整棵子树并集
##   dup_local / world_origin = 相对父节点的局部位移 / 世界原点
func _scan_dups(node: Node3D, root: Node3D, ancestor_names: Array, scene_root: Node3D,
		depth: int) -> int:
	var total := 0
	for sub in node.get_children():
		if not (sub is Node3D):
			continue
		var sub3 := sub as Node3D
		var passed := ancestor_names.duplicate()
		passed.append(str(sub3.name))
		if ancestor_names.has(str(sub3.name)):
			total += 1
			var own := AABB()
			var found := false
			var own_meshes := 0
			for c in sub3.get_children():
				if c.name == sub3.name:
					continue
				var b := _aabb_world(scene_root, c)
				if b.size == Vector3.ZERO:
					continue
				own = b if not found else own.merge(b)
				found = true
				own_meshes += c.find_children("*", "MeshInstance3D", true, false).size()
			var whole := _aabb_world(scene_root, sub3)
			print("DUP\t%s\tdepth=%d\tdup_local=%s\tworld_origin=%s\tyaw=%+.3f\tworld_center=%s\tworld_size=%s\tmeshes=%d\tsubtree_center=%s\tsubtree_size=%s" % [
				sub3.name, depth, _v(sub3.transform.origin),
				_v(_chain_transform(root, sub3).origin), sub3.rotation_degrees.y,
				_v(own.get_center()), _v(own.size), own_meshes,
				_v(whole.get_center()), _v(whole.size),
			])
		total += _scan_dups(sub3, root, passed, scene_root, depth + 1)
	return total


## 从 top 起链、包含 top 自身，把 node 子树的全部 mesh AABB 并成**世界空间** AABB。
## 与 _mesh_aabb 的区别：这里 top 传 scene_root，因此结果直接落在世界空间。
func _aabb_world(top: Node3D, node: Node) -> AABB:
	var acc := AABB()
	var found := false
	for value in node.find_children("*", "MeshInstance3D", true, false):
		var mi := value as MeshInstance3D
		if mi.mesh == null:
			continue
		var box: AABB = _chain_transform(top, mi) * mi.mesh.get_aabb()
		acc = box if not found else acc.merge(box)
		found = true
	return acc


func _mesh_aabb(root: Node3D) -> AABB:
	var acc := AABB()
	var found := false
	for value in root.find_children("*", "MeshInstance3D", true, false):
		var mi := value as MeshInstance3D
		if mi.mesh == null:
			continue
		var box: AABB = _chain_transform(root, mi) * mi.mesh.get_aabb()
		acc = box if not found else acc.merge(box)
		found = true
	return acc


## 从 node 一路乘到 top（**包含 top 自己的 transform**）。
func _chain_transform(top: Node3D, node: Node) -> Transform3D:
	var total := Transform3D.IDENTITY
	var cursor: Node = node
	while cursor != null:
		if cursor is Node3D:
			total = (cursor as Node3D).transform * total
		if cursor == top:
			break
		cursor = cursor.get_parent()
	return total
