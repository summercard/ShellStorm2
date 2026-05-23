class_name StorageRoomLogic
extends Node2D
## 藏储室逻辑 — 处理隐藏箱发现、守卫怪物生成
## 房间角落有隐藏箱，需要探索或特定条件才能开启
## 可能伴随守卫怪物

signal storage_discovered()
signal storage_unlocked()

enum StorageState {
	HIDDEN,      # 隐藏箱未被发现（玩家未进入交互范围）
	DISCOVERED,  # 已被发现但未解锁
	UNLOCKED,    # 已解锁可开启
}

## 配置
@export var has_guard: bool = true          # 是否有守卫怪物
@export var guard_count: int = 2             # 守卫数量
@export var loot_table: String = "scavenge_floor_3"  # 掉落表（高质量）
@export var requires_key: bool = false        # 是否需要钥匙
@export var discover_radius: float = 80.0    # 发现隐藏箱的距离

## 状态
var _state: StorageState = StorageState.HIDDEN
var _discovered: bool = false
var _unlocked: bool = false
var _hidden_chest: Area2D = null
var _hidden_chest_root: Node = null
var _crate: Area2D = null
var _guard_spawned: bool = false

## 引用
var _wave_spawner: Node = null
var _inventory_module: InventoryModule = null

func _ready() -> void:
	_setup_storage_rooms()
	_connect_signals()

func _setup_storage_rooms() -> void:
	# 查找隐藏箱
	_hidden_chest = get_node_or_null("HiddenChest/Container") as Area2D
	if _hidden_chest != null:
		_hidden_chest_root = _hidden_chest.get_parent()
		# 初始状态：隐藏箱需要被发现
		var sprite: ColorRect = _hidden_chest_root.get_node_or_null("Sprite") as ColorRect
		if sprite != null:
			# 初始透明度较低（需要探索发现）
			sprite.modulate = Color(1, 1, 1, 0.4)
		
		# 监听玩家进入隐藏箱区域
		_hidden_chest.body_entered.connect(_on_hidden_chest_discovered)
	
	# 查找辅助箱
	_crate = get_node_or_null("Crate") as Area2D
	if _crate != null:
		# 辅助箱正常可开启
		_setup_crate()

func _setup_crate() -> void:
	var container: ContainerInteraction = _crate as ContainerInteraction
	if container != null:
		# 设置辅助箱为可交互状态（不需要发现）
		container.set_locked(false)

func _connect_signals() -> void:
	# 获取波次生成器（用于守卫生成）
	_wave_spawner = get_node_or_null("WaveSpawner")

## 玩家进入隐藏箱检测范围（发现隐藏箱）
func _on_hidden_chest_discovered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if _discovered:
		return
	
	_discovered = true
	_state = StorageState.DISCOVERED
	storage_discovered.emit()
	
	# 提升隐藏箱可见度
	var sprite: ColorRect = _hidden_chest_root.get_node_or_null("Sprite") as ColorRect if _hidden_chest_root != null else null
	if sprite != null:
		# 发现后恢复正常透明度，并显示交互标签
		sprite.modulate = Color(1, 1, 1, 0.85)
	
	var label: Label = _hidden_chest_root.get_node_or_null("InteractLabel") as Label if _hidden_chest_root != null else null
	if label != null:
		if requires_key:
			label.text = "[E] 锁定"
		else:
			label.text = "[E] 搜索"
		label.modulate = Color(1, 1, 1, 1)
	
	# 如果有守卫，触发守卫生成
	if has_guard and not _guard_spawned:
		_spawn_guards()
	
	print("[StorageRoomLogic] 隐藏箱已被发现，守卫状态: %s" % ("有" if has_guard else "无"))

## 生成守卫怪物
func _spawn_guards() -> void:
	if _wave_spawner == null or _guard_spawned:
		return
	
	_guard_spawned = true
	
	# 通过波次生成器生成守卫
	if _wave_spawner.has_method("spawn_ambush_enemies"):
		_wave_spawner.spawn_ambush_enemies(guard_count)
		print("[StorageRoomLogic] 已生成 %d 只守卫" % guard_count)
	else:
		print("[StorageRoomLogic] WaveSpawner 无 ambush 方法，跳过守卫生成")

## 解锁隐藏箱（满足条件后调用）
func unlock() -> void:
	if _unlocked:
		return
	_unlocked = true
	_state = StorageState.UNLOCKED
	storage_unlocked.emit()
	
	if _hidden_chest != null:
		var container: ContainerInteraction = _hidden_chest as ContainerInteraction
		if container != null:
			container.set_locked(false)

## 设置背包引用
func set_inventory(inventory: InventoryModule) -> void:
	_inventory_module = inventory
	
	# 同步给子节点容器
	if _hidden_chest != null:
		var container: ContainerInteraction = _hidden_chest as ContainerInteraction
		if container != null and container.has_method("set_inventory"):
			container.set_inventory(inventory)
	if _crate != null:
		var crate: ContainerInteraction = _crate as ContainerInteraction
		if crate != null and crate.has_method("set_inventory"):
			crate.set_inventory(inventory)

## 更新掉落表
func update_loot_table(table_name: String, floor: int) -> void:
	loot_table = table_name
	if _hidden_chest != null:
		var container: ContainerInteraction = _hidden_chest as ContainerInteraction
		if container != null:
			container.update_loot_table(table_name, floor)

## 获取状态
func get_state() -> StorageState:
	return _state

## 是否已解锁
func is_unlocked() -> bool:
	return _unlocked
