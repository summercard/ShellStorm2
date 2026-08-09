extends Node
class_name WeaponAssemblyTree

# WeaponAssemblyTree.gd — 与维度无关的武器装配数据树。
# 3D 射击、弹药计时与投射物生成由 WeaponModel3D 持有；这里仅保存装配、
# 合成属性、命运效果所需状态和 UI 快照，禁止再加载 2D 子弹场景。

## 信号
signal tree_changed  # 树结构变化
signal stats_changed(computed_stats: Dictionary)  # 属性变化
signal validation_failed(reason: String)  # 装配规则校验失败
signal weapon_reloaded  # 换弹完成
signal ammo_changed(current: int, max: int)  # 弹药变化
signal reload_started  # 开始换弹

## 树的根节点（主枪身）
var root: AssemblyNode = null

## 最大深度限制（防止无限递归/组合爆炸）
const MAX_DEPTH: int = 5

## 装配快照保留弹药字段供 UI/存档兼容；正式战斗计时由 WeaponModel3D 持有。
var _is_reloading: bool = false

## 射击参数（由装配树动态决定）
var fire_rate: float = 4.0  # 每秒射击次数（来自根枪身）
var reload_time: float = 2.0  # 换弹时间（秒）
var magazine_size: int = 30  # 弹匣容量
var current_ammo: int = 30  # 当前弹药
var projectile_count: int = 1  # 每次射击投射物数量
var spread: float = 0.0  # 扩散角度（弧度）
var bullet_speed: float = 1.0  # 弹速倍率（1.0 = 不变）
var bullet_damage: int = 5  # 每颗子弹的伤害值

## 所有节点注册表（用于通过 node_id 快速查找）
var _node_registry: Dictionary = {}

## 超频受击惩罚倍率（由超频命卡写入，overheat_penalty>1 时每次射击叠加受击伤害倍率）
var _overheat_penalty: float = 1.0


## 构造函数：从一个根节点装配树创建
func _init(root_node: AssemblyNode = null) -> void:
	if root_node != null:
		set_root(root_node)


func _exit_tree() -> void:
	## AssemblyNode is intentionally a data-only Node (it never enters the
	## SceneTree), so Godot will not free its mounted descendants for us.  Release
	## the ownership graph explicitly whenever a run/player weapon tree ends.
	clear_assembly(false)


## 设置根节点（主枪身）
func set_root(new_root: AssemblyNode) -> bool:
	if new_root == null:
		push_error("[WeaponAssemblyTree] Root cannot be null")
		return false
	if new_root.node_type != AssemblyNode.NodeType.GUN_BODY:
		push_error("[WeaponAssemblyTree] Root must be a GUN_BODY node")
		return false
	if root != null:
		clear_assembly(false)
	root = new_root
	root.depth = 0
	_register_node(root)
	_apply_stats(root.get_computed_stats())
	tree_changed.emit()
	stats_changed.emit(root.get_computed_stats())
	return true


## 挂载节点到指定槽位
func mount(
	parent_node: AssemblyNode, slot_type: AssemblyNode.SlotType, child: AssemblyNode
) -> bool:
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
	_apply_stats(root.get_computed_stats())
	tree_changed.emit()
	stats_changed.emit(root.get_computed_stats())
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


func clear_assembly(notify: bool = true) -> void:
	## Public lifecycle boundary for a whole weapon tree.  Do not use this for a
	## regular unmount: callers may transfer the detached node to a new root.
	var old_root := root
	root = null
	_node_registry.clear()
	_is_reloading = false
	fire_rate = 0.0
	reload_time = 0.0
	magazine_size = 0
	current_ammo = 0
	projectile_count = 0
	spread = 0.0
	bullet_speed = 1.0
	bullet_damage = 0
	_overheat_penalty = 1.0
	if old_root != null and is_instance_valid(old_root):
		_free_assembly_subtree(old_root)
	if notify:
		tree_changed.emit()
		stats_changed.emit({})
		ammo_changed.emit(0, 0)


func _free_assembly_subtree(node: AssemblyNode) -> void:
	for slot_type in node.slots.keys():
		var child: AssemblyNode = node.slots[slot_type] as AssemblyNode
		node.slots[slot_type] = null
		if child != null and is_instance_valid(child):
			child.parent_node = null
			_free_assembly_subtree(child)
	node.parent_node = null
	node.free()


## 获取整棵树的根
func get_root() -> AssemblyNode:
	return root


## 获取树的最大深度
func get_max_depth() -> int:
	return root.get_max_depth() if root != null else 0


## 获取当前武器的合成属性（对外暴露的计算接口）
func get_computed_stats() -> Dictionary:
	return root.get_computed_stats() if root != null else {}


## 节点数值被命运卡直接修改后，立即同步到实战射击参数与 UI。
func refresh_stats() -> void:
	if root == null:
		return
	var previous_ammo := current_ammo
	var stats := root.get_computed_stats()
	_apply_stats(stats)
	current_ammo = mini(previous_ammo, magazine_size)
	tree_changed.emit()
	stats_changed.emit(stats)
	ammo_changed.emit(current_ammo, magazine_size)


## 获取树的可读结构（用于调试/UI）
func _get_tree_string() -> String:
	return root.get_path_string() if root != null else "(empty)"


func get_assembly_tree_string() -> String:
	return _get_tree_string()


## 公开接口：消耗一次击杀必暴击堆栈（返回 true 表示本次射击强制暴击）
## 由 3D 武器命中敌人并击杀后调用。
func consume_crit_on_kill_stack() -> bool:
	if _crit_on_kill_stack > 0:
		_crit_on_kill_stack -= 1
		crit_stacks_changed.emit(_crit_on_kill_stack)
		return true
	return false


## 公开接口：获取当前击杀必暴击堆栈数量
func get_crit_on_kill_stack() -> int:
	return _crit_on_kill_stack


## 公开接口：获取超频受击惩罚倍率（由超频命卡写入，取值>1时玩家受击伤害增加）
func get_overheat_penalty() -> float:
	return _overheat_penalty


## 公开接口：增加击杀必暴击堆栈（由 3D 局内运行时在 kill_recorded 后调用）。
func add_crit_on_kill_stack(count: int = 1) -> void:
	_crit_on_kill_stack = mini(_crit_on_kill_stack + count, MAX_CRIT_STACK)
	crit_stacks_changed.emit(_crit_on_kill_stack)

const MAX_CRIT_STACK: int = 10

## 击杀必暴击堆栈变化信号（供 UI 层订阅以更新 HUD 暴击计数显示）
signal crit_stacks_changed(new_count: int)

## 击杀必暴击堆栈（crit_on_kill 命运卡片机制）
## 每次击杀后累加，消费时按子弹计，不按射击计
## 上限 MAX_CRIT_STACK，避免无限叠加导致暴击失去节奏感
var _crit_on_kill_stack: int = 0


func start_reload() -> void:
	"""开始换弹"""
	if _is_reloading or current_ammo == magazine_size:
		return
	_is_reloading = true
	reload_started.emit()
	await get_tree().create_timer(reload_time).timeout
	current_ammo = magazine_size
	_is_reloading = false
	weapon_reloaded.emit()
	ammo_changed.emit(current_ammo, magazine_size)


## 从 computed_stats 更新射击参数（每次树结构变化时调用）
func _apply_stats(stats: Dictionary) -> void:
	fire_rate = stats.get("fire_rate", 4.0)
	reload_time = stats.get("reload_time", 2.0)
	magazine_size = stats.get("magazine_size", 30)
	projectile_count = stats.get("bullet_count", 1)
	spread = stats.get("spread", 0.0)
	# 子弹自有属性（从 BULLET 节点透传上来）
	bullet_damage = stats.get("bullet_damage", 5)
	bullet_speed = stats.get("bullet_speed", 1.0)
	current_ammo = magazine_size  # 重置弹药
	_overheat_penalty = stats.get("overheat_penalty", 1.0)  # 超频受击惩罚倍率


## 获取武器信息（调试用）
func get_weapon_info() -> Dictionary:
	return {
		"fire_rate": fire_rate,
		"projectile_count": projectile_count,
		"spread": spread,
		"reload_time": reload_time,
		"ammo": "%d/%d" % [current_ammo, magazine_size],
		"damage": root.get_computed_stats().get("damage", 10) if root != null else 0,
		"reloading": _is_reloading,
		"tree_string": get_assembly_tree_string(),
	}


## 获取调试信息
func get_debug_info() -> Dictionary:
	if root == null:
		return {"status": "empty"}
	return {
		"max_depth": get_max_depth(),
		"node_count": _node_registry.size(),
		"computed_stats": root.get_computed_stats(),
		"tree_string": get_assembly_tree_string(),
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
