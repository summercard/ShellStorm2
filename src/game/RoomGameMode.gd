class_name RoomGameMode
## 房间游戏模式 — 将 MapManager 地图系统接入 Godot 游戏主循环
## 替代 Main.gd 中的占位敌人生成逻辑

extends Node2D

signal room_cleared(room_data: RoomData)
signal game_over(reason: String)
signal extraction_ready()
signal kill_recorded()
signal wave_progress_changed(killed: int, total: int, wave: int)

@export var initial_floor: int = 1
@export var map_seed: int = -1

## 核心管理器
var map_manager: MapManager
var fate_card_ui: Control
var player: Node2D

## 搜打撤模块
var inventory_module: InventoryModule
var insurance_module: InsuranceModule
var extraction_module: ExtractionModule
var death_settlement_module: DeathSettlementModule

## UI 引用
@onready var player_spawn_marker: Marker2D = get_node_or_null("PlayerSpawn") as Marker2D
@onready var ui_layer: CanvasLayer = get_node_or_null("../GameUIManager") as CanvasLayer
@onready var hp_bar: ProgressBar = get_node_or_null("../GameUIManager/GameHUD/HPBarBG/HPBar") as ProgressBar
@onready var score_label: Label = get_node_or_null("../GameUIManager/GameHUD/TopRightPanel/VBox/ScoreLabel") as Label
@onready var wave_label: Label = get_node_or_null("../GameUIManager/GameHUD/TopRightPanel/VBox/WaveLabel") as Label
@onready var currency_label: Label = get_node_or_null("../GameUIManager/GameHUD/CurrencyLabel") as Label
@onready var room_info_label: Label = get_node_or_null("../GameUIManager/GameHUD/RoomInfoLabel") as Label
@onready var clearing_progress: ProgressBar = get_node_or_null("../GameUIManager/GameHUD/ClearingProgress") as ProgressBar
@onready var game_camera: Camera2D = get_node_or_null("../Camera2D") as Camera2D

## UI 管理器引用（用于飘字等效果）
var _ui_manager: Node = null

## 状态
var current_floor: int = 1
var score: int = 0
var _room_cleared_flag: bool = false
var _kill_count: int = 0
var _start_room_done: bool = false

## 波次生成器（当前房间）
var _current_wave_spawner: RoomWaveSpawner = null

func _ready() -> void:
	_setup_map_manager()
	_setup_extraction_modules()
	_setup_signals()
	# 同步信标数量（在 UI 绑定之前，确保 extraction_director 有正确计数）
	_sync_beacon_count()
	_setup_ui_manager()
	_spawn_player()
	_setup_camera()
	_call_ui_manager_method("set_player", player)
	_start_game()

## 初始化/同步相机：当前项目没有跟随逻辑时，玩家会看起来偏离画面中心。
func _setup_camera() -> void:
	if game_camera == null:
		return
	game_camera.enabled = true
	game_camera.make_current()
	game_camera.position_smoothing_enabled = true
	game_camera.position_smoothing_speed = 8.0
	_sync_camera_to_player(true)

func _sync_camera_to_player(force: bool = false) -> void:
	if game_camera == null or player == null or not is_instance_valid(player):
		return
	if force:
		game_camera.global_position = player.global_position
	else:
		game_camera.global_position = player.global_position

## 初始化 UI 管理器引用并绑定游戏模块
func _setup_ui_manager() -> void:
	# 查找 GameUIManager（作为 CanvasLayer 子节点或同级节点）
	_ui_manager = get_node_or_null("UI/GameUIManager")
	if _ui_manager == null:
		_ui_manager = get_node_or_null("GameUIManager")
	if _ui_manager == null:
		_ui_manager = get_node_or_null("../GameUIManager")  # 尝试父节点同级
	# 如果仍然找不到，延迟查找（UI 可能后实例化）
	if _ui_manager == null:
		await get_tree().process_frame
		_ui_manager = get_node_or_null("UI/GameUIManager")
		if _ui_manager == null:
			_ui_manager = get_node_or_null("GameUIManager")
		if _ui_manager == null:
			_ui_manager = get_node_or_null("../GameUIManager")

	# 绑定各模块到 GameUIManager（GameUIManager 需要知道 RoomGameMode 的引用才能订阅信号）
	_call_ui_manager_method("set_room_game_mode", self)
	_call_ui_manager_method("set_extraction_module", extraction_module)
	_call_ui_manager_method("set_inventory_module", inventory_module)
	_call_ui_manager_method("set_insurance_module", insurance_module)
	# 同步信标数量（需要 extraction_director 已 bind_inventory）
	var bc: int = 0
	if map_manager != null and map_manager.extraction_director != null:
		bc = map_manager.extraction_director.get_beacon_count()
	_call_ui_manager_method("set_beacon_count", bc)

## 安全调用 _ui_manager 的方法（处理 null 和方法不存在情况）
func _call_ui_manager_method(method_name: String, arg = null) -> void:
	if _ui_manager == null:
		return
	if not _ui_manager.has_method(method_name):
		return
	if arg != null:
		_ui_manager.call(method_name, arg)
	else:
		_ui_manager.call(method_name)

## 初始化地图管理器
func _setup_map_manager() -> void:
	map_manager = MapManager.new()
	add_child(map_manager)

	map_manager.map_generated.connect(_on_map_generated)
	map_manager.room_entered.connect(_on_room_entered)
	map_manager.room_exited.connect(_on_room_exited)
	map_manager.floor_changed.connect(_on_floor_changed)
	map_manager.all_rooms_cleared.connect(_on_all_rooms_cleared)

## 初始化搜打撤模块
func _setup_extraction_modules() -> void:
	inventory_module = InventoryModule.new(12)       # 12格背包
	insurance_module = InsuranceModule.new(2)     # 2格保险格
	extraction_module = ExtractionModule.new()
	death_settlement_module = DeathSettlementModule.new()
	_apply_pending_loadout()

	## 信号连接（用于UI更新等）
	inventory_module.inventory_changed.connect(_on_inventory_changed)
	inventory_module.inventory_changed.connect(_sync_beacon_count)  # 背包变化时同步信标数量
	insurance_module.insurance_changed.connect(_on_insurance_changed)
	extraction_module.extraction_completed.connect(_on_extraction_completed)
	extraction_module.extraction_aborted.connect(_on_extraction_aborted)
	death_settlement_module.death_settlement_processed.connect(_on_death_settlement_processed)

func _apply_pending_loadout() -> void:
	if BaseManager == null or inventory_module == null:
		return
	var loadout_items: Array[Dictionary] = BaseManager.consume_pending_loadout()
	for item in loadout_items:
		var count: int = item.get("count", 1)
		var added: int = inventory_module.add_item(item, count)
		if added < count:
			item["count"] = count - added
			BaseManager.add_vault_item(item)

## 连接信号
func _setup_signals() -> void:
	Global.start_game()
	Global.game_over.connect(_on_global_game_over)

	GameManager.hp_changed.connect(_on_hp_changed)
	GameManager.currency_changed.connect(_on_currency_changed)

## 生成玩家
func _spawn_player() -> void:
	var player_scene = preload("res://scenes/Player.tscn")
	player = player_scene.instantiate()
	if player_spawn_marker != null:
		player.global_position = player_spawn_marker.global_position
	else:
		player.global_position = Vector2(640, 360)
	add_child(player)
	_sync_camera_to_player(true)
	if player.has_signal("hp_changed"):
		player.hp_changed.connect(_on_hp_changed)
	if FateCardGameBridge.has_method("set_player"):
		FateCardGameBridge.set_player(player)

## 开始游戏
func _start_game() -> void:
	# 生成第一层地图
	map_manager.generate_map(initial_floor, map_seed)
	map_manager.enter_room(0)

	# 设置 UI
	if hp_bar:
		hp_bar.max_value = GameManager.max_hp
		hp_bar.value = GameManager.current_hp
	_update_ui()

## 地图生成完成
func _on_map_generated(graph: NodeGraph) -> void:
	# 在场景中实例化所有房间
	instantiate_all_rooms()

	# 打印地图状态
	print(debug_status())

	# 更新房间信息
	_update_room_info_label("地图已生成，等待进入...")

	# 同步信标数量（从背包读取信标道具数量）
	_sync_beacon_count()

## 实例化所有房间到场景
func instantiate_all_rooms() -> void:
	var graph: NodeGraph = map_manager.get_graph()
	if graph == null:
		return

	var all_nodes: Array = graph.get_all_nodes()

	for room_node in all_nodes:
		var room_data: RoomData = room_node.room_data

		# 跳过出生房（玩家已经在场景中了）
		if room_data.room_type == RoomData.RoomType.PLAYER_SPAWN:
			continue

		# 房间实例化到世界（使用 RoomFactory，传入背包引用）
		var factory := RoomFactory.new()
		var room_instance: Node2D = factory.create_room(room_data, self, inventory_module)

		# 设置房间在世界中的位置
		room_instance.global_position = room_data.position
		map_manager.register_instantiated_room(room_node.id, room_instance)

func _sum_ints(values: Array[int]) -> int:
	var total := 0
	for value in values:
		total += value
	return total

## 进入房间
func _on_room_entered(room_data: RoomData) -> void:
	_room_cleared_flag = false
	_update_room_info_label("当前: %s [%s]" % [RoomData.get_type_name(room_data.room_type), RoomData.get_level_name(room_data.floor_level)])

	if room_data.room_type == RoomData.RoomType.PLAYER_SPAWN:
		_update_room_info_label("选择命运卡片后进入战斗")
		_show_initial_fate_cards()
		_update_clearing_progress(0, 1)
		return

	# 商人房：自动弹出交易面板（进入即触发，无需按E）
	if room_data.room_type == RoomData.RoomType.MERCHANT:
		_update_clearing_progress(0, 1)
		_auto_open_merchant(room_data)
		return

	# 战斗房：启动波次生成器
	if room_data.is_combat():
		_start_combat_waves(room_data)
	else:
		_update_clearing_progress(0, 1)

## 离开房间（清理当前房间生成器）
func _on_room_exited(room_id: String) -> void:
	_stop_current_room_spawner()

## 楼层切换
func _on_floor_changed(old_floor: int, new_floor: int) -> void:
	current_floor = new_floor
	_update_room_info_label("进入第 %d 层..." % [new_floor])
	_room_cleared_flag = true

	# 切换到新楼层后重新实例化
	instantiate_all_rooms()

## 所有房间清理完毕（地图清空）
func _on_all_rooms_cleared() -> void:
	extraction_ready.emit()

## 全局游戏结束
func _on_global_game_over() -> void:
	# 触发死亡结算
	if death_settlement_module != null and inventory_module != null:
		var settlement_result: Dictionary = death_settlement_module.process_death_settlement(
			inventory_module, insurance_module
		)
		_print_death_settlement(settlement_result)
	# 记录基地数据（死亡）
	if BaseManager != null:
		BaseManager.record_run(false, _get_kill_count())
	game_over.emit("玩家死亡")

func _print_death_settlement(result: Dictionary) -> void:
	var text: String = death_settlement_module.get_death_summary_text(result)
	print(text)

## 撤离完成后赋予玩家应得的 extraction_points
## extraction_points 是局后ersistent 资源，用于在 Workshop 解锁蓝图
func _grant_extraction_points() -> void:
	var floor_bonus: int = current_floor * 15
	var loot_count: int = 0
	if inventory_module != null:
		loot_count = inventory_module.get_used_slots()
	if insurance_module != null:
		loot_count += insurance_module.get_used_slots()
	var loot_bonus: int = loot_count * 3
	var total_points: int = floor_bonus + loot_bonus
	if total_points > 0:
		BaseManager.add_extraction_points(total_points)
		print("[RoomGameMode] Granted extraction_points: %d (floor bonus=%d, loot bonus=%d)" % [total_points, floor_bonus, loot_bonus])

## 撤离完成回调
func _on_extraction_completed(success: bool, loot: Array[Dictionary]) -> void:
	# 如果是交易撤离，需要通知 ExtractionDirector 做最终结算
	var ext_type: String = extraction_module.get_extraction_type() if extraction_module else ""
	if ext_type == "TRADE" and map_manager != null and map_manager.extraction_director != null:
		map_manager.extraction_director.try_use_trade_extraction(success, GameManager.currency, current_floor)

	if success:
		var extracted: int = death_settlement_module.process_extraction_settlement(inventory_module, insurance_module)
		var insurance_items: Array[Dictionary] = insurance_module.get_all_insured_items()
		_grant_extraction_points()
		var saved_to_vault: int = _persist_extracted_items_to_vault()
		_print_extraction_success(extracted, insurance_items)
		print("[RoomGameMode] Saved extracted items to vault: %d" % saved_to_vault)
		_sync_beacon_count()
		# 记录成功撤离到基地
		if BaseManager != null:
			BaseManager.record_run(true, _kill_count)
	else:
		_print_extraction_failure()

func _get_kill_count() -> int:
	return _kill_count

func _print_extraction_success(extracted_count: int, insurance_items: Array[Dictionary]) -> void:
	var lines: Array[String] = ["=== 撤离成功 ==="]
	lines.append("背包物品已保存: %d 件" % extracted_count)
	if not insurance_items.is_empty():
		lines.append("保险格物品: %d 件" % insurance_items.size())
	print("\n".join(lines))

func _persist_extracted_items_to_vault() -> int:
	if BaseManager == null:
		return 0
	var saved := 0
	var overflow := 0
	if inventory_module != null:
		for slot in inventory_module.get_occupied_slots():
			var item: Dictionary = slot.get("item", {}).duplicate(true)
			if item.is_empty():
				continue
			item["count"] = slot.get("count", 1)
			if BaseManager.add_vault_item(item):
				saved += 1
			else:
				overflow += 1
		inventory_module.clear_all()
	if insurance_module != null:
		for insured in insurance_module.get_all_insured_items():
			var item: Dictionary = insured.get("item", {}).duplicate(true)
			if item.is_empty():
				continue
			item["count"] = insured.get("count", 1)
			if BaseManager.add_vault_item(item):
				saved += 1
			else:
				overflow += 1
		insurance_module.clear_all()
	if overflow > 0:
		BaseManager.add_extraction_points(overflow * 5)
		print("[RoomGameMode] Vault full, converted %d overflow items to extraction_points" % overflow)
	return saved

func _print_extraction_failure() -> void:
	print("=== 撤离失败 ===")
	print("撤离未成功，物资可能丢失。")

## 撤离中断回调
func _on_extraction_aborted() -> void:
	_update_room_info_label("撤离已中断！")
	print("撤离读条被中断。")

## 死亡结算处理完毕回调
func _on_death_settlement_processed(dropped: Array[Dictionary], insurance_saved: Array[Dictionary]) -> void:
	var lines: Array[String] = ["=== 死亡结算 ==="]
	lines.append("保险保住: %d 件" % insurance_saved.size())
	lines.append("战利品损失: %d 件" % dropped.size())
	print("\n".join(lines))

## 更新房间信息标签
func _update_room_info_label(text: String) -> void:
	if room_info_label:
		room_info_label.text = text

## 更新清理进度
func _update_clearing_progress(killed: int, total: int) -> void:
	if clearing_progress:
		clearing_progress.max_value = max(1, total)
		clearing_progress.value = killed

## 启动战斗房波次生成
func _start_combat_waves(room_data: RoomData) -> void:
	# 停止旧的生成器
	_stop_current_room_spawner()

	# 计算波次配置
	var enemy_plan: Array[Dictionary] = map_manager.get_current_room_enemy_plan()
	var wave_counts: Array[int] = _calculate_wave_counts_for_enemy_plan(room_data, enemy_plan.size())
	if wave_counts.is_empty():
		wave_counts = _calculate_wave_counts(room_data)

	# 创建波次生成器
	_current_wave_spawner = RoomWaveSpawner.new()
	add_child(_current_wave_spawner)

	# 连接波次信号
	_current_wave_spawner.wave_started.connect(_on_wave_started)
	_current_wave_spawner.all_waves_cleared.connect(_on_all_waves_cleared)
	_current_wave_spawner.wave_progress_updated.connect(_on_wave_progress_updated)

	# 查找当前房间实例（用于获取房间节点引用）
	var current_room_node: Node2D = _get_current_room_instance()

	# 启动生成
	_current_wave_spawner.configure(wave_counts, current_room_node, player, current_floor, room_data.floor_level, self, room_data.size)
	_current_wave_spawner.set_enemy_pool(enemy_plan)
	_current_wave_spawner.start()
	_update_clearing_progress(0, _sum_ints(wave_counts))

func _calculate_wave_counts_for_enemy_plan(room_data: RoomData, enemy_count: int) -> Array[int]:
	if enemy_count <= 0:
		return []
	var wave_count: int = 1
	match room_data.floor_level:
		RoomData.FloorLevel.SHALLOW:
			wave_count = 1
		RoomData.FloorLevel.MEDIUM, RoomData.FloorLevel.DEEP:
			wave_count = 2
		RoomData.FloorLevel.ABYSS:
			wave_count = 3
	wave_count = clamp(wave_count, 1, enemy_count)

	var waves: Array[int] = []
	var remaining: int = enemy_count
	for i in range(wave_count):
		var this_wave: int = int(ceil(float(remaining) / float(wave_count - i)))
		waves.append(this_wave)
		remaining -= this_wave
	return waves

## 计算波次数量配置
func _calculate_wave_counts(room_data: RoomData) -> Array[int]:
	var base_count: int = 2 + current_floor
	var wave_count: int = 1

	match room_data.floor_level:
		RoomData.FloorLevel.SHALLOW:
			wave_count = 1
			base_count = 2 + current_floor
		RoomData.FloorLevel.MEDIUM:
			wave_count = 2
			base_count = 2 + current_floor / 2
		RoomData.FloorLevel.DEEP:
			wave_count = 2
			base_count = 3 + current_floor / 2
		RoomData.FloorLevel.ABYSS:
			wave_count = 3
			base_count = 3 + current_floor / 2

	# 每波敌人数递减：第一波最多，后续减少
	var waves: Array[int] = []
	var remaining: int = base_count * wave_count
	for i in range(wave_count):
		var this_wave: int = remaining / (wave_count - i)
		waves.append(this_wave)
		remaining -= this_wave

	return waves

## 停止当前房间的波次生成器
func _stop_current_room_spawner() -> void:
	if _current_wave_spawner != null and is_instance_valid(_current_wave_spawner):
		_current_wave_spawner.stop()
		_current_wave_spawner.queue_free()
	_current_wave_spawner = null

## 获取当前房间对应的场景实例节点
func _get_current_room_instance() -> Node2D:
	if map_manager == null:
		return self
	var room_id: int = map_manager._current_room_id
	var instance: Node2D = map_manager.get_instantiated_room(room_id)
	if instance != null:
		return instance
	return self  # Fallback

## 波次开始回调
func _on_wave_started(wave: int, total: int) -> void:
	_update_room_info_label("第 %d/%d 波袭来！" % [wave, total])

func _on_wave_progress_updated(killed: int, total: int, wave: int) -> void:
	wave_progress_changed.emit(killed, total, wave)

## 所有波次清理完毕回调
func _on_all_waves_cleared() -> void:
	var room_data: RoomData = map_manager.get_current_room_data()
	if room_data:
		_on_room_cleared(room_data)

## 显示初始命运卡片选择（强制展示：出生房进入时自动弹出，不依赖Tab）
func _show_initial_fate_cards() -> void:
	await get_tree().process_frame

	# 检查局前是否已通过命运占卜屋预选了卡片
	var pending: Dictionary = BaseManager.get_pending_fate_card()
	if not pending.is_empty():
		# 从 pending 数据重建 FateCard 实例并自动应用
		var card := _reconstruct_fate_card_from_dict(pending)
		if card != null:
			var result := FateCardGameBridge.apply_card(card)
			if result.success:
				print("[RoomGameMode] 局前预选卡片已应用: %s" % card.card_name)
			else:
				print("[RoomGameMode] 局前预选卡片应用失败: %s — %s" % [card.card_name, result.message])
		BaseManager.clear_pending_fate_card()
		call_deferred("_enter_first_combat_room")
		return

	# 无预选卡片时，强制在 GameUIManager 面板中展示 3 张初始卡
	_show_fate_cards_in_panel()

## 从局前预选字典重建 FateCard 实例
func _reconstruct_fate_card_from_dict(d: Dictionary) -> FateCard:
	# card_id / card_name / card_type / card_rarity / description / tags / effect / visual
	if d.is_empty() or not d.has("card_name"):
		return null
	var card: FateCard = FateCard.new(str(d.get("card_name", "Unknown")), int(d.get("card_type", 0)), int(d.get("card_rarity", 0)))
	card.card_id = d.get("card_id", "")
	card.description = d.get("description", "")
	if d.has("tags"):
		card.tags = Array(d["tags"], TYPE_STRING, "", [])
	if d.has("effect"):
		card.effect = d["effect"]
	if d.has("visual"):
		card.visual = d["visual"]
	return card

func _enter_first_combat_room() -> void:
	if _start_room_done:
		return
	if map_manager == null or player == null or not is_instance_valid(player):
		return
	var graph: NodeGraph = map_manager.get_graph()
	if graph == null:
		return
	var target_id: int = _find_first_combat_room_id(graph, map_manager._current_room_id)
	if target_id < 0:
		return

	_start_room_done = true
	_stop_current_room_spawner()
	var room_instance: Node2D = map_manager.get_instantiated_room(target_id)
	if room_instance != null:
		player.global_position = room_instance.global_position
	else:
		player.global_position = Vector2.ZERO
	_sync_camera_to_player(true)
	map_manager.enter_room(target_id)

func _find_first_combat_room_id(graph: NodeGraph, start_id: int) -> int:
	var visited: Dictionary = {}
	var queue: Array[int] = []
	if start_id >= 0:
		for n in graph.get_neighbors(start_id):
			queue.append(n)
	# 保底：如果出生点没有邻居，遍历所有节点
	if queue.is_empty():
		for node in graph.get_all_nodes():
			queue.append(node.id)

	while not queue.is_empty():
		var id: int = queue.pop_front()
		if visited.has(id):
			continue
		visited[id] = true
		var node := graph.get_node(id)
		if node == null:
			continue
		var data: RoomData = node.room_data
		# 初次试玩优先普通/精英战斗房；Boss 留给后续流程。
		if data != null and data.is_combat() and data.room_type != RoomData.RoomType.BOSS:
			return id
		for next_id in graph.get_neighbors(id):
			if not visited.has(next_id):
				queue.append(next_id)
	return -1

func _get_fate_card_controller() -> Control:
	if fate_card_ui != null:
		return fate_card_ui
	var existing = get_node_or_null("FateCardUIController")
	if existing:
		fate_card_ui = existing as Control
	return fate_card_ui

## 自动打开商人交易面板（商人房进入时自动触发）
func _auto_open_merchant(room_data: RoomData) -> void:
	# MerchantInteraction.gd 脚本挂载在 RoomMerchant（根节点）而非 MerchantArea
	# 所以要用 RoomMerchant 节点获取 MerchantInteraction，而不是 MerchantArea
	var merchant_node: Node2D = null
	if map_manager != null and map_manager._current_room_id >= 0:
		var room_instance: Node2D = map_manager.get_instantiated_room(map_manager._current_room_id)
		if room_instance != null:
			merchant_node = room_instance as Node2D

	if merchant_node == null:
		push_warning("[RoomGameMode] Cannot auto-open merchant: room instance not found for room %s" % room_data.room_id)
		return

	# 确保 MerchantInteraction 脚本已挂载
	if not merchant_node.has_method("set_inventory"):
		push_warning("[RoomGameMode] RoomMerchant node has no MerchantInteraction script")
		return

	# merchant_node 就是 RoomMerchant 节点（挂载了 MerchantInteraction.gd）
	var merchant_interaction: Node = merchant_node

	# 绑定背包和商品
	merchant_interaction.set_inventory(inventory_module)

	# 确保背包模块已设置（MerchantInteraction 需要这个引用）
	merchant_interaction.set_inventory(inventory_module)

	# 预生成商品（如果没有的话）
	if merchant_interaction._goods.is_empty():
		var loot := LootModule.get_instance()
		if loot != null:
			var goods: Array[Dictionary] = loot.generate_merchant_goods(room_data.floor, 6)
			merchant_interaction.prepare_goods(goods)

	# 获取或创建商人面板并直接展示
	var ui: MerchantUI = merchant_interaction.get_or_create_merchant_ui()
	if ui != null:
		ui.show_merchant(merchant_interaction._goods)
		# 同步商人状态为 ACTIVE，避免离开时状态不一致导致无法正确关闭
		merchant_interaction.force_set_active()
		_update_room_info_label("与 [%s] 交易中..." % merchant_interaction.shop_name)
	else:
		# 降级：控制台打印商品
		merchant_interaction._print_goods_list()
		_update_room_info_label("[%s] 在附近徘徊..." % merchant_interaction.shop_name)

## 获取或创建 GameUIManager 中的命运卡片选择面板
## 复用 GameUIManager.tscn 中已有的 FateCardPanel（Control 节点）
func _get_or_create_fate_card_panel() -> Control:
	if _ui_manager == null:
		return null
	# GameUIManager 的 CanvasLayer 下有 FateCardPanel
	var panel: Control = _ui_manager.get_node_or_null("FateCardPanel")
	if panel == null:
		push_warning("[RoomGameMode] FateCardPanel not found in GameUIManager")
	return panel

## 在 GameUIManager 的 FateCardPanel 中显示 3 张初始命运卡片（强制展示）
func _show_fate_cards_in_panel() -> void:
	var panel: Control = _get_or_create_fate_card_panel()
	if panel == null:
		push_warning("[RoomGameMode] Cannot show fate cards: panel not found")
		# Fallback: 不要默默失败，改为打印提示给玩家
		_update_room_info_label("命运卡片加载失败，自动进入战斗")
		call_deferred("_enter_first_combat_room")
		return

	# 构建卡片容器（从 VBox/CardsContainer 获取，如不存在则创建）
	var cards_container: HBoxContainer = panel.get_node_or_null("VBox/CardsContainer") as HBoxContainer
	if cards_container == null:
		# 动态创建 VBox 容器结构
		var vbox := VBoxContainer.new()
		vbox.name = "VBox"
		vbox.custom_minimum_size = Vector2(600, 220)
		vbox.alignment = VBoxContainer.ALIGNMENT_CENTER
		panel.add_child(vbox)
		cards_container = HBoxContainer.new()
		cards_container.name = "CardsContainer"
		cards_container.custom_minimum_size = Vector2(560, 220)
		cards_container.alignment = HBoxContainer.ALIGNMENT_CENTER
		vbox.add_child(cards_container)

	# 清空旧卡片
	for child in cards_container.get_children():
		child.queue_free()

	# 随机抽取 3 张
	var all_cards: Array[FateCard] = FateCardPresets.all_presets()
	all_cards.shuffle()
	var options: Array[FateCard] = all_cards.slice(0, 3)

	for card in options:
		var btn := _create_fate_card_button(card)
		cards_container.add_child(btn)

	# 显示面板
	panel.visible = true

	# 更新提示标签
	var instruction: Label = panel.get_node_or_null("VBox/InstructionLabel") as Label
	if instruction == null:
		# 动态创建说明标签
		instruction = Label.new()
		instruction.name = "InstructionLabel"
		instruction.text = "选择一张命运卡片（自动应用）"
		instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var vbox_parent: Node = cards_container.get_parent()
		if vbox_parent and vbox_parent.has_node("InstructionLabel"):
			instruction = vbox_parent.get_node("InstructionLabel") as Label
		elif vbox_parent:
			vbox_parent.add_child(instruction)
			var idx: int = cards_container.get_index()
			vbox_parent.move_child(instruction, idx)

	if instruction:
		instruction.text = "选择一张命运卡片（自动应用）"
		instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

## 创建一张命运卡片按钮（用于面板内动态创建）
func _create_fate_card_button(card: FateCard) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(160, 200)

	var rarity_color: Color = FateCard.rarity_color(card.card_rarity)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.10, 0.11, 0.16, 0.97)
	bg_style.set_border_width_all(2)
	bg_style.set_border_color(rarity_color)
	bg_style.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", bg_style)

	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.18, 0.20, 0.28, 0.97)
	hover_style.set_border_width_all(2)
	hover_style.set_border_color(Color(1.0, 0.9, 0.6, 0.9))
	hover_style.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("hover", hover_style)

	var pressed_style := StyleBoxFlat.new()
	pressed_style.bg_color = Color(0.22, 0.24, 0.32, 0.97)
	pressed_style.set_border_width_all(3)
	pressed_style.set_border_color(Color(1.0, 0.8, 0.3, 1.0))
	pressed_style.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("pressed", pressed_style)

	btn.add_theme_color_override("font_color", rarity_color)
	btn.add_theme_font_size_override("font_size", 13)
	btn.tooltip_text = card.description

	# 多行文本按钮标签
	var type_str := FateCard.type_name(card.card_type)
	btn.text = "[%s] %s\n%s\n%s" % [
		FateCard.rarity_name(card.card_rarity),
		card.card_name,
		type_str,
		card.description
	]
	btn.set_meta("fate_card", card)
	btn.pressed.connect(_on_fate_card_button_pressed.bind(card))

	return btn

## 玩家点击了命运卡片按钮
func _on_fate_card_button_pressed(card: FateCard) -> void:
	var result := FateCardGameBridge.apply_card(card)
	if result.success:
		print("[RoomGameMode] 命运卡片应用成功: %s — %s" % [card.card_name, result.message])
	else:
		push_warning("[RoomGameMode] 命运卡片应用失败: %s — %s" % [card.card_name, result.message])

	# 关闭面板
	var panel: Control = _get_or_create_fate_card_panel()
	if panel:
		panel.visible = false

	# 通知玩家，并进入第一间战斗房，避免出生房无怪导致试玩卡住。
	_update_room_info_label("命运卡片 [%s] 已应用，进入战斗！" % card.card_name)
	call_deferred("_enter_first_combat_room")

## 调试/占位操作：在出生房按交互键也可以直接进入战斗，避免 UI 选择异常时卡住。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		var current_data: RoomData = map_manager.get_current_room_data() if map_manager != null else null
		if current_data != null and current_data.room_type == RoomData.RoomType.PLAYER_SPAWN:
			var panel: Control = _get_or_create_fate_card_panel()
			if panel == null or not panel.visible:
				_enter_first_combat_room()

## 每帧检测房间清理状态 & 撤离读条
func _process(delta: float) -> void:
	_sync_camera_to_player(false)
	# 更新撤离读条
	if extraction_module != null and extraction_module.get_status() == ExtractionModule.ExtractionStatus.COUNTDOWN:
		extraction_module.update(delta)

	# 更新波次生成器
	if _current_wave_spawner != null and is_instance_valid(_current_wave_spawner):
		_current_wave_spawner.tick(delta)

	var current_data: RoomData = map_manager.get_current_room_data()
	if current_data == null:
		return

	# 非战斗房间直接标记为已清理
	if not current_data.is_combat():
		if not _room_cleared_flag:
			_room_cleared_flag = true
			room_cleared.emit(current_data)
		return

	# 检测战斗房清理状态（波次生成器优先）
	if _current_wave_spawner != null and is_instance_valid(_current_wave_spawner):
		var info: Dictionary = _current_wave_spawner.get_wave_info()
		var alive: int = info.get("alive", 0)
		var total: int = info.get("total", 0)
		var killed: int = info.get("killed", max(0, total - alive))
		var current_wave: int = info.get("current", 1)
		_update_clearing_progress(killed, total)
		if _current_wave_spawner.is_complete():
			_on_room_cleared(current_data)
		return

	# Fallback: 旧字典追踪方式
	var killed: int = map_manager.get_current_room_killed_count()
	var enemies: Array[Dictionary] = map_manager.get_current_room_enemies()
	var total: int = enemies.size() + killed

	_update_clearing_progress(killed, total)

	if map_manager.is_current_room_cleared():
		_on_room_cleared(current_data)

## 房间清理完成
func _on_room_cleared(room_data: RoomData) -> void:
	# 防止重复触发（波次生成器已处理过）
	if _room_cleared_flag:
		return
	_room_cleared_flag = true

	room_cleared.emit(room_data)

	var reward_text: String = _calculate_room_reward(room_data)
	_update_room_info_label("%s 已清理！%s" % [RoomData.get_type_name(room_data.room_type), reward_text])

	# 解锁通往下一个房间的门
	var graph: NodeGraph = map_manager.get_graph()
	if graph != null:
		var current_id: int = map_manager._current_room_id
		var neighbors: Array = graph.get_neighbors(current_id)
		var path_dir: PathDirector = map_manager.path_director
		for neighbor_id in neighbors:
			path_dir.open_door(current_id, neighbor_id)

	# 检测是否还有下一个房间
	_check_map_completion()

## 计算房间奖励
func _calculate_room_reward(room_data: RoomData) -> String:
	var xp: int = 0
	var credits: int = 0

	match room_data.room_type:
		RoomData.RoomType.COMBAT:
			xp = 10 + room_data.floor * 5
			credits = 10 + room_data.floor * 5
		RoomData.RoomType.ELITE:
			xp = 50 + room_data.floor * 20
			credits = 50 + room_data.floor * 10
		RoomData.RoomType.BOSS:
			xp = 200 + room_data.floor * 50
			credits = 100 * room_data.floor
		RoomData.RoomType.SCAVENGE:
			xp = 5 + room_data.floor * 2
			credits = 20 + room_data.floor * 10
		_:
			xp = 5
			credits = 5

	GameManager.add_currency(credits)
	return "XP +%d | 魂 +%d" % [xp, credits]

## 检测地图是否完成
func _check_map_completion() -> void:
	var graph: NodeGraph = map_manager.get_graph()
	if graph == null:
		return

	var boss_node: NodeGraph.RoomNode = graph.get_deepest_node()
	if boss_node != null and boss_node.room_data.room_type == RoomData.RoomType.BOSS:
		if map_manager._current_room_id == boss_node.id:
			# 当前在Boss房，击败Boss后可进入下一层
			_update_room_info_label("Boss已击败！前往下一层或撤离...")

## 通知怪物死亡（外部调用）
func notify_enemy_killed(enemy_data: Dictionary) -> void:
	score += enemy_data.get("xp_value", 10)
	_kill_count += 1

	# 处理怪物掉落（物品入背包）
	var loot: Array[Dictionary] = LootModule.get_instance().generate_enemy_loot(enemy_data)
	var currency_earned: int = 0
	for item_data in loot:
		if item_data.get("is_currency", false):
			currency_earned += item_data.get("count", 0)
		else:
			# 物品入背包
			if inventory_module != null:
				inventory_module.add_item(item_data, item_data.get("count", 1))

	# 基础击杀奖励 + 额外掉落货币
	var base_reward: int = enemy_data.get("currency_value", 10)
	GameManager.add_currency(base_reward)
	currency_earned += base_reward

	# 显示货币飘字（在世界坐标显示）
	if _ui_manager != null:
		var enemy_pos: Vector2 = enemy_data.get("last_position", Vector2.ZERO)
		_ui_manager.show_currency_popup(currency_earned, enemy_pos)

	# 如果是精英怪，触发精英撤离点解锁
	if enemy_data.get("is_elite", false) and map_manager != null:
		map_manager.extraction_director.unlock_elite_extraction()

	kill_recorded.emit()
	_update_ui()

## 手动前进到下一层
func advance_to_next_floor() -> void:
	var next_graph: NodeGraph = map_manager.advance_to_next_floor()
	current_floor = map_manager.get_current_floor()
	_room_cleared_flag = false

## 获取当前地图管理器
func get_map_manager() -> MapManager:
	return map_manager

## 同步信标数量（从背包读取信标道具数量到 ExtractionDirector）
## 同时绑定背包引用，用于信标消耗时真实扣除
func _sync_beacon_count() -> void:
	if map_manager == null or map_manager.extraction_director == null:
		return
	# bind_inventory 会同时设置引用和同步计数
	map_manager.extraction_director.bind_inventory(inventory_module)

func _on_inventory_changed() -> void:
	_sync_beacon_count()
	_call_ui_manager_method("set_beacon_count", map_manager.extraction_director.get_beacon_count() if map_manager and map_manager.extraction_director else 0)

func _on_insurance_changed() -> void:
	pass

## 获取玩家节点（供 GameUIManager 获取 Player 引用用于消耗品效果）
func get_player() -> Node2D:
	return player
func get_inventory() -> InventoryModule:
	return inventory_module

## 获取保险格模块
func get_insurance() -> InsuranceModule:
	return insurance_module

## 获取撤离模块
func get_extraction_module() -> ExtractionModule:
	return extraction_module

## 开始撤离读条（供UI或信号调用）
func begin_extraction(extraction_type: String, countdown: float = 5.0) -> bool:
	if extraction_module == null:
		return false
	if extraction_module.get_status() != ExtractionModule.ExtractionStatus.IDLE:
		return false
	return extraction_module.start_extraction(extraction_type, countdown)

## HP变化回调
func _on_hp_changed(current: int, maximum: int) -> void:
	if hp_bar:
		hp_bar.max_value = maximum
		hp_bar.value = current

## 货币变化回调
func _on_currency_changed(amount: int) -> void:
	if currency_label:
		currency_label.text = "魂: %d" % amount

## 更新基础UI
func _update_ui() -> void:
	if score_label:
		score_label.text = "Score: %d" % score
	if wave_label:
		wave_label.text = "Floor: %d" % current_floor
	if currency_label:
		currency_label.text = "魂: %d" % GameManager.currency

## 调试：打印游戏状态
func debug_status() -> String:
	var lines: Array[String] = [
		"RoomGameMode Floor %d" % [current_floor],
		"Score: %d | Room cleared: %s" % [score, _room_cleared_flag]
	]

	if map_manager != null:
		lines.append(map_manager.debug_status())

	return "\n".join(lines)
