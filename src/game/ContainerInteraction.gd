class_name ContainerInteraction
extends Area2D
## 容器交互组件 — 挂在可开启的容器节点上（箱子/宝箱/补给箱等）
## 检测玩家接近，按E键开启，从 LootModule 生成掉落，物品入背包

## 信号
signal container_opened(loot: Array[Dictionary])
signal interaction_available(available: bool)

enum ContainerState {
	LOCKED,  # 未解锁（可能需要钥匙或未到触发时机）
	AVAILABLE,  # 可交互（玩家在范围内）
	OPENED,  # 已开启（可能还有额外掉落）
}

## 配置
@export var container_type: String = "crate"  # "crate", "chest", "locker", "hidden_cache"
@export var loot_table: String = ""  # 掉落表名，如 "scavenge_floor_1"
@export var floor: int = 1  # 当前楼层（影响掉落数量）
@export var interaction_radius: float = 60.0  # 交互范围（像素）
@export var open_animation: bool = true  # 是否播放开启动画
var guaranteed_items: Array[String] = []

## 状态
var _state: ContainerState = ContainerState.AVAILABLE
var _player_in_range: bool = false
var _interact_label: Label = null
var _opened: bool = false
var _quality_boost: int = 0  ## 下次开箱品质提升（由环境命运触发器设置）
var _extra_loot_enabled: bool = false  ## 下次开箱额外掉落（由环境命运触发器设置）

## 引用
var _inventory_module: InventoryModule = null
var _loot_module: LootModule = null


func _ready() -> void:
	_setup_interaction_label()
	_state = ContainerState.AVAILABLE
	interaction_available.emit(false)


## 设置背包引用（由 RoomGameMode 在实例化时传入）
func set_inventory(inventory: InventoryModule) -> void:
	_inventory_module = inventory


## 设置掉落模块引用
func setup_loot() -> void:
	_loot_module = LootModule.get_instance()


## 创建交互提示标签（使用场景已有的 InteractLabel 节点）
func _setup_interaction_label() -> void:
	_interact_label = get_node_or_null("InteractLabel") as Label
	if _interact_label == null:
		_interact_label = get_node_or_null("../InteractLabel") as Label
	if _interact_label != null:
		_interact_label.z_index = 100
		# 初始隐藏
		_interact_label.modulate = Color(1, 1, 1, 0)

	# 连接 Area2D 信号（检测玩家进入/离开）
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


## Area2D 玩家进入信号回调
func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		if _state != ContainerState.LOCKED and not _opened and _interact_label:
			_interact_label.modulate = Color(1, 1, 1, 1)
		interaction_available.emit(true)


## Area2D 玩家离开信号回调
func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		if _interact_label:
			_interact_label.modulate = Color(1, 1, 1, 0)
		interaction_available.emit(false)


## 每帧处理输入
func _process(delta: float) -> void:
	if _opened:
		return

	# 检测 E 键按下（Space）
	if _player_in_range and Input.is_action_just_pressed("interact"):
		_try_open_container()


## 尝试开启容器
func _try_open_container() -> void:
	if _opened:
		return
	if _state == ContainerState.LOCKED:
		return

	_opened = true
	_state = ContainerState.OPENED
	if _interact_label:
		_interact_label.modulate = Color(1, 1, 1, 0)
	_disable_opened_container_obstacle()
	interaction_available.emit(false)

	# 播放开启动画（如果有）
	if open_animation:
		_play_open_animation()

	# 生成掉落
	var loot: Array[Dictionary] = _generate_loot()

	# 将掉落物品加入背包
	var granted: int = _grant_loot(loot)

	# 发送信号
	container_opened.emit(loot)

	print("[ContainerInteraction] %s 已开启，获得 %d 件物品" % [container_type, granted])


func _disable_opened_container_obstacle() -> void:
	monitoring = false
	collision_layer = 0
	collision_mask = 0
	var blocker := get_node_or_null("VisionBlocker")
	if blocker != null:
		blocker.queue_free()
	var shape := get_node_or_null("InteractionArea") as CollisionShape2D
	if shape != null:
		shape.set_deferred("disabled", true)


## 生成掉落
func _generate_loot() -> Array[Dictionary]:
	if _loot_module == null:
		setup_loot()
	if _loot_module == null:
		return []

	var loot: Array[Dictionary]

	# 根据容器类型确定掉落数量
	match container_type:
		"chest":
			# 宝箱：优质掉落，2-4件
			loot = _loot_module.generate_loot(loot_table, 2 + floor / 2)
		"crate":
			loot = _loot_module.generate_loot(loot_table, 1 + floor / 3)
		"locker":
			loot = _loot_module.generate_loot(loot_table, 2)
		"hidden_cache":
			loot = _loot_module.generate_loot(loot_table, 3 + floor / 2)
		_:
			loot = _loot_module.generate_loot(loot_table, 1)

		# 应用命运效果：额外掉落（生成一件额外物品）
	if _extra_loot_enabled and not loot.is_empty():
		var extra: Array[Dictionary] = _loot_module.generate_loot(loot_table, 1)
		for item in extra:
			loot.append(item)
		print("[ContainerInteraction] 命运效果：额外掉落已应用，+1件物品")

	# 指定赠送的核心道具只出现一次，避免初始箱随机重复主武器。
	for item_id in guaranteed_items:
		loot = loot.filter(func(item: Dictionary) -> bool: return item.get("id", "") != item_id)

	for item_id in guaranteed_items:
		var guaranteed := ItemRegistry.get_instance().get_item(item_id)
		if not guaranteed.is_empty():
			guaranteed["count"] = max(1, int(guaranteed.get("count", 1)))
			loot.append(guaranteed)

	# 应用命运效果：品质提升（提升已生成物品的品质标签，过滤低品质）
	# 逻辑：将所有物品的 loot_table_tier 提升 _quality_boost 级（仅影响显示，不改变实际数据）
	if _quality_boost > 0:
		for item in loot:
			var current_tier: int = item.get("loot_table_tier", 0)
			item["loot_table_tier"] = current_tier + _quality_boost
			print(
				(
					"[ContainerInteraction] 命运效果：物品 %s 品质提升 +%d (tier %d→%d)"
					% [item.get("name", "?"), _quality_boost, current_tier, item["loot_table_tier"]]
				)
			)

	# 重置命运效果标记
	_reset_fate_effects()

	return loot


## 将掉落加入背包（过滤掉货币条目）
func _grant_loot(loot: Array[Dictionary]) -> int:
	if _inventory_module == null or loot.is_empty():
		return 0

	# 过滤掉 is_currency 条目（货币直接由调用方处理，不入背包）
	var real_items: Array[Dictionary] = []
	for item_data in loot:
		if item_data.get("is_currency", false):
			# 货币跳过后续处理（货币由 RoomGameMode.notify_enemy_killed 处理）
			continue
		real_items.append(item_data)

	var granted: int = _loot_module.grant_loot_to_inventory(real_items, _inventory_module)

	# 通过游戏全局组广播容器开启事件（供 UI 层监听飘字效果）
	# 使用 Node 的 group 广播，避免直接依赖 GameUIManager
	get_tree().call_group(
		"game_ui", "_on_container_loot_granted", global_position, real_items, granted
	)

	return granted


## 播放开启动画（简单的缩放+消失）
func _play_open_animation() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	# 向上飘起并淡出
	tween.tween_property(self, "position:y", position.y - 20, 0.4).set_trans(Tween.TRANS_QUAD)
	tween.chain().tween_property(self, "modulate:a", 0.0, 0.3)

	# 或者：简单旋转消失
	var original_scale := scale
	tween.tween_property(self, "scale", original_scale * 1.2, 0.2).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "modulate:a", 0.0, 0.2)


## 设置容器状态
func set_locked(locked: bool) -> void:
	if locked:
		_state = ContainerState.LOCKED
		if _interact_label:
			_interact_label.text = "[E] 锁定"
			_interact_label.modulate = Color(1, 0.5, 0.5, 0.7)
	else:
		_state = ContainerState.AVAILABLE
		if _interact_label:
			_interact_label.text = "[E] 开启"
			if not _player_in_range:
				_interact_label.modulate = Color(1, 1, 1, 0)


## 获取容器状态
func get_state() -> ContainerState:
	return _state


## 是否已开启
func is_opened() -> bool:
	return _opened


## 设置下次开箱品质提升（由环境命运触发器调用）
func set_quality_boost(boost: int) -> void:
	_quality_boost = boost
	print("[ContainerInteraction] 品质提升已设置: +%d" % boost)


## 设置下次开箱额外掉落（由环境命运触发器调用）
func set_extra_loot(enabled: bool) -> void:
	_extra_loot_enabled = enabled
	print("[ContainerInteraction] 额外掉落已设置: %s" % enabled)


## 重置命运效果标记（在开箱后调用）
func _reset_fate_effects() -> void:
	_quality_boost = 0
	_extra_loot_enabled = false


## 更新掉落表（房间切换楼层时调用）
func update_loot_table(table_name: String, new_floor: int) -> void:
	loot_table = table_name
	floor = new_floor
	# 重置容器状态，允许重新生成掉落（如果设计允许重复开启）
	_opened = false
	_state = ContainerState.AVAILABLE
