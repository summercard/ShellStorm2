class_name GameUIManager
## 游戏 UI 总管理器
## 独立管理所有游戏界面元素，与 RoomGameMode 解耦
## RoomGameMode 通过 signal 通知 UI 更新，UI Manager 订阅 signal

extends CanvasLayer

## 物品使用处理器引用（通过脚本路径获取，避免循环依赖）
const _ITEM_USE_HANDLER_PATH := "res://src/game/ItemUseHandler.gd"

## — 游戏状态 UI —
@onready var hp_bar: ProgressBar = $GameHUD/HPBarBG/HPBar
@onready var dash_cooldown_bar: ProgressBar = $GameHUD/DashCooldownBG/DashCooldownBar
@onready var score_label: Label = $GameHUD/TopRightPanel/VBox/ScoreLabel
@onready var wave_label: Label = $GameHUD/TopRightPanel/VBox/WaveLabel
@onready var currency_label: Label = $GameHUD/CurrencyLabel
@onready var room_info_label: Label = $GameHUD/RoomInfoLabel
@onready var clearing_progress: ProgressBar = $GameHUD/ClearingProgress
@onready var minimap_panel: PanelContainer = $GameHUD/MiniMapPanel
@onready var minimap_view: ReferenceRect = $GameHUD/MiniMapPanel/MiniMapView

## — 弹药 UI —
@onready var ammo_panel: PanelContainer = $GameHUD/AmmoPanel
@onready var ammo_bar: ProgressBar = $GameHUD/AmmoPanel/AmmoBar
@onready var ammo_label: Label = $GameHUD/AmmoPanel/AmmoLabel
@onready var reload_indicator: Label = $GameHUD/AmmoPanel/ReloadIndicator
var _is_reloading: bool = false
var _reload_progress: float = 0.0
var _reload_duration: float = 0.0

## — 背包 UI —
@onready var inventory_panel: PanelContainer = $InventoryPanel
@onready var inventory_capacity_label: Label = $InventoryPanel/VBox/CapacityLabel
@onready var inventory_grid: GridContainer = $InventoryPanel/VBox/InventoryGrid
@onready var insurance_panel: PanelContainer = $InsurancePanel
@onready var insurance_label: Label = $InsurancePanel/VBox/InsuranceLabel
@onready var insurance_grid: GridContainer = $InsurancePanel/VBox/InsuranceGrid

## — 撤离 UI —
@onready var extraction_panel: PanelContainer = $ExtractionPanel
@onready var extraction_type_label: Label = $ExtractionPanel/VBox/ExtractionTypeLabel
@onready var extraction_buttons_container: VBoxContainer = $ExtractionPanel/VBox/ExtractionButtons
@onready var countdown_bar: ProgressBar = $ExtractionPanel/VBox/CountdownBar
@onready var countdown_label: Label = $ExtractionPanel/VBox/CountdownLabel
@onready var beacon_label: Label = $ExtractionPanel/VBox/BeaconLabel
@onready var abort_button: Button = $ExtractionPanel/VBox/AbortButton

var _extraction_types: Array[String] = ["STANDARD", "BEACON", "BOSS_KILL", "ELITE_KILL", "TRADE"]
var _beacon_count: int = 0

## — 命运卡片 UI —
@onready var fate_card_panel: Control = $FateCardPanel
var _fate_card_card_container: HBoxContainer = null        ## 卡片按钮容器
var _fate_card_instruction: Label = null                ## 提示标签
var _fate_card_panel_base: Control = null  ## 命运卡片选择面板容器（Control 类型，与场景一致）
var _wave_kill_anim_tween: Tween = null
var _wave_indicator_label: Label = null  ## 波次指示器（运行时获取）
var _wave_outline_label: Label = null  ## 波次描边标签（与 WaveIndicatorLabel 配合）
var _score_outline_label: Label = null  ## 分数描边标签
var _currency_outline_label: Label = null  ## 货币描边标签
var _wave_num_outline_label: Label = null  ## 楼层描边标签
var _ammo_outline_label: Label = null  ## 弹药描边标签
var _fate_card_notification_label: Label = null  ## 命运卡片提示标签
var _fate_card_notification_timer: float = 0.0  ## 提示显示计时器
const _FATE_CARD_NOTIFICATION_DURATION: float = 4.0  ## 提示显示4秒

var _screen_shake: Node = null  ## ScreenShake 引用（用于震屏反馈）
var _health_vignette: Control = null  ## 低血量 Vignette 引用

var _room_game_mode: Node = null
var _inventory_module: Object = null
var _extraction_module: Object = null
var _insurance_module: Object = null
var _inventory_ui: Control = null  ## InventoryUI 引用（由本类实例化）
var _extraction_director: Node = null  ## ExtractionDirector 引用（用于信标撤离计数）
var _run_choice_overlay: Control = null
var _run_choice_kind: String = ""

## — 小地图 UI（PH11）—
var _minimap_panel: PanelContainer = null
var _minimap_view: ReferenceRect = null
var _minimap_dirty: bool = false  ## 标记需要重绘
var _minimap_nodes: Array[Dictionary] = []  ## 当前地图节点缓存
var _minimap_player_node_id: int = -1  ## 玩家所在节点ID

## — 游戏结束界面 —
var death_overlay: ColorRect
var game_over_panel: PanelContainer
var death_title: Label
var reason_label: Label
var stats_label: Label
var loot_label: Label
var retry_button: Button
var menu_button: Button

## — 撤离成功面板 —
var extraction_success_panel: PanelContainer
var extracted_count_label: Label
var extracted_items_vbox: VBoxContainer
var continue_button: Button

var _death_stats: Dictionary = {"score": 0, "kills": 0, "floor": 1}
var _death_loot: Dictionary = {"saved": 0, "lost": 0}
var _kill_count: int = 0

## 背包物品操作信号
signal item_to_insurance_requested(slot_index: int)
signal item_extraction_requested(slot_index: int)
signal inventory_ui_changed()
signal fate_choice_selected(choice_id: String)
signal extraction_choice_selected(choice_id: String)

func _ready() -> void:
	# 注册为 game_ui 组（供 ContainerInteraction 等通过 group call 触发 UI 方法）
	add_to_group("game_ui")
	_ensure_hud_layout()

	# 延迟获取子节点（避免 CanvasLayer @onready 路径问题）
	death_overlay = get_node_or_null("DeathOverlay")
	game_over_panel = get_node_or_null("GameOverPanel")
	death_title = get_node_or_null("GameOverPanel/VBox/DeathTitle")
	reason_label = get_node_or_null("GameOverPanel/VBox/ReasonLabel")
	stats_label = get_node_or_null("GameOverPanel/VBox/StatsLabel")
	loot_label = get_node_or_null("GameOverPanel/VBox/LootLabel")
	retry_button = get_node_or_null("GameOverPanel/VBox/RetryButton")
	menu_button = get_node_or_null("GameOverPanel/VBox/MenuButton")

	# 初始隐藏
	if extraction_panel:
		extraction_panel.visible = false
		if abort_button:
			abort_button.pressed.connect(_on_abort_button_pressed)
	if inventory_panel:
		inventory_panel.visible = false
	if fate_card_panel:
		fate_card_panel.visible = false
	if clearing_progress:
		clearing_progress.visible = false
	if death_overlay:
		death_overlay.visible = false
	if game_over_panel:
		game_over_panel.visible = false

	# 绑定按钮信号
	if retry_button:
		retry_button.pressed.connect(_on_retry_pressed)
	if menu_button:
		menu_button.pressed.connect(_on_menu_pressed)

	# 撤离成功面板节点获取
	extraction_success_panel = get_node_or_null("ExtractionSuccessPanel")
	extracted_count_label = get_node_or_null("ExtractionSuccessPanel/VBox/ExtractedCountLabel")
	extracted_items_vbox = get_node_or_null("ExtractionSuccessPanel/VBox/ScrollContainer/ItemsVBox")
	continue_button = get_node_or_null("ExtractionSuccessPanel/VBox/ContinueButton")
	if extraction_success_panel:
		extraction_success_panel.visible = false
		if continue_button:
			continue_button.pressed.connect(_on_continue_pressed)

	# 构建背包和保险格 UI
	_build_inventory_grid()
	_build_insurance_grid()
	if insurance_panel:
		insurance_panel.visible = false

	# 监听存入/取出信号（自连接）
	item_to_insurance_requested.connect(_on_item_to_insurance_requested)
	item_extraction_requested.connect(_on_item_extraction_requested)

	# 初始化命运卡片提示标签（复用 GameHUD 中的 WaveIndicatorLabel）
	_fate_card_notification_label = get_node_or_null("GameHUD/WaveIndicatorLabel")
	if _fate_card_notification_label:
		_fate_card_notification_label.visible = false

	# 初始化 ScreenShake 引用（从 Camera2D 子节点获取）
	_screen_shake = get_node_or_null("Camera2D/ScreenShake")
	if not _screen_shake:
		_screen_shake = get_tree().root.find_child("ScreenShake", true, false)

	# 初始化低血量 Vignette（HealthVignette 挂为本类子节点）
	_health_vignette = load("res://src/fx/HealthVignette.tscn").instantiate()
	add_child(_health_vignette)

func _ensure_hud_layout() -> void:
	var hud := get_node_or_null("GameHUD") as Control
	if hud == null:
		return
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.offset_left = 0
	hud.offset_top = 0
	hud.offset_right = 0
	hud.offset_bottom = 0

## 绑定房间游戏模式
func set_room_game_mode(mode: Node) -> void:
	_room_game_mode = mode
	_init_minimap()

	if mode == null or not is_instance_valid(mode):
		return

	# 连接信号。这里要防止重复连接；UI 重新绑定时 Godot 会报 Signal already connected。
	if mode.has_signal("room_cleared") and not mode.room_cleared.is_connected(_on_room_cleared):
		mode.room_cleared.connect(_on_room_cleared)
	if mode.has_signal("game_over") and not mode.game_over.is_connected(_on_game_over):
		mode.game_over.connect(_on_game_over)
	if mode.has_signal("extraction_ready") and not mode.extraction_ready.is_connected(_on_extraction_ready):
		mode.extraction_ready.connect(_on_extraction_ready)
	if mode.has_signal("floor_changed") and not mode.floor_changed.is_connected(_on_floor_changed):
		mode.floor_changed.connect(_on_floor_changed)
	if mode.has_signal("kill_recorded") and not mode.kill_recorded.is_connected(_on_kill_recorded):
		mode.kill_recorded.connect(_on_kill_recorded)
	if mode.has_signal("wave_progress_changed") and not mode.wave_progress_changed.is_connected(_on_wave_progress_changed):
		mode.wave_progress_changed.connect(_on_wave_progress_changed)
	# 小地图随地图生成和房间切换刷新
	if mode.has_signal("map_generated") and not mode.map_generated.is_connected(_on_map_generated_for_minimap):
		mode.map_generated.connect(_on_map_generated_for_minimap)
	if mode.has_signal("room_entered") and not mode.room_entered.is_connected(_on_room_entered_for_minimap):
		mode.room_entered.connect(_on_room_entered_for_minimap)
	if mode.has_signal("adjacent_rooms_revealed") and not mode.adjacent_rooms_revealed.is_connected(_on_adjacent_rooms_revealed):
		mode.adjacent_rooms_revealed.connect(_on_adjacent_rooms_revealed)

## 绑定玩家（用于闪避冷却条等）
func set_player(player: Node) -> void:
	if player and player.has_signal("dash_cooldown_changed") and not player.dash_cooldown_changed.is_connected(_on_dash_cooldown_changed):
		player.dash_cooldown_changed.connect(_on_dash_cooldown_changed)
	if player and player.has_signal("dash_started") and not player.dash_started.is_connected(_on_dash_started):
		player.dash_started.connect(_on_dash_started)
	# 让低血量 Vignette 直接监听玩家 HP 信号
	if _health_vignette and _health_vignette.has_method("set_player_ref"):
		_health_vignette.set_player_ref(player)
	# 连接武器弹药信号
	_bind_weapon_signals(player)

func _bind_weapon_signals(player: Node) -> void:
	if player == null or not is_instance_valid(player):
		return
	var wt = player.get_weapon_tree() if player.has_method("get_weapon_tree") else null
	if wt != null:
		if not wt.ammo_changed.is_connected(_on_ammo_changed):
			wt.ammo_changed.connect(_on_ammo_changed.bind())
		if not wt.reload_started.is_connected(_on_reload_started):
			wt.reload_started.connect(_on_reload_started.bind())
		if not wt.weapon_reloaded.is_connected(_on_weapon_reloaded):
			wt.weapon_reloaded.connect(_on_weapon_reloaded.bind())
	else:
		# Player 还没准备好，等一下再试
		await get_tree().create_timer(0.5).timeout
		if player and is_instance_valid(player) and player.has_method("get_weapon_tree"):
			_bind_weapon_signals(player)

## 绑定背包模块
func set_inventory_module(module: Object) -> void:
	_inventory_module = module
	if module == null:
		return
	if module.has_signal("inventory_changed") and not module.inventory_changed.is_connected(_on_inventory_changed):
		module.inventory_changed.connect(_on_inventory_changed)
	if module.has_signal("capacity_changed") and not module.capacity_changed.is_connected(_on_capacity_changed):
		module.capacity_changed.connect(_on_capacity_changed)
	_refresh_inventory_ui()
	_on_inventory_changed()

## 绑定保险格模块
func set_insurance_module(module: Object) -> void:
	_insurance_module = module
	if module == null:
		return
	if module.has_signal("insurance_changed") and not module.insurance_changed.is_connected(_on_insurance_changed):
		module.insurance_changed.connect(_on_insurance_changed)
	_refresh_insurance_ui()

## 绑定撤离模块
func set_extraction_module(module: Object) -> void:
	_extraction_module = module
	if module != null:
		_connect_extraction_module_signals(module)

## 更新 HP 显示
func update_hp(current: int, maximum: int) -> void:
	if hp_bar:
		hp_bar.max_value = maximum
		hp_bar.value = current

## 更新分数（带跳动动画 + 描边）
func update_score(score_val: int) -> void:
	if score_label:
		score_label.text = "Score: %d" % score_val
		_bounce_label(score_label)
		_sync_score_outline()

## 击杀记录
func _on_kill_recorded() -> void:
	_kill_count += 1

## 更新货币（带跳动动画 + 描边）
func update_currency(amount: int) -> void:
	if currency_label:
		currency_label.text = "魂: %d" % amount
		_bounce_label(currency_label)
		_sync_currency_outline()

## 连接 ExtractionModule 信号（由 set_extraction_module 调用）
func _connect_extraction_module_signals(module: Object) -> void:
	if module == null:
		return
	if module.has_signal("extraction_completed") and not module.extraction_completed.is_connected(_on_extraction_completed):
		module.extraction_completed.connect(_on_extraction_completed)
	if module.has_signal("extraction_progress_updated") and not module.extraction_progress_updated.is_connected(_on_extraction_progress_updated):
		module.extraction_progress_updated.connect(_on_extraction_progress_updated)
	if module.has_signal("extraction_aborted") and not module.extraction_aborted.is_connected(_on_extraction_aborted):
		module.extraction_aborted.connect(_on_extraction_aborted)

## 撤离读条进度更新
func _on_extraction_progress_updated(progress: float) -> void:
	if countdown_bar:
		countdown_bar.value = progress
		var total: float = countdown_bar.max_value
		var remaining: float = (1.0 - progress) * total
		_update_countdown_label(remaining, total)

## 显示货币飘字（在指定世界坐标显示 +N魂 飘字）
## world_pos: 世界坐标（会被转换到 CanvasLayer 坐标系）
## amount: 货币数量（正数显示为绿色 +N魂，负数显示为红色 -N魂）
func show_currency_popup(amount: int, world_pos: Vector2) -> void:
	var popup_label := Label.new()
	popup_label.text = "+%d魂" % amount if amount > 0 else "%d魂" % amount
	popup_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4, 1.0) if amount > 0 else Color(1.0, 0.3, 0.3, 1.0))
	popup_label.add_theme_font_size_override("font_size", 16)
	popup_label.z_index = 200  # 在 UI 层之上

	# 转换世界坐标到 CanvasLayer 局部坐标
	var canvas_pos: Vector2 = _world_to_canvas(world_pos)
	popup_label.global_position = canvas_pos

	# 添加到 CanvasLayer（使用 z_index 排序）
	add_child(popup_label)

	# 上浮动画：Y -60像素，透明度 1→0，1.5秒
	var tween := popup_label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(popup_label, "position:y", canvas_pos.y - 60, 1.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(popup_label, "modulate:a", 0.0, 0.5).set_delay(1.0)
	await tween.finished
	if popup_label and is_instance_valid(popup_label):
		popup_label.queue_free()

func show_damage_popup(world_pos: Vector2, damage: int, is_crit: bool = false) -> void:
	var label := Label.new()
	label.text = str(damage) + ("!" if is_crit else "")
	label.add_theme_font_size_override("font_size", 28 if is_crit else 18)
	label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.15, 1.0) if is_crit else Color(1.0, 0.36, 0.18, 1.0))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.z_index = 260
	var start_pos := _world_to_canvas(world_pos) + Vector2(randf_range(-10, 10), -28 + randf_range(-6, 6))
	label.position = start_pos
	add_child(label)

	var shadow := Label.new()
	shadow.text = label.text
	shadow.add_theme_font_size_override("font_size", label.get_theme_font_size("font_size"))
	shadow.add_theme_color_override("font_color", Color(0, 0, 0, 0.7))
	shadow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shadow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	shadow.position = start_pos + Vector2(2, 2)
	shadow.z_index = label.z_index - 1
	add_child(shadow)

	label.scale = Vector2(1.25, 1.25)
	shadow.scale = label.scale
	var end_y := start_pos.y - (64.0 if is_crit else 48.0)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", end_y, 0.75).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(label, "modulate:a", 0.0, 0.75).set_trans(Tween.TRANS_LINEAR)
	tween.tween_property(label, "scale", Vector2(0.85, 0.85), 0.75).set_trans(Tween.TRANS_LINEAR)
	tween.tween_property(shadow, "position:y", end_y + 2, 0.75).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(shadow, "modulate:a", 0.0, 0.75).set_trans(Tween.TRANS_LINEAR)
	tween.tween_property(shadow, "scale", Vector2(0.85, 0.85), 0.75).set_trans(Tween.TRANS_LINEAR)
	tween.chain().tween_callback(func():
		if is_instance_valid(label):
			label.queue_free()
		if is_instance_valid(shadow):
			shadow.queue_free()
	)

## 世界坐标 → CanvasLayer 局部坐标
func _world_to_canvas(world_pos: Vector2) -> Vector2:
	var viewport := get_viewport()
	if viewport == null:
		return world_pos
	var camera := viewport.get_camera_2d()
	if camera == null:
		return world_pos
	var viewport_size := viewport.get_visible_rect().size
	return (world_pos - camera.get_screen_center_position()) * camera.zoom + viewport_size * 0.5

## 容器开启时显示物品获得飘字（由 ContainerInteraction 通过 group call 触发）
func _on_container_loot_granted(world_pos: Vector2, items: Array[Dictionary], granted_count: int) -> void:
	if items.is_empty():
		return

	# 将世界坐标转为 CanvasLayer 局部坐标
	var canvas_pos: Vector2 = _world_to_canvas(world_pos)

	# 如果只获得一件，直接飘字
	# 如果获得多件，显示汇总 + 逐件序列飘字
	var total_count: int = 0
	for item_data in items:
		total_count += item_data.get("count", 1)

	var popup_label := Label.new()
	popup_label.z_index = 200
	popup_label.add_theme_font_size_override("font_size", 14)
	popup_label.modulate = Color(1.0, 0.88, 0.55, 1.0)  # 金黄色

	if granted_count == 1:
		var item_name: String = items[0].get("name", items[0].get("id", "物品"))
		var count: int = items[0].get("count", 1)
		popup_label.text = "+%s x%d" % [item_name, count] if count > 1 else "+%s" % item_name
		popup_label.global_position = canvas_pos
		add_child(popup_label)
		_fly_and_fade(popup_label, canvas_pos)
	else:
		# 多件物品：显示汇总，后续逐件飘字（偏移）
		popup_label.text = "+%d 件物品" % granted_count
		popup_label.global_position = canvas_pos
		add_child(popup_label)
		_fly_and_fade(popup_label, canvas_pos)
		# 后续物品依次偏移飘出
		for i in range(min(items.size(), 5)):
			await get_tree().create_timer(0.18 + i * 0.12).timeout
			var item_data: Dictionary = items[i]
			var item_name: String = item_data.get("name", item_data.get("id", "?"))
			var count: int = item_data.get("count", 1)
			var offset_pos: Vector2 = canvas_pos + Vector2(randi() % 40 - 20, -30 - i * 20)
			var item_label := Label.new()
			item_label.z_index = 200
			item_label.add_theme_font_size_override("font_size", 12)
			item_label.modulate = Color(0.8, 0.8, 0.6, 0.9)
			item_label.text = "+%s x%d" % [item_name, count] if count > 1 else "+%s" % item_name
			item_label.global_position = offset_pos
			add_child(item_label)
			_fly_and_fade(item_label, offset_pos)

## 小地图刷新信号处理
func _on_map_generated_for_minimap(graph: NodeGraph) -> void:
	_minimap_dirty = true

func _on_room_entered_for_minimap(room_data: RoomData) -> void:
	_minimap_dirty = true
	# 根据房间类型更新 room_info_label（中文显示）
	if room_info_label and room_data != null:
		var type_name := ""
		match room_data.room_type:
			RoomData.RoomType.PLAYER_SPAWN: type_name = "玩家出生"
			RoomData.RoomType.COMBAT: type_name = "普通战斗"
			RoomData.RoomType.ELITE: type_name = "精英战斗"
			RoomData.RoomType.SCAVENGE: type_name = "搜刮"
			RoomData.RoomType.MERCHANT: type_name = "商人"
			RoomData.RoomType.UPGRADE: type_name = "改造"
			RoomData.RoomType.EVENT: type_name = "事件"
			RoomData.RoomType.EXTRACTION: type_name = "撤离"
			RoomData.RoomType.BOSS: type_name = "Boss"
			_: type_name = "房间"
		room_info_label.text = type_name

## 小地图 REVEAL 事件信号处理（地图揭示后刷新小地图）
func _on_adjacent_rooms_revealed(room_id: String, revealed_count: int) -> void:
	print("[GameUIManager] 小地图刷新：REVEAL事件揭示了 %d 个相邻房间 from room %s" % [revealed_count, room_id])
	# 重建小地图节点数据（读取 MapManager 中已更新的 revealed 元数据）
	_refresh_minimap_nodes()
	_minimap_dirty = true

## 飘字动画：Y 上浮 + 淡出消失
func _fly_and_fade(label: Label, start_pos: Vector2) -> void:
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", start_pos.y - 50, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(label, "modulate:a", 0.0, 0.5).set_delay(0.7)
	await tween.finished
	if label and is_instance_valid(label):
		label.queue_free()

## 更新楼层
func update_floor(floor: int) -> void:
	if wave_label:
		wave_label.text = "Floor: %d" % floor
		_bounce_label(wave_label)
		_sync_wave_outline()

## — 小地图绘制（PH11 P1）—
func _init_minimap() -> void:
	_minimap_panel = minimap_panel
	_minimap_view = minimap_view
	if _minimap_view and not _minimap_view.resized.is_connected(_on_minimap_view_resized):
		_minimap_view.resized.connect(_on_minimap_view_resized)
	_minimap_dirty = true

func _on_minimap_view_resized() -> void:
	_minimap_dirty = true

func _refresh_minimap_nodes() -> void:
	_minimap_nodes.clear()
	_minimap_player_node_id = -1
	if _room_game_mode == null or not _room_game_mode.has_method("get_map_manager"):
		return
	var mm = _room_game_mode.get_map_manager()
	var graph: NodeGraph = mm.get_graph() if mm else null
	if graph == null:
		return
	var nodes: Array = graph.get_all_nodes()
	var current_room_id: int = mm.get_current_room_id() if mm.has_method("get_current_room_id") else -1
	var view_size: Vector2 = _minimap_view.size if _minimap_view else Vector2(164, 164)
	var map_rect: Rect2 = _calc_map_bounds(nodes)

	# 获取玩家世界位置（用于计算小地图玩家点偏移）
	var player_world_pos: Vector2 = Vector2.ZERO
	var player_ref: Node = mm.get_player() if mm.has_method("get_player") else null
	if player_ref and is_instance_valid(player_ref):
		player_world_pos = player_ref.global_position

	for node in nodes:
		var rd: RoomData = node.room_data
		var color: Color = _get_room_color(rd.room_type)
		var pos: Vector2
		if map_rect.size.x > 0 and map_rect.size.y > 0:
			var norm: Vector2 = (node.position - map_rect.position) / map_rect.size
			pos = Vector2(norm.x * view_size.x, norm.y * view_size.y)
		else:
			pos = Vector2(view_size.x * 0.5, view_size.y * 0.5)
		_minimap_nodes.append({
			"id": node.id,
			"pos": pos,
			"node_pos": node.position,  # 房间世界坐标（计算玩家相对偏移用）
			"color": color,
			"type": rd.room_type,
			"is_current": node.id == current_room_id,
			"connections": node.connections.duplicate(),
			"revealed": rd.get_meta("revealed") if rd.has_meta("revealed") else false,
		})
	_minimap_dirty = true

func _calc_map_bounds(nodes: Array) -> Rect2:
	if nodes.is_empty():
		return Rect2(0, 0, 1, 1)
	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF
	for node in nodes:
		min_x = minf(min_x, node.position.x)
		min_y = minf(min_y, node.position.y)
		max_x = maxf(max_x, node.position.x)
		max_y = maxf(max_y, node.position.y)
	var pad := 50.0
	return Rect2(min_x - pad, min_y - pad, (max_x - min_x) + pad * 2, (max_y - min_y) + pad * 2)

func _get_room_color(room_type: int) -> Color:
	match room_type:
		0: return Color(0.5, 1.0, 0.5, 0.9)
		1: return Color(1.0, 0.3, 0.3, 0.9)
		2: return Color(1.0, 0.6, 0.1, 0.9)
		3: return Color(0.3, 0.8, 1.0, 0.9)
		4: return Color(1.0, 0.85, 0.2, 0.9)
		5: return Color(0.6, 0.4, 1.0, 0.9)
		6: return Color(0.9, 0.3, 0.9, 0.9)
		7: return Color(0.2, 1.0, 0.6, 0.9)
		8: return Color(1.0, 0.1, 0.1, 1.0)
		_: return Color(0.7, 0.7, 0.7, 0.9)

func _draw_minimap_rserver(canvas: RID) -> void:
	if _minimap_nodes.is_empty():
		return
	var view_size: Vector2 = _minimap_view.size if _minimap_view else Vector2(164, 164)
	RenderingServer.canvas_item_add_rect(canvas, Rect2(Vector2.ZERO, view_size), Color(0.07, 0.07, 0.12, 0.95))

	# 计算玩家当前房间的相对偏移（用于在当前房间节点上显示玩家位置）
	var player_local_offset: Vector2 = Vector2.ZERO
	var player_node_pos: Vector2 = Vector2.ZERO  # 当前房间节点的世界坐标
	var map_rect: Rect2 = _calc_map_bounds(_minimap_nodes)

	# 获取玩家世界坐标
	var player_world_pos: Vector2 = Vector2.ZERO
	if _room_game_mode and _room_game_mode.has_method("get_player"):
		var p: Node = _room_game_mode.get_player()
		if p and is_instance_valid(p):
			player_world_pos = p.global_position

	# 找到当前房间节点（is_current=true）的世界坐标
	for nd in _minimap_nodes:
		if nd.get("is_current", false):
			player_node_pos = nd.get("node_pos", Vector2.ZERO)
			break

	# 计算玩家在当前房间内的相对偏移（归一化到小地图视图内）
	if map_rect.size.x > 0 and map_rect.size.y > 0 and player_node_pos != Vector2.ZERO:
		var rel: Vector2 = (player_world_pos - player_node_pos) / map_rect.size
		# 限制最大偏移不超过房间节点大小的2倍
		var max_offset: float = minf(view_size.x, view_size.y) * 0.25
		player_local_offset = rel * maxf(view_size.x, view_size.y) * 0.5
		player_local_offset = Vector2(
			clamp(player_local_offset.x, -max_offset, max_offset),
			clamp(player_local_offset.y, -max_offset, max_offset)
		)

	# 绘制连接线
	for node_data in _minimap_nodes:
		var pos: Vector2 = node_data["pos"]
		for conn_id in node_data["connections"]:
			var conn_pos: Vector2 = _get_node_pos_by_id(conn_id)
			RenderingServer.canvas_item_add_line(canvas, pos, conn_pos, Color(0.3, 0.3, 0.4, 0.7), 1.0)

	# 绘制房间节点（未揭示的房间降低透明度）
	for node_data in _minimap_nodes:
		var pos: Vector2 = node_data["pos"]
		var color: Color = node_data["color"]
		var is_current: bool = node_data["is_current"]
		var is_revealed: bool = node_data.get("revealed", false)
		# 未揭示且非当前房间：降低透明度并缩小
		if not is_revealed and not is_current:
			color.a = 0.25
		var node_size := 8.0
		if is_current:
			node_size = 12.0
			RenderingServer.canvas_item_add_rect(canvas, Rect2(pos - Vector2(node_size + 3, node_size + 3), Vector2((node_size + 3) * 2, (node_size + 3) * 2)), Color(1.0, 1.0, 1.0, 0.35))
		RenderingServer.canvas_item_add_rect(canvas, Rect2(pos - Vector2(node_size, node_size), Vector2(node_size * 2, node_size * 2)), color)

	# 绘制玩家位置点（白色小圆点，跟随玩家在当前房间内的实际位置偏移）
	var current_node_pos: Vector2 = Vector2.ZERO
	for nd in _minimap_nodes:
		if nd.get("is_current", false):
			current_node_pos = nd.get("pos", Vector2.ZERO)
			break
	if current_node_pos != Vector2.ZERO:
		var player_dot_pos: Vector2 = current_node_pos + player_local_offset
		# 玩家点：白色填充圆（用小矩形模拟点）
		RenderingServer.canvas_item_add_rect(canvas, Rect2(player_dot_pos - Vector2(2.5, 2.5), Vector2(5, 5)), Color(1.0, 1.0, 1.0, 1.0))
		# 外圈高亮（表示玩家）
		RenderingServer.canvas_item_add_rect(canvas, Rect2(player_dot_pos - Vector2(4, 4), Vector2(8, 8)), Color(0.4, 0.8, 1.0, 0.4))

func _get_node_pos_by_id(node_id: int) -> Vector2:
	for nd in _minimap_nodes:
		if nd.get("id") == node_id:
			return nd.get("pos")
	return Vector2.ZERO

func refresh_minimap() -> void:
	_minimap_dirty = true

func _draw() -> void:
	if _minimap_view == null or _minimap_nodes.is_empty():
		return
	# ReferenceRect/Control 本身才有可绘制的 CanvasItem RID；避免调用不存在的 get_top_level_rc()。
	_draw_minimap_rserver(_minimap_view.get_canvas_item())

## 房间清理完成
func _on_room_cleared(room_data) -> void:
	if room_info_label:
		room_info_label.text = "房间清理完成！"
	clearing_progress.visible = false
	# 显示命运卡片提示
	_show_fate_card_notification()
	# 波次完成庆祝：飘字 + 震屏（Boss 房显示"Boss 已击败！"）
	var room_type_val: int = -1
	if room_data is RoomData:
		room_type_val = int(room_data.room_type)
	elif room_data is Dictionary and room_data.has("room_type"):
		room_type_val = int(room_data.get("room_type", -1))
	_show_wave_complete_celebration(room_type_val)

## 波次完成庆祝飘字（金色大字，居中屏幕）
func _show_wave_complete_celebration(room_type: int = -1) -> void:
	# 根据房间类型选择文案：Boss 房显示"Boss 已击败！"否则显示"房间清理完成！"
	var is_boss_room: bool = room_type == 8  # RoomData.RoomType.BOSS = 8
	var message: String = "Boss 已击败！" if is_boss_room else "房间清理完成！"
	var celebration_label := Label.new()
	celebration_label.text = message
	celebration_label.z_index = 300
	celebration_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	celebration_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# 金黄色，带描边感的深色阴影
	celebration_label.add_theme_font_size_override("font_size", 28)
	celebration_label.modulate = Color(1.0, 0.92, 0.4, 1.0)

	# 居中屏幕（顶层 label，position 无意义，靠 anchors 居中）
	celebration_label.set_anchors_preset(Control.PRESET_CENTER)
	celebration_label.position = Vector2.ZERO
	add_child(celebration_label)

	# 初始状态：透明 + 缩小
	celebration_label.modulate.a = 0.0
	celebration_label.scale = Vector2(0.6, 0.6)

	# 缩放入场（0.3s）→ 停留（0.8s）→ 上升飘出 + 淡出（0.6s）
	var tween := celebration_label.create_tween()
	tween.set_parallel(true)
	# 入场动画
	tween.tween_property(celebration_label, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(celebration_label, "scale", Vector2(1.0, 1.0), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 停留 0.8s
	tween.chain().set_parallel(false)
	tween.chain().tween_interval(0.8)
	# 飘出 + 淡出
	tween.chain().set_parallel(true)
	tween.tween_property(celebration_label, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_property(celebration_label, "position:y", celebration_label.position.y - 30, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(func():
		if celebration_label and is_instance_valid(celebration_label):
			celebration_label.queue_free()
	)

	# 波次完成震屏效果（比伤害震屏轻，用于强化"完成了"的节拍感）
	if _screen_shake and _screen_shake.has_method("trigger"):
		_screen_shake.call("trigger", 4.0, 0.10)

## — Boss 事件处理器（由 RoomGameMode 调用）—
## Boss 出现时回调（目前仅日志记录，Boss 血条 UI 可后续扩展）
func on_boss_spawned(boss_data: Dictionary) -> void:
	room_info_label.text = "Boss 出现了！"

## Boss 受伤时回调（目前仅日志记录，Boss 血条 UI 可后续扩展）
func on_boss_damaged(boss_id: String, damage: float, new_hp: float) -> void:
	pass  # Boss 血条 UI 后续扩展

## Boss 阶段切换时回调（目前仅日志记录，Boss 血条 UI 可后续扩展）
func on_boss_phase_changed(boss_id: String, new_phase: int) -> void:
	room_info_label.text = "Boss 进入阶段 %d！" % new_phase

## Boss 被击败时回调（目前仅日志记录）
func on_boss_defeated(boss_id: String, rewards: Dictionary) -> void:
	room_info_label.text = "Boss 已击败！"

## 显示命运卡片提示（房间清理后、或出生时）
## 命运卡片触发时短暂屏幕闪光特效（白金色快速闪烁）
func _show_fate_card_notification() -> void:
	if _fate_card_notification_label == null:
		return
	_fate_card_notification_timer = _FATE_CARD_NOTIFICATION_DURATION
	_fate_card_notification_label.visible = true
	_fate_card_notification_label.modulate.a = 0.0
	# 淡入动画
	var tween: Tween = _fate_card_notification_label.create_tween()
	tween.tween_property(_fate_card_notification_label, "modulate:a", 1.0, 0.3)
	# 命运触发时屏幕闪光（快速白色淡入淡出，z_index 高于普通UI）
	_show_fate_card_flash()

## 命运卡片触发时屏幕闪光特效
func _show_fate_card_flash() -> void:
	var flash := ColorRect.new()
	flash.name = "FateFlash"
	flash.anchors_preset = Control.PRESET_FULL_RECT
	flash.offset_left = 0
	flash.offset_top = 0
	flash.offset_right = 0
	flash.offset_bottom = 0
	flash.color = Color(1.0, 0.95, 0.6, 0.0)  # 淡金色闪光
	flash.z_index = 400
	add_child(flash)

	# 快速闪入→淡出（0.2s 闪入 + 0.35s 淡出）
	var ft := flash.create_tween()
	ft.set_parallel(true)
	ft.tween_property(flash, "color:a", 0.18, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ft.chain().set_parallel(false)
	ft.chain().tween_property(flash, "color:a", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	ft.chain().tween_callback(func():
		if flash and is_instance_valid(flash):
			flash.queue_free()
	)

## 显示命运卡片提示（供外部调用，支持自定义文字）
func show_fate_card_notification(message: String = "") -> void:
	if _fate_card_notification_label == null:
		return
	if message != "":
		_fate_card_notification_label.text = message
	_fate_card_notification_label.modulate.a = 1.0
	_fate_card_notification_timer = _FATE_CARD_NOTIFICATION_DURATION
	_fate_card_notification_label.visible = true
	var tween: Tween = _fate_card_notification_label.create_tween()
	tween.tween_property(_fate_card_notification_label, "modulate:a", 1.0, 0.3)
	_show_fate_card_flash()

func show_run_choice_panel(kind: String, title: String, subtitle: String, choices: Array) -> void:
	if _fate_card_notification_label:
		_fate_card_notification_timer = 0.0
		_fate_card_notification_label.visible = false
	_ensure_run_choice_overlay()
	if _run_choice_overlay == null:
		return
	_run_choice_kind = kind
	for child in _run_choice_overlay.get_children():
		child.queue_free()

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.025, 0.035, 0.68)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_run_choice_overlay.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_run_choice_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 330)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title_label := Label.new()
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 28)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.58, 1.0))
	vbox.add_child(title_label)

	var subtitle_label := Label.new()
	subtitle_label.text = subtitle
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle_label.add_theme_font_size_override("font_size", 14)
	subtitle_label.add_theme_color_override("font_color", Color(0.78, 0.86, 0.92, 1.0))
	vbox.add_child(subtitle_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(row)

	for choice in choices:
		var btn := Button.new()
		var choice_id := str(choice.get("id", ""))
		var card_title := str(choice.get("title", choice_id))
		var tag := str(choice.get("tag", "选择"))
		var body := str(choice.get("body", ""))
		btn.text = "%s\n[%s]\n%s" % [card_title, tag, body]
		btn.custom_minimum_size = Vector2(220, 150)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		btn.disabled = bool(choice.get("disabled", false))
		btn.focus_mode = Control.FOCUS_ALL
		btn.add_theme_font_size_override("font_size", 15)
		btn.pressed.connect(_on_run_choice_pressed.bind(kind, choice_id))
		row.add_child(btn)

	_run_choice_overlay.visible = true
	_run_choice_overlay.modulate.a = 0.0
	var tween := _run_choice_overlay.create_tween()
	tween.tween_property(_run_choice_overlay, "modulate:a", 1.0, 0.16)

func hide_run_choice_panel() -> void:
	if _run_choice_overlay:
		_run_choice_overlay.visible = false
		_run_choice_kind = ""

func _ensure_run_choice_overlay() -> void:
	if _run_choice_overlay != null and is_instance_valid(_run_choice_overlay):
		return
	_run_choice_overlay = Control.new()
	_run_choice_overlay.name = "RunChoiceOverlay"
	_run_choice_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_run_choice_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_run_choice_overlay.z_index = 520
	_run_choice_overlay.visible = false
	add_child(_run_choice_overlay)

func _on_run_choice_pressed(kind: String, choice_id: String) -> void:
	hide_run_choice_panel()
	match kind:
		"fate":
			fate_choice_selected.emit(choice_id)
		"extraction":
			extraction_choice_selected.emit(choice_id)

## 命运触发通知别名（兼容 MapFateTriggers 调用）
func show_fate_trigger_notification(trigger_type: String, threshold: int, preview: String) -> void:
	show_fate_card_notification("%s ×%d → %s" % [trigger_type, threshold, preview])

## 隐藏命运卡片提示
func _hide_fate_card_notification() -> void:
	if _fate_card_notification_label == null:
		return
	# 淡出动画
	var tween: Tween = _fate_card_notification_label.create_tween()
	tween.tween_property(_fate_card_notification_label, "modulate:a", 0.0, 0.3)
	await tween.finished
	if _fate_card_notification_label:
		_fate_card_notification_label.visible = false

## 游戏结束
func _on_game_over(reason: String = "未知原因") -> void:
	# 构建死亡统计
	_death_stats["score"] = int(score_label.text.replace("Score: ", "")) if score_label else 0
	_death_stats["floor"] = int(wave_label.text.replace("Floor: ", "")) if wave_label else 1

	if death_title:
		death_title.text = "你已倒下"
	if reason_label:
		reason_label.text = "原因: %s" % reason
	if stats_label:
		stats_label.text = "最终得分: %d\n击毙: %d\n存活楼层: %d" % [
			_death_stats["score"],
			_kill_count,
			_death_stats["floor"]
		]
	if loot_label:
		loot_label.text = "战利品: 保险保住 %d 件 / 损失 %d 件" % [
			_death_loot["saved"],
			_death_loot["lost"]
		]

	if death_overlay:
		death_overlay.visible = true
	if game_over_panel:
		game_over_panel.visible = true
	get_tree().paused = true

## 设置死亡统计（房间模式调用）
func set_death_stats(stats: Dictionary) -> void:
	_death_stats = stats

## 设置战利品信息
func set_loot_info(saved: int, lost: int) -> void:
	_death_loot = {"saved": saved, "lost": lost}
	if loot_label:
		loot_label.text = "战利品: 保险保住 %d 件 / 损失 %d 件" % [saved, lost]

## 标签跳动动画（数值变化时触发）
func _bounce_label(label: Label) -> void:
	if not label:
		return
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "scale", Vector2(1.3, 1.3), 0.08).set_trans(Tween.TRANS_QUAD)
	tween.chain().tween_property(label, "scale", Vector2(1.0, 1.0), 0.12).set_trans(Tween.TRANS_BOUNCE)

## 同步 ScoreLabel 描边
func _sync_score_outline() -> void:
	if score_label == null:
		return
	if _score_outline_label != null:
		_score_outline_label.queue_free()
		_score_outline_label = null
	_score_outline_label = _make_outline(score_label)
	if _score_outline_label != null:
		var parent: Node = score_label.get_parent()
		if parent:
			parent.add_child(_score_outline_label)
			parent.move_child(_score_outline_label, score_label.get_index())

## 同步 CurrencyLabel 描边
func _sync_currency_outline() -> void:
	if currency_label == null:
		return
	if _currency_outline_label != null:
		_currency_outline_label.queue_free()
		_currency_outline_label = null
	_currency_outline_label = _make_outline(currency_label)
	if _currency_outline_label != null:
		var parent: Node = currency_label.get_parent()
		if parent:
			parent.add_child(_currency_outline_label)
			parent.move_child(_currency_outline_label, currency_label.get_index())

## 同步弹药描边（与 ammo_label 配合，弹药数值变化时同步描边副本）
func _sync_ammo_outline() -> void:
	if ammo_label == null:
		return
	if _ammo_outline_label != null:
		_ammo_outline_label.queue_free()
		_ammo_outline_label = null
	_ammo_outline_label = _make_outline(ammo_label)
	if _ammo_outline_label != null:
		var parent: Node = ammo_label.get_parent()
		if parent:
			parent.add_child(_ammo_outline_label)
			parent.move_child(_ammo_outline_label, ammo_label.get_index())

## 同步 WaveLabel 描边
func _sync_wave_outline() -> void:
	if wave_label == null:
		return
	if _wave_num_outline_label != null:
		_wave_num_outline_label.queue_free()
		_wave_num_outline_label = null
	_wave_num_outline_label = _make_outline(wave_label)
	if _wave_num_outline_label != null:
		var parent: Node = wave_label.get_parent()
		if parent:
			parent.add_child(_wave_num_outline_label)
			parent.move_child(_wave_num_outline_label, wave_label.get_index())

## 创建一个标签的描边副本（偏移2px，黑色60%透明度）
func _make_outline(main_label: Label) -> Label:
	if main_label == null:
		return null
	var ol := Label.new()
	ol.text = main_label.text
	ol.position = main_label.position + Vector2(2, 2)
	ol.modulate = Color(0.0, 0.0, 0.0, 0.6)
	ol.z_index = main_label.z_index - 1
	ol.horizontal_alignment = main_label.horizontal_alignment
	ol.vertical_alignment = main_label.vertical_alignment
	if main_label.has_theme_font_size("font_size"):
		ol.add_theme_font_size_override("font_size", main_label.get_theme_font_size("font_size"))
	ol.scale = main_label.scale
	return ol

func _on_retry_pressed() -> void:
	get_tree().paused = false
	death_overlay.visible = false
	game_over_panel.visible = false
	get_tree().reload_current_scene()

func _on_menu_pressed() -> void:
	get_tree().paused = false
	death_overlay.visible = false
	game_over_panel.visible = false
	# 返回基地主界面（而非直接重新开始游戏）
	get_tree().change_scene_to_file("res://scenes/BaseMenu.tscn")

## 楼层变化
func _on_floor_changed(old_f: int, new_f: int) -> void:
	update_floor(new_f)

## 背包变化
func _on_inventory_changed() -> void:
	if inventory_capacity_label and _inventory_module:
		var used = _inventory_module.get_used_slots()
		inventory_capacity_label.text = "背包 %d/12" % used
	# 同步信标数量（背包变化可能影响信标道具）
	_sync_beacon_label_from_inventory()
	_refresh_inventory_ui()

## 容量变化
func _on_capacity_changed(current: int, maximum: int) -> void:
	if inventory_capacity_label:
		inventory_capacity_label.text = "背包 %d/%d" % [current, maximum]
	_refresh_inventory_ui()

## 从背包同步信标数量到UI标签（背包变化或消耗品使用后调用）
func _sync_beacon_label_from_inventory() -> void:
	var ed := _get_extraction_director_safe()
	if ed == null or not ed.has_method("get_beacon_count"):
		return
	_beacon_count = int(ed.get_beacon_count())
	_update_beacon_label()

## 闪避冷却进度更新（ratio: 0.0=就绪，1.0=冷却中）
func _on_dash_cooldown_changed(cooldown_ratio: float) -> void:
	if dash_cooldown_bar:
		# value=1 就绪，value=0 冷却中（进度条反向）
		dash_cooldown_bar.value = 1.0 - cooldown_ratio

## 闪避启动时高亮
func _on_dash_started() -> void:
	if dash_cooldown_bar:
		dash_cooldown_bar.modulate = Color(0.6, 0.9, 1.0, 1.0)
		# 淡出高亮
		var t := dash_cooldown_bar.create_tween()
		t.tween_property(dash_cooldown_bar, "modulate", Color.WHITE, 0.3)

## 波次进度更新（显示波次击杀状态 + 平滑动画）
func _on_wave_progress_changed(killed: int, total: int, wave: int) -> void:
	if clearing_progress == null:
		return

	# 进度比例
	var ratio: float = 0.0
	if total > 0:
		ratio = float(killed) / float(total)

	# 目标值
	var target := ratio * clearing_progress.max_value
	var current := clearing_progress.value

	# 进度条颜色随进度变化：0%=暗红 → 50%=橙 → 100%=亮绿
	if ratio < 0.5:
		clearing_progress.modulate = Color(1.0, 0.4 + ratio * 0.6, 0.2, 1.0)
	elif ratio < 0.8:
		clearing_progress.modulate = Color(1.0, 0.7 + (ratio - 0.5) * 1.0, 0.2 + (ratio - 0.5) * 0.8, 1.0)
	else:
		clearing_progress.modulate = Color(0.4 + ratio * 0.6, 1.0, 0.4, 1.0)

	# 已有动画则停止，避免叠加
	if _wave_kill_anim_tween != null and _wave_kill_anim_tween.is_valid():
		_wave_kill_anim_tween.kill()

	# 平滑动画（200ms，过冲效果让数字滚动更有"撞击感"）
	_wave_kill_anim_tween = clearing_progress.create_tween()
	_wave_kill_anim_tween.set_trans(Tween.TRANS_BACK)
	_wave_kill_anim_tween.set_ease(Tween.EASE_OUT)
	_wave_kill_anim_tween.tween_property(clearing_progress, "value", target, 0.2)

	# 更新波次文字指示器
	var remaining := total - killed
	if _wave_indicator_label == null:
		_wave_indicator_label = get_node_or_null("GameHUD/WaveIndicatorLabel")
	if _wave_indicator_label:
		if remaining > 0:
			_wave_indicator_label.text = "第 %d 波 | 剩余 %d 敌人" % [wave, remaining]
			_wave_indicator_label.modulate = Color(1.0, 0.85, 0.6, 1.0)
		else:
			_wave_indicator_label.text = "第 %d 波 完成！" % [wave]
			_wave_indicator_label.modulate = Color(0.5, 1.0, 0.6, 1.0)

		# 销毁旧描边标签（避免每次刷新残留）
		if _wave_outline_label != null:
			_wave_outline_label.queue_free()
			_wave_outline_label = null

		# 创建描边标签（暗色副本，位于主标签下方偏移2px）
		_wave_outline_label = Label.new()
		_wave_outline_label.text = _wave_indicator_label.text
		_wave_outline_label.position = _wave_indicator_label.position + Vector2(2, 2)
		_wave_outline_label.modulate = Color(0.0, 0.0, 0.0, 0.6)
		_wave_outline_label.z_index = _wave_indicator_label.z_index - 1
		_wave_outline_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_wave_outline_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_wave_outline_label.add_theme_font_size_override("font_size", _wave_indicator_label.get_theme_font_size("font_size"))
		_wave_outline_label.scale = _wave_indicator_label.scale

		# 插入到主标签之前（使其在视觉上位于底层）
		var parent := _wave_indicator_label.get_parent()
		if parent != null:
			parent.add_child(_wave_outline_label)
			parent.move_child(_wave_outline_label, _wave_indicator_label.get_index())

		# 文字弹入动画（主标签 + 描边同步）
		var lbl_tween := _wave_indicator_label.create_tween()
		var outline_tween := _wave_outline_label.create_tween() if _wave_outline_label else null
		lbl_tween.tween_property(_wave_indicator_label, "scale", Vector2(1.15, 1.15), 0.08)
		if outline_tween:
			outline_tween.tween_property(_wave_outline_label, "scale", Vector2(1.15, 1.15), 0.08)
		lbl_tween.tween_property(_wave_indicator_label, "scale", Vector2(1.0, 1.0), 0.12)
		if outline_tween:
			outline_tween.tween_property(_wave_outline_label, "scale", Vector2(1.0, 1.0), 0.12)

## 撤离完成
func _on_extraction_completed(_success: bool, loot: Array) -> void:
	extraction_panel.visible = false
	_show_extraction_success()

## 显示撤离成功面板（淡入动画 + 物品闪光）
func _show_extraction_success() -> void:
	if extraction_success_panel == null:
		return

	# 先设为可见但完全透明+缩小，作为动画起点
	extraction_success_panel.visible = true
	extraction_success_panel.modulate.a = 0.0
	extraction_success_panel.scale = Vector2(0.85, 0.85)

	get_tree().paused = true

	# 获取背包和保险格物品
	var extracted: Array[Dictionary] = []
	if _inventory_module and _inventory_module.has_method("get_all_items"):
		extracted = _inventory_module.get_all_items()
	var insured: Array[Dictionary] = []
	if _insurance_module and _insurance_module.has_method("get_all_insured_items"):
		insured = _insurance_module.get_all_insured_items()

	# 更新物品数量标签
	var total_count := extracted.size() + insured.size()
	if extracted_count_label:
		extracted_count_label.text = "物品已保存: %d 件" % total_count

	# 清空并填充物品列表（带品质边框颜色）
	if extracted_items_vbox:
		for child in extracted_items_vbox.get_children():
			child.queue_free()
		for item in extracted:
			var item_name: String = item.get("id", "未知物品")
			var tier: int = item.get("loot_table_tier", 0)
			var lbl := Label.new()
			lbl.text = "• %s" % item_name
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			# 品质边框颜色：0=白/黄，1=蓝，2=紫，3=金
			match tier:
				3: lbl.modulate = Color(1.0, 0.85, 0.2, 1.0)   # 金
				2: lbl.modulate = Color(0.75, 0.35, 1.0, 1.0)  # 紫
				1: lbl.modulate = Color(0.35, 0.55, 1.0, 1.0)  # 蓝
				_: lbl.modulate = Color(1.0, 0.92, 0.6, 1.0)   # 米黄
			extracted_items_vbox.add_child(lbl)
		for item in insured:
			var item_name: String = item.get("id", "保险物品")
			var tier: int = item.get("loot_table_tier", 0)
			var lbl := Label.new()
			lbl.text = "• %s [保险]" % item_name
			match tier:
				3: lbl.modulate = Color(0.8, 0.95, 0.6, 1.0)
				2: lbl.modulate = Color(0.85, 0.75, 1.0, 1.0)
				1: lbl.modulate = Color(0.7, 0.8, 1.0, 1.0)
				_: lbl.modulate = Color(0.7, 0.85, 0.7, 1.0)
			extracted_items_vbox.add_child(lbl)

	# 淡入+放大动画（0.4s 后弹回正常大小）
	var tween := extraction_success_panel.create_tween()
	tween.set_parallel(true)
	tween.tween_property(extraction_success_panel, "modulate:a", 1.0, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(extraction_success_panel, "scale", Vector2(1.0, 1.0), 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# 撤离成功时轻度震屏（强化"完成撤离"的仪式感）
	if _screen_shake and _screen_shake.has_method("trigger"):
		_screen_shake.call("trigger", 3.5, 0.12)

func show_run_extraction_success(stats: Dictionary) -> void:
	_show_extraction_success()
	if extracted_count_label:
		extracted_count_label.text = "撤离成功  波次 %d  击杀 %d  魂 %d" % [
			int(stats.get("wave", 0)),
			int(stats.get("kills", 0)),
			int(stats.get("currency", 0))
		]
	if extracted_items_vbox:
		var score_label_node := Label.new()
		score_label_node.text = "最终得分: %d  风险层级: %d" % [
			int(stats.get("score", 0)),
			int(stats.get("risk", 0))
		]
		score_label_node.modulate = Color(0.85, 0.95, 1.0, 1.0)
		extracted_items_vbox.add_child(score_label_node)

## 继续按钮 — 返回基地主界面
func _on_continue_pressed() -> void:
	get_tree().paused = false
	if extraction_success_panel:
		extraction_success_panel.visible = false
	if game_over_panel:
		game_over_panel.visible = false
	if death_overlay:
		death_overlay.visible = false
	# 返回基地主界面
	get_tree().change_scene_to_file("res://scenes/BaseMenu.tscn")

## 撤离中断
func _on_extraction_aborted() -> void:
	if room_info_label:
		room_info_label.text = "撤离已中断！"
	if abort_button:
		abort_button.disabled = true
		abort_button.text = "已中断"

## 中断撤离按钮
func _on_abort_button_pressed() -> void:
	if abort_button:
		abort_button.disabled = true
		abort_button.text = "中断中..."
	if _extraction_module:
		_extraction_module.abort_extraction()

## 显示撤离选择面板（房间清理后）
func _on_extraction_ready() -> void:
	if extraction_panel:
		_update_beacon_label()
		_build_extraction_buttons()
		_update_extraction_buttons()  # 刷新按钮状态（可能刚有extraction_unlocked信号解锁了条件撤离点）
		extraction_panel.visible = true

## 构建撤离类型按钮
func _build_extraction_buttons() -> void:
	if extraction_buttons_container == null:
		return
	for child in extraction_buttons_container.get_children():
		child.queue_free()

	for etype in _extraction_types:
		var btn := Button.new()
		btn.text = _get_extraction_button_text(etype)
		var can_use := _can_use_extraction_type(etype)
		btn.disabled = not can_use
		if not can_use:
			btn.tooltip_text = _get_extraction_disabled_reason(etype)
		btn.pressed.connect(_on_extraction_type_button_pressed.bind(etype))
		extraction_buttons_container.add_child(btn)

func _get_extraction_button_text(etype: String) -> String:
	match etype:
		"STANDARD": return "撤离点 (安全但偏远)"
		"BEACON": return "信标撤离 (消耗道具)"
		"BOSS_KILL": return "Boss撤离 (需击败Boss)"
		"ELITE_KILL": return "精英撤离 (需击败精英)"
		"TRADE": return "交易撤离 (消耗资源)"
	return etype

func _get_map_manager_safe() -> Node:
	if _room_game_mode == null or not is_instance_valid(_room_game_mode):
		return null
	if not _room_game_mode.has_method("get_map_manager"):
		return null
	var mm = _room_game_mode.get_map_manager()
	if mm == null or not is_instance_valid(mm):
		return null
	return mm

func _get_extraction_director_safe() -> Object:
	var mm := _get_map_manager_safe()
	if mm == null:
		return null
	var ed = mm.get("extraction_director")
	if ed == null:
		return null
	return ed

func _get_current_floor_safe() -> int:
	if _room_game_mode == null or not is_instance_valid(_room_game_mode):
		return 1
	var floor_value = _room_game_mode.get("current_floor")
	if floor_value == null:
		return 1
	return max(1, int(floor_value))

func _get_extraction_disabled_reason(etype: String) -> String:
	match etype:
		"BEACON": return "没有信标道具"
		"BOSS_KILL": return "尚未击败Boss，无法解锁"
		"ELITE_KILL": return "尚未击败精英怪，无法解锁"
		"TRADE":
			var ed := _get_extraction_director_safe()
			if ed != null and ed.has_method("get_trade_cost"):
				var cost: int = int(ed.get_trade_cost(_get_current_floor_safe()))
				return "需要 %d 魂，当前货币不足" % cost
			return "当前模式未接入交易撤离"
	return ""

func _can_use_extraction_type(etype: String) -> bool:
	match etype:
		"STANDARD":
			return true
		"BEACON":
			return _beacon_count > 0
		"BOSS_KILL":
			var ed_boss := _get_extraction_director_safe()
			return ed_boss != null and ed_boss.has_method("get_points_by_type") and ed_boss.get_points_by_type(ExtractionDirector.ExtractionType.BOSS_KILL, true).size() > 0
		"ELITE_KILL":
			var ed_elite := _get_extraction_director_safe()
			return ed_elite != null and ed_elite.has_method("get_points_by_type") and ed_elite.get_points_by_type(ExtractionDirector.ExtractionType.ELITE_KILL, true).size() > 0
		"TRADE":
			var ed_trade_check := _get_extraction_director_safe()
			return ed_trade_check != null and ed_trade_check.has_method("get_trade_cost") and GameManager.currency >= int(ed_trade_check.get_trade_cost(_get_current_floor_safe()))
	return false

func _update_extraction_buttons() -> void:
	if extraction_buttons_container == null:
		return
	var children := extraction_buttons_container.get_children()
	var count: int = mini(children.size(), _extraction_types.size())
	for i in range(count):
		var btn: Button = children[i] as Button
		if btn == null:
			continue
		var etype: String = _extraction_types[i]
		btn.disabled = not _can_use_extraction_type(etype)
		btn.modulate = Color.WHITE if not btn.disabled else Color.GRAY
		btn.tooltip_text = "" if not btn.disabled else _get_extraction_disabled_reason(etype)

func _update_beacon_label() -> void:
	if beacon_label:
		beacon_label.text = "信标数量: %d" % _beacon_count

## 撤离类型按钮点击
func _on_extraction_type_button_pressed(etype: String) -> void:
	var countdown: float = 5.0
	match etype:
		"STANDARD": countdown = 8.0
		"BEACON": countdown = 10.0
		"BOSS_KILL": countdown = 3.0
		"ELITE_KILL": countdown = 5.0
		"TRADE": countdown = 5.0

	# 信标撤离：先消耗信标道具创建撤离点
	if etype == "BEACON":
		var ed_beacon := _get_extraction_director_safe()
		if ed_beacon != null and ed_beacon.has_method("summon_beacon_extraction"):
			ed_beacon.summon_beacon_extraction()
			if ed_beacon.has_method("get_beacon_count"):
				_beacon_count = int(ed_beacon.get_beacon_count())

	# 交易撤离：预扣货币（不满足则禁用按钮）
	if etype == "TRADE":
		var ed_trade := _get_extraction_director_safe()
		if ed_trade != null and ed_trade.has_method("get_trade_cost"):
			var cost: int = int(ed_trade.get_trade_cost(_get_current_floor_safe()))
			if not GameManager.spend_currency(cost):
				return
			ed_trade.set("_trade_pending_refund", false)

	if _room_game_mode == null or not _room_game_mode.has_method("begin_extraction"):
		if room_info_label:
			room_info_label.text = "当前战斗模式暂未接入撤离流程"
		return

	if extraction_panel:
		extraction_panel.visible = false
	_room_game_mode.begin_extraction(etype, countdown)
	_start_extraction_countdown_ui(etype, countdown)

## 开始撤离读条UI
func _start_extraction_countdown_ui(extraction_type: String, duration: float) -> void:
	extraction_type_label.text = "撤离中: %s" % extraction_type
	countdown_bar.visible = true
	countdown_label.visible = true
	abort_button.visible = true
	countdown_bar.max_value = 1.0
	countdown_bar.value = 0.0
	_update_countdown_label(duration, duration)

	# 隐藏撤离按钮容器
	if extraction_buttons_container:
		for child in extraction_buttons_container.get_children():
			child.visible = false

## 更新读条进度
func update_countdown(progress: float, remaining: float) -> void:
	if countdown_bar:
		countdown_bar.value = progress
		_update_countdown_label(remaining, countdown_bar.max_value)

func _update_countdown_label(remaining: float, total: float) -> void:
	if countdown_label:
		countdown_label.text = "%.1f 秒" % remaining

## 同步信标数量（由 RoomGameMode 在初始化时调用）
func set_beacon_count(count: int) -> void:
	_beacon_count = count
	_update_beacon_label()
	_update_extraction_buttons()  # 信标数量变化时同步刷新按钮可用性（BEACON按钮依赖_beacon_count）

## 隐藏所有面板
func hide_all_panels() -> void:
	if extraction_panel:
		extraction_panel.visible = false
	if inventory_panel:
		inventory_panel.visible = false
	if fate_card_panel:
		fate_card_panel.visible = false

## 每帧更新命运卡片提示计时器
## 弹药变化回调
func _on_ammo_changed(current: int, maximum: int) -> void:
	if ammo_bar:
		ammo_bar.max_value = maximum
		ammo_bar.value = current
	if ammo_label:
		ammo_label.text = "%d/%d" % [current, maximum]
		_sync_ammo_outline()
		# 弹药紧张时改变颜色
		var ratio := float(current) / float(maximum) if maximum > 0 else 0.0
		if ratio <= 0.15:
			ammo_label.modulate = Color(1.0, 0.3, 0.3, 1.0)  # 红色警告
		elif ratio <= 0.35:
			ammo_label.modulate = Color(1.0, 0.75, 0.2, 1.0)  # 橙色警告
		else:
			ammo_label.modulate = Color.WHITE
	if ammo_bar:
		var ratio := float(current) / float(maximum) if maximum > 0 else 0.0
		if ratio <= 0.15:
			ammo_bar.modulate = Color(1.0, 0.3, 0.2, 1.0)  # 红色警告
		elif ratio <= 0.35:
			ammo_bar.modulate = Color(1.0, 0.75, 0.2, 1.0)  # 橙色警告
		else:
			ammo_bar.modulate = Color(0.45, 1.0, 0.55, 1.0)  # 绿色正常

## 开始换弹
func _on_reload_started() -> void:
	_is_reloading = true
	if reload_indicator:
		reload_indicator.visible = true
		reload_indicator.text = "换弹中..."
	if ammo_label:
		ammo_label.modulate = Color(0.65, 0.65, 0.65, 1.0)  # 换弹时变灰
	# 从 WeaponAssemblyTree 获取 reload_time
	var wt = _get_weapon_tree()
	if wt != null:
		_reload_duration = wt.reload_time
	else:
		_reload_duration = 2.0
	_reload_progress = 0.0

## 换弹完成
func _on_weapon_reloaded() -> void:
	_is_reloading = false
	_reload_progress = 0.0
	if reload_indicator:
		reload_indicator.visible = false
	if ammo_label:
		ammo_label.modulate = Color.WHITE

## 获取武器装配树引用
func _get_weapon_tree():
	if _room_game_mode != null and _room_game_mode.has_method("get_player"):
		var player = _room_game_mode.get_player()
		if player != null and player.has_method("get_weapon_tree"):
			return player.get_weapon_tree()
	return null

func _process(delta: float) -> void:
	if _is_reloading and _reload_duration > 0:
		_reload_progress = min(_reload_progress + delta, _reload_duration)
		if ammo_bar:
			ammo_bar.value = _reload_progress
		if reload_indicator:
			reload_indicator.text = "换弹 %.0f%%" % (100.0 * _reload_progress / _reload_duration)
	if _fate_card_notification_timer > 0.0:
		_fate_card_notification_timer -= delta
		if _fate_card_notification_timer <= 0.0:
			_fate_card_notification_timer = 0.0
			_hide_fate_card_notification()

## — 物品存入取出（保险格）系统 —
const SLOT_SIZE := 56
const SLOT_SCENE: PackedScene = preload("res://scenes/ItemSlot.tscn")

var _inventory_slot_nodes: Array[Control] = []
var _insurance_slot_nodes: Array[Control] = []

func _build_inventory_grid() -> void:
	if inventory_grid == null:
		return
	for child in inventory_grid.get_children():
		child.queue_free()
	_inventory_slot_nodes.clear()
	for i in 12:
		var slot := _create_slot()
		slot.name = "InvSlot_%d" % i
		inventory_grid.add_child(slot)
		_inventory_slot_nodes.append(slot)
		_connect_slot_signals(slot, i, true)

func _build_insurance_grid() -> void:
	if insurance_grid == null:
		return
	for child in insurance_grid.get_children():
		child.queue_free()
	_insurance_slot_nodes.clear()
	for i in 2:
		var slot := _create_slot()
		slot.name = "InsSlot_%d" % i
		insurance_grid.add_child(slot)
		_insurance_slot_nodes.append(slot)
		_connect_slot_signals(slot, i, false)

func _create_slot() -> Control:
	var slot: Control
	if SLOT_SCENE != null:
		slot = SLOT_SCENE.instantiate() as Control
	else:
		var tr := TextureRect.new()
		tr.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		slot = tr
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0.12, 0.14, 0.18, 0.9)
	normal_style.set_border_width_all(1)
	normal_style.set_border_color(Color(0.3, 0.33, 0.4, 0.6))
	normal_style.set_corner_radius_all(4)
	slot.add_theme_stylebox_override("normal", normal_style)
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.2, 0.25, 0.35, 0.9)
	hover_style.set_border_width_all(1)
	hover_style.set_border_color(Color(0.5, 0.6, 0.8, 0.8))
	hover_style.set_corner_radius_all(4)
	slot.add_theme_stylebox_override("hover", hover_style)
	return slot

func _connect_slot_signals(slot: Control, idx: int, is_inventory: bool) -> void:
	if slot.has_method("set_slot_index"):
		slot.call("set_slot_index", idx)
	if slot.has_signal("slot_clicked"):
		(slot as Node).slot_clicked.connect(_on_slot_clicked.bind(is_inventory))
	if slot.has_signal("slot_right_clicked"):
		(slot as Node).slot_right_clicked.connect(_on_slot_right_clicked.bind(is_inventory))

func _refresh_inventory_ui() -> void:
	if _inventory_module == null or inventory_grid == null:
		return
	var occupied: Array[Dictionary] = _inventory_module.get_occupied_slots()
	var slot_data: Dictionary = {}
	for si in occupied:
		slot_data[si["slot"]] = si
	for i in _inventory_slot_nodes.size():
		var slot: Control = _inventory_slot_nodes[i]
		if slot_data.has(i):
			_update_slot_with_item(slot, slot_data[i])
		else:
			_clear_slot(slot)
	var used: int = _inventory_module.get_used_slots()
	var cap: int = _inventory_module.get_capacity()
	if inventory_capacity_label:
		inventory_capacity_label.text = "背包 %d/%d" % [used, cap]

func _refresh_insurance_ui() -> void:
	if _insurance_module == null or insurance_grid == null:
		return
	var occupied: Array[Dictionary] = []
	if _insurance_module.has_method("get_occupied_slots"):
		occupied = _insurance_module.get_occupied_slots()
	var slot_data: Dictionary = {}
	for si in occupied:
		slot_data[si.get("insurance_slot", si.get("slot", 0))] = si
	for i in _insurance_slot_nodes.size():
		var slot: Control = _insurance_slot_nodes[i]
		if slot_data.has(i):
			_update_slot_with_item(slot, slot_data[i])
		else:
			_clear_slot(slot)
	var used: int = occupied.size()
	if insurance_label:
		insurance_label.text = "保险格 %d/%d" % [used, 2]

func _update_slot_with_item(slot: Control, slot_info: Dictionary) -> void:
	var item: Dictionary = slot_info.get("item", {})
	var item_id: String = item.get("id", "")
	var count: int = slot_info.get("count", 1)
	var icon_path: String = item.get("icon", "")
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		var tex: Texture2D = load(icon_path) as Texture2D
		if slot is TextureRect:
			(slot as TextureRect).texture = tex
	else:
		if slot is TextureRect:
			(slot as TextureRect).texture = null
	if slot.has_node("CountLabel"):
		var cl: Label = slot.get_node("CountLabel") as Label
		if count > 1:
			cl.text = "x%d" % count
			cl.visible = true
		else:
			cl.visible = false
	var style_box := StyleBoxFlat.new()
	style_box.bg_color = Color(0.2, 0.22, 0.28, 0.95)
	style_box.set_border_width_all(2)
	style_box.set_border_color(Color(0.6, 0.7, 0.9, 0.7))
	style_box.set_corner_radius_all(4)
	slot.add_theme_stylebox_override("normal", style_box)

func _clear_slot(slot: Control) -> void:
	if slot is TextureRect:
		(slot as TextureRect).texture = null
	if slot.has_node("CountLabel"):
		var cl: Label = slot.get_node("CountLabel") as Label
		cl.visible = false
	var style_box := StyleBoxFlat.new()
	style_box.bg_color = Color(0.12, 0.14, 0.18, 0.9)
	style_box.set_border_width_all(1)
	style_box.set_border_color(Color(0.3, 0.33, 0.4, 0.6))
	style_box.set_corner_radius_all(4)
	slot.add_theme_stylebox_override("normal", style_box)

func _on_insurance_changed() -> void:
	_refresh_insurance_ui()

func _on_slot_clicked(slot_index: int, is_inventory: bool) -> void:
	if is_inventory:
		item_to_insurance_requested.emit(slot_index)
	else:
		item_extraction_requested.emit(slot_index)

func _on_slot_right_clicked(slot_index: int, is_inventory: bool) -> void:
	if is_inventory:
		# 尝试使用消耗品（右键使用物品）
		var slot_data: Dictionary = _inventory_module.get_slot(slot_index)
		if not slot_data.is_empty():
			var item: Dictionary = slot_data["item"]
			var use_action: String = item.get("use_action", "")
			if not use_action.is_empty():
				# 消耗品使用：扣物品 + 触发效果
				if _inventory_module.consume_item(item.get("id", ""), 1):
					# 动态加载 handler 脚本并调用（避免跨脚本类型声明问题）
					var handler_script: GDScript = load(_ITEM_USE_HANDLER_PATH)
					var handler: Object = handler_script.new()
					var context: Dictionary = {"player": _get_player_reference()}
					var ok: bool = handler.apply(item, context)
					handler.free()
					if not ok:
						# 使用失败：尝试恢复物品（consume 已调用，这里只是占位）
						_inventory_module.add_item(item, 1)
					_refresh_inventory_ui()
					return
		# 非消耗品：存入保险格
		item_to_insurance_requested.emit(slot_index)
	else:
		item_extraction_requested.emit(slot_index)

## 获取 Player 引用（供 ItemUseHandler 上下文使用）
func _get_player_reference() -> Node:
	if _room_game_mode != null and _room_game_mode.has_method("get_player"):
		return _room_game_mode.get_player()
	# Fallback：按节点路径查找
	var player: Node = get_node_or_null("/root/Main/YSort/Player")
	if player == null:
		player = get_node_or_null("/root/Main/Player")
	return player

## 保险存入请求处理（被调用时执行存入保险格逻辑）
func _on_item_to_insurance_requested(slot_index: int) -> void:
	if _inventory_module == null or _insurance_module == null:
		return
	var slot_data: Dictionary = _inventory_module.get_slot(slot_index)
	if slot_data.is_empty():
		return
	var ok: bool = _insurance_module.insure_item(_inventory_module, slot_index)
	if not ok:
		print("[GameUIManager] 保险格已满，无法存入物品")
		return
	_refresh_inventory_ui()
	_refresh_insurance_ui()

## 保险取出请求处理
func _on_item_extraction_requested(slot_index: int) -> void:
	if _inventory_module == null or _insurance_module == null:
		return
	var item: Dictionary = _insurance_module.claim_item(slot_index)
	if item.is_empty():
		return
	_inventory_module.add_item(item, item.get("count", 1))
	_refresh_inventory_ui()
	_refresh_insurance_ui()

## 输入处理：I 键切换背包+保险面板
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_inventory"):
		if inventory_panel:
			var visible := not inventory_panel.visible
			inventory_panel.visible = visible
			if insurance_panel:
				insurance_panel.visible = visible
			if visible:
				_refresh_inventory_ui()
				_refresh_insurance_ui()
			get_viewport().set_input_as_handled()
