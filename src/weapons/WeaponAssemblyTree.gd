extends Node
class_name WeaponAssemblyTree

# WeaponAssemblyTree.gd — 武器装配树管理器
# 管理整把武器的装配树结构，提供树的构建、查询、验证等接口
# 与 WeaponCore 解耦：WeaponCore 负责射击行为，本类负责装配结构

## 信号
signal tree_changed()                              # 树结构变化
signal stats_changed(computed_stats: Dictionary)   # 属性变化
signal validation_failed(reason: String)          # 装配规则校验失败
signal weapon_fired(position: Vector2, direction: Vector2, count: int)  # 射击事件（代理）
signal weapon_reloaded()                            # 换弹完成
signal ammo_changed(current: int, max: int)       # 弹药变化
signal reload_started()                            # 开始换弹

## 树的根节点（主枪身）
var root: AssemblyNode = null

## 最大深度限制（防止无限递归/组合爆炸）
const MAX_DEPTH: int = 5

## 弹药属性（直接从 WeaponCore 迁移过来的弹药管理逻辑）
var _fire_cooldown: float = 0.0
var _is_reloading: bool = false
var _reload_timer: float = 0.0

## 射击参数（由装配树动态决定）
var fire_rate: float = 4.0      # 每秒射击次数（来自根枪身）
var reload_time: float = 2.0    # 换弹时间（秒）
var magazine_size: int = 30     # 弹匣容量
var current_ammo: int = 30      # 当前弹药
var projectile_count: int = 1   # 每次射击投射物数量
var spread: float = 0.0         # 扩散角度（弧度）
var bullet_scene: PackedScene = preload("res://scenes/Bullet.tscn")
var bullet_speed: float = 600.0
var bullet_damage: int = 10

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
	_apply_stats(root.get_computed_stats())
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
func _get_tree_string() -> String:
	return root.get_path_string() if root != null else "(empty)"

## ========== 射击接口（从 WeaponCore 迁移过来的逻辑）==========

## 主射击方法 — 带世界坐标（用于枪口偏移）
## 与 WeaponCore.fire_from 接口兼容，装配树作为统一射击入口
func fire_from(spawn_pos: Vector2, direction: Vector2) -> bool:
	"""
	执行射击，从指定世界坐标生成子弹。
	参数: spawn_pos — 子弹生成的世界坐标（通常是枪口位置）
	参数: direction — 射击方向（归一化向量）
	返回: 是否成功发射
	"""
	if not _can_fire():
		return false

	_fire_cooldown = 1.0 / fire_rate if fire_rate > 0 else 0.0

	if not _is_reloading and current_ammo > 0:
		_spawn_projectiles_from(spawn_pos, direction)
		current_ammo -= 1
		ammo_changed.emit(current_ammo, magazine_size)
		weapon_fired.emit(spawn_pos, direction, projectile_count)

		if current_ammo <= 0:
			start_reload()
		return true
	return false

## 兼容旧接口
func fire(direction: Vector2) -> bool:
	"""兼容旧接口，从 global_position 发射"""
	# WeaponAssemblyTree extends Node, not Node2D - require explicit position
	return fire_from(Vector2.ZERO, direction)

func _can_fire() -> bool:
	"""检查是否可以射击"""
	return root != null and _fire_cooldown <= 0 and not _is_reloading and current_ammo > 0

func _spawn_projectiles_from(spawn_pos: Vector2, direction: Vector2) -> void:
	"""生成投射物（支持扩散）"""
	for i in range(projectile_count):
		var spread_angle := _calculate_spread(i)
		var spawn_dir := direction.rotated(spread_angle)
		_spawn_bullet_from(spawn_pos, spawn_dir)

func _calculate_spread(index: int) -> float:
	"""计算单个投射物的扩散角度"""
	if projectile_count <= 1 or spread <= 0:
		return 0.0
	var step := spread / float(projectile_count - 1)
	var offset := -spread * 0.5
	return offset + step * index

func _spawn_bullet_from(spawn_pos: Vector2, direction: Vector2) -> void:
	"""从指定位置生成子弹"""
	if bullet_scene:
		var bullet = bullet_scene.instantiate()
		if bullet.has_method("fire"):
			bullet.fire(spawn_pos, direction, bullet_speed, bullet_damage)
		get_tree().root.add_child(bullet)

## 换弹
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

## 更新方法（供外部 _process 调用）
func tick(delta: float) -> void:
	if _fire_cooldown > 0:
		_fire_cooldown -= delta

## 从 computed_stats 更新射击参数（每次树结构变化时调用）
func _apply_stats(stats: Dictionary) -> void:
	fire_rate = stats.get("fire_rate", 4.0)
	reload_time = stats.get("reload_time", 2.0)
	magazine_size = stats.get("magazine_size", 30)
	projectile_count = stats.get("bullet_count", 1)
	spread = stats.get("spread", 0.0)
	current_ammo = magazine_size  # 重置弹药

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
		"tree_string": get_tree_string(),
	}

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