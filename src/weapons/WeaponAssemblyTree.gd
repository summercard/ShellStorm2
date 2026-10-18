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

## 掉落品质（蓝 / 紫 / 金）。由 `WeaponInstance` 在装配树建成后注入。
## **不进装配快照**：品质是实例属性，快照会被原样存档，写进去会在每次读档重复乘。
## 效果只在 `get_computed_stats()` 出口乘一次，因此幂等。规则见 `WeaponDropGrade`。
var drop_grade: String = WeaponDropGrade.GRADE_BLUE

## 弹药模块是否绑定锁定（掉落枪自带，不可拆卸/替换）。
## 由 `WeaponInstance` 在装配树建成/装载后注入；权威值在实例上，这里只是运行投影。
## 所有「换弹药槽」的入口都读它 —— 只灰 UI 按钮挡不住局内快捷装配与工作台两条链。
var bullet_module_locked: bool = false

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
var _overheat_shots := 0
var growth_stacks := 0
var _crit_damage_shots := 0
var _attachment_ready_at := 0.0
signal attachment_triggered(event: String, attachment: Dictionary, target: Node)


## 构造函数：从一个根节点装配树创建
func _init(root_node: AssemblyNode = null) -> void:
	if root_node != null:
		set_root(root_node)


func _exit_tree() -> void:
	## AssemblyNode is intentionally a data-only Node (it never enters the
	## SceneTree), so Godot will not free its mounted descendants for us.  Release
	## the ownership graph explicitly whenever a run/player weapon tree ends.
	clear_assembly(false)


func _notification(what: int) -> void:
	# 临时预览/事务树不会进入 SceneTree；free() 时仍必须释放数据节点。
	if what == NOTIFICATION_PREDELETE and root != null:
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
	root.set_subtree_depth(0)
	_register_subtree(root)
	_apply_stats(get_computed_stats())
	tree_changed.emit()
	stats_changed.emit(get_computed_stats())
	return true


## 挂载节点到指定槽位
func mount(
	parent_node: AssemblyNode, slot_type: AssemblyNode.SlotType, child: AssemblyNode
) -> bool:
	if parent_node == null or child == null or root == null:
		validation_failed.emit("装配节点无效")
		return false
	if root != null and "melee" in root.tags and (
		slot_type == AssemblyNode.SlotType.BULLET
		or child.node_type == AssemblyNode.NodeType.BULLET
	):
		validation_failed.emit("近战武器不接受子弹模块")
		return false
	if child.node_type == AssemblyNode.NodeType.ATTACHMENT:
		var internal_fate_attachment := (
			child.node_name.begins_with("FateAttachment_")
			or "Fate.Combine" in child.tags
			or "Fate.AddChildNode" in child.tags
		)
		var declared_slot := child.get_attachment_slot_type()
		# FateAttachment 属于递归构筑内部节点，沿用卡牌指定槽，不套用枪械公开配件兼容表。
		if not internal_fate_attachment and declared_slot < 0 and slot_type != AssemblyNode.SlotType.MOUNT:
			validation_failed.emit("内部构筑配件只能进入递归挂载槽")
			return false
		if not internal_fate_attachment and declared_slot >= 0 and declared_slot != int(slot_type):
			validation_failed.emit("配件类型与目标槽位不匹配")
			return false
		if not internal_fate_attachment and declared_slot >= 0 and (parent_node != root or not root.supports_attachment_slot(int(slot_type))):
			validation_failed.emit("当前枪械未开放%s槽" % AssemblyNode.get_attachment_slot_display_name(int(slot_type)))
			return false
	# 深度检查
	if _get_subtree_depth(child) - child.depth + parent_node.depth + 1 > MAX_DEPTH:
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
	var previous_ammo := current_ammo
	_apply_stats(get_computed_stats())
	if "melee" not in root.tags:
		current_ammo = clampi(previous_ammo, 0, magazine_size)
	tree_changed.emit()
	stats_changed.emit(get_computed_stats())
	ammo_changed.emit(current_ammo, magazine_size)
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
	var previous_ammo := current_ammo
	var stats := get_computed_stats()
	_apply_stats(stats)
	if root != null and "melee" not in root.tags:
		current_ammo = clampi(previous_ammo, 0, magazine_size)
	tree_changed.emit()
	stats_changed.emit(stats)
	ammo_changed.emit(current_ammo, magazine_size)
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
	_overheat_shots = 0
	growth_stacks = 0
	_crit_on_kill_stack = 0
	_crit_damage_shots = 0
	_attachment_ready_at = 0.0
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
## 计算全树数值，并在**出口**叠加掉落品质的伤害倍率。
##
## 为什么在出口而不是写进节点 `base_stats`：
##   · 节点 base_stats 会被序列化进 `assembly_snapshot`，读档 → 再乘 → 复利；
##   · 出口只算一遍，`refresh_stats()` / UI 面板 / 实战读的是同一份数，不会两套数字。
##
## 蓝品质（×1.00）直接跳过，返回逐值不变 ⇒ 未掉落的出厂枪 / 商人枪行为零变化。
func get_computed_stats() -> Dictionary:
	if root == null:
		return {}
	var stats := root.get_computed_stats()
	var multiplier := WeaponDropGrade.damage_multiplier(drop_grade)
	if not is_equal_approx(multiplier, 1.0):
		# 远程最终伤害 = `damage + bullet_damage`（见 WeaponModel3D._configure_common_stats），
		# 两个键都乘，否则品质加成会被子弹伤害那一半稀释。
		stats["damage"] = _scale_stat(stats.get("damage", 0), multiplier)
		if stats.has("bullet_damage"):
			stats["bullet_damage"] = _scale_stat(stats["bullet_damage"], multiplier)
	stats["drop_grade"] = drop_grade
	stats["grade_damage_multiplier"] = multiplier
	return stats


## 按原值的类型缩放的整数/浮点保守处理：整数进、整数出，避免 UI 上冒出 16.499999。
static func _scale_stat(raw: Variant, multiplier: float) -> Variant:
	if raw is int:
		return int(round(float(raw) * multiplier))
	return float(raw) * multiplier


## 节点数值被命运卡直接修改后，立即同步到实战射击参数与 UI。
func refresh_stats() -> void:
	if root == null:
		return
	var previous_ammo := current_ammo
	# 必须走 self.get_computed_stats()（含品质倍率），不能直连 root ——
	# 直连会让「改品质后刷新」这一下把加成丢掉，只有首次装配才生效。
	var stats := get_computed_stats()
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


## 本地化版装配树串（供工作台/工坊等玩家可见界面复用）。
## 与 get_assembly_tree_string() 刻意分开：后者保持内部英文 ID，供调试/日志使用，
## 不被语言切换影响；本函数经 GameText 把节点名换成显示名。
func get_localized_assembly_tree_string() -> String:
	if root == null:
		return GameText.text("panel.empty_weapon")
	var parts: Array[String] = []
	var cursor: AssemblyNode = root
	while cursor != null:
		parts.push_front(GameText.node_name(cursor.node_name))
		cursor = cursor.parent_node
	return " / ".join(parts)


## 公开接口：消耗一次击杀必暴击堆栈（返回 true 表示本次射击强制暴击）
## 由 3D 武器命中敌人并击杀后调用。
func consume_crit_on_kill_stack() -> bool:
	if bool(get_computed_stats().get("crit_on_kill", false)) and _crit_on_kill_stack > 0:
		_crit_on_kill_stack -= 1
		crit_stacks_changed.emit(_crit_on_kill_stack)
		return true
	return false


## 公开接口：获取当前击杀必暴击堆栈数量
func get_crit_on_kill_stack() -> int:
	return _crit_on_kill_stack


## 公开接口：获取超频受击惩罚倍率（由超频命卡写入，取值>1时玩家受击伤害增加）
func get_overheat_penalty() -> float:
	return pow(_overheat_penalty, _overheat_shots)


## 公开接口：增加击杀必暴击堆栈（由 3D 局内运行时在 kill_recorded 后调用）。
func add_crit_on_kill_stack(_count: int = 1) -> void:
	# 无来源的旧房间广播不能给当前枪增加王后奖励。
	pass


func record_projectile_kill(was_critical: bool) -> void:
	var stats := get_computed_stats()
	if bool(stats.get("crit_on_kill", false)):
		_crit_on_kill_stack = mini(_crit_on_kill_stack + 1, MAX_CRIT_STACK)
		crit_stacks_changed.emit(_crit_on_kill_stack)
	if was_critical and int(stats.get("crit_kill_bonus_shots", 0)) > 0:
		_crit_damage_shots = int(stats["crit_kill_bonus_shots"])


func consume_shot_damage_bonus() -> float:
	_overheat_shots += 1
	if _crit_damage_shots <= 0:
		return 1.0
	_crit_damage_shots -= 1
	return float(get_computed_stats().get("crit_kill_damage_multiplier", 1.0))


func record_growth_result(hit: bool, behavior: Dictionary) -> void:
	if not bool(behavior.get("size_growth", false)):
		return
	if hit and bool(behavior.get("consume_growth_on_hit", false)):
		growth_stacks = 0
	elif hit != bool(behavior.get("grow_on_miss", false)):
		growth_stacks = mini(growth_stacks + 1, int(behavior.get("growth_max_stacks", 5)))


func claim_attachment_trigger(event: String, target: Node = null) -> Dictionary:
	var stats := get_computed_stats()
	var enabled := bool(stats.get("fate_attachment_hit_trigger" if event == "hit" else "fate_attachment_reload_trigger", false))
	var now := Time.get_ticks_msec() / 1000.0
	if not enabled or now < _attachment_ready_at:
		return {}
	var attachment: Dictionary = stats.get("fate_attachment", {}).duplicate(true)
	if attachment.is_empty():
		return {}
	_attachment_ready_at = now + float(stats.get("attachment_cooldown", 0.0))
	attachment_triggered.emit(event, attachment, target)
	return attachment

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
	if str(stats.get("weapon_kind", "ranged")) == "melee":
		fire_rate = 0.0
		reload_time = 0.0
		magazine_size = 0
		projectile_count = 0
		spread = 0.0
		bullet_damage = 0
		bullet_speed = 0.0
		current_ammo = 0
		_overheat_penalty = stats.get("overheat_penalty", 1.0)
		return
	fire_rate = stats.get("fire_rate", 4.0)
	reload_time = stats.get("reload_time", 2.0)
	magazine_size = maxi(1, int(float(stats.get("magazine_size", 30)) * float(stats.get("fate_magazine_multiplier", 1.0))))
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
		"damage": get_computed_stats().get("damage", 10),
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
		"computed_stats": get_computed_stats(),
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
