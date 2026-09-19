class_name TowerGeometry3D
extends RefCounted
## 塔楼模块统一使用米制。门、楼道、平台和楼梯只能从这里读取净宽与位移，
## 避免局部函数各用一套数字造成接缝、重叠或不可通行。

const DOOR_CLEAR_WIDTH_M := 2.2
const DOOR_CLEAR_HEIGHT_M := 2.5
const GRID_UNIT_M := 5.0
const MAP_SIZE_M := 250.0
const CORE_SIZE_M := 65.0
# 50×50 偶数格整层与13×13奇数格核心无法同时以世界原点为格线中心；
# 核心平移半格后，65m边界、楼梯洞口与250m地砖边界重新严格对齐。
const CORE_CENTER_XZ := Vector2(2.5, 2.5)
const COMBAT_ROOM_SIZE_M := 30.0
const COMBAT_ROOM_SIZE_Y_M := 25.0
const COMBAT_ROOM_GRID := Vector2i(6, 5)
const ROOM_CORRIDOR_GAP_M := GRID_UNIT_M
const COMBAT_STAIR_LOBBY_SIZE_M := 15.0
const BOSS_ARENA_SIZE_M := 90.0
const COMBAT_GRID_CENTERS_M := [-77.5, -27.5, 27.5, 77.5]
const PASSAGE_WIDTH_M := 6.0
const APPROACH_OUTSET_M := 6.0
const RUN_LENGTH_M := 15.0
const LANE_GAP_M := 2.0
const LANE_CENTER_SPACING_M := PASSAGE_WIDTH_M + LANE_GAP_M
# Blender v006 两套楼梯共用的局部接口坐标。根节点位于上层门轴，
# local +X 指向核心外侧；导入 Godot 后 Blender local +Y 对应 local -Z。
const STAIR_UPPER_LANE_OFFSET_M := 11.501
const STAIR_LOWER_LANE_OFFSET_M := STAIR_UPPER_LANE_OFFSET_M - LANE_CENTER_SPACING_M
const STAIR_RUN_START_M := 3.1203
const STAIR_RUN_END_M := STAIR_RUN_START_M + RUN_LENGTH_M
const STAIR_TURN_CENTER_M := 21.0071
const STAIR_FOOTPRINT_SIZE_M := Vector2(15.0, 30.0)
const STAIR_FOOTPRINT_MIN_LOCAL_XZ_M := Vector2(0.0, -2.5)
const STAIR_FOOTPRINT_MAX_LOCAL_XZ_M := Vector2(15.0, 27.5)
const STAIR_LOWER_LANDING_RAISE_M := 0.1
const GUARD_HEIGHT_M := 1.2
const GUARD_END_CLEARANCE_M := 4.0
const FLOOR_THICKNESS_M := 0.30
const FLOOR_HEIGHT_M := 12.0
# 墙体逻辑/阻挡仍覆盖完整层高；视觉网格顶部留0.1m，避免与上层地板共面。
const WALL_LOGICAL_HEIGHT_M := FLOOR_HEIGHT_M
const WALL_VISUAL_HEIGHT_M := FLOOR_HEIGHT_M - 0.1
const WALL_VISUAL_TOP_CLEARANCE_M := WALL_LOGICAL_HEIGHT_M - WALL_VISUAL_HEIGHT_M


static func snap_component_axis(center_m: float, size_m: float) -> float:
	# 组件边界落在 5m 格线上，奇数格组件中心自然落在半格，偶数格落在整格。
	return snappedf(center_m - size_m * 0.5, GRID_UNIT_M) + size_m * 0.5


static func is_component_axis_aligned(center_m: float, size_m: float) -> bool:
	return is_equal_approx(center_m, snap_component_axis(center_m, size_m))


# —— 通用组件视觉解析：跨模块唯一真源（2026-09-19）——
# 背景：DungeonRoom3D / TowerFloorStage3D / TowerDescent3D 原先各自实现
# 「递归取第一个 MeshInstance3D」。这个隐式约定已被实测打破：
# prp_tower_wall_door_5m 的第一个 MeshInstance3D 是 visible=false 的门扇
# （取证见 assets/art/props/dungeon_3d/qa/verify_tower_module_prefabs.gd）。
# 现在统一按组件自己声明的 metadata/visual_node_name 解析，三级回退：
#   1) 按节点路径（支持 "A/B" 形式）
#   2) 按节点名递归查找
#   3) 回退：子树中第一个「可见」的 MeshInstance3D（跳过隐藏件与装饰空节点）
# 组件若走整 Prefab 实例化，本函数只用于读取尺寸做断言，不参与装配。
static func resolve_visual_node(root: Node, declared_name := "") -> Node:
	if root == null:
		return null
	var declared := declared_name
	if declared.is_empty():
		declared = str(root.get_meta("visual_node_name", ""))
	if not declared.is_empty():
		if root is Node:
			var by_path := root.get_node_or_null(NodePath(declared))
			if by_path != null:
				return by_path
		for value in root.find_children(declared, "", true, false):
			return value
	return _first_visible_geometry(root)


static func _first_visible_geometry(root: Node) -> Node:
	if root is MeshInstance3D:
		var mesh_instance := root as MeshInstance3D
		if mesh_instance.mesh != null and mesh_instance.visible:
			return mesh_instance
	for child in root.get_children():
		var found := _first_visible_geometry(child)
		if found != null:
			return found
	return null


static func resolve_visual_mesh(root: Node, declared_name := "") -> Mesh:
	var node := resolve_visual_node(root, declared_name)
	if node == null:
		return null
	var mesh_instance := node as MeshInstance3D
	if mesh_instance != null:
		return mesh_instance.mesh
	return _first_visible_mesh_in(node)


static func _first_visible_mesh_in(root: Node) -> Mesh:
	if root is MeshInstance3D:
		var mesh_instance := root as MeshInstance3D
		if mesh_instance.mesh != null and mesh_instance.visible:
			return mesh_instance.mesh
	for child in root.get_children():
		var found := _first_visible_mesh_in(child)
		if found != null:
			return found
	return null


# —— 包络解析：把「声明节点子树里全部可见网格」并成 root 局部空间的 AABB ——
# 为什么必须按节点变换累积：Mesh.get_aabb() 是「网格自身坐标系」的包围盒，
# 不含 MeshInstance3D 与其父节点（如 ImportedModel / *_ROOT）的变换。
# 例如 prp_tower_wall_door_5m 的门垛网格自身 AABB 的 y 是 -4.5..7.4，
# 真正贴合 0..11.9 的是「累积到 prefab 根」之后的结果。只读网格 AABB 会误判。
# 契约检查（bounds_size_m）与美术替换验收都以此为准。
static func resolve_visual_bounds(root: Node, declared_name := "") -> AABB:
	var node := resolve_visual_node(root, declared_name)
	if node == null:
		return AABB()
	# resolve_visual_node 可能返回 root 的子孙；求从 root 到该节点的变换链。
	var xform := _transform_between(root, node)
	# acc[0] = 累积 AABB，acc[1] = 是否已并入过任何盒（不能用「零尺寸」当哨兵：
	# 合法的零尺寸盒会与「尚未并入」混淆）。
	var acc: Array = [_empty_aabb(), false]
	_accumulate_visible_bounds(node, xform, acc)
	return acc[0] as AABB


static func _transform_between(root: Node, node: Node) -> Transform3D:
	if root == node:
		return Transform3D.IDENTITY
	var chain: Array[Node3D] = []
	var cursor := node
	while cursor != null and cursor != root:
		var as_3d := cursor as Node3D
		if as_3d == null:
			break
		chain.append(as_3d)
		cursor = cursor.get_parent()
	var xform := Transform3D.IDENTITY
	for index in range(chain.size() - 1, -1, -1):
		xform = xform * chain[index].transform
	return xform


static func _accumulate_visible_bounds(
	node: Node, xform: Transform3D, acc: Array
) -> void:
	var mesh_instance := node as MeshInstance3D
	if mesh_instance != null and mesh_instance.mesh != null and mesh_instance.visible:
		var box := _aabb_transformed(mesh_instance.mesh.get_aabb(), xform)
		acc[0] = box if not bool(acc[1]) else (acc[0] as AABB).merge(box)
		acc[1] = true
	for child in node.get_children():
		var as_3d := child as Node3D
		var child_xform := xform
		if as_3d != null:
			child_xform = xform * as_3d.transform
		_accumulate_visible_bounds(child, child_xform, acc)


## AABB 没有与 Transform3D 的运算符；用 8 个角点变换后重新求包围盒。
## 缩放/旋转都要正确生效，不能用「只平移 position」的近似。
static func _aabb_transformed(box: AABB, xform: Transform3D) -> AABB:
	var first := xform * box.position
	var result := AABB(first, Vector3.ZERO)
	var corners: Array[Vector3] = [
		box.position + Vector3(box.size.x, 0.0, 0.0),
		box.position + Vector3(0.0, box.size.y, 0.0),
		box.position + Vector3(0.0, 0.0, box.size.z),
		box.position + Vector3(box.size.x, box.size.y, 0.0),
		box.position + Vector3(box.size.x, 0.0, box.size.z),
		box.position + Vector3(0.0, box.size.y, box.size.z),
		box.position + box.size,
	]
	for corner in corners:
		result = result.expand(xform * corner)
	return result


## 空 AABB 哨兵：size 为 0 表示「还没有并入任何盒」。
static func _empty_aabb() -> AABB:
	return AABB(Vector3.ZERO, Vector3.ZERO)


## 读取资产声明的包络尺寸；缺声明时返回零向量，由调用方决定是否报错。
static func declared_bounds_size(root: Node) -> Vector3:
	return root.get_meta("bounds_size_m", Vector3.ZERO) as Vector3


## 装配基准 Y 偏移：把「模块原点」搬到「模块底面」，让调用方统一按楼面 Y=0 摆放。
## 依据是资产声明的 origin_contract，而不是实测网格 AABB ——
## 这样美术加装饰件（例如门墙的装饰门框下探 0.14m）时不会把整面墙顶高 0.14m。
##   bottom_center / center_bottom → 原点已在底面，偏移 0
##   centered_slab                 → 原点在板厚中心，需抬 板厚/2
## 未声明的旧资产回退到 AABB 反算，保持既有数值不变。
static func origin_offset_y(root: Node) -> float:
	var contract := str(root.get_meta("origin_contract", ""))
	var size := declared_bounds_size(root)
	match contract:
		"bottom_center", "center_bottom":
			return 0.0
		"centered_slab":
			return size.y * 0.5
	var mesh := resolve_visual_mesh(root)
	if mesh == null:
		return 0.0
	return -mesh.get_aabb().position.y


## 契约字段存在性检查：四类通用物体必须声明同一套字段。
## 返回缺失字段名列表（空数组 = 合规）。这份清单就是「统一规格」的可执行定义。
static func missing_contract_fields(
	root: Node, required: Array[String]
) -> Array[String]:
	var missing: Array[String] = []
	for key in required:
		if not root.has_meta(key):
			missing.append(key)
	return missing
