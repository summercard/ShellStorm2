class_name GameUIManager
## 游戏 UI 总管理器
## 独立管理所有游戏界面元素，与 RoomGameMode 解耦
## RoomGameMode 通过 signal 通知 UI 更新，UI Manager 订阅 signal

extends CanvasLayer

## 物品使用处理器引用（通过脚本路径获取，避免循环依赖）
const _ITEM_USE_HANDLER_PATH := "res://src/game/ItemUseHandler.gd"
const _WEAPON_PANEL_SCENE: PackedScene = preload("res://scenes/WeaponAssemblyTreePanel.tscn")

## — 游戏状态 UI —
@onready var hp_bar: ProgressBar = $GameHUD/HPBarBG/HPBar
@onready var hp_bar_trail: ProgressBar = $GameHUD/HPBarBG/HPBarTrail
@onready var player_state_panel: PanelContainer = $GameHUD/PlayerStatePanel
@onready var player_state_accent: ColorRect = $GameHUD/PlayerStatePanel/HBox/StateAccent
@onready var player_state_label: Label = $GameHUD/PlayerStatePanel/HBox/VBox/StateLabel
@onready var player_status_label: Label = $GameHUD/PlayerStatePanel/HBox/VBox/StatusLabel

## HP 尾迹跟随 tween（用 meta 持有，避免被 GC 回收）
var _hp_trail_tween: Tween = null
var _hp_readout: Label = null
var _bound_player: Node = null
var _player_state_id := "idle"
var _player_low_health := false
var _player_hp_ratio := 1.0
var _player_status_effects: Dictionary = {}
var _player_state_pulse := 0.0
var _player_state_tween: Tween = null
var _hp_damage_tween: Tween = null
## 标记：是否正在追尾（避免在 _process 中重复触发）
@onready var dash_cooldown_bar: ProgressBar = $GameHUD/DashCooldownBG/DashCooldownBar
@onready var dash_label: Label = $GameHUD/DashCooldownBG/DashLabel
@onready var score_label: Label = $GameHUD/TopRightPanel/VBox/ScoreLabel
@onready var wave_label: Label = $GameHUD/TopRightPanel/VBox/WaveLabel
@onready var currency_label: Label = $GameHUD/CurrencyLabel
@onready var risk_label: Label = $GameHUD/RiskLabel
@onready var crit_label: Label = $GameHUD/CritLabel
@onready var room_info_label: Label = $GameHUD/RoomInfoLabel
@onready var clearing_progress: ProgressBar = $GameHUD/ClearingProgress
@onready var minimap_panel: PanelContainer = $GameHUD/MiniMapPanel
@onready var minimap_view: MinimapView = $GameHUD/MiniMapPanel/MiniMapView

## — 弹药 UI —
@onready var ammo_panel: PanelContainer = $GameHUD/AmmoPanel
@onready var ammo_bar: ProgressBar = $GameHUD/AmmoPanel/AmmoBar
@onready var ammo_label: Label = $GameHUD/AmmoPanel/AmmoLabel
@onready var reload_indicator: Label = $GameHUD/AmmoPanel/ReloadIndicator
@onready var fire_rate_bar: ProgressBar = $GameHUD/FireRatePanel/FireRateBar
@onready var fire_rate_label: Label = $GameHUD/FireRatePanel/FireRateLabel
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
var _active_extraction_duration: float = 0.0
var _extraction_success_shown := false

## — Boss HP UI —
var _boss_hp_panel: PanelContainer = null
var _boss_hp_bar: ProgressBar = null
var _boss_name_label: Label = null
var _boss_hp_label: Label = null
var _boss_max_hp: float = 0.0
var _boss_current_hp: float = 0.0

## — 命运卡片 UI —
@onready var fate_card_panel: Control = $FateCardPanel
var _fate_card_card_container: HBoxContainer = null  ## 卡片按钮容器
var _fate_card_instruction: Label = null  ## 提示标签
var _fate_card_panel_base: Control = null  ## 命运卡片选择面板容器（Control 类型，与场景一致）
var _wave_kill_anim_tween: Tween = null
var _wave_total: int = 0
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
var _weapon_panel: Control = null
var _equipped_weapon_slot: TextureRect = null
var _equipped_weapon_label: Label = null
var _selected_inventory_slot: int = -1
var _selected_insurance_slot: int = -1
var _dragging_inventory_panel: bool = false
var _inventory_drag_start_mouse: Vector2 = Vector2.ZERO
var _inventory_drag_start_panel: Vector2 = Vector2.ZERO
var _inventory_drag_start_insurance: Vector2 = Vector2.ZERO
var _item_hover_card: PanelContainer = null
var _item_hover_label: Label = null
var _extraction_director: Node = null  ## ExtractionDirector 引用（用于信标撤离计数）
var _run_choice_overlay: Control = null
var _run_choice_kind: String = ""

## — 小地图 UI（v0.1）—
var _minimap_panel: PanelContainer = null
var _minimap_view: MinimapView = null
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
var _extraction_success_backdrop: ColorRect = null
var _extraction_floor_label: Label = null  # 撤离面板楼层标签

var _death_stats: Dictionary = {"score": 0, "kills": 0, "floor": 1}
var _death_loot: Dictionary = {"saved": 0, "lost": 0}
var _kill_count: int = 0

## 背包物品操作信号
signal item_to_insurance_requested(slot_index: int)
signal item_extraction_requested(slot_index: int)
signal inventory_ui_changed
signal fate_choice_selected(choice_id: String)
signal extraction_choice_selected(choice_id: String)


func _ready() -> void:
	# 注册为 game_ui 组（供 ContainerInteraction 等通过 group call 触发 UI 方法）
	add_to_group("game_ui")
	# HUD is deliberately above optional fog and world-space effects.
	layer = 30
	_ensure_hud_layout()
	_apply_combat_hud_presentation()

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
		extraction_success_panel.process_mode = Node.PROCESS_MODE_ALWAYS
		if continue_button:
			continue_button.process_mode = Node.PROCESS_MODE_ALWAYS
			continue_button.pressed.connect(_on_continue_pressed)
		_ensure_extraction_success_modal()
		_extraction_floor_label = get_node_or_null("ExtractionSuccessPanel/VBox/FloorLabel")

	# 构建背包、保险格与 HUD 装备位 UI
	_setup_inventory_system_ui()
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
	# 初始化 Boss HP UI 面板（在 GameHUD 之上，居中顶部）
	_init_boss_hp_ui()


func _ensure_hud_layout() -> void:
	var hud := get_node_or_null("GameHUD") as Control
	if hud == null:
		return
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.offset_left = 0
	hud.offset_top = 0
	hud.offset_right = 0
	hud.offset_bottom = 0


func _apply_combat_hud_presentation() -> void:
	## A restrained command-console treatment: consistent surface hierarchy,
	## strong numeric readability and no dependency on a raster UI skin.
	for panel_path in [
		"GameHUD/TopRightPanel", "GameHUD/HPBarBG", "GameHUD/DashCooldownBG",
		"GameHUD/AmmoPanel", "GameHUD/FireRatePanel", "GameHUD/MiniMapPanel",
	]:
		var panel := get_node_or_null(panel_path) as PanelContainer
		if panel == null:
			continue
		var style := UIStyleFactory.make_panel_with_border(1, UIPalette.BORDER_NORMAL, 6, 1)
		style.content_margin_left = 8.0
		style.content_margin_top = 4.0
		style.content_margin_right = 8.0
		style.content_margin_bottom = 4.0
		panel.add_theme_stylebox_override("panel", style)

	for label in [score_label, wave_label, currency_label, risk_label, crit_label, room_info_label]:
		_style_hud_label(label, 15, UIPalette.TEXT_PRIMARY)
	_style_hud_label(score_label, 17, UIPalette.TEXT_GOLD)
	_style_hud_label(wave_label, 14, UIPalette.TEXT_SECONDARY)
	_style_hud_label(room_info_label, 16, UIPalette.TEXT_PRIMARY)
	if room_info_label != null:
		room_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	if hp_bar != null:
		hp_bar.add_theme_stylebox_override("background", UIStyleFactory.make_progress_fill(UIPalette.BG_SLOT))
	if hp_bar_trail != null:
		hp_bar_trail.add_theme_stylebox_override("background", UIStyleFactory.make_progress_fill(UIPalette.BG_SLOT))
	if dash_cooldown_bar != null:
		dash_cooldown_bar.add_theme_stylebox_override("background", UIStyleFactory.make_progress_fill(UIPalette.BG_SLOT))
		dash_cooldown_bar.add_theme_stylebox_override("fill", UIStyleFactory.make_progress_fill(UIPalette.BORDER_FOCUS))
	if ammo_bar != null:
		ammo_bar.add_theme_stylebox_override("background", UIStyleFactory.make_progress_fill(UIPalette.BG_SLOT))
	if fire_rate_bar != null:
		fire_rate_bar.add_theme_stylebox_override("background", UIStyleFactory.make_progress_fill(UIPalette.BG_SLOT))
		fire_rate_bar.add_theme_stylebox_override("fill", UIStyleFactory.make_progress_fill(UIPalette.TEXT_GOLD))
	_style_hud_label(dash_label, 13, UIPalette.TEXT_PRIMARY)
	_style_hud_label(ammo_label, 14, UIPalette.TEXT_PRIMARY)
	_style_hud_label(fire_rate_label, 13, UIPalette.TEXT_SECONDARY)
	_style_hud_label(reload_indicator, 14, UIPalette.TEXT_GOLD)
	if dash_label != null:
		dash_label.text = "机动  READY"
	if fire_rate_label != null:
		fire_rate_label.text = "火力  READY"
	_ensure_hp_readout()
	_refresh_player_state_panel(false)


func _style_hud_label(label: Label, font_size: int, color: Color) -> void:
	if label == null:
		return
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.82))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)


func _ensure_hp_readout() -> void:
	if hp_bar == null:
		return
	_hp_readout = hp_bar.get_node_or_null("Readout") as Label
	if _hp_readout == null:
		_hp_readout = Label.new()
		_hp_readout.name = "Readout"
		_hp_readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hp_readout.set_anchors_preset(Control.PRESET_FULL_RECT)
		_hp_readout.offset_left = 0.0
		_hp_readout.offset_top = 0.0
		_hp_readout.offset_right = 0.0
		_hp_readout.offset_bottom = 0.0
		_hp_readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hp_readout.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_hp_readout.z_index = 8
		hp_bar.add_child(_hp_readout)
	_style_hud_label(_hp_readout, 13, UIPalette.TEXT_PRIMARY)
	_update_hp_readout(int(hp_bar.value), int(hp_bar.max_value))


func _update_hp_readout(current: int, maximum: int) -> void:
	if _hp_readout != null:
		_hp_readout.text = "生命  %d / %d" % [current, maximum]


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
	if (
		mode.has_signal("extraction_ready")
		and not mode.extraction_ready.is_connected(_on_extraction_ready)
	):
		mode.extraction_ready.connect(_on_extraction_ready)
	if mode.has_signal("floor_changed") and not mode.floor_changed.is_connected(_on_floor_changed):
		mode.floor_changed.connect(_on_floor_changed)
	if mode.has_signal("kill_recorded") and not mode.kill_recorded.is_connected(_on_kill_recorded):
		mode.kill_recorded.connect(_on_kill_recorded)
	if (
		mode.has_signal("wave_progress_changed")
		and not mode.wave_progress_changed.is_connected(_on_wave_progress_changed)
	):
		mode.wave_progress_changed.connect(_on_wave_progress_changed)
	# 小地图随地图生成和房间切换刷新
	if (
		mode.has_signal("map_generated")
		and not mode.map_generated.is_connected(_on_map_generated_for_minimap)
	):
		mode.map_generated.connect(_on_map_generated_for_minimap)
	if (
		mode.has_signal("room_entered")
		and not mode.room_entered.is_connected(_on_room_entered_for_minimap)
	):
		mode.room_entered.connect(_on_room_entered_for_minimap)
	if (
		mode.has_signal("adjacent_rooms_revealed")
		and not mode.adjacent_rooms_revealed.is_connected(_on_adjacent_rooms_revealed)
	):
		mode.adjacent_rooms_revealed.connect(_on_adjacent_rooms_revealed)


## 绑定玩家（用于闪避冷却条等）
func set_player(player: Node) -> void:
	_disconnect_bound_player()
	_bound_player = player
	if player == null or not is_instance_valid(player):
		_player_state_id = "offline"
		_player_low_health = false
		_player_status_effects.clear()
		_refresh_player_state_panel(false)
		return
	if (
		player
		and player.has_signal("dash_cooldown_changed")
		and not player.dash_cooldown_changed.is_connected(_on_dash_cooldown_changed)
	):
		player.dash_cooldown_changed.connect(_on_dash_cooldown_changed)
	if (
		player
		and player.has_signal("dash_started")
		and not player.dash_started.is_connected(_on_dash_started)
	):
		player.dash_started.connect(_on_dash_started)
	_connect_player_signal(player, "hp_changed", update_hp)
	_connect_player_signal(player, "presentation_state_changed", _on_player_presentation_state_changed)
	_connect_player_signal(player, "low_health_changed", _on_player_low_health_changed)
	_connect_player_signal(player, "damage_taken", _on_player_damage_taken)
	_connect_player_signal(player, "status_effect_changed", _on_player_status_effect_changed)
	_connect_player_signal(player, "weapon_instance_changed", _on_weapon_instance_changed)
	if player.has_method("get_presentation_state"):
		_player_state_id = str(player.call("get_presentation_state"))
	if player.has_method("is_low_health"):
		_player_low_health = bool(player.call("is_low_health"))
	_player_status_effects["silenced"] = bool(player.get("_is_silenced"))
	var maximum := maxi(1, int(player.get("max_hp")))
	var current := clampi(int(player.get("current_hp")), 0, maximum)
	_player_hp_ratio = float(current) / float(maximum)
	update_hp(current, maximum)
	_refresh_player_state_panel(false)
	# 让低血量 Vignette 直接监听玩家 HP 信号
	if _health_vignette and _health_vignette.has_method("set_player_ref"):
		_health_vignette.set_player_ref(player)
	# 连接武器弹药信号
	_bind_weapon_signals(player)
	_bind_weapon_panel(player)
	_update_equipped_weapon_slot()


func _connect_player_signal(player: Node, signal_name: StringName, callback: Callable) -> void:
	if player.has_signal(signal_name) and not player.is_connected(signal_name, callback):
		player.connect(signal_name, callback)


func _disconnect_bound_player() -> void:
	if _bound_player == null or not is_instance_valid(_bound_player):
		return
	var bindings: Array = [
		["dash_cooldown_changed", _on_dash_cooldown_changed],
		["dash_started", _on_dash_started],
		["hp_changed", update_hp],
		["presentation_state_changed", _on_player_presentation_state_changed],
		["low_health_changed", _on_player_low_health_changed],
		["damage_taken", _on_player_damage_taken],
		["status_effect_changed", _on_player_status_effect_changed],
		["weapon_instance_changed", _on_weapon_instance_changed],
	]
	for binding in bindings:
		var signal_name := StringName(binding[0])
		var callback := Callable(binding[1])
		if _bound_player.has_signal(signal_name) and _bound_player.is_connected(signal_name, callback):
			_bound_player.disconnect(signal_name, callback)


func _on_player_presentation_state_changed(state_id: String, _context: Dictionary) -> void:
	_player_state_id = state_id
	_refresh_player_state_panel(true)


func _on_player_low_health_changed(active: bool, hp_ratio: float) -> void:
	_player_low_health = active
	_player_hp_ratio = clampf(hp_ratio, 0.0, 1.0)
	_refresh_player_state_panel(true)


func _on_player_damage_taken(_amount: int, current: int, maximum: int) -> void:
	update_hp(current, maximum)
	_play_hp_damage_feedback()


func _on_player_status_effect_changed(effect_id: String, active: bool, _duration: float) -> void:
	_player_status_effects[effect_id] = active
	_refresh_player_state_panel(true)


func _refresh_player_state_panel(animate: bool = true) -> void:
	if player_state_panel == null:
		return
	var profile := _player_state_profile(_player_state_id)
	var accent: Color = profile.get("color", UIPalette.BORDER_NORMAL)
	if _player_low_health:
		accent = UIPalette.HP_LOW
	elif bool(_player_status_effects.get("silenced", false)):
		accent = Color(0.72, 0.38, 1.0, 1.0)
	var urgent := _player_low_health or _player_state_id in ["hurt", "dead"]
	var style := UIStyleFactory.make_panel_with_border(1, accent, 6, 2 if urgent else 1)
	style.content_margin_left = 8.0
	style.content_margin_top = 5.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 5.0
	if _player_state_id == "dead":
		style.bg_color = Color(0.11, 0.025, 0.035, 0.96)
	player_state_panel.add_theme_stylebox_override("panel", style)
	if player_state_accent != null:
		player_state_accent.color = accent
	if player_state_label != null:
		player_state_label.text = str(profile.get("label", "姿态 · 未知"))
		player_state_label.add_theme_color_override("font_color", accent.lightened(0.24))
		_style_hud_label(player_state_label, 14, accent.lightened(0.24))
	if player_status_label != null:
		_style_hud_label(player_status_label, 11, UIPalette.TEXT_SECONDARY)
	_update_player_status_text(profile)
	if animate:
		_pulse_player_state_panel()


func _player_state_profile(state_id: String) -> Dictionary:
	match state_id:
		"idle":
			return {"label": "姿态 · 待命", "detail": "生命维持系统稳定", "color": Color(0.38, 0.70, 0.82)}
		"moving":
			return {"label": "姿态 · 机动", "detail": "地形辅助接合", "color": Color(0.28, 0.86, 0.92)}
		"dashing":
			return {"label": "姿态 · 突进", "detail": "推进器瞬时过载", "color": Color(0.50, 0.90, 1.0)}
		"hurt":
			return {"label": "姿态 · 受创", "detail": "装甲正在吸收冲击", "color": Color(1.0, 0.34, 0.28)}
		"locked":
			return {"label": "姿态 · 交互锁定", "detail": "武器保险已接合", "color": Color(0.96, 0.72, 0.24)}
		"dead":
			return {"label": "生命终止", "detail": "生命维持系统离线", "color": Color(0.82, 0.16, 0.19)}
		"offline":
			return {"label": "状态链路离线", "detail": "等待作战单位接入", "color": UIPalette.TEXT_DISABLED}
		_:
			return {"label": "姿态 · 未知", "detail": "状态遥测异常", "color": UIPalette.BORDER_NORMAL}


func _update_player_status_text(profile: Dictionary = {}) -> void:
	if player_status_label == null:
		return
	var alerts: Array[String] = []
	if _player_low_health:
		alerts.append("CRITICAL %02d%%" % roundi(_player_hp_ratio * 100.0))
	if bool(_player_status_effects.get("silenced", false)):
		var remaining := 0.0
		if _bound_player != null and is_instance_valid(_bound_player):
			remaining = maxf(0.0, float(_bound_player.get("_silence_timer")))
		alerts.append("JAMMED %.1fs" % remaining)
	if alerts.is_empty():
		if profile.is_empty():
			profile = _player_state_profile(_player_state_id)
		player_status_label.text = str(profile.get("detail", "状态同步"))
	else:
		player_status_label.text = "  /  ".join(alerts)


func _pulse_player_state_panel() -> void:
	if player_state_panel == null:
		return
	if _player_state_tween != null and is_instance_valid(_player_state_tween):
		_player_state_tween.kill()
	player_state_panel.pivot_offset = player_state_panel.size * 0.5
	player_state_panel.scale = Vector2(1.055, 0.94)
	player_state_panel.modulate = Color(1.22, 1.22, 1.22, 1.0)
	_player_state_tween = player_state_panel.create_tween()
	_player_state_tween.set_parallel(true)
	_player_state_tween.tween_property(player_state_panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_player_state_tween.tween_property(player_state_panel, "modulate", Color.WHITE, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _play_hp_damage_feedback() -> void:
	var hp_panel := get_node_or_null("GameHUD/HPBarBG") as Control
	if hp_panel == null:
		return
	if _hp_damage_tween != null and is_instance_valid(_hp_damage_tween):
		_hp_damage_tween.kill()
	hp_panel.pivot_offset = hp_panel.size * 0.5
	hp_panel.scale = Vector2(1.06, 0.88)
	hp_panel.rotation = -0.018
	if _hp_readout != null:
		_hp_readout.add_theme_color_override("font_color", Color(1.0, 0.66, 0.58))
	_hp_damage_tween = hp_panel.create_tween()
	_hp_damage_tween.set_parallel(true)
	_hp_damage_tween.tween_property(hp_panel, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_hp_damage_tween.tween_property(hp_panel, "rotation", 0.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if _hp_readout != null:
		_hp_damage_tween.tween_callback(func() -> void: _style_hud_label(_hp_readout, 13, UIPalette.TEXT_PRIMARY)).set_delay(0.18)


func get_player_state_widget_snapshot() -> Dictionary:
	return {
		"visible": player_state_panel != null and player_state_panel.visible,
		"state": _player_state_id,
		"low_health": _player_low_health,
		"silenced": bool(_player_status_effects.get("silenced", false)),
		"state_text": player_state_label.text if player_state_label != null else "",
		"status_text": player_status_label.text if player_status_label != null else "",
		"rect": player_state_panel.get_global_rect() if player_state_panel != null else Rect2(),
	}


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
		if not wt.fire_cooldown_changed.is_connected(_on_fire_cooldown_changed):
			wt.fire_cooldown_changed.connect(_on_fire_cooldown_changed.bind())
		if not wt.tree_changed.is_connected(_update_equipped_weapon_slot):
			wt.tree_changed.connect(_update_equipped_weapon_slot)
	else:
		# Player 还没准备好时下一空闲帧重试；UI 销毁后 deferred 调用自动失效。
		call_deferred("_retry_bind_weapon_signals", player)


func _retry_bind_weapon_signals(player: Node) -> void:
	if player and is_instance_valid(player) and player.has_method("get_weapon_tree"):
		_bind_weapon_signals(player)


func _bind_weapon_panel(player: Node) -> void:
	if player == null or not is_instance_valid(player) or not player.has_method("get_weapon_tree"):
		return
	if _weapon_panel == null:
		_weapon_panel = _WEAPON_PANEL_SCENE.instantiate() as Control
		_weapon_panel.name = "WeaponAssemblyTreePanel"
		_weapon_panel.position = Vector2(18, 96)
		add_child(_weapon_panel)
	var wt = player.get_weapon_tree()
	if wt != null and _weapon_panel.has_method("set_weapon_tree"):
		_weapon_panel.call("set_weapon_tree", wt)
	if _weapon_panel.has_method("set_weapon_owner"):
		_weapon_panel.call("set_weapon_owner", player)


## 绑定背包模块
func set_inventory_module(module: Object) -> void:
	_inventory_module = module
	if module == null:
		return
	if (
		module.has_signal("inventory_changed")
		and not module.inventory_changed.is_connected(_on_inventory_changed)
	):
		module.inventory_changed.connect(_on_inventory_changed)
	if (
		module.has_signal("capacity_changed")
		and not module.capacity_changed.is_connected(_on_capacity_changed)
	):
		module.capacity_changed.connect(_on_capacity_changed)
	_refresh_inventory_ui()
	_on_inventory_changed()


## 绑定保险格模块
func set_insurance_module(module: Object) -> void:
	_insurance_module = module
	if module == null:
		return
	if (
		module.has_signal("insurance_changed")
		and not module.insurance_changed.is_connected(_on_insurance_changed)
	):
		module.insurance_changed.connect(_on_insurance_changed)
	_refresh_insurance_ui()


## 绑定撤离模块
func set_extraction_module(module: Object) -> void:
	_extraction_module = module
	if module != null:
		_connect_extraction_module_signals(module)


## 更新 HP 显示
func update_hp(current: int, maximum: int) -> void:
	_player_hp_ratio = float(current) / maxf(1.0, float(maximum))
	if hp_bar:
		hp_bar.max_value = maximum
		hp_bar.value = current
		# 尾迹：只在 HP 下降时追尾（不追上当前值）
		if hp_bar_trail:
			hp_bar_trail.max_value = maximum
			if hp_bar_trail.value > float(current):
				_start_hp_trail_catchup(float(current))
		_update_hp_bar_color()
	_update_hp_readout(current, maximum)


## 启动 HP 尾迹追尾动画（0.4s 追上当前 HP 值）
func _start_hp_trail_catchup(target_value: float) -> void:
	if hp_bar_trail == null:
		return
	if _hp_trail_tween != null and is_instance_valid(_hp_trail_tween):
		_hp_trail_tween.kill()
	_hp_trail_tween = hp_bar_trail.create_tween()
	_hp_trail_tween.tween_property(
		hp_bar_trail, "value", target_value, 0.4,
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## 根据 HP 比例调整红色生命条亮度
var _last_hp_color_ratio: float = -1.0  ## 上次刷新的 HP 比例（带 0.1 deadzone 防抖）
func _update_hp_bar_color() -> void:
	if hp_bar == null or hp_bar.max_value <= 0.0:
		return
	var ratio: float = hp_bar.value / hp_bar.max_value
	# 0.1 阈值 deadzone，避免每帧抖动
	if absf(ratio - _last_hp_color_ratio) < 0.1 and _last_hp_color_ratio >= 0.0:
		return
	_last_hp_color_ratio = ratio
	# 生命条始终使用红色生命语义；危险程度由亮度、抖动与暗红拖尾表达。
	var fill_color := Color(0.92, 0.08, 0.10, 1.0).lerp(
		Color(1.0, 0.24, 0.20, 1.0), 1.0 - ratio
	)
	hp_bar.add_theme_stylebox_override("fill", UIStyleFactory.make_progress_fill(fill_color))
	# 尾迹颜色：始终是比当前色暗一档的同色（看起来像褪色的尾）
	var trail_color: Color = fill_color
	trail_color.r *= 0.55
	trail_color.g *= 0.55
	trail_color.b *= 0.55
	hp_bar_trail.add_theme_stylebox_override("fill", UIStyleFactory.make_progress_fill(trail_color))


## 更新分数（带跳动动画 + 描边）
func update_score(score_val: int) -> void:
	if score_label:
		score_label.text = "战绩  %06d" % score_val
		score_label.set_meta("score_value", score_val)
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


## 更新风险等级显示（由 RoomGameMode 调用）
func update_risk(level: int) -> void:
	if risk_label:
		risk_label.text = "风险: %d" % level
		_risk_outline_sync()


## 更新暴击堆栈显示（由 CoreCombatMode/RoomGameMode 调用）
## 显示当前蓄势待发的"击杀后必暴击"剩余层数
func update_crit_stacks(count: int) -> void:
	if crit_label:
		if count > 0:
			crit_label.text = "暴击: %d" % count
			crit_label.modulate = Color(1.0, 0.88, 0.15, 1.0)  # 金黄色高亮
		else:
			crit_label.text = "暴击: 0"  # 0层时显示而非清空，保持存在感
			crit_label.modulate = Color(1.0, 0.88, 0.15, 0.6)  # 灰色半透明


var _risk_outline_done: bool = false


func _risk_outline_sync() -> void:
	if _risk_outline_done or risk_label == null:
		return
	_risk_outline_done = true


## 连接 ExtractionModule 信号（由 set_extraction_module 调用）
func _connect_extraction_module_signals(module: Object) -> void:
	if module == null:
		return
	if (
		module.has_signal("extraction_completed")
		and not module.extraction_completed.is_connected(_on_extraction_completed)
	):
		module.extraction_completed.connect(_on_extraction_completed)
	if (
		module.has_signal("extraction_progress_updated")
		and not module.extraction_progress_updated.is_connected(_on_extraction_progress_updated)
	):
		module.extraction_progress_updated.connect(_on_extraction_progress_updated)
	if (
		module.has_signal("extraction_aborted")
		and not module.extraction_aborted.is_connected(_on_extraction_aborted)
	):
		module.extraction_aborted.connect(_on_extraction_aborted)


## 撤离读条进度更新
func _on_extraction_progress_updated(progress: float) -> void:
	if countdown_bar:
		countdown_bar.value = progress
		var total: float = _active_extraction_duration
		var remaining: float = (1.0 - progress) * total
		_update_countdown_label(remaining, total)


## 显示货币飘字（在指定世界坐标显示 +N魂 飘字）
## world_pos: 世界坐标（会被转换到 CanvasLayer 坐标系）
## amount: 货币数量（正数显示为绿色 +N魂，负数显示为红色 -N魂）
func show_currency_popup(amount: int, world_pos: Vector2) -> void:
	var popup_label := Label.new()
	popup_label.text = "+%d魂" % amount if amount > 0 else "%d魂" % amount
	popup_label.add_theme_color_override(
		"font_color", Color(0.3, 1.0, 0.4, 1.0) if amount > 0 else Color(1.0, 0.3, 0.3, 1.0)
	)
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
	(
		tween
		. tween_property(popup_label, "position:y", canvas_pos.y - 60, 1.5)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	tween.chain().tween_property(popup_label, "modulate:a", 0.0, 0.5).set_delay(1.0)
	tween.chain().tween_callback(popup_label.queue_free)


func show_damage_popup(world_pos: Vector2, damage: int, is_crit: bool = false) -> void:
	var label := Label.new()
	label.text = str(damage) + ("!" if is_crit else "")
	label.add_theme_font_size_override("font_size", 28 if is_crit else 18)
	label.add_theme_color_override(
		"font_color", Color(1.0, 0.92, 0.15, 1.0) if is_crit else Color(1.0, 0.36, 0.18, 1.0)
	)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.z_index = 260
	var start_pos := (
		_world_to_canvas(world_pos) + Vector2(randf_range(-10, 10), -28 + randf_range(-6, 6))
	)
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
	tween.chain().tween_callback(
		func():
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
func _on_container_loot_granted(
	world_pos: Vector2, items: Array[Dictionary], granted_count: int
) -> void:
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
		# 后续物品用 Tween 延迟依次飘出，不创建跨场景 SceneTreeTimer 协程。
		for i in range(min(items.size(), 5)):
			var item_data: Dictionary = items[i]
			var item_name: String = item_data.get("name", item_data.get("id", "?"))
			var count: int = item_data.get("count", 1)
			var offset_pos: Vector2 = canvas_pos + Vector2(randi() % 40 - 20, -30 - i * 20)
			var item_label := Label.new()
			item_label.z_index = 200
			item_label.add_theme_font_size_override("font_size", 12)
			item_label.modulate = Color(0.8, 0.8, 0.6, 0.0)
			item_label.text = "+%s x%d" % [item_name, count] if count > 1 else "+%s" % item_name
			item_label.global_position = offset_pos
			add_child(item_label)
			_fly_and_fade(item_label, offset_pos, 0.18 + i * 0.12, 0.9)


## 小地图刷新信号处理
func _on_map_generated_for_minimap(graph: NodeGraph) -> void:
	_minimap_dirty = true


func _on_room_entered_for_minimap(room_data: RoomData) -> void:
	_minimap_dirty = true
	# 根据房间类型更新 room_info_label（中文显示）
	if room_info_label and room_data != null:
		var type_name := ""
		var floor_desc := "第%d关" % room_data.floor
		# 垂直层信息
		if room_data.vertical_level != RoomData.VerticalLevel.MAIN:
			var vname := RoomData.get_vertical_level_name(room_data.vertical_level)
			floor_desc += " [%s]" % vname
		
		match room_data.room_type:
			RoomData.RoomType.PLAYER_SPAWN:
				type_name = "玩家出生"
			RoomData.RoomType.COMBAT:
				type_name = "普通战斗"
			RoomData.RoomType.ELITE:
				type_name = "精英战斗"
			RoomData.RoomType.SCAVENGE:
				type_name = "搜刮"
			RoomData.RoomType.MERCHANT:
				type_name = "商人"
			RoomData.RoomType.UPGRADE:
				type_name = "改造"
			RoomData.RoomType.EVENT:
				type_name = "事件"
			RoomData.RoomType.EXTRACTION:
				type_name = "撤离"
			RoomData.RoomType.BOSS:
				type_name = "Boss"
			RoomData.RoomType.BASEMENT:
				type_name = "地下室"
			RoomData.RoomType.STAIRS_DOWN:
				type_name = "楼梯口(下)"
			RoomData.RoomType.STAIRS_UP:
				type_name = "楼梯口(上)"
			RoomData.RoomType.ELEVATOR:
				type_name = "电梯"
			_:
				type_name = "房间"
		room_info_label.text = "%s · %s" % [floor_desc, type_name]


## 小地图 REVEAL 事件信号处理（地图揭示后刷新小地图）
func _on_adjacent_rooms_revealed(room_id: String, revealed_count: int) -> void:
	print("[GameUIManager] 小地图刷新：REVEAL事件揭示了 %d 个相邻房间 from room %s" % [revealed_count, room_id])
	# 重建小地图节点数据（读取 MapManager 中已更新的 revealed 元数据）
	_refresh_minimap_nodes()
	_minimap_dirty = true


## 飘字动画：Y 上浮 + 淡出消失
func _fly_and_fade(label: Label, start_pos: Vector2, delay: float = 0.0, target_alpha: float = 1.0) -> void:
	var tween := label.create_tween()
	if delay > 0.0:
		tween.tween_interval(delay)
		tween.tween_property(label, "modulate:a", target_alpha, 0.05)
	tween.tween_property(label, "position:y", start_pos.y - 50, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.5).set_delay(0.7)
	tween.chain().tween_callback(label.queue_free)


## 更新楼层
func update_floor(floor: int) -> void:
	if wave_label:
		wave_label.text = "深度  %02d" % floor
		wave_label.set_meta("floor_value", floor)
		_bounce_label(wave_label)
		_sync_wave_outline()


## — 小地图绘制（v0.1 P1）—
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
		_push_minimap_data()
		return
	var mm = _room_game_mode.get_map_manager()
	var graph: NodeGraph = mm.get_graph() if mm else null
	if graph == null:
		_push_minimap_data()
		return
	var nodes: Array = graph.get_all_nodes()
	var current_room_id: int = (
		mm.get_current_room_id() if mm.has_method("get_current_room_id") else -1
	)

	# 玩家世界位置
	var player_world_pos: Vector2 = Vector2.ZERO
	var player_ref: Node = mm.get_player() if mm.has_method("get_player") else null
	if player_ref and is_instance_valid(player_ref):
		player_world_pos = player_ref.global_position

	# 缓存房间世界坐标（用于连接线绘制和玩家相对偏移）
	var node_pos_by_id: Dictionary = {}
	for node in nodes:
		node_pos_by_id[node.id] = node.position

	# 收集节点数据
	for node in nodes:
		var rd: RoomData = node.room_data
		_minimap_nodes.append(
			{
				"id": node.id,
				"node_pos": node.position,
				"type": rd.room_type,
				"is_current": node.id == current_room_id,
				"is_revealed": rd.get_meta("revealed") if rd.has_meta("revealed") else true,
			}
		)

	# 收集门连接（含开闭状态 + 门类型）
	var connections: Array[Dictionary] = []
	var pd = mm.path_director if mm else null
	if pd != null:
		for node in nodes:
			var open_info: Array[Dictionary] = pd.get_open_door_info(node.id)
			for info in open_info:
				var from_id: int = info.get("from_id", -1)
				var to_id: int = info.get("to_id", -1)
				var from_pos: Vector2 = node_pos_by_id.get(from_id, Vector2.ZERO)
				var to_pos: Vector2 = node_pos_by_id.get(to_id, Vector2.ZERO)
				connections.append(
					{
						"from_pos": from_pos,
						"to_pos": to_pos,
						"is_open": info.get("is_open", false),
						"door_type": info.get("door_type", "normal"),
					}
				)
			# 未开启的门（PathDirector 暂未暴露 list_closed_doors，遍历 connections）
			for conn_id in node.connections:
				if pd.are_connected(node.id, conn_id):
					continue  # 已开门
				# 闭合门：补充虚线
				connections.append(
					{
						"from_pos": node_pos_by_id.get(node.id, Vector2.ZERO),
						"to_pos": node_pos_by_id.get(conn_id, Vector2.ZERO),
						"is_open": false,
						"door_type": "normal",
					}
				)

	# 当前房间世界坐标（用于玩家点偏移）
	var current_node_pos: Vector2 = node_pos_by_id.get(current_room_id, Vector2.ZERO)
	_minimap_player_node_id = current_room_id

	# 推送给 MinimapView
	_minimap_dirty = true
	_push_minimap_data(true)


## 推数据到 MinimapView（自身决定如何 set_data）
func _push_minimap_data(force: bool = false) -> void:
	if _minimap_view == null:
		return
	if _minimap_nodes.is_empty():
		_minimap_view.clear()
		return
	if not force and not _minimap_dirty:
		return
	_minimap_dirty = false

	# 玩家世界位置（实时）
	var player_world_pos: Vector2 = Vector2.ZERO
	var player_node_pos: Vector2 = Vector2.ZERO
	if _room_game_mode and _room_game_mode.has_method("get_player"):
		var p: Node = _room_game_mode.get_player()
		if p and is_instance_valid(p):
			player_world_pos = p.global_position
	# 找当前房间世界坐标
	for nd in _minimap_nodes:
		if nd.get("is_current", false):
			player_node_pos = nd.get("node_pos", Vector2.ZERO)
			break

	# 收集 connections（与 _refresh_minimap_nodes 同步）
	var connections: Array[Dictionary] = []
	if _room_game_mode and _room_game_mode.has_method("get_map_manager"):
		var mm = _room_game_mode.get_map_manager()
		var pd = mm.path_director if mm else null
		var graph: NodeGraph = mm.get_graph() if mm else null
		if pd != null and graph != null:
			var node_pos_by_id: Dictionary = {}
			for node in graph.get_all_nodes():
				node_pos_by_id[node.id] = node.position
			for node in graph.get_all_nodes():
				for info in pd.get_open_door_info(node.id):
					connections.append(
						{
							"from_pos": node_pos_by_id.get(info.get("from_id", -1), Vector2.ZERO),
							"to_pos": node_pos_by_id.get(info.get("to_id", -1), Vector2.ZERO),
							"is_open": info.get("is_open", false),
							"door_type": info.get("door_type", "normal"),
						}
					)
				for conn_id in node.connections:
					if pd.are_connected(node.id, conn_id):
						continue
					connections.append(
						{
							"from_pos": node_pos_by_id.get(node.id, Vector2.ZERO),
							"to_pos": node_pos_by_id.get(conn_id, Vector2.ZERO),
							"is_open": false,
							"door_type": "normal",
						}
					)

	_minimap_view.set_data(_minimap_nodes, connections, player_world_pos, player_node_pos)


func refresh_minimap() -> void:
	_minimap_dirty = true
	_push_minimap_data(true)


## 房间清理完成
func _on_room_cleared(room_data) -> void:
	if room_info_label:
		room_info_label.text = "房间清理完成！"
	clearing_progress.visible = false
	# 显示命运卡片选择界面（而非仅显示文字提示）
	_show_fate_card_selection_ui()
	# 波次完成庆祝：飘字 + 震屏（Boss 房显示"Boss 已击败！"）
	var room_type_val: int = -1
	if room_data is RoomData:
		room_type_val = int(room_data.room_type)
	elif room_data is Dictionary and room_data.has("room_type"):
		room_type_val = int(room_data.get("room_type", -1))
	_show_wave_complete_celebration(room_type_val)


## 显示命运卡片选择界面（通过 room_game_mode 获取 FateCardUIController 并调用 show_card_selection）
func _show_fate_card_selection_ui() -> void:
	if _room_game_mode == null or not is_instance_valid(_room_game_mode):
		return
	# 从 RoomGameMode/DemoRoomGameMode 获取已实例化的 FateCardUIController
	var fate_ui: Control = _room_game_mode._get_fate_card_controller()
	if fate_ui != null and fate_ui.has_method("show_card_selection"):
		fate_ui.call("show_card_selection")
	else:
		# 兜底：仍显示文字提示
		_show_fate_card_notification()


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
	(
		tween
		. tween_property(celebration_label, "modulate:a", 1.0, 0.3)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	(
		tween
		. tween_property(celebration_label, "scale", Vector2(1.0, 1.0), 0.3)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	# 停留 0.8s
	tween.chain().set_parallel(false)
	tween.chain().tween_interval(0.8)
	# 飘出 + 淡出
	tween.chain().set_parallel(true)
	(
		tween
		. tween_property(celebration_label, "modulate:a", 0.0, 0.5)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN)
	)
	(
		tween
		. chain()
		. tween_property(celebration_label, "position:y", celebration_label.position.y - 30, 0.5)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_IN)
	)
	tween.chain().tween_callback(
		func():
			if celebration_label and is_instance_valid(celebration_label):
				celebration_label.queue_free()
	)

	# 波次完成震屏效果（比伤害震屏轻，用于强化"完成了"的节拍感）
	if _screen_shake and _screen_shake.has_method("trigger"):
		_screen_shake.call("trigger", 4.0, 0.10)


## — Boss 事件处理器（由 RoomGameMode 调用）—
## Boss 出现时回调（显示 Boss HP UI + 出场公告）
func on_boss_spawned(boss_data: Dictionary) -> void:
	var boss_name: String = boss_data.get("boss_id", "BOSS")
	var max_hp: float = boss_data.get("max_hp", 500.0)
	var current_hp: float = max_hp
	# 出场公告：先闪白提示 Boss 名称（0.6秒），再显示血条
	_flashte_boss_name_label(boss_name)
	show_boss_hp(boss_name, max_hp, current_hp)


## Boss 出场时名字闪烁公告（先白闪提示，再切回 room_info_label）
func _flashte_boss_name_label(boss_name: String) -> void:
	if room_info_label == null:
		return
	# 记录原始文字，恢复后用
	var original_text: String = room_info_label.text
	var original_color: Color = room_info_label.get_theme_color("font_color")
	# 白闪烁公告
	room_info_label.text = "⚔ %s 出现了！" % boss_name
	room_info_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.95, 1.0))
	# 0.7 秒后恢复 room_info_label 原始颜色和文字
	var t := create_tween()
	t.tween_interval(0.7)
	t.tween_callback(_restore_room_info_label.bind(original_text, original_color))
	# 演出：大横幅 + 屏幕震动 + 屏幕白闪
	_play_boss_intro_animation(boss_name)


## Boss 出场大横幅演出
## 1. 屏幕震动 (0.4s)
## 2. 全屏白闪 (0.3s)
## 3. 居中大横幅 (0.7s, 1.0x scale->1.15x->1.0x, 淡入淡出)
func _play_boss_intro_animation(boss_name: String) -> void:
	# 屏幕震动
	var shake: Node = get_tree().root.find_child("ScreenShake", true, false)
	if shake != null and shake.has_method("trigger"):
		shake.call("trigger", 14.0, 0.4)
	# 全屏白闪
	var flash := ColorRect.new()
	flash.name = "BossIntroFlash"
	flash.color = Color(1.0, 1.0, 1.0, 0.0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = 450
	add_child(flash)
	var flash_tween := flash.create_tween()
	flash_tween.tween_property(flash, "color:a", 0.5, 0.06)
	flash_tween.tween_property(flash, "color:a", 0.0, 0.30)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	flash_tween.tween_callback(flash.queue_free)
	# 居中大横幅
	_show_boss_intro_banner(boss_name)


## Boss 出场大横幅 (label + 阴影，1.7s 自动消失)
func _show_boss_intro_banner(boss_name: String) -> void:
	var banner := Label.new()
	banner.name = "BossIntroBanner"
	banner.text = "⚔ %s ⚔" % boss_name
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", 56)
	banner.add_theme_color_override("font_color", UIPalette.TEXT_GOLD)
	# 描边
	banner.add_theme_constant_override("shadow_offset_x", 3)
	banner.add_theme_constant_override("shadow_offset_y", 3)
	banner.add_theme_color_override("font_shadow_color", Color(0.4, 0.0, 0.0, 0.95))
	banner.modulate = Color(1, 1, 1, 0)
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.custom_minimum_size = Vector2(800, 80)
	banner.pivot_offset = Vector2(400, 40)
	banner.scale = Vector2(0.7, 0.7)
	banner.z_index = 460
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(banner)
	var t := banner.create_tween()
	# 弹入（0.7 -> 1.15 -> 1.0）
	t.tween_property(banner, "modulate:a", 1.0, 0.18)
	t.tween_property(banner, "scale", Vector2(1.15, 1.15), 0.18)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(banner, "scale", Vector2(1.0, 1.0), 0.10)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 停留 0.7s
	t.tween_interval(0.7)
	# 淡出
	t.tween_property(banner, "modulate:a", 0.0, 0.40)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(banner.queue_free)


func _restore_room_info_label(original_text: String, original_color: Color) -> void:
	if room_info_label == null:
		return
	room_info_label.text = original_text
	room_info_label.add_theme_color_override("font_color", original_color)


## Boss 受伤时回调（更新 Boss HP 条）
func on_boss_damaged(boss_id: String, damage: float, new_hp: float) -> void:
	_boss_current_hp = new_hp
	if _boss_hp_bar != null:
		_boss_hp_bar.value = new_hp
	_update_boss_hp_label()


## Boss 阶段切换时回调（目前仅日志记录，Boss 血条 UI 可后续扩展）
func on_boss_phase_changed(boss_id: String, new_phase: int) -> void:
	room_info_label.text = "Boss 进入阶段 %d！" % new_phase


## Boss 被击败时回调（目前仅日志记录）
func on_boss_defeated(boss_id: String, rewards: Dictionary) -> void:
	room_info_label.text = "Boss 已击败！"
	_hide_boss_hp_ui()
	_show_boss_defeated_victory()
	_trigger_boss_defeated_screen_effects()


## Boss击败后的胜利提示文字动画
func _show_boss_defeated_victory() -> void:
	var victory_label := Label.new()
	victory_label.name = "BossDefeatedVictory"
	victory_label.text = "✦ BOSS DEFEATED ✦"
	victory_label.position = Vector2(640, 400)
	victory_label.size = Vector2(600, 60)
	victory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	victory_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	victory_label.add_theme_font_size_override("font_size", 42)
	victory_label.modulate.a = 0.0
	victory_label.z_index = 2000
	add_child(victory_label)

	var tween := victory_label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(victory_label, "modulate:a", 1.0, 0.2)
	tween.tween_property(victory_label, "position:y", 350.0, 0.5)
	tween.chain().tween_property(victory_label, "modulate:a", 0.0, 0.6)
	tween.chain().tween_callback(victory_label.queue_free)


## Boss击败时的屏幕震动+白闪特效（通过 ScreenShake）
func _trigger_boss_defeated_screen_effects() -> void:
	var shake: Node = get_tree().root.find_child("ScreenShake", true, false)
	if shake != null:
		if shake.has_method("screen_shake_death"):
			shake.call("screen_shake_death")
		elif shake.has_method("trigger"):
			shake.call("trigger", 22.0, 0.5)
		if shake.has_method("screen_flash"):
			shake.call("screen_flash", Color(1.0, 1.0, 1.0, 0.8), 0.2)


## — Boss HP UI 初始化 —
func _init_boss_hp_ui() -> void:
	# 创建 Boss HP 面板（居中屏幕顶部，战斗时显示）
	_boss_hp_panel = PanelContainer.new()
	_boss_hp_panel.name = "BossHPPanel"
	_boss_hp_panel.anchors_preset = 7  # Center horizontal, top
	_boss_hp_panel.anchor_left = 0.5
	_boss_hp_panel.anchor_top = 0.0
	_boss_hp_panel.anchor_right = 0.5
	_boss_hp_panel.anchor_bottom = 0.0
	_boss_hp_panel.offset_left = -180.0
	_boss_hp_panel.offset_top = 16.0
	_boss_hp_panel.offset_right = 180.0
	_boss_hp_panel.offset_bottom = 70.0
	_boss_hp_panel.grow_horizontal = 2
	_boss_hp_panel.visible = false
	add_child(_boss_hp_panel)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.alignment = VBoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 4)
	_boss_hp_panel.add_child(vbox)

	# Boss 名称标签
	_boss_name_label = Label.new()
	_boss_name_label.name = "BossNameLabel"
	_boss_name_label.text = "BOSS"
	_boss_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_name_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3, 1.0))
	_boss_name_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_boss_name_label)

	# Boss HP 条背景
	var hp_bg := PanelContainer.new()
	hp_bg.add_theme_stylebox_override("panel", _make_boss_hp_bg_style())
	vbox.add_child(hp_bg)

	# Boss HP 条（ProgressBar）
	_boss_hp_bar = ProgressBar.new()
	_boss_hp_bar.name = "BossHPBar"
	_boss_hp_bar.max_value = 100.0
	_boss_hp_bar.value = 100.0
	_boss_hp_bar.show_percentage = false
	_boss_hp_bar.custom_minimum_size = Vector2(340, 18)
	# 设置百分比文字颜色（浅色）
	_boss_hp_bar.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.8))
	# 设置 bar 填充样式（深红背景+亮红前景）
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(0.25, 0.05, 0.05, 1.0)
	fill_style.corner_radius_top_left = 3.0
	fill_style.corner_radius_top_right = 3.0
	fill_style.corner_radius_bottom_right = 3.0
	fill_style.corner_radius_bottom_left = 3.0
	_boss_hp_bar.add_theme_stylebox_override("fill", fill_style)
	hp_bg.add_child(_boss_hp_bar)

	# HP 数值标签
	_boss_hp_label = Label.new()
	_boss_hp_label.name = "BossHPLabel"
	_boss_hp_label.text = "100 / 100"
	_boss_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_hp_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1.0))
	_boss_hp_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_boss_hp_label)


## 创建 Boss HP 背景样式
func _make_boss_hp_bg_style() -> StyleBox:
	# Boss HP 背景使用偏暗红背景
	var style := UIStyleFactory.make_panel_with_border(0, Color(0.45, 0.20, 0.20, 0.85), 4, 0)
	style.content_margin_left = 4.0
	style.content_margin_top = 4.0
	style.content_margin_right = 4.0
	style.content_margin_bottom = 4.0
	return style


## 显示 Boss HP UI
func show_boss_hp(boss_name: String, max_hp: float, current_hp: float) -> void:
	if _boss_hp_panel == null:
		return
	_boss_max_hp = max_hp
	_boss_current_hp = current_hp
	_boss_name_label.text = boss_name
	_boss_hp_bar.max_value = max_hp
	_boss_hp_bar.value = current_hp
	_update_boss_hp_label()
	# 先重置到屏幕外上方（offset_top 为负 = 在可见区上方），然后播放滑入+淡入动画
	_boss_hp_panel.offset_top = -80.0
	_boss_hp_panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_boss_hp_panel.visible = true
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_boss_hp_panel, "offset_top", 16.0, 0.35)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(_boss_hp_panel, "modulate:a", 1.0, 0.3)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## 更新 Boss HP 数值显示
func _update_boss_hp_label() -> void:
	if _boss_hp_label != null:
		_boss_hp_label.text = "%d / %d" % [int(_boss_current_hp), int(_boss_max_hp)]


## 刷新 Boss HP（供外部调用）
func update_boss_hp(current_hp: float) -> void:
	_boss_current_hp = current_hp
	if _boss_hp_bar != null:
		_boss_hp_bar.value = current_hp
	_update_boss_hp_label()


## 隐藏 Boss HP UI
func _hide_boss_hp_ui() -> void:
	if _boss_hp_panel != null:
		_boss_hp_panel.visible = false


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
	ft.tween_property(flash, "color:a", 0.18, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(
		Tween.EASE_OUT
	)
	ft.chain().set_parallel(false)
	ft.chain().tween_property(flash, "color:a", 0.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(
		Tween.EASE_IN
	)
	ft.chain().tween_callback(
		func():
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
	if _extraction_success_shown:
		return
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
	tween.tween_callback(func() -> void:
		if _fate_card_notification_label != null and is_instance_valid(_fate_card_notification_label):
			_fate_card_notification_label.visible = false
	)


## 游戏结束
func _on_game_over(reason: String = "未知原因") -> void:
	# 构建死亡统计
	_death_stats["score"] = int(score_label.get_meta("score_value", 0)) if score_label else 0
	_death_stats["floor"] = int(wave_label.get_meta("floor_value", 1)) if wave_label else 1

	if death_title:
		death_title.text = "你已倒下"
	if reason_label:
		reason_label.text = "原因: %s" % reason
	if stats_label:
		stats_label.text = (
			"最终得分: %d\n击毙: %d\n存活楼层: %d"
			% [_death_stats["score"], _kill_count, _death_stats["floor"]]
		)
	if loot_label:
		loot_label.text = "战利品: 保险保住 %d 件 / 损失 %d 件" % [_death_loot["saved"], _death_loot["lost"]]

	if death_overlay:
		death_overlay.visible = true
	if game_over_panel:
		game_over_panel.visible = true
		# 允许在暂停状态下接收输入
		game_over_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	if retry_button:
		retry_button.process_mode = Node.PROCESS_MODE_ALWAYS
	if menu_button:
		menu_button.process_mode = Node.PROCESS_MODE_ALWAYS
	Global.acquire_pause("game_over")


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
	tween.chain().tween_property(label, "scale", Vector2(1.0, 1.0), 0.12).set_trans(
		Tween.TRANS_BOUNCE
	)


## 同步 ScoreLabel 描边
func _sync_score_outline() -> void:
	# HUD 标签统一使用主题 font_shadow；旧的 Label 副本会被 VBox 当成正式内容
	# 参与布局，导致楼层文字被推入生命条区域。
	if _score_outline_label != null:
		_score_outline_label.queue_free()
		_score_outline_label = null


## 同步 CurrencyLabel 描边
func _sync_currency_outline() -> void:
	if _currency_outline_label != null:
		_currency_outline_label.queue_free()
		_currency_outline_label = null


## 同步弹药描边（与 ammo_label 配合，弹药数值变化时同步描边副本）
func _sync_ammo_outline() -> void:
	if _ammo_outline_label != null:
		_ammo_outline_label.queue_free()
		_ammo_outline_label = null


## 同步 WaveLabel 描边
func _sync_wave_outline() -> void:
	if _wave_num_outline_label != null:
		_wave_num_outline_label.queue_free()
		_wave_num_outline_label = null


func _on_retry_pressed() -> void:
	Global.clear_pause_reasons()
	death_overlay.visible = false
	game_over_panel.visible = false
	get_tree().reload_current_scene()


func _on_menu_pressed() -> void:
	Global.clear_pause_reasons()
	death_overlay.visible = false
	game_over_panel.visible = false
	# 返回基地主界面（而非直接重新开始游戏）
	get_tree().change_scene_to_file(GameDesignConfig.BASE_SCENE_3D)


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
	if dash_label != null:
		dash_label.text = "机动  READY" if cooldown_ratio <= 0.02 else "机动  %02d%%" % int((1.0 - cooldown_ratio) * 100.0)


## 闪避启动时高亮
func _on_dash_started() -> void:
	if dash_cooldown_bar:
		dash_cooldown_bar.modulate = Color(0.6, 0.9, 1.0, 1.0)
		# 淡出高亮
		var t := dash_cooldown_bar.create_tween()
		t.tween_property(dash_cooldown_bar, "modulate", Color.WHITE, 0.3)


## 射速冷却进度更新（ratio: 1.0=就绪，0.0=冷却中）
func _on_fire_cooldown_changed(cooldown_ratio: float) -> void:
	if fire_rate_bar:
		fire_rate_bar.value = cooldown_ratio
	if fire_rate_label != null:
		fire_rate_label.text = "火力  READY" if cooldown_ratio >= 0.98 else "火力  %02d%%" % int(cooldown_ratio * 100.0)


## 波次进度更新（显示波次击杀状态 + 平滑动画）
func _on_wave_progress_changed(killed: int, total: int, wave: int) -> void:
	if total > 0:
		_wave_total = total
	if total == 0:
		total = max(1, _wave_total)

	var ratio: float = float(killed) / float(total)

	# 进度条更新
	if clearing_progress != null:
		var target := ratio * clearing_progress.max_value

		# 已有动画则停止，避免叠加
		if _wave_kill_anim_tween != null and _wave_kill_anim_tween.is_valid():
			_wave_kill_anim_tween.kill()

		# 进度条颜色变化
		if ratio < 0.5:
			clearing_progress.modulate = Color(1.0, 0.4 + ratio * 0.6, 0.2, 1.0)
		elif ratio < 0.8:
			clearing_progress.modulate = Color(1.0, 0.7 + (ratio - 0.5) * 1.0, 0.2 + (ratio - 0.5) * 0.8, 1.0)
		else:
			clearing_progress.modulate = Color(0.4 + ratio * 0.6, 1.0, 0.4, 1.0)

		# 平滑动画
		_wave_kill_anim_tween = clearing_progress.create_tween()
		_wave_kill_anim_tween.set_trans(Tween.TRANS_BACK)
		_wave_kill_anim_tween.tween_property(clearing_progress, "value", target, 0.2)

	# WaveLabel 文字同步更新（双保险：即便进度条失效，文字也正确）
	if wave_label != null:
		wave_label.text = "第 %d 波 | %d/%d" % [wave, killed, total]

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
		_wave_outline_label.add_theme_font_size_override(
			"font_size", _wave_indicator_label.get_theme_font_size("font_size")
		)
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
	# 撤离成功时播放完成音效（与 extraction_start 形成完整音效闭环）
	if has_method("play_sfx"):
		call("play_sfx", "extraction_done")
	_show_extraction_success()


## 显示撤离成功面板（淡入动画 + 物品闪光）
func _show_extraction_success() -> void:
	if extraction_success_panel == null or _extraction_success_shown:
		return
	_extraction_success_shown = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	_prepare_extraction_success_modal()

	# 先设为可见但完全透明+缩小，作为动画起点
	extraction_success_panel.visible = true
	extraction_success_panel.modulate.a = 0.0
	extraction_success_panel.scale = Vector2(0.92, 0.92)

	# 清空物品列表（物品渲染已移至 show_run_extraction_success 中的 stats 传入）
	if extracted_items_vbox:
		for child in extracted_items_vbox.get_children():
			child.queue_free()
	# 更新物品数量标签（从 stats 传入的 extracted_items 长度估算）
	var total_count := 0
	if extracted_items_vbox.get_child_count() > 2:
		total_count = extracted_items_vbox.get_child_count() - 2  # 减去 score_label_node 和 points_node
	if extracted_count_label:
		extracted_count_label.text = "物品已保存: %d 件" % total_count

	# 结算已立即可见；轻量动画在暂停状态下仍由 UI 自身继续处理。
	extraction_success_panel.modulate.a = 0.0
	extraction_success_panel.scale = Vector2(0.92, 0.92)
	var tween := extraction_success_panel.create_tween()
	tween.set_parallel(true)
	(
		tween
		. tween_property(extraction_success_panel, "modulate:a", 1.0, 0.4)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	(
		tween
		. tween_property(extraction_success_panel, "scale", Vector2(1.0, 1.0), 0.4)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)

	# 撤离成功时轻度震屏（强化"完成撤离"的仪式感）
	if _screen_shake and _screen_shake.has_method("trigger"):
		_screen_shake.call("trigger", 3.5, 0.12)

	Global.acquire_pause("extraction_success")


func _ensure_extraction_success_modal() -> void:
	if _extraction_success_backdrop == null or not is_instance_valid(_extraction_success_backdrop):
		_extraction_success_backdrop = ColorRect.new()
		_extraction_success_backdrop.name = "ExtractionSuccessBackdrop"
		_extraction_success_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
		_extraction_success_backdrop.color = Color(0.02, 0.025, 0.035, 0.84)
		_extraction_success_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
		_extraction_success_backdrop.process_mode = Node.PROCESS_MODE_ALWAYS
		_extraction_success_backdrop.z_index = 2000
		_extraction_success_backdrop.visible = false
		add_child(_extraction_success_backdrop)
	extraction_success_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	extraction_success_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	extraction_success_panel.z_index = 2001
	if continue_button:
		continue_button.process_mode = Node.PROCESS_MODE_ALWAYS
		continue_button.mouse_filter = Control.MOUSE_FILTER_STOP
		continue_button.focus_mode = Control.FOCUS_ALL


func _prepare_extraction_success_modal() -> void:
	_ensure_extraction_success_modal()
	extraction_success_panel.move_to_front()
	hide_run_choice_panel()
	if fate_card_panel:
		fate_card_panel.visible = false
	if extraction_panel:
		extraction_panel.visible = false
	if inventory_panel:
		inventory_panel.visible = false
	if insurance_panel:
		insurance_panel.visible = false
	if _weapon_panel != null and _weapon_panel.has_method("hide_panel"):
		_weapon_panel.call("hide_panel")
	var hud := get_node_or_null("GameHUD") as Control
	if hud:
		hud.visible = false
	_hide_boss_hp_ui()
	if _extraction_success_backdrop:
		_extraction_success_backdrop.visible = true
	if continue_button:
		continue_button.disabled = false
		continue_button.grab_focus()


func show_run_extraction_success(stats: Dictionary) -> void:
	_show_extraction_success()
	var ep_total: int = BaseManager.get_extraction_points()
	var elite_kills: int = int(stats.get("elite_kills", 0))
	var elite_bounty: int = int(stats.get("elite_bounty", 0))
	var kill_str: String = "波次 %d  击杀 %d" % [int(stats.get("wave", 0)), int(stats.get("kills", 0))]
	if elite_kills > 0:
		kill_str += "  ★精英×%d(+%d)" % [elite_kills, elite_bounty]
	if extracted_count_label:
		extracted_count_label.text = (
			"撤离成功  %s  魂 %d  基地币 %d" % [kill_str, int(stats.get("currency", 0)), ep_total]
		)
	if extracted_items_vbox:
		# 显示本局获得的积分（灵魂兑换）
		var points_earned: int = int(stats.get("points_earned", 0))
		if points_earned > 0:
			var points_node := Label.new()
			points_node.text = "▶ 本局获得基地币: +%d" % points_earned
			points_node.modulate = Color(0.3, 1.0, 0.55, 1.0)
			points_node.add_theme_font_size_override("font_size", 16)
			extracted_items_vbox.add_child(points_node)
		var score_label_node := Label.new()
		score_label_node.text = (
			"最终得分: %d  风险层级: %d" % [int(stats.get("score", 0)), int(stats.get("risk", 0))]
		)
		score_label_node.modulate = Color(0.85, 0.95, 1.0, 1.0)
		extracted_items_vbox.add_child(score_label_node)
		# 如果 stats 中带了本局带出的真实物品列表（在背包清空前读取），直接渲染
		# 否则回退到实时读取（适用于 CoreCombatMode 等没有提前传入 extracted_items 的场景）
		var extracted_slots: Array[Dictionary] = []
		var passed_extracted: Array[Dictionary] = []
		for slot_data in stats.get("extracted_items", []):
			if slot_data is Dictionary:
				passed_extracted.append(slot_data)
		if not passed_extracted.is_empty():
			extracted_slots = passed_extracted
		elif _inventory_module and _inventory_module.has_method("get_occupied_slots"):
			extracted_slots = _inventory_module.get_occupied_slots()
		var insured_slots: Array[Dictionary] = []
		var passed_insured: Array[Dictionary] = []
		for slot_data in stats.get("insured_items", []):
			if slot_data is Dictionary:
				passed_insured.append(slot_data)
		if not passed_insured.is_empty():
			insured_slots = passed_insured
		elif _insurance_module and _insurance_module.has_method("get_all_insured_items"):
			insured_slots = _insurance_module.get_all_insured_items()
		for slot_data in extracted_slots:
			var item: Dictionary = slot_data.get("item", {})
			var item_name: String = item.get("name", item.get("id", "未知物品"))
			var tier: int = item.get("loot_table_tier", 0)
			var lbl := Label.new()
			lbl.text = "• %s" % item_name
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			match tier:
				3:
					lbl.modulate = Color(1.0, 0.85, 0.2, 1.0)
				2:
					lbl.modulate = Color(0.75, 0.35, 1.0, 1.0)
				1:
					lbl.modulate = Color(0.35, 0.55, 1.0, 1.0)
				_:
					lbl.modulate = Color(1.0, 0.92, 0.6, 1.0)
			extracted_items_vbox.add_child(lbl)
		for slot_data in insured_slots:
			var item: Dictionary = slot_data.get("item", {})
			var item_name: String = item.get("name", item.get("id", "保险物品"))
			var tier: int = item.get("loot_table_tier", 0)
			var lbl := Label.new()
			lbl.text = "• %s [保险]" % item_name
			match tier:
				3:
					lbl.modulate = Color(0.8, 0.95, 0.6, 1.0)
				2:
					lbl.modulate = Color(0.85, 0.75, 1.0, 1.0)
				1:
					lbl.modulate = Color(0.7, 0.8, 1.0, 1.0)
				_:
					lbl.modulate = Color(0.7, 0.85, 0.7, 1.0)
			extracted_items_vbox.add_child(lbl)
	if _extraction_floor_label:
		var floor: int = int(stats.get("floor", 1))
		_extraction_floor_label.text = "第 %d 层" % floor
		_extraction_floor_label.visible = true


## 继续按钮 — 返回基地主界面
func _on_continue_pressed() -> void:
	Global.clear_pause_reasons()
	_extraction_success_shown = false
	if _extraction_success_backdrop:
		_extraction_success_backdrop.visible = false
	if extraction_success_panel:
		extraction_success_panel.visible = false
	if game_over_panel:
		game_over_panel.visible = false
	if death_overlay:
		death_overlay.visible = false
	# 返回基地主界面
	var change_error := get_tree().change_scene_to_file(GameDesignConfig.BASE_SCENE_3D)
	if change_error != OK:
		push_error("返回基地场景切换失败：%s" % error_string(change_error))


## 撤离中断（玩家受击中断 / 手动中断）
func _on_extraction_aborted() -> void:
	if room_info_label:
		room_info_label.text = "撤离已中断！"
	# 播放撤离中断音效
	if has_method("play_sfx"):
		call("play_sfx", "extraction_abort")
	if abort_button:
		abort_button.visible = false
		abort_button.disabled = true
		abort_button.text = "已中断"
	# 中断撤离读条UI：隐藏倒计时条和剩余时间，恢复撤离选择按钮
	if countdown_bar:
		countdown_bar.visible = false
		countdown_bar.value = 0.0
	if countdown_label:
		countdown_label.visible = false
	if extraction_type_label:
		extraction_type_label.text = "选择撤离方式"
	if extraction_buttons_container:
		for child in extraction_buttons_container.get_children():
			child.visible = true
	_active_extraction_duration = 0.0


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
		_restore_extraction_choice_panel()


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
		"STANDARD":
			return "撤离点 (安全但偏远)"
		"BEACON":
			return "信标撤离 (消耗道具)"
		"BOSS_KILL":
			return "Boss撤离 (需击败Boss)"
		"ELITE_KILL":
			return "精英撤离 (需击败精英)"
		"TRADE":
			return "交易撤离 (消耗资源)"
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
		"BEACON":
			return "没有信标道具"
		"BOSS_KILL":
			return "尚未击败Boss，无法解锁"
		"ELITE_KILL":
			return "尚未击败精英怪，无法解锁"
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
			return (
				ed_boss != null
				and ed_boss.has_method("get_points_by_type")
				and (
					(
						ed_boss
						. get_points_by_type(ExtractionDirector.ExtractionType.BOSS_KILL, true)
						. size()
					)
					> 0
				)
			)
		"ELITE_KILL":
			var ed_elite := _get_extraction_director_safe()
			return (
				ed_elite != null
				and ed_elite.has_method("get_points_by_type")
				and (
					(
						ed_elite
						. get_points_by_type(ExtractionDirector.ExtractionType.ELITE_KILL, true)
						. size()
					)
					> 0
				)
			)
		"TRADE":
			var ed_trade_check := _get_extraction_director_safe()
			return (
				ed_trade_check != null
				and ed_trade_check.has_method("get_trade_cost")
				and (
					GameManager.currency
					>= int(ed_trade_check.get_trade_cost(_get_current_floor_safe()))
				)
			)
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
		"STANDARD":
			countdown = 8.0
		"BEACON":
			countdown = 10.0
		"BOSS_KILL":
			countdown = 3.0
		"ELITE_KILL":
			countdown = 5.0
		"TRADE":
			countdown = 5.0

	if _room_game_mode == null or not _room_game_mode.has_method("begin_extraction"):
		if room_info_label:
			room_info_label.text = "当前战斗模式暂未接入撤离流程"
		return

	if not _is_extraction_backend_ready():
		_restore_extraction_choice_panel("撤离装置尚未就绪")
		return

	# 信标撤离：先消耗信标道具创建撤离点
	if etype == "BEACON":
		var ed_beacon := _get_extraction_director_safe()
		if ed_beacon != null and ed_beacon.has_method("summon_beacon_extraction"):
			if not bool(ed_beacon.summon_beacon_extraction()):
				_restore_extraction_choice_panel("信标撤离启动失败")
				return
			if ed_beacon.has_method("get_beacon_count"):
				_beacon_count = int(ed_beacon.get_beacon_count())

	# 交易撤离：预扣货币（不满足则禁用按钮）
	if etype == "TRADE":
		var ed_trade := _get_extraction_director_safe()
		if ed_trade != null and ed_trade.has_method("get_trade_cost"):
			var cost: int = int(ed_trade.get_trade_cost(_get_current_floor_safe()))
			if not GameManager.spend_currency(cost):
				_restore_extraction_choice_panel("魂不足，无法交易撤离")
				return
			ed_trade.set("_trade_pending_refund", false)

	var started: bool = bool(_room_game_mode.call("begin_extraction", etype, countdown))
	if not started:
		if etype == "TRADE":
			var ed_trade_refund := _get_extraction_director_safe()
			if ed_trade_refund != null and ed_trade_refund.has_method("get_trade_cost"):
				GameManager.add_currency(
					int(ed_trade_refund.get_trade_cost(_get_current_floor_safe()))
				)
		_restore_extraction_choice_panel("撤离启动失败，请重新选择")
		return

	_start_extraction_countdown_ui(etype, countdown)


## 开始撤离读条UI
func _start_extraction_countdown_ui(extraction_type: String, duration: float) -> void:
	_active_extraction_duration = duration
	if extraction_panel:
		extraction_panel.visible = true
	extraction_type_label.text = "撤离中: %s" % extraction_type
	countdown_bar.visible = true
	countdown_label.visible = true
	abort_button.visible = true
	abort_button.disabled = false
	abort_button.text = "中断撤离"
	countdown_bar.max_value = 1.0
	countdown_bar.value = 0.0
	_update_countdown_label(duration, duration)

	# 隐藏撤离按钮容器
	if extraction_buttons_container:
		for child in extraction_buttons_container.get_children():
			child.visible = false


func show_extraction_room_countdown(duration: float) -> void:
	_start_extraction_countdown_ui("守点撤离", duration)


func _is_extraction_backend_ready() -> bool:
	if _extraction_module == null or not _extraction_module.has_method("get_status"):
		return true
	return int(_extraction_module.get_status()) == ExtractionModule.ExtractionStatus.IDLE


func _restore_extraction_choice_panel(message: String = "") -> void:
	_active_extraction_duration = 0.0
	if room_info_label and not message.is_empty():
		room_info_label.text = message
	if extraction_type_label:
		extraction_type_label.text = "选择撤离方式"
	if countdown_bar:
		countdown_bar.visible = false
		countdown_bar.value = 0.0
	if countdown_label:
		countdown_label.visible = false
	if abort_button:
		abort_button.visible = false
		abort_button.disabled = false
		abort_button.text = "中断撤离"
	if extraction_buttons_container:
		for child in extraction_buttons_container.get_children():
			child.visible = true
	_update_beacon_label()
	_update_extraction_buttons()
	if extraction_panel:
		extraction_panel.visible = true


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
		ammo_label.text = "弹匣  %d / %d" % [current, maximum]
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
	# 换弹时将 ammo_bar 切换为显示"换弹进度"（而不是弹药量）
	if ammo_bar:
		ammo_bar.max_value = _reload_duration
		ammo_bar.value = 0.0
		ammo_bar.modulate = Color(0.45, 0.8, 1.0, 1.0)  # 蓝色表示换弹中


## 换弹完成
func _on_weapon_reloaded() -> void:
	_is_reloading = false
	_reload_progress = 0.0
	if reload_indicator:
		reload_indicator.visible = false
	if ammo_label:
		ammo_label.modulate = Color.WHITE
	# 换弹完成后恢复 ammo_bar 为弹药量显示（根据当前弹药量设置颜色）
	if ammo_bar:
		ammo_bar.modulate = Color(0.45, 1.0, 0.55, 1.0)  # 绿色正常


## 获取武器装配树引用
func _get_weapon_tree():
	if _room_game_mode != null and _room_game_mode.has_method("get_player"):
		var player = _room_game_mode.get_player()
		if player != null and player.has_method("get_weapon_tree"):
			return player.get_weapon_tree()
	return null


func _process(delta: float) -> void:
	_player_state_pulse += delta
	if player_state_panel != null:
		var urgent := _player_low_health or bool(_player_status_effects.get("silenced", false))
		var pulse_alpha := 1.0
		if urgent:
			pulse_alpha = 0.72 + (sin(_player_state_pulse * TAU * 2.2) * 0.5 + 0.5) * 0.28
		if player_state_accent != null:
			player_state_accent.modulate = Color(1.0, 1.0, 1.0, pulse_alpha)
		if urgent:
			_update_player_status_text()
	# 小地图脏标记驱动：节点/门数据变化时整批重推
	if _minimap_dirty:
		_minimap_dirty = false
		_push_minimap_data(true)
	# 玩家位置每帧轻量更新（仅改一个 Vector2）
	if _minimap_view and _minimap_view.has_active_player():
		var p: Node = _room_game_mode.get_player() if _room_game_mode and _room_game_mode.has_method("get_player") else null
		if p and is_instance_valid(p):
			_minimap_view.update_player_position(p.global_position)
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
	if _item_hover_card != null and _item_hover_card.visible:
		_position_item_hover_card()
	# HP bar 颜色刷新（每帧尝试，内部有 0.1 deadzone 抑制抖动）
	_update_hp_bar_color()


func blocks_gameplay_input() -> bool:
	if inventory_panel != null and inventory_panel.visible:
		return true
	if insurance_panel != null and insurance_panel.visible:
		return true
	if fate_card_panel != null and fate_card_panel.visible:
		return true
	if _run_choice_overlay != null and _run_choice_overlay.visible:
		return true
	if game_over_panel != null and game_over_panel.visible:
		return true
	if _extraction_success_shown:
		return true
	if extraction_success_panel != null and extraction_success_panel.visible:
		return true
	return false


## — 物品存入取出（保险格）系统 —
const SLOT_SIZE := 56
const SLOT_SCENE: PackedScene = preload("res://scenes/ItemSlot.tscn")

var _inventory_slot_nodes: Array[Control] = []
var _insurance_slot_nodes: Array[Control] = []


func _setup_inventory_system_ui() -> void:
	_ensure_equipped_weapon_widget()
	_style_inventory_panel(inventory_panel, "背包")
	_style_inventory_panel(insurance_panel, "保险箱")
	if (
		inventory_panel != null
		and not inventory_panel.gui_input.is_connected(_on_inventory_panel_gui_input)
	):
		inventory_panel.gui_input.connect(_on_inventory_panel_gui_input)
	if (
		insurance_panel != null
		and not insurance_panel.gui_input.is_connected(_on_inventory_panel_gui_input)
	):
		insurance_panel.gui_input.connect(_on_inventory_panel_gui_input)


func _ensure_equipped_weapon_widget() -> void:
	if _equipped_weapon_slot != null and is_instance_valid(_equipped_weapon_slot):
		return
	var hud := get_node_or_null("GameHUD") as Control
	if hud == null:
		return
	var panel := PanelContainer.new()
	panel.name = "EquippedWeaponPanel"
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 18
	panel.offset_top = 18
	panel.offset_right = 182
	panel.offset_bottom = 92
	var style := UIStyleFactory.make_panel_with_border(1, UIPalette.BORDER_NORMAL, 6, 1)
	panel.add_theme_stylebox_override("panel", style)
	hud.add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	_equipped_weapon_slot = TextureRect.new()
	_equipped_weapon_slot.name = "EquippedWeaponSlot"
	_equipped_weapon_slot.custom_minimum_size = Vector2(56, 56)
	_equipped_weapon_slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_equipped_weapon_slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(_equipped_weapon_slot)

	_equipped_weapon_label = Label.new()
	_equipped_weapon_label.name = "EquippedWeaponLabel"
	_equipped_weapon_label.custom_minimum_size = Vector2(86, 56)
	_equipped_weapon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_equipped_weapon_label.add_theme_font_size_override("font_size", 12)
	_equipped_weapon_label.add_theme_color_override("font_color", Color(0.86, 0.90, 0.96, 1.0))
	row.add_child(_equipped_weapon_label)


func _style_inventory_panel(panel: PanelContainer, title: String) -> void:
	if panel == null:
		return
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override(
		"panel",
		UIStyleFactory.make_panel_with_border(1, UIPalette.BORDER_ACCENT, 6, 1),
	)
	panel.tooltip_text = "%s: 拖动面板空白处移动。左键使用/装备，Shift+左键存保险，右键同样可操作；保险箱左键取回。" % title


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
	slot.add_theme_stylebox_override("normal", UIStyleFactory.make_slot_style(false))
	slot.add_theme_stylebox_override("hover", UIStyleFactory.make_slot_style(true))
	return slot


func _connect_slot_signals(slot: Control, idx: int, is_inventory: bool) -> void:
	if slot.has_method("set_slot_index"):
		slot.call("set_slot_index", idx)
	if slot.has_signal("slot_clicked"):
		(slot as Node).slot_clicked.connect(_on_slot_clicked.bind(is_inventory))
	if slot.has_signal("slot_right_clicked"):
		(slot as Node).slot_right_clicked.connect(_on_slot_right_clicked.bind(is_inventory))
	_ensure_slot_hover_signals(slot)
	slot.set_meta("slot_is_inventory", is_inventory)


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
	_highlight_selected_slots()
	_update_equipped_weapon_slot()


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
	_highlight_selected_slots()


func _update_slot_with_item(slot: Control, slot_info: Dictionary) -> void:
	var item: Dictionary = slot_info.get("item", {})
	var item_id: String = item.get("id", "")
	var count: int = slot_info.get("count", 1)
	_ensure_slot_hover_signals(slot)
	slot.set_meta("slot_item", item.duplicate(true))
	slot.set_meta("slot_count", count)
	var icon_path: String = item.get("icon", "")
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		var tex: Texture2D = load(icon_path) as Texture2D
		if slot is TextureRect:
			(slot as TextureRect).texture = tex
	else:
		if slot is TextureRect:
			(slot as TextureRect).texture = _make_item_icon(item)
	_update_slot_text(slot, item)
	slot.tooltip_text = (
		"%s\n%s\n左键: 使用/装备/装配  Shift+左键: 存保险  右键: 快速操作"
		% [item.get("name", item_id), item.get("description", item.get("type", "物品"))]
	)
	if slot.has_node("CountLabel"):
		var cl: Label = slot.get_node("CountLabel") as Label
		if count > 1:
			cl.text = "x%d" % count
			cl.visible = true
		else:
			cl.visible = false
	slot.add_theme_stylebox_override("normal", UIStyleFactory.make_slot_filled_style())


func _clear_slot(slot: Control) -> void:
	if slot is TextureRect:
		(slot as TextureRect).texture = null
	if slot.has_meta("slot_item"):
		slot.remove_meta("slot_item")
	if slot.has_meta("slot_count"):
		slot.remove_meta("slot_count")
	if _item_hover_card != null and _item_hover_card.visible:
		_hide_item_hover_card()
	_update_slot_text(slot, {})
	slot.tooltip_text = ""
	if slot.has_node("CountLabel"):
		var cl: Label = slot.get_node("CountLabel") as Label
		cl.visible = false
	slot.add_theme_stylebox_override("normal", UIStyleFactory.make_slot_style(false))


func _highlight_selected_slots() -> void:
	for i in _inventory_slot_nodes.size():
		_apply_slot_selection(_inventory_slot_nodes[i], i == _selected_inventory_slot)
	for i in _insurance_slot_nodes.size():
		_apply_slot_selection(_insurance_slot_nodes[i], i == _selected_insurance_slot)


func _apply_slot_selection(slot: Control, selected: bool) -> void:
	if slot == null:
		return
	var style_box := StyleBoxFlat.new()
	style_box.bg_color = Color(0.18, 0.20, 0.27, 0.96) if selected else UIPalette.BG_SLOT
	style_box.set_border_width_all(2 if selected else 1)
	style_box.set_border_color(
		Color(1.0, 0.82, 0.35, 0.95) if selected else UIPalette.BORDER_SUBTLE
	)
	style_box.set_corner_radius_all(4)
	slot.add_theme_stylebox_override("normal", style_box)


func _on_inventory_panel_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		if event.pressed:
			_dragging_inventory_panel = true
			_inventory_drag_start_mouse = get_viewport().get_mouse_position()
			_inventory_drag_start_panel = (
				Vector2(inventory_panel.offset_left, inventory_panel.offset_top)
				if inventory_panel != null
				else Vector2.ZERO
			)
			_inventory_drag_start_insurance = (
				Vector2(insurance_panel.offset_left, insurance_panel.offset_top)
				if insurance_panel != null
				else Vector2.ZERO
			)
		else:
			_dragging_inventory_panel = false
	elif event is InputEventMouseMotion and _dragging_inventory_panel:
		get_viewport().set_input_as_handled()
		var delta := get_viewport().get_mouse_position() - _inventory_drag_start_mouse
		_move_inventory_panel_pair(delta)


func _ensure_slot_hover_signals(slot: Control) -> void:
	if slot == null or slot.has_meta("slot_hover_connected"):
		return
	slot.mouse_entered.connect(_on_slot_mouse_entered.bind(slot))
	slot.mouse_exited.connect(_on_slot_mouse_exited.bind(slot))
	slot.set_meta("slot_hover_connected", true)


func _on_slot_mouse_entered(slot: Control) -> void:
	if slot == null:
		return
	var item: Dictionary = {}
	var count := 1
	var slot_index := int(slot.get("slot_index"))
	var is_inventory := bool(slot.get_meta("slot_is_inventory", true))
	if is_inventory and _inventory_module != null:
		var slot_data: Dictionary = _inventory_module.get_slot(slot_index)
		item = slot_data.get("item", {})
		count = int(slot_data.get("count", 1))
	elif not is_inventory and _insurance_module != null and _insurance_module.has_method("get_occupied_slots"):
		for slot_data in _insurance_module.get_occupied_slots():
			if int(slot_data.get("insurance_slot", slot_data.get("slot", -1))) == slot_index:
				item = slot_data.get("item", {})
				count = int(slot_data.get("count", 1))
				break
	elif slot.has_meta("slot_item"):
		item = slot.get_meta("slot_item")
		count = int(slot.get_meta("slot_count", 1))
	if item.is_empty():
		return
	_show_item_hover_card(item, count)


func _on_slot_mouse_exited(slot: Control) -> void:
	_hide_item_hover_card()


func _ensure_item_hover_card() -> void:
	if _item_hover_card != null and is_instance_valid(_item_hover_card):
		return
	_item_hover_card = PanelContainer.new()
	_item_hover_card.name = "ItemHoverCard"
	_item_hover_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_item_hover_card.z_index = 2600
	_item_hover_card.visible = false
	var style := UIStyleFactory.make_panel_with_border(0, UIPalette.BORDER_FOCUS, 6, 1)
	style.set_content_margin_all(10)
	_item_hover_card.add_theme_stylebox_override("panel", style)
	_item_hover_label = Label.new()
	_item_hover_label.custom_minimum_size = Vector2(220, 0)
	_item_hover_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_item_hover_label.add_theme_font_size_override("font_size", 13)
	_item_hover_label.add_theme_color_override("font_color", Color(0.9, 0.94, 1.0, 1.0))
	_item_hover_card.add_child(_item_hover_label)
	add_child(_item_hover_card)


func _show_item_hover_card(item: Dictionary, count: int) -> void:
	_ensure_item_hover_card()
	if _item_hover_card == null or _item_hover_label == null:
		return
	var name := str(item.get("name", item.get("id", "物品")))
	var rarity := str(item.get("rarity", "common"))
	var type_text := str(item.get("type", "物品"))
	var desc := str(item.get("description", ""))
	var action := "左键: 选择"
	if item.get("type", "") == "weapon" or item.get("subtype", "") == "gun_body":
		action = "左键: 装备"
	elif item.get("type", "") in ["module", "attachment"]:
		action = "左键: 装配"
	elif not str(item.get("use_action", "")).is_empty():
		action = "左键: 使用"
	var build_text := ""
	if str(item.get("type", "")) == "weapon":
		var instance_id := str(item.get("weapon_instance_id", ""))
		var upgrades: Variant = item.get("fate_upgrades", [])
		var used: int = upgrades.size() if upgrades is Array else 0
		build_text = "\n实例 #%s · 命运永久 %d/%d\n配件可更换且不占命运槽" % [
			instance_id.right(6).to_upper(), used, int(item.get("fate_slot_capacity", 8)),
		]
	_item_hover_label.text = "%s x%d\n%s / %s%s\n%s\n%s  |  Shift+左键: 存保险" % [
		name,
		count,
		type_text,
		rarity,
		build_text,
		desc,
		action,
	]
	_item_hover_card.visible = true
	_item_hover_card.move_to_front()
	_position_item_hover_card()


func _hide_item_hover_card() -> void:
	if _item_hover_card != null:
		_item_hover_card.visible = false


func _position_item_hover_card() -> void:
	if _item_hover_card == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var pos := get_viewport().get_mouse_position() + Vector2(18, 18)
	var card_size := _item_hover_card.size
	if card_size == Vector2.ZERO:
		card_size = _item_hover_card.get_combined_minimum_size()
	pos.x = clamp(pos.x, 8.0, max(8.0, viewport_size.x - card_size.x - 8.0))
	pos.y = clamp(pos.y, 8.0, max(8.0, viewport_size.y - card_size.y - 8.0))
	_item_hover_card.global_position = pos


func _move_inventory_panel_pair(delta: Vector2) -> void:
	if inventory_panel != null:
		var size := inventory_panel.size
		inventory_panel.offset_left = _inventory_drag_start_panel.x + delta.x
		inventory_panel.offset_top = _inventory_drag_start_panel.y + delta.y
		inventory_panel.offset_right = inventory_panel.offset_left + size.x
		inventory_panel.offset_bottom = inventory_panel.offset_top + size.y
	if insurance_panel != null:
		var size := insurance_panel.size
		insurance_panel.offset_left = _inventory_drag_start_insurance.x + delta.x
		insurance_panel.offset_top = _inventory_drag_start_insurance.y + delta.y
		insurance_panel.offset_right = insurance_panel.offset_left + size.x
		insurance_panel.offset_bottom = insurance_panel.offset_top + size.y


func _update_equipped_weapon_slot() -> void:
	if _equipped_weapon_slot == null or not is_instance_valid(_equipped_weapon_slot):
		_ensure_equipped_weapon_widget()
	if _equipped_weapon_slot == null:
		return
	var player := _get_player_reference()
	var item := _current_equipped_weapon_item(player)
	if item.is_empty():
		_equipped_weapon_slot.texture = null
		if _equipped_weapon_label != null:
			_equipped_weapon_label.text = "主武器\n未装备"
		return
	_equipped_weapon_slot.texture = _make_item_icon(item)
	_update_slot_text(_equipped_weapon_slot, item)
	var instance_id := str(item.get("weapon_instance_id", ""))
	var upgrades: Variant = item.get("fate_upgrades", [])
	var used: int = upgrades.size() if upgrades is Array else 0
	var capacity := int(item.get("fate_slot_capacity", 8))
	_equipped_weapon_slot.tooltip_text = "当前装备: %s #%s\n命运永久 %d/%d" % [
		item.get("name", "武器"), instance_id.right(6).to_upper(), used, capacity,
	]
	if _equipped_weapon_label != null:
		_equipped_weapon_label.text = "主武器\n%s #%s · %d/%d" % [
			item.get("name", "武器"), instance_id.right(6).to_upper(), used, capacity,
		]


func _current_equipped_weapon_item(player: Node) -> Dictionary:
	if player == null:
		return {}
	if player.has_method("get_equipped_weapon_item"):
		return player.call("get_equipped_weapon_item") as Dictionary
	if not player.has_method("get_weapon_tree"):
		return {}
	var wt: WeaponAssemblyTree = player.get_weapon_tree() as WeaponAssemblyTree
	if wt == null:
		return {}
	return _item_for_weapon_root(wt.get_root())


func _on_weapon_instance_changed(_snapshot: Dictionary) -> void:
	_update_equipped_weapon_slot()
	_refresh_inventory_ui()


func _on_insurance_changed() -> void:
	_refresh_insurance_ui()


func _on_slot_clicked(slot_index: int, is_inventory: bool) -> void:
	if is_inventory:
		_selected_inventory_slot = slot_index
		_selected_insurance_slot = -1
		if Input.is_key_pressed(KEY_SHIFT):
			item_to_insurance_requested.emit(slot_index)
			return
		if _activate_inventory_slot(slot_index):
			return
		_highlight_selected_slots()
	else:
		_selected_insurance_slot = slot_index
		_selected_inventory_slot = -1
		_highlight_selected_slots()
		item_extraction_requested.emit(slot_index)


func _on_slot_right_clicked(slot_index: int, is_inventory: bool) -> void:
	if is_inventory:
		if not _activate_inventory_slot(slot_index):
			item_to_insurance_requested.emit(slot_index)
	else:
		item_extraction_requested.emit(slot_index)


func _activate_inventory_slot(slot_index: int) -> bool:
	if _inventory_module == null:
		return false
	var slot_data: Dictionary = _inventory_module.get_slot(slot_index)
	if slot_data.is_empty():
		return false
	var item: Dictionary = slot_data["item"]
	if item.get("type", "") == "weapon" or item.get("subtype", "") == "gun_body":
		if _equip_weapon_from_inventory(slot_index, item):
			_refresh_inventory_ui()
		return true
	if item.get("type", "") in ["module", "attachment"]:
		if _install_weapon_module_from_item(item):
			_inventory_module.remove_from_slot(slot_index, 1)
			_refresh_inventory_ui()
		return true
	var use_action: String = item.get("use_action", "")
	if not use_action.is_empty():
		if _inventory_module.consume_item(item.get("id", ""), 1):
			var handler_script: GDScript = load(_ITEM_USE_HANDLER_PATH)
			var handler: Object = handler_script.new()
			var context: Dictionary = {"player": _get_player_reference()}
			var ok: bool = handler.apply(item, context)
			handler.free()
			if not ok:
				_inventory_module.add_item(item, 1)
			_refresh_inventory_ui()
		return true
	return false


func _make_item_icon(item: Dictionary) -> Texture2D:
	var img := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	var color := _item_color(item)
	img.fill(Color(0.08, 0.09, 0.12, 1.0))
	for y in range(4, 44):
		for x in range(4, 44):
			img.set_pixel(x, y, color)
	for i in range(48):
		img.set_pixel(i, 0, Color.WHITE)
		img.set_pixel(i, 47, Color.WHITE)
		img.set_pixel(0, i, Color.WHITE)
		img.set_pixel(47, i, Color.WHITE)
	return ImageTexture.create_from_image(img)


func _item_color(item: Dictionary) -> Color:
	match item.get("rarity", "common"):
		"uncommon":
			return Color(0.25, 0.62, 0.95, 1.0)
		"rare":
			return Color(0.58, 0.35, 0.95, 1.0)
		"epic":
			return Color(0.95, 0.45, 0.18, 1.0)
		_:
			pass
	match item.get("type", ""):
		"module":
			return Color(0.22, 0.72, 0.56, 1.0)
		"attachment":
			return Color(0.76, 0.58, 0.24, 1.0)
		"weapon":
			return Color(0.88, 0.50, 0.24, 1.0)
		"blueprint":
			return Color(0.32, 0.50, 0.95, 1.0)
		"key":
			return Color(0.95, 0.76, 0.22, 1.0)
		"consumable":
			return Color(0.68, 0.86, 0.30, 1.0)
		_:
			return Color(0.55, 0.58, 0.64, 1.0)


func _update_slot_text(slot: Control, item: Dictionary) -> void:
	var label := slot.get_node_or_null("ItemGlyph") as Label
	if item.is_empty():
		if label != null:
			label.visible = false
		return
	if label == null:
		label = Label.new()
		label.name = "ItemGlyph"
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 15)
		label.add_theme_color_override("font_color", Color.WHITE)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(label)
	label.text = _item_glyph(item)
	label.visible = true


func _item_glyph(item: Dictionary) -> String:
	var subtype := str(item.get("subtype", ""))
	if item.get("id", "") == "item_room_key":
		return "KEY"
	if item.get("type", "") == "blueprint":
		return "BP"
	if subtype == "bullet":
		return "BUL"
	if subtype == "gun_body":
		return "GUN"
	if item.get("type", "") == "attachment":
		return "ATT"
	if item.get("type", "") == "weapon":
		return "GUN"
	if item.get("type", "") == "module":
		return "MOD"
	if item.get("use_action", "") == "heal":
		return "HP"
	if item.get("use_action", "") == "refill_ammo":
		return "AM"
	return "ITM"


func _install_weapon_module_from_item(item: Dictionary) -> bool:
	var player := _get_player_reference()
	if player == null or not player.has_method("get_weapon_tree"):
		return false
	var wt: WeaponAssemblyTree = player.get_weapon_tree() as WeaponAssemblyTree
	if wt == null or wt.get_root() == null:
		return false
	var assembly_id := str(item.get("assembly_id", item.get("id", "")))
	var new_node: AssemblyNode = BlueprintRegistry.create_assembly_node(assembly_id)
	if new_node == null:
		return false
	var root: AssemblyNode = wt.get_root()
	var slot_type := AssemblyNode.SlotType.MOUNT
	match item.get("subtype", ""):
		"bullet":
			slot_type = AssemblyNode.SlotType.BULLET
		"muzzle":
			slot_type = AssemblyNode.SlotType.MUZZLE
		"magazine":
			slot_type = AssemblyNode.SlotType.MAGAZINE
		_:
			slot_type = AssemblyNode.SlotType.MOUNT
	var existing: AssemblyNode = root.slots.get(slot_type)
	if existing != null:
		wt.unmount(existing)
	var ok := wt.mount(root, slot_type, new_node)
	if ok:
		show_fate_card_notification("已装配: %s。按 K 查看武器树" % item.get("name", item.get("id", "模块")))
		if _weapon_panel != null and _weapon_panel.has_method("set_weapon_tree"):
			_weapon_panel.call("set_weapon_tree", wt)
	else:
		show_fate_card_notification("装配失败: %s" % item.get("name", "模块"))
	return ok


func _equip_weapon_from_inventory(slot_index: int, item: Dictionary) -> bool:
	if _inventory_module == null:
		return false
	var player := _get_player_reference()
	if player == null or not player.has_method("equip_weapon_item"):
		return false
	var incoming := WeaponInstance.ensure_weapon_item(item)
	if incoming.is_empty():
		show_fate_card_notification("无法装备: %s" % item.get("name", "武器"))
		return false
	var incoming_id := str(incoming.get("weapon_instance_id", ""))
	if incoming_id == str(player.call("get_equipped_weapon_instance_id")):
		show_fate_card_notification("已经装备: %s" % item.get("name", "武器"))
		return false
	if not _inventory_module.remove_from_slot(slot_index, 1):
		return false
	var result := player.call("equip_weapon_item", incoming) as Dictionary
	if not bool(result.get("success", false)):
		_inventory_module.add_item(incoming, 1)
		show_fate_card_notification("装备失败: %s" % result.get("reason", "武器实例无效"))
		return false
	var old_weapon_item := result.get("old_item", {}) as Dictionary
	if not old_weapon_item.is_empty():
		if _inventory_module.add_item(old_weapon_item, 1) != 1:
			# 原武器无法入包时回滚，避免整枪及其构筑丢失。
			player.call("equip_weapon_item", old_weapon_item)
			_inventory_module.add_item(incoming, 1)
			show_fate_card_notification("背包无空位，无法替换武器")
			return false
	_bind_weapon_panel(player)
	_update_equipped_weapon_slot()
	show_fate_card_notification("已装备: %s #%s；原武器及其完整构筑已放回背包" % [
		incoming.get("name", incoming.get("id", "武器")), incoming_id.right(6).to_upper(),
	])
	return true


func _item_for_weapon_root(root: AssemblyNode) -> Dictionary:
	if root == null:
		return {}
	var item_id := ""
	match root.node_name:
		"GunBody_Pistol":
			item_id = "weapon_pistol"
		"GunBody_Shotgun":
			item_id = "weapon_shotgun"
		"GunBody_Rifle":
			item_id = "weapon_rifle"
		"GunBody_Machinegun":
			item_id = "weapon_machinegun"
		"GunBody_Sniper":
			item_id = "weapon_sniper"
		"GunBody_Launcher":
			item_id = "weapon_launcher"
		"GunBody_Charge":
			item_id = "weapon_charge"
		_:
			item_id = ""
	if item_id.is_empty():
		return {}
	return ItemRegistry.get_instance().get_item(item_id)


func _get_player_reference() -> Node:
	if _room_game_mode != null and _room_game_mode.has_method("get_player"):
		return _room_game_mode.get_player()
	var player: Node = get_node_or_null("/root/Main/YSort/Player")
	if player == null:
		player = get_node_or_null("/root/Main/Player")
	return player


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
	_selected_inventory_slot = -1
	_refresh_inventory_ui()
	_refresh_insurance_ui()


func _on_item_extraction_requested(slot_index: int) -> void:
	if _inventory_module == null or _insurance_module == null:
		return
	var item: Dictionary = _insurance_module.claim_item(slot_index)
	if item.is_empty():
		return
	var count := maxi(1, int(item.get("count", 1)))
	var inventory_before: Array[Dictionary] = _inventory_module.get_slots_snapshot()
	var added: int = _inventory_module.add_item(item, count)
	if added != count:
		_inventory_module.restore_slots_snapshot(inventory_before)
		if _insurance_module.has_method("insure_item_direct"):
			_insurance_module.insure_item_direct(item)
		show_fate_card_notification("背包已满，无法取回保险物品")
		return
	_selected_insurance_slot = -1
	_refresh_inventory_ui()
	_refresh_insurance_ui()


func _input(event: InputEvent) -> void:
	if _extraction_success_shown:
		# ESCAPE: 撤离成功后按 ESC 也可直接返回基地
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_on_continue_pressed()
			get_viewport().set_input_as_handled()
		return
	var inventory_pressed := event.is_action_pressed("ui_inventory")
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_I:
		inventory_pressed = true
	if inventory_pressed:
		if inventory_panel:
			var panel_visible := not inventory_panel.visible
			inventory_panel.visible = panel_visible
			if insurance_panel:
				insurance_panel.visible = panel_visible
			if panel_visible:
				inventory_panel.move_to_front()
				_refresh_inventory_ui()
				_refresh_insurance_ui()
				if _weapon_panel != null and _weapon_panel.has_method("show_panel"):
					_weapon_panel.call("show_panel")
					_weapon_panel.move_to_front()
			elif _weapon_panel != null and _weapon_panel.has_method("hide_panel"):
				_weapon_panel.call("hide_panel")
			if not panel_visible:
				_hide_item_hover_card()
			get_viewport().set_input_as_handled()
	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
	):
		if event.keycode == KEY_K:
			if _weapon_panel != null and _weapon_panel.has_method("toggle"):
				_weapon_panel.call("toggle")
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_TAB:
			# 门后命卡选择期间不劫持Tab（让 FateCardUIController 消费关闭事件）
			var door_fate_active := false
			if _room_game_mode != null and is_instance_valid(_room_game_mode):
				var prop = _room_game_mode.get("_door_fate_selection_active")
				if prop != null:
					door_fate_active = bool(prop)
			if not door_fate_active:
				if _weapon_panel != null and _weapon_panel.has_method("toggle"):
					_weapon_panel.call("toggle")
			get_viewport().set_input_as_handled()
