extends Node
class_name WeaponAssemblyTree

# WeaponAssemblyTree.gd — 武器装配树管理器
# 管理整把武器的装配树结构，提供树的构建、查询、验证等接口
# 与 WeaponCore 解耦：WeaponCore 负责射击行为，本类负责装配结构

## 信号
signal tree_changed  # 树结构变化
signal stats_changed(computed_stats: Dictionary)  # 属性变化
signal validation_failed(reason: String)  # 装配规则校验失败
signal weapon_fired(position: Vector2, direction: Vector2, count: int)  # 射击事件（代理）
signal weapon_reloaded  # 换弹完成
signal ammo_changed(current: int, max: int)  # 弹药变化
signal reload_started  # 开始换弹
signal fire_cooldown_changed(cooldown_ratio: float)  # 射速冷却进度（1.0=就绪，0.0=冷却中）

## 树的根节点（主枪身）
var root: AssemblyNode = null

## 最大深度限制（防止无限递归/组合爆炸）
const MAX_DEPTH: int = 5

## 弹药属性（直接从 WeaponCore 迁移过来的弹药管理逻辑）
## 注意：换弹使用 async await 模式，不使用 _reload_timer 累加
var _fire_cooldown: float = 0.0
var _is_reloading: bool = false

## 射击参数（由装配树动态决定）
var fire_rate: float = 4.0  # 每秒射击次数（来自根枪身）
var reload_time: float = 2.0  # 换弹时间（秒）
var magazine_size: int = 30  # 弹匣容量
var current_ammo: int = 30  # 当前弹药
var projectile_count: int = 1  # 每次射击投射物数量
var spread: float = 0.0  # 扩散角度（弧度）
var bullet_scene: PackedScene = preload("res://scenes/Bullet.tscn")
## 基础弹速（会被 bullet_speed 属性倍率缩放）
const BASE_BULLET_SPEED: float = 600.0
var bullet_speed: float = 1.0  # 弹速倍率（1.0 = 不变）
var bullet_damage: int = 5  # 每颗子弹的伤害值

## 所有节点注册表（用于通过 node_id 快速查找）
var _node_registry: Dictionary = {}

## 子弹挂载枪缓存（命运卡片"子弹背枪"机制）
## 避免每生成一颗子弹都遍历整棵树，树下变化时由 tree_changed 信号更新
var _cached_bullet_attached_gun: AssemblyNode = null

## 伤害倍率（由 Player.apply_damage_multiplier() 同步过来，如 BLESS_DEAD）
var _damage_multiplier: float = 1.0

## 超频受击惩罚倍率（由超频命卡写入，overheat_penalty>1 时每次射击叠加受击伤害倍率）
var _overheat_penalty: float = 1.0


## 构造函数：从一个根节点装配树创建
func _init(root_node: AssemblyNode = null) -> void:
	if root_node != null:
		set_root(root_node)
	# 连接 tree_changed 信号以刷新挂载枪缓存
	tree_changed.connect(_on_tree_changed)


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
	_fire_count = 0  # 重置射击计数器（换枪/换子弹时）
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
	_cached_bullet_attached_gun = null
	_fire_cooldown = 0.0
	_is_reloading = false
	_fire_count = 0
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
	"""从指定位置生成子弹，暴击判定"""
	# every_nth_fire：每第N发触发挂载枪额外射击（"每第七发子弹携带一把枪"）
	var bullet_node: AssemblyNode = _find_bullet_node()
	var nth_fire: int = 0
	var nth_attach_gun: bool = false
	var crit_mult: float = 2.0  # 默认暴击倍率 2.0（兼容无命运卡片的普通子弹）
	if bullet_node != null:
		var bn_stats: Dictionary = bullet_node.get_base_stats()
		nth_fire = int(bn_stats.get("every_nth_fire", 0))
		nth_attach_gun = bool(bn_stats.get("every_nth_attach_gun", false))
		crit_mult = float(bn_stats.get("crit_damage_multiplier", 2.0))

	# 暴击判定：优先消费击杀必暴击堆栈，否则 10% 基础概率
	var is_crit := consume_crit_on_kill_stack()
	if not is_crit:
		is_crit = randf() < 0.10
	var base_damage := int(float(bullet_damage) * crit_mult) if is_crit else bullet_damage
	var final_damage := int(float(base_damage) * _damage_multiplier)  # 应用伤害倍率（BLESS_DEAD等）

	_fire_count += 1
	var is_nth_shot: bool = (nth_fire > 0 and _fire_count % nth_fire == 0)
	var fire_nth_attached_gun: bool = is_nth_shot and nth_attach_gun

	if bullet_scene:
		var bullet = bullet_scene.instantiate()
		_add_projectile_to_world(bullet)
		if bullet.has_method("fire"):
			bullet.fire(
				spawn_pos, direction, BASE_BULLET_SPEED * bullet_speed, final_damage, is_crit
			)
		# 检查子弹节点是否有挂载枪（命运卡片"子弹背枪"机制）
		# 使用缓存避免每颗子弹都遍历整棵树
		var attached_gun: AssemblyNode = _find_bullet_attached_gun()
		if attached_gun != null and bullet.has_method("set_attached_gun"):
			bullet.set_attached_gun(attached_gun)
		# 应用子弹节点自身的命运视觉（变大了、加眼睛等）
		if bullet.has_method("apply_fate_stats_from_node") and bullet_node != null:
			bullet.apply_fate_stats_from_node(bullet_node)
		# every_nth_fire：第N发额外发射挂载枪子弹（"每第七发携带一把枪"）
		# 注意：不传 attached_gun，避免同一挂载枪节点被多个子弹同时显示
		if fire_nth_attached_gun and attached_gun != null:
			_spawn_every_nth_attached_bullet(spawn_pos, direction, attached_gun)

	# 处理枪上加枪：主枪开火时副枪也跟随射击
	_fire_co_mounted_gun(spawn_pos, direction)


## 公开接口：消耗一次击杀必暴击堆栈（返回 true 表示本次射击强制暴击）
## 由玩家子弹命中敌人并击杀后调用
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


## 公开接口：增加击杀必暴击堆栈（由外部调用，RoomGameMode 在 kill_recorded 信号触发后调用）
func add_crit_on_kill_stack(count: int = 1) -> void:
	_crit_on_kill_stack = mini(_crit_on_kill_stack + count, MAX_CRIT_STACK)
	crit_stacks_changed.emit(_crit_on_kill_stack)


## 树结构变化时刷新挂载枪缓存
func _on_tree_changed() -> void:
	_cached_bullet_attached_gun = _find_bullet_attached_gun_raw()


## 遍历装配树找到有挂载枪的子弹节点（命运卡片"子弹背枪"机制）
## 内部实现，不使用缓存
func _find_bullet_attached_gun_raw() -> AssemblyNode:
	if root == null:
		return null
	# 遍历所有节点，找 BULLET 类型且 MOUNT 槽有数据的节点
	var all_nodes := root.get_all_descendants()
	all_nodes.append(root)  # 包含根节点
	for node in all_nodes:
		if node.node_type == AssemblyNode.NodeType.BULLET:
			var mounted_gun: AssemblyNode = node.slots[AssemblyNode.SlotType.MOUNT]
			if mounted_gun != null and mounted_gun.node_type == AssemblyNode.NodeType.GUN_BODY:
				return mounted_gun
	return null


## 公开接口：获取缓存的挂载枪（供 _spawn_bullet_from 使用）
func _find_bullet_attached_gun() -> AssemblyNode:
	return _cached_bullet_attached_gun


## 设置伤害倍率（由 Player.apply_damage_multiplier() 同步过来）
func apply_damage_multiplier(multiplier: float) -> void:
	_damage_multiplier = multiplier


## 遍历装配树找到第一个 BULLET 类型节点（供命运视觉使用）
func _find_bullet_node() -> AssemblyNode:
	if root == null:
		return null
	var all_nodes := root.get_all_descendants()
	all_nodes.append(root)
	for node in all_nodes:
		if node.node_type == AssemblyNode.NodeType.BULLET:
			return node
	return null


## 枪上加枪：主枪开火时触发副枪射击
## 遍历装配树找到有 Fate.SecondaryGun 标签的枪身节点并让其发射子弹
func _fire_co_mounted_gun(spawn_pos: Vector2, direction: Vector2) -> void:
	if root == null:
		return
	# 收集所有节点并检查是否有副枪
	var all_nodes := root.get_all_descendants()
	all_nodes.append(root)
	for node in all_nodes:
		if node.node_type == AssemblyNode.NodeType.GUN_BODY and node.tags.has("Fate.SecondaryGun"):
			# 获取副枪属性并发射
			var stats: Dictionary = node.get_base_stats()
			var gun_fire_rate: float = stats.get("fire_rate", 4.0)
			var gun_damage: int = stats.get("damage", 5)
			var bullet_count: int = stats.get("bullet_count", 1)
			# 计算射击间隔
			var fire_interval: float = 1.0 / gun_fire_rate if gun_fire_rate > 0 else 0.25
			# 副枪独立冷却追踪（每个副枪节点自己的冷却）
			var cooldown_key := "co_mounted_" + node.node_id
			var cooldown: float = _co_mounted_cooldowns.get(cooldown_key, 0.0)
			if cooldown > 0:
				_co_mounted_cooldowns[cooldown_key] = cooldown - get_process_delta_time()
				continue  # 当前冷却中，跳过此副枪，继续检查下一个
			_co_mounted_cooldowns[cooldown_key] = fire_interval
			# 生成副枪子弹（从主枪枪口位置偏移发射）
			var offset_pos := spawn_pos + direction * 15.0
			_spawn_bullet_from_co_gun(offset_pos, direction, gun_damage, bullet_count)


var _co_mounted_cooldowns: Dictionary = {}

## 射击计数器：用于 every_nth_fire 机制（"每第七发子弹携带一把枪"）
var _fire_count: int = 0

const MAX_CRIT_STACK: int = 10

## 击杀必暴击堆栈变化信号（供 UI 层订阅以更新 HUD 暴击计数显示）
signal crit_stacks_changed(new_count: int)

## 击杀必暴击堆栈（crit_on_kill 命运卡片机制）
## 每次击杀后累加，消费时按子弹计，不按射击计
## 上限 MAX_CRIT_STACK，避免无限叠加导致暴击失去节奏感
var _crit_on_kill_stack: int = 0


## every_nth_fire：第N发额外发射挂载枪子弹
## 与普通挂载枪（子弹背枪，持续跟随）不同，这是"每第N发时额外发射一发烧枪"
func _spawn_every_nth_attached_bullet(spawn_pos: Vector2, direction: Vector2, attached_gun: AssemblyNode) -> void:
	var stats: Dictionary = attached_gun.get_base_stats()
	var gun_damage: int = stats.get("damage", 5)
	var bullet_count: int = stats.get("bullet_count", 1)
	var offset_pos := spawn_pos + direction * 20.0
	# 额外挂载枪子弹使用独立缩放伤害
	var nth_damage: int = maxi(1, int(float(gun_damage) * 0.5))
	_spawn_bullet_from_co_gun(offset_pos, direction, nth_damage, bullet_count)


func _spawn_bullet_from_co_gun(
	spawn_pos: Vector2, direction: Vector2, damage: int, bullet_count: int
) -> void:
	"""生成副枪的子弹（不带暴击判定，减少性能开销）"""
	if bullet_scene:
		for i in range(bullet_count):
			var spread_angle := _calculate_spread(i)
			var spawn_dir := direction.rotated(spread_angle)
			var bullet = bullet_scene.instantiate()
			_add_projectile_to_world(bullet)
			if bullet.has_method("fire"):
				bullet.fire(spawn_pos, spawn_dir, BASE_BULLET_SPEED * bullet_speed, damage, false)
			# 副枪子弹也需要挂载枪视觉（命运卡片"子弹背枪"机制）
			var attached_gun: AssemblyNode = _find_bullet_attached_gun()
			if attached_gun != null and bullet.has_method("set_attached_gun"):
				bullet.set_attached_gun(attached_gun)
			# 副枪子弹也需要命运视觉（变大了、加眼睛等）
			if bullet.has_method("apply_fate_stats_from_node"):
				var bullet_node: AssemblyNode = _find_bullet_node()
				if bullet_node != null:
					bullet.apply_fate_stats_from_node(bullet_node)


## 世界坐标 → 子弹父节点（bullet 的 parent 要在 current_scene 不然无法碰撞）
func _get_bullet_parent() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var parent: Node = tree.current_scene
	if parent == null:
		parent = tree.root
	return parent


## 换弹
func _add_projectile_to_world(projectile: Node) -> void:
	var parent := _get_bullet_parent()
	parent.add_child(projectile)


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
		# 发射冷却进度（1.0=完全冷却，冷却完成后=1.0就绪）
		var ratio: float = (
			1.0 - clampf(_fire_cooldown / maxf(0.001, 1.0 / maxf(fire_rate, 0.1)), 0.0, 1.0)
		)
		fire_cooldown_changed.emit(ratio)
	else:
		# 冷却完毕，发射就绪
		fire_cooldown_changed.emit(1.0)


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
