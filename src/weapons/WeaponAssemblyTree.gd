extends Node
class_name WeaponAssemblyTree

# WeaponAssemblyTree.gd — 武器装配树管理器
# 管理整把武器的装配树结构，提供树的构建、查询、验证等接口
# 与 WeaponCore 解耦：WeaponCore 负责射击行为，本类负责装配结构

## 信号
signal tree_changed()                              # 树结构变化
signal stats_changed(computed_stats: Dictionary)   # 属性变化
signal validation_failed(reason: String)          # 装配规则校验失败

## 树的根节点（主枪身）
var root: AssemblyNode = null

## 最大深度限制（防止无限递归/组合爆炸）
const MAX_DEPTH: int = 5

## 所有节点注册表（用于通过 node_id 快速查找）
var _node_registry: Dictionary = {}

## 构造函数：从一个根节点装配树创建
func _init(root_node: AssemblyNode = null) -> void:
	if root_node != null:
		set_root(root_node)

## 设置根节点（主枪身）
func set_root(new_root: AssemblyNode) -> bool:
	if new_root == null:
		push_error("[WeaponAssemblyTree] Root cannot be null")
		return false
	if new_root.node_type != AssemblyNode.NodeType.GUN_BODY:
		push_error("[WeaponAssemblyTree] Root must be a GUN_BODY node")
		return false
	if root != null:
		_unregister_all()
	root = new_root
	root.depth = 0
	_register_node(root)
	tree_changed.emit()
	stats_changed.emit(root.get_computed_stats())
	return true

## 挂载节点到指定槽位
func mount(parent_node: AssemblyNode, slot_type: AssemblyNode.SlotType, child: AssemblyNode) -> bool:
	# 深度检查
	if _get_subtree_depth(child) + parent_node.depth > MAX_DEPTH:
		validation_failed.emit("超过最大深度限制 (%d)" % MAX_DEPTH)
		return false
	# 循环引用检查
	if parent_node._has_ancestor(child) or parent_node == child:
		validation_failed.emit("检测到循环引用")
		return false
	# 挂载
	if not parent_node.mount(slot_type, child):
		validation_failed.emit("槽位挂载失败（可能已被占用）")
		return false
	_register_subtree(child)
	tree_changed.emit()
	stats_changed.emit(root.get_computed_stats() if root != null else {})
	return true

## 卸载节点
func unmount(node: AssemblyNode) -> bool:
	var slot_type = _find_slot_to_unmount(node)
	if slot_type < 0:
		return false
	var parent = node.parent_node
	if parent == null:
		return false
	_unregister_subtree(node)
	parent.unmount(slot_type)
	tree_changed.emit()
	stats_changed.emit(root.get_computed_stats() if root != null else {})
	return true

## 获取整棵树的根
func get_root() -> AssemblyNode:
	return root

## 获取树的最大深度
func get_max_depth() -> int:
	return root.get_max_depth() if root != null else 0

## 获取当前武器的合成属性（对外暴露的计算接口）
func get_computed_stats() -> Dictionary:
	return root.get_computed_stats() if root != null else {}

## 获取树的可读结构（用于调试/UI）
func get_tree_string() -> String:
	return root.get_path_string() if root != null else "(empty)"

## 获取调试信息
func get_debug_info() -> Dictionary:
	if root == null:
		return {"status": "empty"}
	return {
		"max_depth": get_max_depth(),
		"node_count": _node_registry.size(),
		"computed_stats": root.get_computed_stats(),
		"tree_string": get_tree_string(),
		"root_info": root.get_debug_info(),
	}

## ========== 内部方法 ==========

func _get_subtree_depth(node: AssemblyNode) -> int:
	return node.get_max_depth()

func _find_slot_to_unmount(node: AssemblyNode) -> int:
	if node.parent_node == null:
		return -1
	for st in AssemblyNode.SlotType.keys():
		var idx = AssemblyNode.SlotType.get(st)
		if node.parent_node.slots[idx] == node:
			return idx
	return -1

func _register_node(node: AssemblyNode) -> void:
	_node_registry[node.node_id] = node

func _unregister_node(node: AssemblyNode) -> void:
	_node_registry.erase(node.node_id)

func _register_subtree(node: AssemblyNode) -> void:
	_node_registry[node.node_id] = node
	for child in node.get_all_descendants():
		_node_registry[child.node_id] = child

func _unregister_subtree(node: AssemblyNode) -> void:
	_node_registry.erase(node.node_id)
	for child in node.get_all_descendants():
		_node_registry.erase(child.node_id)

func _unregister_all() -> void:
	_node_registry.clear()
	if root != null:
		for child in root.get_all_descendants():
			_node_registry.erase(child.node_id)