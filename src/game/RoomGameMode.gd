class_name RoomGameMode
## 房间游戏模式 — 将 MapManager 地图系统接入 Godot 游戏主循环
## 替代 Main.gd 中的占位敌人生成逻辑

extends Node2D

signal room_cleared(room_data: RoomData)
signal room_entered(room_data: RoomData)
signal game_over(reason: String)
signal extraction_ready
signal kill_recorded
signal wave_progress_changed(killed: int, total: int, wave: int)

const ROOM_KEY_PICKUP_SCRIPT := preload("res://src/game/RoomKeyPickup.gd")
const ROOM_DOOR_INTERACTION_SCRIPT := preload("res://src/game/RoomDoorInteraction.gd")
const ROOM_LAYOUT_SCRIPT := preload("res://src/map/RoomLayout.gd")
const SOUL_ORB_SCENE: PackedScene = preload("res://scenes/SoulOrb.tscn")
const GROUND_ITEM_PICKUP_SCRIPT := preload("res://src/items/GroundItemPickup.gd")
const VISION_SYSTEM_SCRIPT := preload("res://src/game/VisionSystem.gd")
const ROOM_LIGHTING_SCRIPT := preload("res://src/fx/RoomLightingSystem.gd")
const ELITE_ARCHIVE_MODULE_SCRIPT := preload("res://src/enemy/EliteArchiveModule.gd")
const ELITE_SPAWN_DIRECTOR_SCRIPT := preload("res://src/enemy/EliteSpawnDirector.gd")
const EXTRACTION_DEFENSE_DURATION := 14.0

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

## 视野系统
var vision_system: Variant = VISION_SYSTEM_SCRIPT.new()

## 迷雾层引用（用于向 FogOfWarLayer 推送墙体几何）
@onready var fog_layer: Node = get_node_or_null("../FogOfWarLayer")

## 精英怪档案（PH06 精英成长链路）
var _elite_archive: Node = null

## 事件房处理器
var _current_event_handler: Node = null

## UI 引用
@onready var player_spawn_marker: Marker2D = get_node_or_null("PlayerSpawn") as Marker2D
@onready var ui_layer: CanvasLayer = get_node_or_null("../GameUIManager") as CanvasLayer
@onready
var hp_bar: ProgressBar = get_node_or_null("../GameUIManager/GameHUD/HPBarBG/HPBar") as ProgressBar
@onready var score_label: Label = (
	get_node_or_null("../GameUIManager/GameHUD/TopRightPanel/VBox/ScoreLabel") as Label
)
@onready var wave_label: Label = (
	get_node_or_null("../GameUIManager/GameHUD/TopRightPanel/VBox/WaveLabel") as Label
)
@onready
var currency_label: Label = get_node_or_null("../GameUIManager/GameHUD/CurrencyLabel") as Label
@onready
var room_info_label: Label = get_node_or_null("../GameUIManager/GameHUD/RoomInfoLabel") as Label
@onready var clearing_progress: ProgressBar = (
	get_node_or_null("../GameUIManager/GameHUD/ClearingProgress") as ProgressBar
)
@onready var game_camera: Camera2D = get_node_or_null("../Camera2D") as Camera2D
@onready var _screen_shake: Node = get_node_or_null("../Camera2D/ScreenShake")

## UI 管理器引用（用于飘字等效果）
var _ui_manager: Node = null
var _wave_indicator_label: Label = null
## 音频管理器引用
var _audio: Node = null

## 状态
var current_floor: int = 1
var score: int = 0
var _room_cleared_flag: bool = false
var _kill_count: int = 0
var _start_room_done: bool = false
var _room_key_count: int = 0
var _inventory_room_key_snapshot: int = 0
var _cleared_room_ids: Dictionary = {}
var _spawned_key_room_ids: Dictionary = {}
var _revealed_room_ids: Dictionary = {}
var _fate_card_choice_committed: bool = false
var _door_fate_selection_active: bool = false
var _reserved_door_fate_card: FateCard = null
var _extraction_defense_active := false
var _extraction_mid_wave_spawned := false
var _extraction_elite_wave_spawned := false
## 风险等级（已清理房间数，每清1间+1，用于敌人压力缩放）
var _run_risk: int = 0

## 波次生成器（当前房间）
var _current_wave_spawner: RoomWaveSpawner = null
## 区域刷怪控制器（当前房间）
var _current_regional_controller: RegionalSpawnController = null
## 精英怪出现调度器（PH06）
var _elite_spawn_director: Node
## 当前房间已击杀精英的 elite_id 列表（用于识别要删除的记录）
var _killed_elite_ids_this_room: Array[String] = []
## 当前房间遭遇的所有精英 elite_id（用于遭遇结果记录）
var _encountered_elite_ids_this_room: Array[String] = []


func _ready() -> void:
	add_to_group("room_game_mode")
	_setup_map_manager()
	_setup_extraction_modules()
	_setup_elite_archive()
	_setup_signals()
	_setup_map_fate_triggers()
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
	# 初始化音频管理器引用（延迟查找，确保 AudioManager 已就绪）
	_audio = get_tree().root.find_child("AudioManager", true, false)


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


func _get_base_manager() -> BaseManager:
	return get_node_or_null("/root/BaseManager") as BaseManager


## 初始化地图管理器
func _setup_map_manager() -> void:
	map_manager = MapManager.new()
	add_child(map_manager)
	# 注入 RoomGameMode 引用，使 ExtractionDirector 能通过回调查询精英/Boss击杀状态
	map_manager.extraction_director.bind_room_game_mode(self)

	map_manager.map_generated.connect(_on_map_generated)
	map_manager.room_entered.connect(_on_room_entered)
	map_manager.room_exited.connect(_on_room_exited)
	map_manager.floor_changed.connect(_on_floor_changed)
	map_manager.all_rooms_cleared.connect(_on_all_rooms_cleared)
	# PH11 P1: REVEAL事件 -> 小地图刷新（RoomEventHandler -> MapManager -> 此处 -> GameUIManager）
	if map_manager.has_signal("adjacent_rooms_revealed"):
		map_manager.adjacent_rooms_revealed.connect(_on_adjacent_rooms_revealed)
	# Boss 事件穿透信号订阅（Boss 刷新 → UI 更新）
	map_manager.boss_spawned.connect(_on_boss_spawned)
	map_manager.boss_damaged.connect(_on_boss_damaged)
	map_manager.boss_phase_changed.connect(_on_boss_phase_changed)
	map_manager.boss_defeated.connect(_on_boss_defeated)


## 初始化搜打撤模块
func _setup_extraction_modules() -> void:
	inventory_module = InventoryModule.new(12)  # 12格背包
	insurance_module = InsuranceModule.new(2)  # 2格保险格
	extraction_module = ExtractionModule.new()
	death_settlement_module = DeathSettlementModule.new()
	_apply_pending_loadout()
	_inventory_room_key_snapshot = inventory_module.get_item_count("item_room_key")

	## 信号连接（用于UI更新等）
	inventory_module.inventory_changed.connect(_on_inventory_changed)
	inventory_module.inventory_changed.connect(_sync_beacon_count)  # 背包变化时同步信标数量
	insurance_module.insurance_changed.connect(_on_insurance_changed)
	extraction_module.extraction_completed.connect(_on_extraction_completed)
	extraction_module.extraction_aborted.connect(_on_extraction_aborted)
	death_settlement_module.death_settlement_processed.connect(_on_death_settlement_processed)


## 初始化精英怪档案模块（PH06 精英成长链路）
func _setup_elite_archive() -> void:
	_elite_archive = ELITE_ARCHIVE_MODULE_SCRIPT.new()
	add_child(_elite_archive)
	_elite_spawn_director = ELITE_SPAWN_DIRECTOR_SCRIPT.new()
	add_child(_elite_spawn_director)
	print("[RoomGameMode] EliteArchiveModule 已初始化（当前存档: %d 精英）" % _elite_archive.get_total_count())


func _on_elite_spawn_recorded(elite_id: String) -> void:
	# PH06: 精英生成时记录遭遇结果（玩家撤离/死亡时统一结算）
	if not elite_id.is_empty() and elite_id not in _encountered_elite_ids_this_room:
		_encountered_elite_ids_this_room.append(elite_id)
		print("[RoomGameMode] 精英遭遇已记录: %s" % elite_id)


## PH06: 成功撤离时结算精英逃脱成长（对所有本局遭遇但未击杀的精英）
func _resolve_elite_encounters_for_extraction() -> void:
	if _elite_archive == null or _encountered_elite_ids_this_room.is_empty():
		return
	# 排除已击杀的（_killed_elite_ids_this_room 中的已经在 kill_elite 时处理过了）
	var escaped_ids: Array[String] = []
	for eid in _encountered_elite_ids_this_room:
		if eid not in _killed_elite_ids_this_room:
			escaped_ids.append(eid)
	if escaped_ids.is_empty():
		return
	var growth_data: Dictionary = {"hp_gain": 0.05, "damage_gain": 0.0, "speed_gain": 0.03, "level_up": 0}
	for eid in escaped_ids:
		_elite_archive.on_encounter_result(eid, "PlayerExtracted", growth_data.duplicate(true))
		print("[RoomGameMode] 精英逃脱成长已结算: %s" % eid)


## PH06: 玩家死亡时结算精英击杀玩家成长（精英获得"击杀玩家"标记并变强）
func _resolve_elite_encounters_for_death() -> void:
	if _elite_archive == null or _encountered_elite_ids_this_room.is_empty():
		return
	# 排除已击杀的（它们已经在 kill_elite 时处理过了）
	var survivor_ids: Array[String] = []
	for eid in _encountered_elite_ids_this_room:
		if eid not in _killed_elite_ids_this_room:
			survivor_ids.append(eid)
	if survivor_ids.is_empty():
		return
	var growth_data: Dictionary = {"hp_gain": 0.15, "damage_gain": 0.20, "speed_gain": 0.05, "level_up": 1}
	for eid in survivor_ids:
		_elite_archive.on_encounter_result(eid, "PlayerDied", growth_data.duplicate(true))
		print("[RoomGameMode] 精英击杀玩家成长已结算: %s" % eid)


func _apply_pending_loadout() -> void:
	var bm: BaseManager = _get_base_manager()
	if bm == null or inventory_module == null:
		return
	var loadout_items: Array[Dictionary] = []
	var raw_loadout: Array = bm.consume_pending_loadout()
	for item in raw_loadout:
		if item is Dictionary:
			loadout_items.append((item as Dictionary).duplicate(true))
	for item in loadout_items:
		var count: int = item.get("count", 1)
		var added: int = inventory_module.add_item(item, count)
		if added < count:
			item["count"] = count - added
			bm.add_vault_item(item)


## 连接信号
func _setup_signals() -> void:
	Global.start_game()
	Global.game_over.connect(_on_global_game_over)

	GameManager.hp_changed.connect(_on_hp_changed)
	GameManager.currency_changed.connect(_on_currency_changed)


## 设置开箱后命运触发回调（连接 ContainerInteraction -> MapFateTriggers）
## 在容器开启时触发环境命运计数（开箱×N）
func _setup_container_fate_bridge() -> void:
	var triggers: Node = get_node_or_null("MapFateTriggers")
	if triggers == null:
		return
	var room_node: Node = _get_current_room_instance()
	if room_node == null:
		return
	var connected := 0
	for ct in _get_container_interactions(room_node):
		var callable := Callable(self, "_on_container_opened_for_fate")
		if ct.has_signal("container_opened") and not ct.container_opened.is_connected(callable):
			ct.container_opened.connect(callable)
			connected += 1
	if connected > 0:
		print("[RoomGameMode] Container -> FateTriggers 桥接已建立: %d" % connected)


func _get_container_interactions(root: Node) -> Array[ContainerInteraction]:
	var result: Array[ContainerInteraction] = []
	if root == null:
		return result
	if root is ContainerInteraction:
		result.append(root as ContainerInteraction)
	for child in root.get_children():
		result.append_array(_get_container_interactions(child))
	return result


func _on_container_opened_for_fate(_loot: Array = []) -> void:
	var triggers: Node = get_node_or_null("MapFateTriggers")
	if triggers != null and triggers.has_method("on_container_opened"):
		triggers.call("on_container_opened")
	call_deferred("_refresh_current_room_vision_occlusion")


## 初始化地图环境命运触发器
func _setup_map_fate_triggers() -> void:
	var triggers := MapFateTriggers.new()
	add_child(triggers)
	triggers.name = "MapFateTriggers"
	print("[RoomGameMode] MapFateTriggers 已初始化")
	# 连接触发器激活信号，触发时通过 FateCardEngine 执行命运卡片效果
	if triggers.trigger_activated.connect(_on_map_fate_trigger_activated) == OK:
		print("[RoomGameMode] MapFateTriggers trigger_activated 信号已连接")
	# 延迟建立容器桥接（等 ContainerInteraction 完全挂载）
	call_deferred("_setup_container_fate_bridge")


## 环境命运触发器激活回调 — 将触发转换为实际命运卡片效果
func _on_map_fate_trigger_activated(
	trigger_type: String, threshold: int, fate_card_id: String, effect_preview: String
) -> void:
	print("[RoomGameMode] 环境命运触发器激活: %s x%d -> %s" % [trigger_type, threshold, fate_card_id])
	# 通过 FateCardEngine 查找并执行对应的命运卡片
	var card: FateCard = FateCardPresets.get_by_card_id(fate_card_id)
	if card == null:
		push_warning("[RoomGameMode] 未找到命运卡片: %s" % fate_card_id)
		return
	# 应用卡片（静态方法，自动从场景树查找玩家武器树）
	var apply_result: FateCardEngine.ApplyResult = FateCardEngine.apply_card_to_player(card)
	if apply_result.success:
		print("[RoomGameMode] 命运卡片应用成功: %s — %s" % [card.card_name, apply_result.message])
		# 向 UI 发送成功通知
		if _ui_manager != null and _ui_manager.has_method("show_fate_card_notification"):
			_ui_manager.show_fate_card_notification("命运效果: %s" % effect_preview)
	else:
		push_warning("[RoomGameMode] 命运卡片应用失败: %s — %s" % [card.card_name, apply_result.message])


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
	# 同步玩家引用到 MapManager（小地图绘制用）
	if map_manager and map_manager.has_method("set_player"):
		map_manager.set_player(player)
	# 连接击杀信号 → 驱动 crit_on_kill 堆栈（每击杀一次，下一颗子弹必定暴击）
	if kill_recorded.is_connected(_on_kill_for_crit_on_kill) == false:
		kill_recorded.connect(_on_kill_for_crit_on_kill)
	# 订阅 crit_stacks_changed 信号，暴击堆栈变化时更新 HUD
	if player != null and player.has_method("get_weapon_tree"):
		var wt: Node = player.call("get_weapon_tree")
		if wt != null and wt.has_signal("crit_stacks_changed"):
			if not wt.crit_stacks_changed.is_connected(_on_crit_stacks_changed):
				wt.crit_stacks_changed.connect(_on_crit_stacks_changed)


## 开始游戏
func _start_game() -> void:
	# 生成第一层地图
	map_manager.generate_map(initial_floor, map_seed)
	_room_key_count = 1 + _inventory_room_key_snapshot
	_cleared_room_ids[0] = true
	_set_room_revealed(0, true)
	_place_player_in_room(0, Vector2.ZERO)
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

		# 房间实例化到世界（使用 RoomFactory，传入背包引用）
		var factory := RoomFactory.new()
		var room_instance: Node2D = factory.create_room(room_data, self, inventory_module)

		# 设置房间在世界中的位置
		room_instance.global_position = room_node.position
		room_instance.visible = false
		map_manager.register_instantiated_room(room_node.id, room_instance)
		_ensure_room_layout(room_instance, room_node.id, room_data)


func _sum_ints(values: Array[int]) -> int:
	var total := 0
	for value in values:
		total += value
	return total


## 进入房间
func _on_room_entered(room_data: RoomData) -> void:
	room_entered.emit(room_data)
	var current_id: int = map_manager.get_current_room_id() if map_manager != null else -1
	_room_cleared_flag = _cleared_room_ids.has(current_id)
	# PH06: 进入新房间时清空本局精英遭遇记录（每房间独立结算）
	_encountered_elite_ids_this_room.clear()
	_killed_elite_ids_this_room.clear()
	_update_room_info_label(
		(
			"当前: %s [%s]"
			% [
				RoomData.get_type_name(room_data.room_type),
				RoomData.get_level_name(room_data.floor_level)
			]
		)
	)
	_refresh_room_doors_for_state()
	_setup_container_fate_bridge()

	# 构建房间视野遮挡几何（供 VisionSystem 使用）
	_build_vision_occlusion_for_room()
	call_deferred("_refresh_current_room_vision_occlusion")

	# 通知 GameUIManager 更新敌人可见性
	_update_enemy_visibility()

	if room_data.room_type == RoomData.RoomType.PLAYER_SPAWN:
		_update_room_info_label("初始房间：你有 1 把钥匙。开门时会触发命运卡牌。")
		_update_clearing_progress(0, 1)
		return

	if room_data.room_type == RoomData.RoomType.EXTRACTION:
		_activate_extraction_room(room_data)
		return

	if room_data.room_type == RoomData.RoomType.BOSS:
		var boss_room := _get_current_room_instance()
		var demo_boss: Node = boss_room.get_node_or_null("DemoBoss") if boss_room != null else null
		if demo_boss != null and demo_boss.has_method("activate"):
			demo_boss.call("activate")

	if _room_cleared_flag:
		_update_clearing_progress(1, 1)
		_update_room_info_label(
			"%s 已清理，选择门继续探索。钥匙 %d" % [RoomData.get_type_name(room_data.room_type), _room_key_count]
		)
		return

	# 商人房：自动弹出交易面板（进入即触发，无需按E）
	if room_data.room_type == RoomData.RoomType.MERCHANT:
		_update_clearing_progress(0, 1)
		_auto_open_merchant(room_data)
		return

	# 改造房：自动弹出武器改造面板（进入即触发，无需按E）
	if room_data.room_type == RoomData.RoomType.UPGRADE:
		_update_clearing_progress(0, 1)
		_auto_open_workbench(room_data)
		return

	# 事件房：激活随机事件处理器
	if room_data.room_type == RoomData.RoomType.EVENT:
		_update_clearing_progress(0, 1)
		_activate_event_room(room_data)
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


## PH11 P1: REVEAL事件触发后刷新小地图
func _on_adjacent_rooms_revealed(room_id: String, revealed_count: int) -> void:
	print("[RoomGameMode] REVEAL事件: 揭示 %d 个相邻房间 from room %s" % [revealed_count, room_id])
	# 通知 GameUIManager 小地图需要重建节点（读取 MapManager 中已更新的 revealed 元数据）
	if _ui_manager != null and _ui_manager.has_method("refresh_minimap"):
		_ui_manager.refresh_minimap()


## 全局游戏结束
func _on_global_game_over() -> void:
	_extraction_defense_active = false
	if extraction_module != null:
		extraction_module.abort_extraction()
	_stop_current_room_spawner()
	# PH06: 玩家死亡时结算所有遭遇精英的击杀玩家成长（精英吃掉玩家）
	_resolve_elite_encounters_for_death()
	# 触发死亡结算
	if death_settlement_module != null and inventory_module != null:
		var settlement_result: Dictionary = death_settlement_module.process_death_settlement(
			inventory_module, insurance_module
		)
		_print_death_settlement(settlement_result)
	# 记录基地数据（死亡）
	var base_manager: BaseManager = _get_base_manager()
	if base_manager != null:
		base_manager.record_run(false, _get_kill_count())
	game_over.emit("玩家死亡")


func _print_death_settlement(result: Dictionary) -> void:
	var text: String = death_settlement_module.get_death_summary_text(result)
	print(text)


## 撤离完成后赋予玩家应得的 extraction_points
## extraction_points 是局后持久化资源，用于在 Workshop 解锁蓝图
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
		var bm: BaseManager = _get_base_manager()
		if bm != null:
			bm.add_extraction_points(total_points)
		print(
			(
				"[RoomGameMode] Granted extraction_points: %d (floor bonus=%d, loot bonus=%d)"
				% [total_points, floor_bonus, loot_bonus]
			)
		)


## 撤离完成回调
func _on_extraction_completed(success: bool, loot: Array[Dictionary]) -> void:
	var defense_wave_info: Dictionary = {}
	if _current_wave_spawner != null and is_instance_valid(_current_wave_spawner):
		defense_wave_info = _current_wave_spawner.get_wave_info()
	_extraction_defense_active = false
	_stop_current_room_spawner()
	# 如果是交易撤离，需要通知 ExtractionDirector 做最终结算
	var ext_type: String = extraction_module.get_extraction_type() if extraction_module else ""
	if ext_type == "TRADE" and map_manager != null and map_manager.extraction_director != null:
		map_manager.extraction_director.try_use_trade_extraction(
			success, GameManager.currency, current_floor
		)

	if success:
		_set_player_input_locked(true)
		_clear_extraction_room_attackers()
		# PH06: 成功撤离时结算所有遭遇精英的逃脱成长
		_resolve_elite_encounters_for_extraction()
		var extracted: int = death_settlement_module.process_extraction_settlement(
			inventory_module, insurance_module
		)
		var insurance_items: Array[Dictionary] = insurance_module.get_all_insured_items()
		_grant_extraction_points()
		var saved_to_vault: int = _persist_extracted_items_to_vault()
		_print_extraction_success(extracted, insurance_items)
		print("[RoomGameMode] Saved extracted items to vault: %d" % saved_to_vault)
		# 播放撤离成功音效
		if _audio and _audio.has_method("play_sfx"):
			_audio.call("play_sfx", "extraction_done")
		_sync_beacon_count()
		# 记录成功撤离到基地
		var bm: BaseManager = _get_base_manager()
		if bm != null:
			bm.record_run(true, _kill_count)
		# 显示撤离成功面板（HUD + 战局统计）
		if ui_layer != null and ui_layer.has_method("show_run_extraction_success"):
			ui_layer.call(
				"show_run_extraction_success",
				{
					"wave": defense_wave_info.get("current", 1),
					"kills": _kill_count,
					"currency": GameManager.currency,
					"score": score,
					"risk": _run_risk,
					"floor": current_floor
				}
			)
	else:
		_print_extraction_failure()


func _clear_extraction_room_attackers() -> void:
	var room_instance := _get_current_room_instance()
	if room_instance == null:
		return
	for child in room_instance.get_children():
		if child.is_in_group("enemy"):
			child.queue_free()


func _get_kill_count() -> int:
	return _kill_count


## 构建当前房间的视野遮挡几何
func _build_vision_occlusion_for_room() -> void:
	vision_system.reset()

	var room_node: Node2D = _get_current_room_instance()
	if room_node == null or map_manager == null:
		return

	# 获取当前房间尺寸
	var room_data: RoomData = map_manager.get_current_room_data()
	var room_size: Vector2 = Vector2(960, 768)  # 默认值
	if room_data != null:
		room_size = room_data.size

	var room_bounds: Rect2 = Rect2(room_node.global_position - room_size * 0.5, room_size)

	# RoomLayout 和明确放置的遮挡组件是唯一可信的阻光来源。
	# FloorLayer 只负责表现；把地砖当墙会让开门后仍残留不可见的封口。
	var wall_rects: Array[Rect2] = []
	# 统一收集实际遮挡体（运行时外墙及有遮挡组件的实体）。
	_append_occluder_rects(room_node, wall_rects)

	vision_system.build_room_occlusion(room_bounds, wall_rects)
	var lighting: Node = room_node.get_node_or_null("RoomLightingSystem")
	if lighting != null and lighting.has_method("get_visibility_light_sources"):
		vision_system.set_static_light_sources(lighting.call("get_visibility_light_sources"))

	# 同步墙体检疫到 FogOfWarLayer（迷雾系统需要同一套几何）
	if fog_layer != null and fog_layer.has_method("set_wall_rects"):
		fog_layer.set_wall_rects(wall_rects)

	# 立即更新一次可见性（初始状态）
	call_deferred("_do_update_enemy_visibility")


func _refresh_current_room_vision_occlusion() -> void:
	if map_manager != null and map_manager.get_current_room_id() >= 0:
		_build_vision_occlusion_for_room()


func _append_occluder_rects(root: Node, rects: Array[Rect2]) -> void:
	for child in root.get_children():
		if child.is_queued_for_deletion():
			continue
		if child is LightOccluder2D:
			var rect := _get_occluder_world_rect(child as LightOccluder2D)
			if rect.size.x > 0.0 and rect.size.y > 0.0 and not _contains_matching_rect(rects, rect):
				rects.append(rect)
		_append_occluder_rects(child, rects)


func _get_occluder_world_rect(occluder: LightOccluder2D) -> Rect2:
	var polygon: OccluderPolygon2D = occluder.occluder as OccluderPolygon2D
	if polygon == null or polygon.polygon.size() < 2:
		return Rect2()
	var first := occluder.to_global(polygon.polygon[0])
	var bounds := Rect2(first, Vector2.ZERO)
	for point in polygon.polygon:
		bounds = bounds.expand(occluder.to_global(point))
	return bounds


func _contains_matching_rect(rects: Array[Rect2], candidate: Rect2) -> bool:
	for existing in rects:
		if (
			existing.position.distance_to(candidate.position) < 2.0
			and existing.size.distance_to(candidate.size) < 2.0
		):
			return true
	return false


## 每帧更新敌人可见性（在 _process 中调用）
func _update_enemy_visibility() -> void:
	# 延迟到下一帧执行（等待 vision_system 就绪）
	call_deferred("_do_update_enemy_visibility")


func _do_update_enemy_visibility() -> void:
	if player == null or not is_instance_valid(player):
		return

	if player.has_method("get_aim_direction"):
		vision_system.set_view_direction(player.call("get_aim_direction") as Vector2)
	var player_light := player.get_node_or_null("PlayerVisionLight")
	if player_light != null and player_light.has_method("get_visibility_descriptor"):
		vision_system.set_player_light_source(player_light.call("get_visibility_descriptor"))

	var enemies: Array[Node] = []
	# 收集当前活跃敌人
	if _current_wave_spawner != null and is_instance_valid(_current_wave_spawner):
		var active: Array[CharacterBody2D] = _current_wave_spawner.get_active_enemies()
		if not active.is_empty():
			enemies.append_array(active)
	if _current_regional_controller != null and is_instance_valid(_current_regional_controller):
		var reg_enemies = _current_regional_controller.get_active_enemies()
		if not reg_enemies.is_empty():
			enemies.append_array(reg_enemies)

	for enemy in enemies:
		if enemy == null or not is_instance_valid(enemy):
			continue
		# 判断敌人是否在视野内（射线检测）
		var enemy_pos: Vector2 = enemy.global_position
		var visible: bool = vision_system.is_point_visible(player.global_position, enemy_pos)

		# 未被照亮或被墙挡住的敌人不可观察，不能留下轮廓提示。
		if enemy is CanvasItem:
			var canvas_enemy: CanvasItem = enemy as CanvasItem
			canvas_enemy.visible = visible
			canvas_enemy.modulate.a = 1.0


func _print_extraction_success(extracted_count: int, insurance_items: Array[Dictionary]) -> void:
	var lines: Array[String] = ["=== 撤离成功 ==="]
	lines.append("背包物品已保存: %d 件" % extracted_count)
	if not insurance_items.is_empty():
		lines.append("保险格物品: %d 件" % insurance_items.size())
	print("\n".join(lines))


func _persist_extracted_items_to_vault() -> int:
	var bm: BaseManager = _get_base_manager()
	if bm == null:
		return 0
	var saved := 0
	var overflow := 0
	if inventory_module != null:
		for slot in inventory_module.get_occupied_slots():
			var item: Dictionary = slot.get("item", {}).duplicate(true)
			if item.is_empty():
				continue
			item["count"] = slot.get("count", 1)
			if bm.add_vault_item(item):
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
			if bm.add_vault_item(item):
				saved += 1
			else:
				overflow += 1
		insurance_module.clear_all()
	if overflow > 0:
		bm.add_extraction_points(overflow * 5)
		print(
			"[RoomGameMode] Vault full, converted %d overflow items to extraction_points" % overflow
		)
	return saved


func _print_extraction_failure() -> void:
	print("=== 撤离失败 ===")
	print("撤离未成功，物资可能丢失。")


## 商人关闭事件 -> 解锁交易撤离
## 当玩家与商人完成首次交易并关闭商人面板时，解锁交易撤离点
func _on_merchant_closed() -> void:
	if map_manager != null and map_manager.extraction_director != null:
		map_manager.extraction_director.unlock_trade_extraction()
		print("[RoomGameMode] 商人大厅关闭 -> 解锁交易撤离")


## 事件房：激活随机事件处理器
func _activate_event_room(room_data: RoomData) -> void:
	# 清理旧的事件处理器
	if _current_event_handler != null:
		_current_event_handler.cleanup()
		_current_event_handler.queue_free()
		_current_event_handler = null

	# 创建新的事件处理器
	var event_handler_script: GDScript = preload("res://src/game/RoomEventHandler.gd") as GDScript
	var event_handler := Node2D.new()
	event_handler.set_script(event_handler_script)
	event_handler.name = "RoomEventHandler"
	add_child(event_handler)
	_current_event_handler = event_handler

	# 设置玩家和房间数据
	if player != null and player.has_method("get_weapon_tree"):
		event_handler.setup(player, room_data)
	else:
		event_handler.setup(self, room_data)

	# 激活事件
	var activated: bool = event_handler.activate()
	if activated:
		_update_room_info_label(
			"事件: %s" % event_handler.get_current_event().get("event_name", "未知")
		)
		print(
			"[RoomGameMode] 事件房已激活: %s" % event_handler.get_current_event().get("event_name", "未知")
		)
	else:
		_update_room_info_label("事件房: 无可用事件")
		print("[RoomGameMode] 事件房激活失败: %s" % room_data.room_id)


func _activate_extraction_room(room_data: RoomData) -> void:
	_stop_current_room_spawner()
	_extraction_defense_active = false
	var current_id: int = map_manager.get_current_room_id() if map_manager != null else -1
	if current_id >= 0:
		_cleared_room_ids[current_id] = true
	_room_cleared_flag = true
	_update_clearing_progress(0, 1)
	_update_room_info_label("撤离房：接近中央装置，按 E 启动撤离信号。")
	var room_instance := _get_current_room_instance()
	if room_instance != null and room_instance.has_method("arm_switch"):
		room_instance.call("arm_switch", self)


## 改造房：自动弹出武器改造面板（进入即触发）
func _auto_open_workbench(room_data: RoomData) -> void:
	# 查找工作台节点（由 RoomFactory 在 UPGRADE 房间创建）
	var room_instance: Node = get_tree().get_root().get_node_or_null("RoomInstance")
	if room_instance == null:
		room_instance = get_node_or_null("..")
	var workbench_node: Node = null
	if room_instance != null:
		workbench_node = room_instance.find_child("Workbench", true, false)
	if workbench_node == null:
		# 尝试全局查找
		workbench_node = get_node_or_null("/root/Workbench")
	if workbench_node == null and room_instance != null:
		workbench_node = room_instance.find_child("Workbench", true, false)

	if workbench_node == null or not workbench_node.has_method("set_inventory"):
		push_warning(
			(
				"[RoomGameMode] Cannot auto-open workbench: workbench node not found or missing script in room %s"
				% room_data.room_id
			)
		)
		_update_room_info_label("工作台未就绪...")
		return

	# 绑定背包
	if workbench_node.has_method("set_inventory"):
		workbench_node.set_inventory(inventory_module)

	# 打开工作台（模拟按下 interact）
	if workbench_node.has_method("_open_workbench"):
		workbench_node._open_workbench()
		_update_room_info_label("武器改造台已打开...")
		print("[RoomGameMode] 工作台自动打开 for room %s" % room_data.room_id)
	else:
		_update_room_info_label("[工作台] 在附近徘徊...")


## 撤离中断回调
func _on_extraction_aborted() -> void:
	_extraction_defense_active = false
	_stop_current_room_spawner()
	var room_instance := _get_current_room_instance()
	if room_instance != null and room_instance.has_method("reset_switch"):
		room_instance.call("reset_switch")
	_update_room_info_label("撤离已中断！")
	print("撤离读条被中断。")
	# 播放撤离中断音效
	if _audio and _audio.has_method("play_sfx"):
		_audio.call("play_sfx", "extraction_abort")


## 死亡结算处理完毕回调
func _on_death_settlement_processed(
	dropped: Array[Dictionary], insurance_saved: Array[Dictionary]
) -> void:
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
	var wave_counts: Array[int] = _calculate_wave_counts_for_enemy_plan(
		room_data, enemy_plan.size()
	)
	if wave_counts.is_empty():
		wave_counts = _calculate_wave_counts(room_data)

	# 创建波次生成器
	_current_wave_spawner = RoomWaveSpawner.new()
	add_child(_current_wave_spawner)

	# 创建区域刷怪控制器（PH11 P1: 房间级刷怪管理 + 区域增援）
	_setup_regional_spawn_controller(room_data)

	# 将区域控制器注入波次生成器（敌人CHASE -> 触发增援）
	if _current_regional_controller != null and is_instance_valid(_current_regional_controller):
		_current_wave_spawner.set_regional_controller(_current_regional_controller)

	# 连接波次信号
	_current_wave_spawner.wave_started.connect(_on_wave_started)
	_current_wave_spawner.all_waves_cleared.connect(_on_all_waves_cleared)
	_current_wave_spawner.wave_progress_updated.connect(_on_wave_progress_updated)
	_current_wave_spawner.elite_spawn_recorded.connect(_on_elite_spawn_recorded)  # PH06: 记录精英遭遇

	# 查找当前房间实例（用于获取房间节点引用）
	var current_room_node: Node2D = _get_current_room_instance()

	# PH12: 配置房间视觉化（TileMap地面/墙体 + 氛围装饰）
	_configure_room_visualizer(current_room_node, room_data)

	# 启动生成
	_current_wave_spawner.configure(
		wave_counts,
		current_room_node,
		player,
		current_floor,
		room_data.floor_level,
		self,
		room_data.size
	)
	# PH06: 从 EliteSpawnDirector 抽取精英并注入到波次生成器
	if _elite_spawn_director != null and _elite_spawn_director.has_method("try_select_elite"):
		var elite_spawn_data: Dictionary = _elite_spawn_director.try_select_elite(current_floor, _run_risk)
		if not elite_spawn_data.is_empty():
			_current_wave_spawner.set_pending_elite_spawn(elite_spawn_data)
			print("[RoomGameMode] 精英待注入: %s" % elite_spawn_data.get("elite_id", "?"))
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
		RoomData.FloorLevel.MEDIUM:
			wave_count = 2
		RoomData.FloorLevel.DEEP:
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
	if _current_regional_controller != null and is_instance_valid(_current_regional_controller):
		_current_regional_controller.queue_free()
	_current_regional_controller = null


## 设置区域刷怪控制器（PH11 P1: 房间级刷怪管理 + 区域增援）
func _setup_regional_spawn_controller(room_data: RoomData) -> void:
	_current_regional_controller = RegionalSpawnController.new()
	add_child(_current_regional_controller)

	# 获取当前房间实例，计算房间边界
	var room_instance: Node2D = _get_current_room_instance()
	var room_bounds: Rect2 = _calculate_room_bounds_for_spawn_controller(room_instance, room_data)

	# 配置控制器参数（根据房间层级调整）
	if room_data.floor_level == RoomData.FloorLevel.ABYSS:
		_current_regional_controller.set_cooldown(10.0)
		_current_regional_controller.set_count(4)
	elif room_data.floor_level == RoomData.FloorLevel.DEEP:
		_current_regional_controller.set_cooldown(12.0)
		_current_regional_controller.set_count(3)
	else:
		_current_regional_controller.set_cooldown(15.0)
		_current_regional_controller.set_count(2)

	# 初始化
	_current_regional_controller.setup(room_instance, room_data, room_bounds, self)

	# PH11 P2: 构建相邻房间敌人字典，注入到控制器
	_build_adjacent_enemies_for_controller(room_data)

	# 连接区域增援信号 -> 触发额外刷怪
	if (
		_current_regional_controller.reinforcement_ready.connect(_on_regional_reinforcement_ready)
		== OK
	):
		print("[RoomGameMode] RegionalSpawnController 增援信号已连接")

	# 连接敌人追击信号 -> 触发增援判断
	_connect_enemy_chase_signals()

	# PH11 P2: 延迟注册当前房间敌人（等敌人真正生成到场景后）
	# 连接精英怪 elite_entered_chase -> 相邻房间AI联动
	_call_deferred_register_adjacent_enemies()


## PH11 P2: 构建相邻房间敌人字典并注入到控制器
## 获取当前房间的相邻房间ID -> 收集每个相邻房间内的敌人节点
func _build_adjacent_enemies_for_controller(room_data: RoomData) -> void:
	if map_manager == null or _current_regional_controller == null:
		return
	var graph: NodeGraph = map_manager.get_graph()
	if graph == null:
		return
	var current_room_id: int = map_manager._current_room_id
	var neighbor_ids: Array[int] = graph.get_neighbors(current_room_id)
	var adjacent_enemies: Dictionary = {}
	for neighbor_id in neighbor_ids:
		var neighbor_enemies: Array[Node] = []
		var neighbor_instance: Node2D = map_manager.get_instantiated_room(neighbor_id)
		if is_instance_valid(neighbor_instance):
			for child in neighbor_instance.get_children():
				if child is CharacterBody2D and child.is_in_group("enemy"):
					neighbor_enemies.append(child)
		adjacent_enemies[neighbor_id] = neighbor_enemies
	_current_regional_controller.set_adjacent_enemies(adjacent_enemies)
	print("[RoomGameMode] P2相邻房间敌人已注入: %s" % adjacent_enemies)


## PH11 P2: 延迟注册当前房间敌人并连接 elite_entered_chase 信号
func _call_deferred_register_adjacent_enemies() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var room_instance: Node2D = _get_current_room_instance()
	if room_instance == null or _current_regional_controller == null:
		return
	var current_enemies: Array[Node] = []
	for child in room_instance.get_children():
		if child is CharacterBody2D and child.is_in_group("enemy"):
			current_enemies.append(child)
	_current_regional_controller.register_enemies(current_enemies)
	print("[RoomGameMode] P2当前房间敌人注册完成: %d个敌人已连精英信号" % current_enemies.size())


## 计算房间边界Rect2（供 RegionalSpawnController 使用）
func _calculate_room_bounds_for_spawn_controller(
	room_instance: Node2D, room_data: RoomData
) -> Rect2:
	var room_center: Vector2 = Vector2.ZERO
	if is_instance_valid(room_instance):
		room_center = room_instance.global_position
	else:
		room_center = room_data.position
	var half_size: Vector2 = room_data.size * 0.5
	return Rect2(room_center - half_size, room_data.size)


## 区域增援触发回调
func _on_regional_reinforcement_ready(room_id: String, count: int) -> void:
	print("[RoomGameMode] 区域增援触发！房间ID=%s，数量=%d" % [room_id, count])
	if _current_wave_spawner != null and is_instance_valid(_current_wave_spawner):
		_current_wave_spawner.trigger_extra_spawn(count)


## 连接当前房间所有敌人的追击信号（房间内任一敌人进入 CHASE -> 区域增援）
func _connect_enemy_chase_signals() -> void:
	# 延迟连接（等敌人真正生成到场景后）
	await get_tree().process_frame
	await get_tree().process_frame
	var room_instance: Node2D = _get_current_room_instance()
	if room_instance == null:
		return
	for child in room_instance.get_children():
		if child is CharacterBody2D and child.has_signal("enemy_entered_chase"):
			if not child.enemy_entered_chase.is_connected(_on_enemy_entered_chase_wrapper):
				child.enemy_entered_chase.connect(_on_enemy_entered_chase_wrapper)


## 敌人进入 CHASE 的信号包装（统一路由到区域控制器）
func _on_enemy_entered_chase_wrapper(enemy: Node, last_known_pos: Vector2) -> void:
	if _current_regional_controller != null and is_instance_valid(_current_regional_controller):
		_current_regional_controller._on_enemy_chase(enemy, last_known_pos)


## 获取当前房间对应的场景实例节点
func _get_current_room_instance() -> Node2D:
	if map_manager == null:
		return self
	var room_id: int = map_manager._current_room_id
	var instance: Node2D = map_manager.get_instantiated_room(room_id)
	if instance != null:
		return instance
	return self  # Fallback


## PH12: 配置房间视觉化（TileMap地面/墙体 + 氛围装饰）
func _configure_room_visualizer(room_node: Node2D, room_data: RoomData) -> void:
	if room_node == null or not is_instance_valid(room_node):
		return
	# Combat 场景将组件挂在根上，其它房型将组件挂在 Visualizer 子节点。
	var visualizer: Node = _get_room_visualizer_node(room_node)
	if visualizer != null and visualizer.has_method("configure"):
		var door_info: Array[Dictionary] = []
		if (
			map_manager != null
			and map_manager.path_director != null
			and map_manager._current_room_id >= 0
		):
			door_info = map_manager.path_director.get_open_door_info(map_manager._current_room_id)
		visualizer.configure(room_data.room_type, room_data.size, door_info)
		print(
			(
				"[RoomGameMode] 房间视觉化已配置: %s size=%s"
				% [RoomData.get_type_name(room_data.room_type), room_data.size]
			)
		)


## 撤离房视觉激活（光圈脉冲+方向标记强化）
func _apply_extraction_visual_activation() -> void:
	if map_manager == null:
		return
	var current_id: int = map_manager.get_current_room_id()
	if current_id < 0:
		return
	var room_instance: Node2D = map_manager.get_instantiated_room(current_id)
	if room_instance == null or not is_instance_valid(room_instance):
		return
	# 查找 ExtractionRoomLogic 组件（挂载在 RoomExtraction 根节点）
	var extraction_logic: Node = room_instance as Node
	if extraction_logic != null and extraction_logic.has_method("activate_extraction"):
		extraction_logic.call("activate_extraction")
		print("[RoomGameMode] 撤离房视觉已激活: %s" % room_instance.name)


## 波次开始回调
func _on_wave_started(wave: int, total: int) -> void:
	_update_room_info_label("第 %d/%d 波袭来！" % [wave, total])
	_show_wave_announcement(wave, total)


## 显示波次公告（底部 WaveIndicatorLabel）
func _show_wave_announcement(wave: int, total: int) -> void:
	if _wave_indicator_label == null:
		if _ui_manager != null and is_instance_valid(_ui_manager):
			_wave_indicator_label = (
				_ui_manager.get_node_or_null("GameHUD/WaveIndicatorLabel") as Label
			)
		if _wave_indicator_label == null:
			_wave_indicator_label = (
				get_node_or_null("../GameUIManager/GameHUD/WaveIndicatorLabel") as Label
			)
	if _wave_indicator_label == null:
		return

	var text := "第 %d/%d 波" % [wave, total]
	_wave_indicator_label.text = text
	_wave_indicator_label.visible = true
	_wave_indicator_label.modulate.a = 1.0

	# 波次公告淡入后停留再淡出
	var tween := _wave_indicator_label.create_tween()
	tween.tween_interval(2.0)
	tween.tween_property(_wave_indicator_label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(
		func():
			if _wave_indicator_label != null and is_instance_valid(_wave_indicator_label):
				_wave_indicator_label.visible = false
	)


func _on_wave_progress_updated(killed: int, total: int, wave: int) -> void:
	wave_progress_changed.emit(killed, total, wave)


## 所有波次清理完毕回调
func _on_all_waves_cleared() -> void:
	if _extraction_defense_active:
		return
	var room_data: RoomData = map_manager.get_current_room_data()
	if room_data:
		_on_room_cleared(room_data)


## 显示开门命运卡片选择：钥匙开启的新门都会先给一次构筑选择。
func _show_door_fate_cards() -> void:
	await get_tree().process_frame
	var bm: BaseManager = _get_base_manager()
	if bm != null and _reserved_door_fate_card == null:
		var raw_pending: Dictionary = bm.get_pending_fate_card()
		if not raw_pending.is_empty():
			_reserved_door_fate_card = _reconstruct_fate_card_from_dict(raw_pending)
			bm.clear_pending_fate_card()
	_show_fate_cards_in_panel()


## 从局前预选字典重建 FateCard 实例
func _reconstruct_fate_card_from_dict(d: Dictionary) -> FateCard:
	# card_id / card_name / card_type / card_rarity / description / tags / effect / visual
	if d.is_empty() or not d.has("card_name"):
		return null
	var card: FateCard = FateCard.new(
		str(d.get("card_name", "Unknown")), int(d.get("card_type", 0)), int(d.get("card_rarity", 0))
	)
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
	_set_room_revealed(target_id, true)
	_place_player_in_room(target_id, Vector2.ZERO)
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
	var room_instance: Node2D = null
	if map_manager != null and map_manager._current_room_id >= 0:
		room_instance = map_manager.get_instantiated_room(map_manager._current_room_id)

	if room_instance == null:
		push_warning(
			(
				"[RoomGameMode] Cannot auto-open merchant: room instance not found for room %s"
				% room_data.room_id
			)
		)
		return

	var merchant_interaction: Node = room_instance.get_node_or_null("MerchantArea")
	if merchant_interaction == null or not merchant_interaction.has_method("set_inventory"):
		push_warning("[RoomGameMode] RoomMerchant has no usable MerchantInteraction")
		return

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
		# 连接交易成功信号 -> 解锁交易撤离（单人购买即解锁，不需要等待关闭）
		if not ui.merchant_closed.is_connected(_on_merchant_closed):
			ui.merchant_closed.connect(_on_merchant_closed)
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


## 在 GameUIManager 的 FateCardPanel 中显示 3 张开门奖励卡片（强制展示）
func _show_fate_cards_in_panel() -> void:
	var panel: Control = _get_or_create_fate_card_panel()
	if panel == null:
		push_warning("[RoomGameMode] Cannot show fate cards: panel not found")
		_update_room_info_label("命运卡片加载失败，门已打开。")
		_fate_card_choice_committed = true
		_door_fate_selection_active = false
		return

	_prepare_fate_modal_panel(panel)
	_fate_card_choice_committed = false
	_door_fate_selection_active = true

	var bg := ColorRect.new()
	bg.name = "ModalDim"
	bg.color = Color(0.02, 0.025, 0.035, 0.72)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.process_mode = Node.PROCESS_MODE_ALWAYS
	panel.add_child(bg)

	var center := CenterContainer.new()
	center.name = "ModalCenter"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	center.process_mode = Node.PROCESS_MODE_ALWAYS
	panel.add_child(center)

	var modal := PanelContainer.new()
	modal.name = "FateModal"
	modal.custom_minimum_size = Vector2(760, 360)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.process_mode = Node.PROCESS_MODE_ALWAYS
	center.add_child(modal)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	margin.process_mode = Node.PROCESS_MODE_ALWAYS
	modal.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.alignment = VBoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	vbox.process_mode = Node.PROCESS_MODE_ALWAYS
	margin.add_child(vbox)

	var instruction := Label.new()
	instruction.name = "InstructionLabel"
	instruction.text = "门后命运：选择一项改造"
	instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction.add_theme_font_size_override("font_size", 24)
	instruction.add_theme_color_override("font_color", Color(1.0, 0.90, 0.55, 1.0))
	instruction.process_mode = Node.PROCESS_MODE_ALWAYS
	vbox.add_child(instruction)

	var subtitle := Label.new()
	subtitle.text = "改造会立刻作用于当前武器。选择后穿过门洞继续探索。"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.78, 0.86, 0.92, 1.0))
	subtitle.process_mode = Node.PROCESS_MODE_ALWAYS
	vbox.add_child(subtitle)

	var cards_container := HBoxContainer.new()
	cards_container.name = "CardsContainer"
	cards_container.alignment = HBoxContainer.ALIGNMENT_CENTER
	cards_container.add_theme_constant_override("separation", 12)
	cards_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards_container.process_mode = Node.PROCESS_MODE_ALWAYS
	vbox.add_child(cards_container)

	# 清空旧卡片（上面的 _prepare 已清空，这里保留防御）
	for child in cards_container.get_children():
		child.queue_free()

	# 随机抽取 3 张
	var all_cards: Array[FateCard] = FateCardPresets.door_reward_presets()
	all_cards.shuffle()
	var options: Array[FateCard] = []
	if _reserved_door_fate_card != null:
		options.append(_reserved_door_fate_card)
		_reserved_door_fate_card = null
	for card in all_cards:
		if options.size() >= 3:
			break
		var is_duplicate := false
		for selected_card in options:
			if selected_card.card_name == card.card_name:
				is_duplicate = true
				break
		if not is_duplicate:
			options.append(card)

	for card in options:
		var btn := _create_fate_card_button(card)
		cards_container.add_child(btn)

	# 显示面板
	panel.visible = true
	panel.move_to_front()
	if _ui_manager != null:
		_ui_manager.layer = 100
		_ui_manager.process_mode = Node.PROCESS_MODE_ALWAYS
	_set_player_input_locked(true)


func _prepare_fate_modal_panel(panel: Control) -> void:
	get_tree().paused = false
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 0
	panel.offset_top = 0
	panel.offset_right = 0
	panel.offset_bottom = 0
	panel.z_index = 700
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	for child in panel.get_children():
		child.queue_free()


## 创建一张命运卡片按钮（用于面板内动态创建）
func _create_fate_card_button(card: FateCard) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(220, 190)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	btn.focus_mode = Control.FOCUS_ALL
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.process_mode = Node.PROCESS_MODE_ALWAYS

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
	btn.text = (
		"[%s] %s\n%s\n%s"
		% [FateCard.rarity_name(card.card_rarity), card.card_name, type_str, card.description]
	)
	btn.set_meta("fate_card", card)
	btn.pressed.connect(_on_fate_card_button_pressed.bind(card))

	return btn


## 玩家点击了命运卡片按钮
func _on_fate_card_button_pressed(card: FateCard) -> void:
	if not _door_fate_selection_active or _fate_card_choice_committed:
		return
	var result := FateCardGameBridge.apply_card(card)
	if not result.success:
		push_warning("[RoomGameMode] 命运卡片应用失败: %s — %s" % [card.card_name, result.message])
		if _ui_manager != null and _ui_manager.has_method("show_fate_card_notification"):
			_ui_manager.call("show_fate_card_notification", "当前武器无法承载 [%s]，请改选另一张" % card.card_name)
		return

	_fate_card_choice_committed = true
	_door_fate_selection_active = false
	print("[RoomGameMode] 命运卡片应用成功: %s — %s" % [card.card_name, result.message])

	# 通知玩家卡片已应用
	if _ui_manager != null and _ui_manager.has_method("show_fate_card_notification"):
		_ui_manager.show_fate_card_notification("✓ %s 已应用！" % card.card_name)

	# 关闭面板
	var panel: Control = _get_or_create_fate_card_panel()
	if panel:
		panel.visible = false
	get_tree().paused = false
	_set_player_input_locked(false)
	if _ui_manager != null:
		_ui_manager.layer = 1
		_ui_manager.process_mode = Node.PROCESS_MODE_INHERIT
		if _ui_manager.has_method("show_fate_card_notification"):
			_ui_manager.call(
				"show_fate_card_notification", "命运生效: %s - %s" % [card.card_name, card.description]
			)

	# 通知玩家；门已经开启，玩家自己穿过门洞进入下一房间。
	_update_room_info_label("命运卡片 [%s] 已应用，穿过门洞开始探索。" % card.card_name)


func _set_player_input_locked(locked: bool) -> void:
	if player == null or not is_instance_valid(player):
		return
	if player.has_method("set_input_locked"):
		player.call("set_input_locked", locked)


func _unhandled_input(_event: InputEvent) -> void:
	pass


## 每帧检测房间清理状态 & 撤离读条
func _process(delta: float) -> void:
	_sync_camera_to_player(false)
	_update_current_room_from_player_position()
	# 更新撤离读条
	if (
		extraction_module != null
		and extraction_module.get_status() == ExtractionModule.ExtractionStatus.COUNTDOWN
	):
		_update_extraction_defense()
		extraction_module.update(delta)

	# 更新波次生成器
	if _current_wave_spawner != null and is_instance_valid(_current_wave_spawner):
		_current_wave_spawner.tick(delta)

	# 更新敌人视野可见性（每帧检查玩家与敌人之间的遮挡）
	if player != null and is_instance_valid(player):
		_do_update_enemy_visibility()

	# 更新区域刷怪控制器（PH11 P1: 冷却计时）
	if _current_regional_controller != null and is_instance_valid(_current_regional_controller):
		_current_regional_controller.tick(delta)

	# 亡者祝福计时（低HP存活检查）
	if not _bless_dead_config.is_empty() and _bless_dead_config.get("active", false):
		var timer = _bless_dead_config.get("survive_timer", 0.0) - delta
		_bless_dead_config["survive_timer"] = timer
		if timer <= 0.0:
			var bonus = _bless_dead_config.get("damage_bonus", 0.1)
			print("[RoomGameMode] 亡者祝福生效！伤害+%.0f%%" % (bonus * 100.0))
			if player != null and player.has_method("apply_damage_multiplier"):
				player.apply_damage_multiplier(1.0 + bonus)
			_bless_dead_config["active"] = false

	var current_data: RoomData = map_manager.get_current_room_data()
	if current_data == null:
		return
	if current_data.room_type in [RoomData.RoomType.PLAYER_SPAWN, RoomData.RoomType.EXTRACTION]:
		return

	# 非战斗房间直接标记为已清理
	if not current_data.is_combat():
		if not _room_cleared_flag:
			_on_room_cleared(current_data)
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
	var current_id: int = map_manager.get_current_room_id() if map_manager != null else -1
	if current_id >= 0:
		_cleared_room_ids[current_id] = true

	room_cleared.emit(room_data)

	var reward_text: String = _calculate_room_reward(room_data)
	_update_room_info_label(
		"%s 已清理！%s | 钥匙已掉落" % [RoomData.get_type_name(room_data.room_type), reward_text]
	)
	# 击杀结算可能发生在物理回调内，掉落物与出口 Area 都在下一拍安全创建。
	call_deferred("_spawn_key_for_room", current_id, room_data)
	call_deferred("_refresh_room_doors_for_state")

	# 风险等级递增并同步 HUD
	_run_risk += 1
	_update_risk_display()

	# 检测是否还有下一个房间
	_check_map_completion()


func _spawn_key_for_room(room_id: int, room_data: RoomData) -> void:
	if room_id < 0 or room_data == null:
		return
	if room_data.room_type in [RoomData.RoomType.PLAYER_SPAWN, RoomData.RoomType.EXTRACTION]:
		return
	if _spawned_key_room_ids.has(room_id):
		return
	_spawned_key_room_ids[room_id] = true
	var room_node: Node2D = _get_current_room_instance()
	if room_node == null:
		return
	var key := Area2D.new()
	key.name = "RoomKey_%d" % room_id
	key.set_script(ROOM_KEY_PICKUP_SCRIPT)
	key.position = Vector2(0, -72)
	room_node.add_child(key)
	if key.has_method("setup"):
		key.call("setup", self, room_id)


func collect_room_key(room_id: int) -> void:
	if room_id < 0:
		return
	_room_key_count += 1
	_update_room_info_label("获得钥匙：选择一个方向的门开启。钥匙 %d" % _room_key_count)
	# 拾取发生在 Area2D.body_entered 的物理查询回调中，门/墙碰撞刷新必须延后。
	call_deferred("_refresh_room_doors_for_state")
	if _ui_manager != null and _ui_manager.has_method("show_fate_card_notification"):
		_ui_manager.call("show_fate_card_notification", "获得房间钥匙：可开启一扇门")


func _refresh_room_doors_for_state() -> void:
	if map_manager == null or map_manager.get_graph() == null:
		return
	var current_id: int = map_manager.get_current_room_id()
	if current_id < 0:
		return
	var room_node: Node2D = map_manager.get_instantiated_room(current_id)
	if room_node == null:
		return
	_clear_room_door_interactions(room_node)
	var graph: NodeGraph = map_manager.get_graph()
	var current_graph_node := graph.get_node(current_id)
	if current_graph_node == null:
		return
	var current_data: RoomData = current_graph_node.room_data
	for neighbor_id in graph.get_neighbors(current_id):
		var is_open := map_manager.path_director.are_connected(current_id, neighbor_id)
		_spawn_door_interaction(room_node, current_data, current_id, neighbor_id, is_open)
	_configure_room_visualizer(room_node, current_data)
	_apply_open_doors_to_room(current_id)


func _clear_room_door_interactions(room_node: Node) -> void:
	if room_node == null:
		return
	for child in room_node.get_children():
		if child.name.begins_with("DoorExit_"):
			child.queue_free()


func _spawn_door_interaction(
	room_node: Node2D, room_data: RoomData, from_id: int, to_id: int, is_open: bool
) -> void:
	var graph: NodeGraph = map_manager.get_graph()
	var from_node := graph.get_node(from_id)
	var to_node := graph.get_node(to_id)
	if from_node == null or to_node == null:
		return
	var direction := _direction_between_rooms(from_node.position, to_node.position)
	var door := Area2D.new()
	door.name = "DoorExit_%d" % to_id
	door.set_script(ROOM_DOOR_INTERACTION_SCRIPT)
	door.position = _door_local_position(room_data.size, direction)
	room_node.add_child(door)
	var door_type := _get_door_type(to_node.room_data)
	if door.has_method("setup"):
		door.call("setup", self, from_id, to_id, direction, door_type, is_open)


func _direction_between_rooms(from_pos: Vector2, to_pos: Vector2) -> Vector2:
	var delta := to_pos - from_pos
	if absf(delta.x) >= absf(delta.y):
		return Vector2.RIGHT if delta.x >= 0.0 else Vector2.LEFT
	return Vector2.DOWN if delta.y >= 0.0 else Vector2.UP


func _door_local_position(room_size: Vector2, direction: Vector2) -> Vector2:
	var half := room_size * 0.5
	var inset := 46.0
	if direction == Vector2.RIGHT:
		return Vector2(half.x - inset, 0)
	if direction == Vector2.LEFT:
		return Vector2(-half.x + inset, 0)
	if direction == Vector2.DOWN:
		return Vector2(0, half.y - inset)
	return Vector2(0, -half.y + inset)


func _get_door_type(room_data: RoomData) -> String:
	if room_data == null:
		return "normal"
	if room_data.room_type == RoomData.RoomType.BOSS:
		return "boss"
	if room_data.room_type == RoomData.RoomType.EXTRACTION:
		return "extraction"
	return "normal"


func try_open_room_door(target_id: int) -> void:
	if map_manager == null or target_id < 0:
		return
	if _door_fate_selection_active:
		_update_room_info_label("先选择当前命运卡片，再继续开门。")
		return
	var current_id: int = map_manager.get_current_room_id()
	if current_id < 0 or current_id == target_id:
		return
	var is_open := map_manager.path_director.are_connected(current_id, target_id)
	if is_open:
		_update_room_info_label("门已经打开，直接走过去。")
		return
	if _room_key_count <= 0:
		_update_room_info_label("需要钥匙才能开启这扇门。")
		return
	if not _cleared_room_ids.has(current_id):
		_update_room_info_label("清理当前房间后才能开门。")
		return
	_consume_room_key()
	map_manager.path_director.open_door(current_id, target_id)
	_set_room_revealed(target_id, true)
	_refresh_room_doors_for_state()
	_apply_open_doors_to_room(current_id)
	_apply_open_doors_to_room(target_id)
	_update_room_info_label("门已打开，命运开始选择。钥匙 %d" % _room_key_count)
	_show_door_fate_cards()


func try_enter_room_via_door(target_id: int) -> void:
	try_open_room_door(target_id)


func _enter_room_by_id(target_id: int, from_id: int) -> void:
	var graph: NodeGraph = map_manager.get_graph()
	if graph == null:
		return
	var target_node := graph.get_node(target_id)
	var from_node := graph.get_node(from_id)
	if target_node == null:
		return
	_stop_current_room_spawner()
	map_manager.exit_room()
	var dir := Vector2.RIGHT
	if from_node != null:
		dir = _direction_between_rooms(from_node.position, target_node.position)
	_place_player_in_room(target_id, -dir)
	_sync_camera_to_player(true)
	map_manager.enter_room(target_id)


func _set_room_revealed(room_id: int, revealed: bool) -> void:
	var room_node: Node2D = (
		map_manager.get_instantiated_room(room_id) if map_manager != null else null
	)
	if room_node == null:
		return
	_revealed_room_ids[room_id] = revealed
	room_node.visible = revealed
	if revealed:
		var lighting: Node = room_node.get_node_or_null("RoomLightingSystem")
		if lighting != null and lighting.has_method("activate"):
			lighting.call("activate")


func _apply_open_doors_to_room(room_id: int) -> void:
	if map_manager == null or map_manager.get_graph() == null:
		return
	var room_node: Node2D = map_manager.get_instantiated_room(room_id)
	if room_node == null:
		return
	var graph := map_manager.get_graph()
	var graph_node := graph.get_node(room_id)
	if graph_node == null:
		return
	var door_info: Array[Dictionary] = _build_room_door_info(room_id, false)
	var layout := room_node.get_node_or_null("RoomLayout")
	if layout != null:
		layout.call("set_open_doors", door_info)
	var open_door_info: Array[Dictionary] = []
	for info in door_info:
		if bool(info.get("is_open", false)):
			open_door_info.append(info)
	var visualizer := _get_room_visualizer_node(room_node)
	if visualizer != null and visualizer.has_method("set_open_doors"):
		visualizer.call("set_open_doors", open_door_info)
	if room_id == map_manager.get_current_room_id():
		call_deferred("_refresh_current_room_vision_occlusion")


func _build_room_door_info(room_id: int, open_only: bool) -> Array[Dictionary]:
	var door_info: Array[Dictionary] = []
	if map_manager == null or map_manager.get_graph() == null:
		return door_info
	var graph := map_manager.get_graph()
	var graph_node := graph.get_node(room_id)
	if graph_node == null:
		return door_info
	for neighbor_id in graph.get_neighbors(room_id):
		var is_open := map_manager.path_director.are_connected(room_id, neighbor_id)
		if open_only and not is_open:
			continue
		var neighbor_node := graph.get_node(neighbor_id)
		if neighbor_node == null:
			continue
		(
			door_info
			. append(
				{
					"from_id": room_id,
					"to_id": neighbor_id,
					"door_type": _get_door_type(neighbor_node.room_data),
					"direction":
					_direction_between_rooms(graph_node.position, neighbor_node.position),
					"is_open": is_open,
				}
			)
		)
	return door_info


func _ensure_room_layout(room_node: Node2D, room_id: int, room_data: RoomData) -> Node:
	if room_node == null:
		return null
	var visualizer := _get_room_visualizer_node(room_node)
	if visualizer != null and visualizer.has_method("set_boundary_collision_enabled"):
		visualizer.call("set_boundary_collision_enabled", false)
	var layout: Node = room_node.get_node_or_null("RoomLayout")
	if layout == null:
		layout = ROOM_LAYOUT_SCRIPT.new() as Node
		layout.name = "RoomLayout"
		room_node.add_child(layout)
	var lighting: Node = room_node.get_node_or_null("RoomLightingSystem")
	if lighting == null:
		lighting = ROOM_LIGHTING_SCRIPT.new() as Node
		lighting.name = "RoomLightingSystem"
		room_node.add_child(lighting)
	lighting.call("configure", room_data.room_type, room_data.size, room_id)
	var lighting_changed := Callable(self, "_refresh_current_room_vision_occlusion")
	if lighting.has_signal("lighting_changed") and not lighting.is_connected("lighting_changed", lighting_changed):
		lighting.connect("lighting_changed", lighting_changed)
	layout.call("configure", room_id, room_data, _build_room_door_info(room_id, false))
	return layout


func _place_player_in_room(room_id: int, entry_direction: Vector2 = Vector2.ZERO) -> void:
	if player == null or not is_instance_valid(player) or map_manager == null:
		return
	var room_node: Node2D = map_manager.get_instantiated_room(room_id)
	if room_node == null:
		player.global_position = Vector2.ZERO
		return
	var graph := map_manager.get_graph()
	var room_size := Vector2(GridConstants.ROOM_PIXEL_WIDTH, GridConstants.ROOM_PIXEL_HEIGHT)
	if graph != null:
		var graph_node := graph.get_node(room_id)
		if graph_node != null and graph_node.room_data != null:
			room_size = graph_node.room_data.size
	var dir := Vector2.ZERO
	if entry_direction.length_squared() > 0.0:
		dir = entry_direction.normalized()
	var local_pos: Vector2 = dir * min(room_size.x, room_size.y) * 0.24
	var margin := Vector2(140.0, 128.0)
	local_pos.x = clamp(local_pos.x, -room_size.x * 0.5 + margin.x, room_size.x * 0.5 - margin.x)
	local_pos.y = clamp(local_pos.y, -room_size.y * 0.5 + margin.y, room_size.y * 0.5 - margin.y)
	player.global_position = room_node.global_position + local_pos


func _get_room_visualizer_node(room_node: Node2D) -> Node:
	if room_node == null:
		return null
	if room_node.has_method("set_open_doors") or room_node.has_method("configure"):
		return room_node
	var direct := room_node.get_node_or_null("Visualizer")
	if direct != null:
		return direct
	direct = room_node.get_node_or_null("RoomVisualizer")
	if direct != null:
		return direct
	return null


func _update_current_room_from_player_position() -> void:
	if map_manager == null or player == null or not is_instance_valid(player):
		return
	var current_id: int = map_manager.get_current_room_id()
	var room_id := _find_room_at_position(player.global_position)
	if room_id < 0 or room_id == current_id:
		return
	if current_id >= 0 and not map_manager.path_director.are_connected(current_id, room_id):
		return
	_stop_current_room_spawner()
	map_manager.enter_room(room_id)


func _find_room_at_position(world_pos: Vector2) -> int:
	if map_manager == null or map_manager.get_graph() == null:
		return -1
	for graph_node in map_manager.get_graph().get_all_nodes():
		var room_id: int = graph_node.id
		if not _revealed_room_ids.get(room_id, false):
			continue
		var room_instance: Node2D = map_manager.get_instantiated_room(room_id)
		if room_instance == null:
			continue
		var room_data: RoomData = graph_node.room_data
		var rect := Rect2(room_instance.global_position - room_data.size * 0.5, room_data.size)
		if rect.has_point(world_pos):
			return room_id
	return -1


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

	# 处理怪物掉落：物品留在死亡点，只有货币奖励由魂球承载。
	var loot: Array[Dictionary] = LootModule.get_instance().generate_enemy_loot(enemy_data)
	var currency_earned: int = 0
	var ground_items: Array[Dictionary] = []
	for item_data in loot:
		if item_data.get("is_currency", false):
			currency_earned += item_data.get("count", 0)
		else:
			ground_items.append(item_data)

	# 基础击杀奖励 + 额外掉落货币
	var base_reward: int = enemy_data.get("currency_value", 10)
	currency_earned += base_reward

	var enemy_pos: Vector2 = enemy_data.get(
		"last_position", player.global_position if player != null else Vector2.ZERO
	)
	_spawn_soul_orb(enemy_pos, currency_earned)
	if not ground_items.is_empty():
		call_deferred("_spawn_enemy_item_pickups", enemy_pos, ground_items)

	# 如果是精英怪，触发精英撤离点解锁并记录击杀
	if enemy_data.get("is_elite", false):
		if map_manager != null:
			map_manager.extraction_director.unlock_elite_extraction()
		# PH06: 通知 EliteArchiveModule 精英被击杀
		var elite_id: String = enemy_data.get("elite_id", "")
		if not elite_id.is_empty() and _elite_archive != null:
			_elite_archive.kill_elite(elite_id)
			_killed_elite_ids_this_room.append(elite_id)
			print("[RoomGameMode] 精英击杀已记录: %s" % elite_id)

	kill_recorded.emit()
	_update_ui()


func _spawn_soul_orb(world_pos: Vector2, amount: int) -> void:
	if amount <= 0:
		return
	var orb: SoulOrb = SOUL_ORB_SCENE.instantiate() as SoulOrb
	if orb == null:
		GameManager.add_currency(amount)
		return
	orb.amount = amount
	orb.global_position = world_pos + Vector2(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0))
	orb.collected.connect(_on_soul_orb_collected)
	add_child(orb)


func _spawn_enemy_item_pickups(world_pos: Vector2, items: Array[Dictionary]) -> void:
	for i in items.size():
		var pickup := GROUND_ITEM_PICKUP_SCRIPT.new() as Node2D
		if pickup == null:
			continue
		pickup.setup(self, items[i])
		add_child(pickup)
		var angle := float(i) * 1.9 + PI * 0.2
		pickup.global_position = world_pos + Vector2(cos(angle), sin(angle)) * (24.0 + i * 8.0)


func collect_ground_item(item_data: Dictionary) -> int:
	if inventory_module == null or item_data.is_empty():
		return 0
	var added := inventory_module.add_item(item_data, int(item_data.get("count", 1)))
	if added <= 0:
		if _ui_manager != null and _ui_manager.has_method("show_fate_card_notification"):
			_ui_manager.call(
				"show_fate_card_notification", "背包已满，无法拾取 %s" % item_data.get("name", "物品")
			)
		return 0
	if item_data.get("id", "") == "item_room_key":
		call_deferred("_refresh_room_doors_for_state")
	var item_name := str(item_data.get("name", item_data.get("id", "物品")))
	if _ui_manager != null and _ui_manager.has_method("show_fate_card_notification"):
		_ui_manager.call("show_fate_card_notification", "拾取: %s x%d" % [item_name, added])
	return added


func _on_soul_orb_collected(amount: int, orb: SoulOrb) -> void:
	GameManager.add_currency(amount)
	if _ui_manager != null and _ui_manager.has_method("show_currency_popup"):
		var pos := (
			orb.global_position
			if orb != null and is_instance_valid(orb)
			else (player.global_position if player != null else Vector2.ZERO)
		)
		_ui_manager.call("show_currency_popup", amount, pos)


func _consume_room_key() -> void:
	if inventory_module != null and inventory_module.has_item("item_room_key"):
		inventory_module.consume_item("item_room_key", 1)
	elif _room_key_count > 0:
		_room_key_count -= 1


## 手动前进到下一层
func advance_to_next_floor() -> void:
	var next_graph: NodeGraph = map_manager.advance_to_next_floor()
	current_floor = map_manager.get_current_floor()
	_room_cleared_flag = false


## — Boss 事件处理器（由 MapManager 穿透信号触发）—
func _on_boss_spawned(boss_data: Dictionary) -> void:
	# 通知 UI 显示 Boss 相关信息（如存在）
	_update_room_info_label("Boss 出现了！")
	if _ui_manager != null and _ui_manager.has_method("on_boss_spawned"):
		_ui_manager.call("on_boss_spawned", boss_data)


func _on_boss_damaged(boss_id: String, damage: float, new_hp: float) -> void:
	# 通知 UI 更新 Boss 血条
	if _ui_manager != null and _ui_manager.has_method("on_boss_damaged"):
		_ui_manager.call("on_boss_damaged", boss_id, damage, new_hp)


func _on_boss_phase_changed(boss_id: String, new_phase: int) -> void:
	# Boss 阶段切换时显示提示
	_update_room_info_label("Boss 进入阶段 %d！" % new_phase)
	if _ui_manager != null and _ui_manager.has_method("on_boss_phase_changed"):
		_ui_manager.call("on_boss_phase_changed", boss_id, new_phase)


func _on_boss_defeated(boss_id: String, rewards: Dictionary) -> void:
	# Boss 击败时触发强烈震屏 + 特殊庆祝文字
	_update_room_info_label("Boss已击败！前往下一层或撤离...")
	# Boss 击败重震屏（boss_defeated 信号说明 BossRoomDirector 已解锁 BOSS_KILL 撤离点）
	if _screen_shake != null and _screen_shake.has_method("trigger"):
		_screen_shake.call("trigger", 12.0, 0.20)
	if _ui_manager != null and _ui_manager.has_method("on_boss_defeated"):
		_ui_manager.call("on_boss_defeated", boss_id, rewards)


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
	if inventory_module != null:
		var inventory_keys := inventory_module.get_item_count("item_room_key")
		var key_delta := inventory_keys - _inventory_room_key_snapshot
		_room_key_count = maxi(0, _room_key_count + key_delta)
		_inventory_room_key_snapshot = inventory_keys
	_call_ui_manager_method(
		"set_beacon_count",
		(
			map_manager.extraction_director.get_beacon_count()
			if map_manager and map_manager.extraction_director
			else 0
		)
	)


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


## 获取当前房间精英怪已击杀数量（供 ExtractionDirector._check_requirements 调用）
func get_elites_killed_in_current_room() -> int:
	if map_manager == null:
		return 0
	var enemies: Array[Dictionary] = map_manager.get_current_room_enemies()
	var killed: int = 0
	for e in enemies:
		if e.get("is_elite", false) and e.get("hp", 1) <= 0:
			killed += 1
	return killed


## 获取当前房间精英怪总数量
func get_current_room_elite_count() -> int:
	if map_manager == null:
		return 0
	var enemies: Array[Dictionary] = map_manager.get_current_room_enemies()
	var elite_count: int = 0
	for e in enemies:
		if e.get("is_elite", false):
			elite_count += 1
	return elite_count


## 获取指定房间的精英怪总数量
func get_room_elite_count(room_id: int) -> int:
	if map_manager == null:
		return 0
	var enemies: Array[Dictionary] = map_manager._spawned_enemies.get(room_id, [])
	var elite_count: int = 0
	for e in enemies:
		if e.get("is_elite", false):
			elite_count += 1
	return elite_count


## 检查Boss房Boss是否已击杀
func is_boss_killed_in_current_room() -> bool:
	if map_manager == null:
		return false
	var room_data: RoomData = map_manager.get_current_room_data()
	if room_data == null or room_data.room_type != RoomData.RoomType.BOSS:
		return false
	return map_manager.is_current_room_cleared()


## 开始撤离读条（供UI或信号调用）
func begin_extraction(extraction_type: String, countdown: float = 5.0) -> bool:
	if extraction_module == null:
		return false
	if extraction_module.get_status() != ExtractionModule.ExtractionStatus.IDLE:
		return false
	return extraction_module.start_extraction(extraction_type, countdown)


func request_extraction_switch_activation() -> bool:
	if map_manager == null or extraction_module == null:
		return false
	var room_data: RoomData = map_manager.get_current_room_data()
	if room_data == null or room_data.room_type != RoomData.RoomType.EXTRACTION:
		return false
	if extraction_module.get_status() != ExtractionModule.ExtractionStatus.IDLE:
		return false
	if not extraction_module.start_extraction("STANDARD", EXTRACTION_DEFENSE_DURATION):
		return false
	_extraction_defense_active = true
	_extraction_mid_wave_spawned = false
	_extraction_elite_wave_spawned = false
	_apply_extraction_visual_activation()
	# 播放撤离开始音效
	if _audio and _audio.has_method("play_sfx"):
		_audio.call("play_sfx", "extraction_start")
	_start_extraction_defense(room_data)
	_update_room_info_label("撤离信号已发送：守住 14 秒，敌潮正在接近！")
	if _ui_manager != null and _ui_manager.has_method("show_extraction_room_countdown"):
		_ui_manager.call("show_extraction_room_countdown", EXTRACTION_DEFENSE_DURATION)
	return true


func _start_extraction_defense(room_data: RoomData) -> void:
	_stop_current_room_spawner()
	_current_wave_spawner = RoomWaveSpawner.new()
	add_child(_current_wave_spawner)
	_current_wave_spawner.configure(
		[],
		_get_current_room_instance(),
		player,
		current_floor,
		room_data.floor_level,
		self,
		room_data.size
	)
	_spawn_extraction_attackers(
		[
			{
				"enemy_type": "melee_chaser",
				"hp": 28,
				"damage": 6,
				"speed": 95.0,
				"currency_value": 8
			},
			{
				"enemy_type": "ranged_caster",
				"hp": 24,
				"damage": 6,
				"speed": 82.0,
				"currency_value": 9
			},
		]
	)


func _update_extraction_defense() -> void:
	if not _extraction_defense_active or extraction_module == null:
		return
	var remaining := extraction_module.get_remaining_time()
	if not _extraction_mid_wave_spawned and remaining <= 9.5:
		_extraction_mid_wave_spawned = true
		_update_room_info_label("撤离信号 2/3：增援逼近！")
		_spawn_extraction_attackers(
			[
				{
					"enemy_type": "melee_chaser",
					"hp": 32,
					"damage": 7,
					"speed": 105.0,
					"currency_value": 9
				},
				{
					"enemy_type": "ambusher",
					"hp": 25,
					"damage": 8,
					"speed": 100.0,
					"currency_value": 10
				},
			]
		)
	if not _extraction_elite_wave_spawned and remaining <= 5.0:
		_extraction_elite_wave_spawned = true
		_spawn_extraction_final_wave()


func _spawn_extraction_final_wave() -> void:
	var elite_chance := minf(1.0, 0.30 + float(_run_risk) * 0.12)
	if randf() < elite_chance:
		_update_room_info_label("撤离信号即将锁定：精英拦截者出现！")
		_spawn_extraction_attackers(
			[
				{
					"enemy_type": "melee_chaser",
					"hp": 85,
					"damage": 11,
					"speed": 100.0,
					"currency_value": 35,
					"is_elite": true,
				}
			]
		)
	else:
		_update_room_info_label("撤离信号即将锁定：最后一波追兵！")
		_spawn_extraction_attackers(
			[
				{
					"enemy_type": "ranged_caster",
					"hp": 34,
					"damage": 8,
					"speed": 88.0,
					"currency_value": 10
				},
				{
					"enemy_type": "melee_chaser",
					"hp": 36,
					"damage": 8,
					"speed": 108.0,
					"currency_value": 10
				},
			]
		)


func _spawn_extraction_attackers(enemy_plan: Array[Dictionary]) -> void:
	if _current_wave_spawner == null or not is_instance_valid(_current_wave_spawner):
		return
	_current_wave_spawner.set_enemy_pool(enemy_plan)
	_current_wave_spawner.trigger_extra_spawn(enemy_plan.size())


## HP变化回调
func _on_hp_changed(current: int, maximum: int) -> void:
	if hp_bar:
		hp_bar.max_value = maximum
		hp_bar.value = current

	# 撤离读条期间受击 → 中断撤离（只有正在读条时才中断）
	if extraction_module != null and extraction_module.get_status() == ExtractionModule.ExtractionStatus.COUNTDOWN:
		extraction_module.abort_extraction()
		_call_ui_manager_method("show_fate_card_notification", "撤离中断：受到攻击！")


## 货币变化回调
func _on_currency_changed(amount: int) -> void:
	if currency_label:
		currency_label.text = "魂: %d" % amount


## crit_on_kill 命运卡片：每次击杀后通知武器树增加一颗暴击堆栈
func _on_kill_for_crit_on_kill() -> void:
	if player != null:
		var wt: Node = player.get_weapon_tree()
		if wt != null and wt.has_method("add_crit_on_kill_stack"):
			wt.call("add_crit_on_kill_stack", 1)


## crit_stacks_changed 信号处理：更新 HUD 暴击计数显示
func _on_crit_stacks_changed(new_count: int) -> void:
	if _ui_manager != null and _ui_manager.has_method("update_crit_stacks"):
		_ui_manager.call("update_crit_stacks", new_count)


## 更新基础UI
func _update_ui() -> void:
	if score_label:
		score_label.text = "Score: %d" % score
	if wave_label:
		wave_label.text = "Floor: %d" % current_floor
	if currency_label:
		currency_label.text = "魂: %d" % GameManager.currency


## 更新风险等级 HUD 显示
func _update_risk_display() -> void:
	if _ui_manager != null and _ui_manager.has_method("update_risk"):
		_ui_manager.update_risk(_run_risk)


## 调试：打印游戏状态
func debug_status() -> String:
	var lines: Array[String] = [
		"RoomGameMode Floor %d" % [current_floor],
		"Score: %d | Room cleared: %s" % [score, _room_cleared_flag]
	]

	if map_manager != null:
		lines.append(map_manager.debug_status())

	return "\n".join(lines)


## ========== 环境命运卡片效果回调方法（由 FateCardEngine._apply_* 调用）==========


## 触发额外波次（REINFORCE_WAVE）
func trigger_extra_wave() -> void:
	print("[RoomGameMode] 触发额外波次（环境命运: 敌增援）")
	var ws = _current_wave_spawner
	if ws != null and ws.has_method("trigger_extra_spawn"):
		ws.trigger_extra_spawn()


## 设置下次开箱品质提升（LUCKY_CHEST）
func set_next_chest_quality_boost(boost: int) -> void:
	print("[RoomGameMode] 设置下次开箱品质提升: +%d" % boost)
	var ct := _get_next_available_container()
	if ct != null:
		ct.set_quality_boost(boost)


## 设置下次开箱额外掉落（EXTRA_LOOT）
func set_extra_loot_next_chest(enabled: bool) -> void:
	print("[RoomGameMode] 设置下次开箱额外掉落: %s" % enabled)
	var ct := _get_next_available_container()
	if ct != null:
		ct.set_extra_loot(enabled)


func _get_next_available_container() -> ContainerInteraction:
	var room_node: Node = _get_current_room_instance()
	for ct in _get_container_interactions(room_node):
		if not ct.is_opened():
			return ct
	return null


## 对当前房间敌人施加诅咒（CURSE_ROOM_ENEMIES）
func apply_curse_to_current_room(damage_multiplier: float) -> void:
	print("[RoomGameMode] 对当前房间施加诅咒: 伤害×%.2f" % damage_multiplier)
	var room_node = null
	if map_manager != null:
		var current_room_id = map_manager.get_current_room_id()
		room_node = map_manager.get_instantiated_room(current_room_id)
	if room_node != null:
		for child in room_node.get_children():
			if child.has_method("apply_damage_multiplier"):
				child.apply_damage_multiplier(damage_multiplier)


## 应用亡者祝福（BLESS_DEAD）
func apply_bless_dead(hp_threshold: float, survive_duration: float, damage_bonus: float) -> void:
	print(
		(
			"[RoomGameMode] 应用亡者祝福: HP<%.0f%%存活%.0f秒->伤害+%.0f%%"
			% [hp_threshold * 100.0, survive_duration, damage_bonus * 100.0]
		)
	)
	_bless_dead_config = {
		"hp_threshold": hp_threshold,
		"survive_timer": survive_duration,
		"damage_bonus": damage_bonus,
		"active": false,
	}
	if not GameManager.hp_changed.is_connected(_on_bless_dead_hp_check):
		GameManager.hp_changed.connect(_on_bless_dead_hp_check)


var _bless_dead_config: Dictionary = {}
var _bless_dead_timer: SceneTreeTimer = null


func _on_bless_dead_hp_check(current: int, maximum: int) -> void:
	if _bless_dead_config.is_empty() or _bless_dead_config.get("active", false):
		return
	var threshold_ratio: float = _bless_dead_config.get("hp_threshold", 0.3)
	if float(current) / float(maximum) <= threshold_ratio:
		_bless_dead_config["active"] = true
		print("[RoomGameMode] 亡者祝福已激活！HP<%.0f%%，等待存活%.0f秒后生效" % [
			threshold_ratio * 100.0,
			_bless_dead_config.get("survive_timer", 30.0)
		])
		# 开始存活计时，计时结束后应用伤害加成
		if is_instance_valid(_bless_dead_timer):
			_bless_dead_timer.timeout.disconnect(_on_bless_dead_survive_timeout)
			_bless_dead_timer = null
		_bless_dead_timer = get_tree().create_timer(_bless_dead_config.get("survive_timer", 30.0))
		if _bless_dead_timer.timeout.is_connected(_on_bless_dead_survive_timeout):
			_bless_dead_timer.timeout.disconnect(_on_bless_dead_survive_timeout)
		_bless_dead_timer.timeout.connect(_on_bless_dead_survive_timeout)


func _on_bless_dead_survive_timeout() -> void:
	# 存活计时结束，应用伤害加成
	var bonus: float = _bless_dead_config.get("damage_bonus", 0.1)
	if player != null and is_instance_valid(player):
		if player.has_method("apply_damage_multiplier"):
			player.apply_damage_multiplier(1.0 + bonus)
		print("[RoomGameMode] 亡者祝福生效！伤害+%.0f%%（永久）" % (bonus * 100.0))
		if _ui_manager != null and _ui_manager.has_method("show_fate_card_notification"):
			_ui_manager.show_fate_card_notification("亡者祝福生效：伤害+%.0f%%（永久）" % (bonus * 100.0))
