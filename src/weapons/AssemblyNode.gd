extends Node
class_name AssemblyNode

# AssemblyNode.gd — 武器装配树节点
# 武器系统的核心数据结构，表示装配树中的一个节点（枪身/子弹/配件）
# 支持递归嵌套：子弹上挂枪身，枪身上挂子弹，形成树状结构

## 节点类型枚举
enum NodeType {
	GUN_BODY,    # 主枪身
	BULLET,      # 子弹
	ATTACHMENT,  # 配件（枪口/弹匣/挂载）
}

## 装配槽位定义
enum SlotType {
	MOUNT,       # 挂载槽（可挂 GunBody 或 Attachment）
	MUZZLE,      # 枪口槽
	MAGAZINE,    # 弹匣槽
	BULLET,      # 子弹槽
}

## 节点元数据
var node_type: NodeType
var node_name: String = ""
var node_id: String = ""          # 全局唯一标识符（GUID）
var tags: Array[String] = []     # 标签，用于规则检查（如 "rifle", "explosive"）

## 属性（由装配决定）
var base_stats: Dictionary = {}   # 基础属性 { "damage": 10, "fire_rate": 4.0, ... }

## 槽位（子节点）
var slots: Dictionary = {
	SlotType.MOUNT: null,      # 挂载槽（通常挂一把枪或一个配件）
	SlotType.MUZZLE: null,     # 枪口槽
	SlotType.MAGAZINE: null,   # 弹匣槽
	SlotType.BULLET: null,     # 子弹槽
}

## 父节点引用（反向指针，构成双向树）
var parent_node: AssemblyNode = null

## 层级深度（根=0，每深入一层+1）
var depth: int = 0

## 节点唯一计数器（用于生成 node_id）
static var _uid_counter: int = 0

func _init(p_node_type: NodeType = NodeType.GUN_BODY, p_name: String = "") -> void:
	node_type = p_node_type
	node_name = p_name if p_name != "" else _default_name(p_node_type)
	node_id = _generate_uid()

static func _generate_uid() -> String:
	_uid_counter += 1
	return "node_%06d" % _uid_counter

static func _default_name(nt: NodeType) -> String:
	match nt:
		NodeType.GUN_BODY: return "GunBody_Unknown"
		NodeType.BULLET: return "Bullet_Unknown"
		NodeType.ATTACHMENT: return "Attachment_Unknown"
	return "Node_Unknown"

## 设置节点基础属性
func set_base_stats(stats: Dictionary) -> void:
	base_stats = stats.duplicate()

## 获取节点基础属性（只读副本）
func get_base_stats() -> Dictionary:
	return base_stats.duplicate()

## 计算当前节点及其所有子节点的合成属性（从叶子向根聚合）
func get_computed_stats() -> Dictionary:
	var computed = base_stats.duplicate()

	# 向下递归聚合子节点属性
	for slot_type in slots:
		var child: AssemblyNode = slots[slot_type]
		if child != null:
			var child_stats = child.get_computed_stats()
			_combine_stats(computed, child_stats)

	return computed

func _combine_stats(target: Dictionary, source: Dictionary) -> void:
	"""将 source 的属性合并到 target（不同标签叠加，相同标签取最大值/加成）"""
	for key in source:
		if key == "damage":
			# 伤害叠加
			target[key] = target.get(key, 0) + source[key]
		elif key == "fire_rate":
			# 射速取最大值（多个枪身时以最快为准）
			target[key] = max(target.get(key, 0.0), source[key])
		elif key == "spread":
			# 扩散叠加
			target[key] = target.get(key, 0.0) + source[key]
		elif key == "bullet_count":
			# 子弹数量叠加
			target[key] = target.get(key, 1) + source[key]
		elif key == "speed":
			# 速度取乘积
			target[key] = target.get(key, 1.0) * source[key]
		else:
			# 其他属性取加成
			target[key] = target.get(key, 0) + source[key]

## 挂载子节点到指定槽位
func mount(slot_type: SlotType, child: AssemblyNode) -> bool:
	"""将子节点挂载到指定槽位。返回是否成功。"""
	if child == null:
		return false

	# 同一槽位只能挂一个
	if slots[slot_type] != null:
		return false

	# 防止循环引用
	if _has_ancestor(child):
		push_error("[AssemblyNode] Cannot mount: circular reference detected (node %s is ancestor of %s)" % [node_id, child.node_id])
		return false

	# 解除旧父节点引用
	if child.parent_node != null:
		child.parent_node.slots[SlotType.MOUNT] = null

	# 建立连接
	slots[slot_type] = child
	child.parent_node = self
	child.depth = depth + 1

	return true

## 解除指定槽位的挂载
func unmount(slot_type: SlotType) -> AssemblyNode:
	"""从槽位卸载子节点。返回被卸载的节点（如有）。"""
	var child: AssemblyNode = slots[slot_type]
	if child != null:
		child.parent_node = null
		child.depth = 0
		slots[slot_type] = null
	return child

## 获取挂载在该节点上的所有子节点（递归）
func get_all_descendants() -> Array[AssemblyNode]:
	var descendants: Array[AssemblyNode] = []
	_collect_descendants(descendants)
	return descendants

func _collect_descendants(arr: Array[AssemblyNode]) -> void:
	for slot_type in slots:
		var child: AssemblyNode = slots[slot_type]
		if child != null:
			arr.append(child)
			child._collect_descendants(arr)

## 获取根节点（沿着父链向上找）
func get_root() -> AssemblyNode:
	var current: AssemblyNode = self
	while current.parent_node != null:
		current = current.parent_node
	return current

## 获取该节点的路径描述（如 "GunBody_A / Bullet_A / GunBody_B"）
func get_path_string() -> String:
	var parts: Array[String] = []
	var current: AssemblyNode = self
	while current != null:
		parts.push_front(current.node_name)
		current = current.parent_node
	return " / ".join(parts)

## 检查某个节点是否为自己的祖先
func _has_ancestor(potential_ancestor: AssemblyNode) -> bool:
	var current: AssemblyNode = parent_node
	while current != null:
		if current == potential_ancestor:
			return true
		current = current.parent_node
	return false

## 获取当前节点树的最大深度
func get_max_depth() -> int:
	var max_d: int = depth
	for slot_type in slots:
		var child: AssemblyNode = slots[slot_type]
		if child != null:
			max_d = max(max_d, child.get_max_depth())
	return max_d

## 获取调试信息
func get_debug_info() -> Dictionary:
	var info: Dictionary = {
		"node_id": node_id,
		"node_type": NodeType.keys()[node_type],
		"node_name": node_name,
		"depth": depth,
		"tags": tags,
		"base_stats": base_stats,
		"computed_stats": get_computed_stats(),
		"path": get_path_string(),
	}
	var slot_info: Array = []
	for st in SlotType.keys():
		var idx = SlotType.get(st)
		var child = slots[idx]
		slot_info.append({
			"slot": st,
			"child": child.node_name if child != null else "(empty)"
		})
	info["slots"] = slot_info
	return info

func to_string() -> String:
	return "[AssemblyNode:%s %s(%s) d=%d]" % [node_id, node_name, NodeType.keys()[node_type], depth]