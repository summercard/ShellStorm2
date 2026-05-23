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
var _fate_card_notification_label: Label = null  ## 命运卡片提示标签
var _fate_card_notification_timer: float = 0.0  ## 提示显示计时器
const _FATE_CARD_NOTIFICATION_DURATION: float = 4.0  ## 提示显示4秒

var _room_game_mode: Node = null
var _inventory_module: Object = null
var _extraction_module: Object = null
var _insurance_module: Object = null
var _inventory_ui: Control = null  ## InventoryUI 引用（由本类实例化）
var _extraction_director: Node = null  ## ExtractionDirector 引用（用于信标撤离计数）

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

func _ready() -> void:
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

## 绑定房间游戏模式
func set_room_game_mode(mode: Node) -> void:
	_room_game_mode = mode
	
	# 连接信号
	if mode.has_signal("room_cleared"):
		mode.room_cleared.connect(_on_room_cleared)
	if mode.has_signal("game_over"):
		mode.game_over.connect(_on_game_over)
	if mode.has_signal("extraction_ready"):
		mode.extraction_ready.connect(_on_extraction_ready)
	if mode.has_signal("floor_changed"):
		mode.floor_changed.connect(_on_floor_changed)
	if mode.has_signal("kill_recorded"):
		mode.kill_recorded.connect(_on_kill_recorded)
	if mode.has_signal("wave_progress_changed"):
		mode.wave_progress_changed.connect(_on_wave_progress_changed)

## 绑定玩家（用于闪避冷却条等）
func set_player(player: Node) -> void:
	if player and player.has_signal("dash_cooldown_changed"):
		player.dash_cooldown_changed.connect(_on_dash_cooldown_changed)
	if player and player.has_signal("dash_started"):
		player.dash_started.connect(_on_dash_started)

## 绑定背包模块
func set_inventory_module(module: Object) -> void:
	_inventory_module = module
	if module.has_signal("inventory_changed"):
		module.inventory_changed.connect(_on_inventory_changed)
	if module.has_signal("capacity_changed"):
		module.capacity_changed.connect(_on_capacity_changed)

## 绑定保险格模块
func set_insurance_module(module: Object) -> void:
	_insurance_module = module
	if module.has_signal("insurance_changed"):
		module.insurance_changed.connect(_on_insurance_changed)

## 绑定撤离模块
func set_extraction_module(module: Object) -> void:
	_extraction_module = module
	_connect_extraction_module_signals(module)

## 更新 HP 显示
func update_hp(current: int, maximum: int) -> void:
	if hp_bar:
		hp_bar.max_value = maximum
		hp_bar.value = current

## 更新分数（带跳动动画）
func update_score(score_val: int) -> void:
	if score_label:
		score_label.text = "Score: %d" % score_val
		_bounce_label(score_label)

## 击杀记录
func _on_kill_recorded() -> void:
	_kill_count += 1

## 更新货币（带跳动动画）
func update_currency(amount: int) -> void:
	if currency_label:
		currency_label.text = "魂: %d" % amount
		_bounce_label(currency_label)

## 连接 ExtractionModule 信号（由 set_extraction_module 调用）
func _connect_extraction_module_signals(module: Object) -> void:
	if module.has_signal("extraction_completed"):
		module.extraction_completed.connect(_on_extraction_completed)
	if module.has_signal("extraction_progress_updated"):
		module.extraction_progress_updated.connect(_on_extraction_progress_updated)
	if module.has_signal("extraction_aborted"):
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

## 世界坐标 → CanvasLayer 局部坐标
func _world_to_canvas(world_pos: Vector2) -> Vector2:
	# 使用 CanvasLayer 的图层变换
	# 简化处理：直接取 Tree 的当前窗口视口根节点
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return world_pos
	# 用 get_global_mouse_position 思路处理：将世界坐标转为屏幕坐标，再转为 CanvasLayer 局部坐标
	# 实际上 CanvasLayer 不变换世界坐标，直接用即可
	# 但需要考虑 Camera2D，如果存在的话用 get_global_mouse_transform() 反推
	# 简化：直接用 world_pos（假设没有 Camera2D 变换或由外部保证）
	return world_pos

## 更新楼层
func update_floor(floor: int) -> void:
	if wave_label:
		wave_label.text = "Floor: %d" % floor
		_bounce_label(wave_label)

## 房间清理完成
func _on_room_cleared(room_data) -> void:
	if room_info_label:
		room_info_label.text = "房间清理完成！"
	clearing_progress.visible = false
	# 显示命运卡片提示
	_show_fate_card_notification()

## 显示命运卡片提示（房间清理后、或出生时）
func _show_fate_card_notification() -> void:
	if _fate_card_notification_label == null:
		return
	_fate_card_notification_timer = _FATE_CARD_NOTIFICATION_DURATION
	_fate_card_notification_label.visible = true
	# 淡入动画
	var tween := _fate_card_notification_label.create_tween()
	tween.tween_property(_fate_card_notification_label, "modulate:a", 1.0, 0.3)

## 隐藏命运卡片提示
func _hide_fate_card_notification() -> void:
	if _fate_card_notification_label == null:
		return
	# 淡出动画
	var tween := _fate_card_notification_label.create_tween()
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
	if _room_game_mode == null:
		return
	var map_mgr = _room_game_mode.get_map_manager()
	if map_mgr == null or map_mgr.extraction_director == null:
		return
	_beacon_count = map_mgr.extraction_director.get_beacon_count()
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

## 波次进度更新（显示波次击杀状态）
func _on_wave_progress_changed(killed: int, total: int, wave: int) -> void:
	pass  # wave_indicator_label not present in current scene

## 撤离完成
func _on_extraction_completed(_success: bool, loot: Array) -> void:
	extraction_panel.visible = false
	_show_extraction_success()

## 显示撤离成功面板
func _show_extraction_success() -> void:
	if extraction_success_panel == null:
		return
	extraction_success_panel.visible = true
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

	# 清空并填充物品列表
	if extracted_items_vbox:
		for child in extracted_items_vbox.get_children():
			child.queue_free()
		for item in extracted:
			var item_name: String = item.get("id", "未知物品")
			var lbl := Label.new()
			lbl.text = "• %s" % item_name
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			extracted_items_vbox.add_child(lbl)
		for item in insured:
			var item_name: String = item.get("id", "保险物品")
			var lbl := Label.new()
			lbl.text = "• %s [保险]" % item_name
			lbl.modulate = Color(0.7, 0.85, 0.7, 1.0)
			extracted_items_vbox.add_child(lbl)

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
		extraction_panel.visible = true

## 构建撤离类型按钮
func _build_extraction_buttons() -> void:
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

func _get_extraction_disabled_reason(etype: String) -> String:
	match etype:
		"BEACON": return "没有信标道具"
		"BOSS_KILL": return "尚未击败Boss，无法解锁"
		"ELITE_KILL": return "尚未击败精英怪，无法解锁"
		"TRADE":
			if _room_game_mode != null:
				var cost := 0
				if _room_game_mode.has_method("get_map_manager"):
					var mm = _room_game_mode.get_map_manager()
					if mm and mm.extraction_director:
						cost = mm.extraction_director.get_trade_cost(_room_game_mode.current_floor)
				return "需要 %d 魂，当前货币不足" % cost
			return "资源不足"
	return ""

func _can_use_extraction_type(etype: String) -> bool:
	match etype:
		"BEACON": return _beacon_count > 0
		"BOSS_KILL": return _room_game_mode != null and _room_game_mode.has_method("get_map_manager") and _room_game_mode.get_map_manager().extraction_director.get_points_by_type(ExtractionDirector.ExtractionType.BOSS_KILL, true).size() > 0
		"ELITE_KILL": return _room_game_mode != null and _room_game_mode.has_method("get_map_manager") and _room_game_mode.get_map_manager().extraction_director.get_points_by_type(ExtractionDirector.ExtractionType.ELITE_KILL, true).size() > 0
		"TRADE": return _room_game_mode != null and _room_game_mode.has_method("get_map_manager") and _room_game_mode.current_floor > 0 and GameManager.currency >= _room_game_mode.get_map_manager().extraction_director.get_trade_cost(_room_game_mode.current_floor)
	return true

func _update_extraction_buttons() -> void:
	for i in extraction_buttons_container.get_children().size():
		var btn: Button = extraction_buttons_container.get_child(i) as Button
		var etype: String = _extraction_types[i]
		btn.disabled = not _can_use_extraction_type(etype)
		btn.modulate = Color.WHITE if not btn.disabled else Color.GRAY

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
	if etype == "BEACON" and _room_game_mode != null:
		var map_mgr = _room_game_mode.get_map_manager()
		if map_mgr != null and map_mgr.extraction_director != null:
			map_mgr.extraction_director.summon_beacon_extraction()
			_beacon_count = map_mgr.extraction_director.get_beacon_count()

	# 交易撤离：预扣货币（不满足则禁用按钮）
	if etype == "TRADE" and _room_game_mode != null:
		var map_mgr = _room_game_mode.get_map_manager()
		if map_mgr != null and map_mgr.extraction_director != null:
			var ed = map_mgr.extraction_director
			var cost = ed.get_trade_cost(_room_game_mode.current_floor)
			if not GameManager.spend_currency(cost):
				# 货币不足，无法交易撤离
				return
			# 货币已预扣，等待撤离完成时通知 ExtractionDirector 做最终结算
			ed.set("_trade_pending_refund", false)  # 标记已预扣，不需要退款

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
	for child in extraction_buttons_container.get_children():
		child.visible = false

## 更新读条进度
func update_countdown(progress: float, remaining: float) -> void:
	countdown_bar.value = progress
	_update_countdown_label(remaining, countdown_bar.max_value)

func _update_countdown_label(remaining: float, total: float) -> void:
	if countdown_label:
		countdown_label.text = "%.1f 秒" % remaining

## 同步信标数量（由 RoomGameMode 在初始化时调用）
func set_beacon_count(count: int) -> void:
	_beacon_count = count
	_update_beacon_label()

## 隐藏所有面板
func hide_all_panels() -> void:
	extraction_panel.visible = false
	inventory_panel.visible = false
	fate_card_panel.visible = false

## 每帧更新命运卡片提示计时器
func _process(delta: float) -> void:
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
	if slot.has_signal("slot_clicked"):
		(slot as Node).slot_clicked.connect(_on_slot_clicked.bind(idx, is_inventory))
	if slot.has_signal("slot_right_clicked"):
		(slot as Node).slot_right_clicked.connect(_on_slot_right_clicked.bind(idx, is_inventory))

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

## 保险取出请求处理
func _on_item_extraction_requested(slot_index: int) -> void:
	if _inventory_module == null or _insurance_module == null:
		return
	var item: Dictionary = _insurance_module.claim_item(slot_index)
	if item.is_empty():
		return
	_inventory_module.add_item(item, item.get("count", 1))

## 输入处理：Tab 切换背包+保险面板
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_tab"):
		if inventory_panel:
			var visible := not inventory_panel.visible
			inventory_panel.visible = visible
			if insurance_panel:
				insurance_panel.visible = visible
			if visible:
				_refresh_inventory_ui()
				_refresh_insurance_ui()
