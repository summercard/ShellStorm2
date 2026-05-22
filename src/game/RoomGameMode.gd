class_name RoomGameMode
## 房间游戏模式 — 将 MapManager 地图系统接入 Godot 游戏主循环
## 替代 Main.gd 中的占位敌人生成逻辑

extends Node2D

signal room_cleared(room_data: RoomData)
signal game_over(reason: String)
signal extraction_ready()

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
@onready var player_spawn_marker: Marker2D = $PlayerSpawn
@onready var ui_layer: CanvasLayer = $UI
@onready var hp_bar: ProgressBar = $UI/HPBar
@onready var score_label: Label = $UI/TopRightPanel/VBox/ScoreLabel
@onready var wave_label: Label = $UI/TopRightPanel/VBox/WaveLabel
@onready var currency_label: Label = $UI/CurrencyLabel
@onready var room_info_label: Label = $UI/RoomInfoLabel
@onready var clearing_progress: ProgressBar = $UI/ClearingProgress

## 状态
var current_floor: int = 1
var score: int = 0
var room_cleared: bool = false

func _ready() -> void:
	_setup_map_manager()
	_setup_extraction_modules()
	_setup_signals()
	_spawn_player()
	_start_game()

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
	
	# 信号连接（用于UI更新等）
	inventory_module.inventory_changed.connect(_on_inventory_changed)
	insurance_module.insurance_changed.connect(_on_insurance_changed)
	extraction_module.extraction_completed.connect(_on_extraction_completed)
	extraction_module.extraction_aborted.connect(_on_extraction_aborted)
	death_settlement_module.death_settlement_processed.connect(_on_death_settlement_processed)

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
	player.global_position = player_spawn_marker.global_position
	add_child(player)

## 开始游戏
func _start_game() -> void:
	# 生成第一层地图
	var graph: NodeGraph = map_manager.generate_map(initial_floor, map_seed)
	
	# 设置 UI
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
		
		# 房间实例化到世界（使用 RoomFactory）
		var factory := RoomFactory.new()
		var room_instance: Node2D = factory.create_room(room_data, self)
		
		# 设置房间在世界中的位置
		room_instance.global_position = room_data.position

## 进入房间
func _on_room_entered(room_data: RoomData) -> void:
	room_cleared = false
	_update_room_info_label("当前: %s [%s]" % [RoomData.get_type_name(room_data.room_type), RoomData.get_level_name(room_data.floor_level)])
	
	# 初始化清理进度条
	var enemies: Array[Dictionary] = map_manager.get_current_room_enemies()
	var total: int = enemies.size()
	_update_clearing_progress(0, total)
	
	# 如果是出生房，显示初始命运卡片
	if room_data.room_type == RoomData.RoomType.PLAYER_SPAWN:
		_show_initial_fate_cards()

## 离开房间
func _on_room_exited(room_id: String) -> void:
	pass

## 楼层切换
func _on_floor_changed(old_floor: int, new_floor: int) -> void:
	current_floor = new_floor
	_update_room_info_label("进入第 %d 层..." % [new_floor])
	room_cleared = true
	
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
	game_over.emit("玩家死亡")

func _print_death_settlement(result: Dictionary) -> void:
	var text: String = death_settlement_module.get_death_summary_text(result)
	print(text)

## 撤离完成回调
func _on_extraction_completed(success: bool, loot: Array[Dictionary]) -> void:
	if success:
		var extracted: int = death_settlement_module.process_extraction_settlement(inventory_module, insurance_module)
		var insurance_items: Array[Dictionary] = insurance_module.get_all_insured_items()
		_print_extraction_success(extracted, insurance_items)
	else:
		_print_extraction_failure()

func _print_extraction_success(extracted_count: int, insurance_items: Array[Dictionary]) -> void:
	var lines: Array[String] = ["=== 撤离成功 ==="]
	lines.append("背包物品已保存: %d 件" % extracted_count)
	if not insurance_items.is_empty():
		lines.append("保险格物品: %d 件" % insurance_items.size())
	print("\n".join(lines))

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

## 显示初始命运卡片选择
func _show_initial_fate_cards() -> void:
	await get_tree().process_frame
	
	var fate_card_ctrl = _get_fate_card_controller()
	if fate_card_ctrl and fate_card_ctrl.has_method("show_card_selection"):
		fate_card_ctrl.show_card_selection()

func _get_fate_card_controller() -> Control:
	if fate_card_ui != null:
		return fate_card_ui
	var existing = get_node_or_null("FateCardUIController")
	if existing:
		fate_card_ui = existing as Control
	return fate_card_ui

## 每帧检测房间清理状态 & 撤离读条
func _process(delta: float) -> void:
	# 更新撤离读条
	if extraction_module != null and extraction_module.get_status() == ExtractionModule.ExtractionStatus.COUNTDOWN:
		extraction_module.update(delta)
	
	var current_data: RoomData = map_manager.get_current_room_data()
	if current_data == null:
		return
	
	# 非战斗房间直接标记为已清理
	if not current_data.is_combat():
		room_cleared = true
		room_cleared.emit(current_data)
		return
	
	# 检测战斗房清理状态
	var killed: int = map_manager.get_current_room_killed_count()
	var enemies: Array[Dictionary] = map_manager.get_current_room_enemies()
	var total: int = enemies.size() + killed
	
	_update_clearing_progress(killed, total)
	
	if map_manager.is_current_room_cleared():
		room_cleared = true
		_on_room_cleared(current_data)

## 房间清理完成
func _on_room_cleared(room_data: RoomData) -> void:
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
	
	var boss_node: RoomNode = graph.get_deepest_node()
	if boss_node != null and boss_node.room_data.room_type == RoomData.RoomType.BOSS:
		if map_manager._current_room_id == boss_node.id:
			# 当前在Boss房，击败Boss后可进入下一层
			_update_room_info_label("Boss已击败！前往下一层或撤离...")

## 通知怪物死亡（外部调用）
func notify_enemy_killed(enemy_data: Dictionary) -> void:
	score += enemy_data.get("xp_value", 10)
	GameManager.add_currency(10)
	_update_ui()

## 手动前进到下一层
func advance_to_next_floor() -> void:
	var next_graph: NodeGraph = map_manager.advance_to_next_floor()
	current_floor = map_manager.get_current_floor()
	room_cleared = false

## 获取当前地图管理器
func get_map_manager() -> MapManager:
	return map_manager

## 获取背包模块
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
		"Score: %d | Room cleared: %s" % [score, room_cleared]
	]
	
	if map_manager != null:
		lines.append(map_manager.debug_status())
	
	return "\n".join(lines)