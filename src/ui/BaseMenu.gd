class_name BaseMenu
extends CanvasLayer

## 基地管理终端兼容界面
## 显示长期进度与建筑状态；副本只能从固定大世界中的建筑入口进入。
##
## BaseManager 通过 Autoload 直接访问（已在 project.godot 注册）

@export var overlay_mode := false

@onready var runs_label: Label = $VBox/HSplit/RightPanel/StatsPanel/VBox/RunsLabel
@onready var extractions_label: Label = $VBox/HSplit/RightPanel/StatsPanel/VBox/ExtractionsLabel
@onready var kills_label: Label = $VBox/HSplit/RightPanel/StatsPanel/VBox/KillsLabel
@onready var points_label: Label = $VBox/HSplit/RightPanel/StatsPanel/VBox/PointsLabel
@onready var start_button: Button = $VBox/HSplit/StartButton
@onready var building_workshop: Button = $VBox/HSplit/RightPanel/BuildingsGrid/BuildingWorkshop
@onready var building_divination: Button = $VBox/HSplit/RightPanel/BuildingsGrid/BuildingDivination
@onready var building_vault: Button = $VBox/HSplit/RightPanel/BuildingsGrid/BuildingVault
@onready var building_archive: Button = $VBox/HSplit/RightPanel/BuildingsGrid/BuildingArchive
@onready var building_fate_card_collection: Button = $VBox/HSplit/RightPanel/BuildingsGrid/BuildingFateCardCollection
@onready var level_select_button: Button = $VBox/LevelSelectButton
@onready var close_overlay_button: Button = $VBox/CloseOverlayButton

## 战利品面板
var _loot_panel: PanelContainer
var _loot_content: VBoxContainer

## 建筑升级面板
var _building_panel: PanelContainer
var _selected_building_type: int = -1

const BUILDING_INFO := {
	0: {"name": "枪械工坊", "desc": "升级增加武器制作选项"},
	1: {"name": "资源转换", "desc": "升级增加资源转换效率"},
	2: {"name": "废品回收", "desc": "升级增加回收产出"},
	3: {"name": "命运占卜屋", "desc": "升级增加命卡抽取选项"},
	4: {"name": "保险柜", "desc": "升级增加存储容量"},
	5: {"name": "黑市", "desc": "升级增加商品种类"},
	6: {"name": "怪物档案室", "desc": "升级解锁精英图鉴"},
}

const BUILDING_ENTRY_SCENES := {
	0: "res://scenes/WorkshopMenu.tscn",
	3: "res://scenes/DivinationMenu.tscn",
	4: "res://scenes/VaultMenu.tscn",
	6: "res://scenes/MonsterArchiveMenu.tscn",
}

func _ready() -> void:
	# BaseManager 已是 Autoload，直接通过全局名称访问
	# 绑定开始按钮
	if start_button:
		start_button.pressed.connect(_on_start_pressed)

	# 建筑按钮 - 命运占卜屋（可用）
	_set_building_enabled(building_divination, "命运占卜屋")
	building_divination.pressed.connect(_on_building_divination_pressed)

	# 建筑按钮 — 枪械工坊（可用，解锁后）
	_set_building_enabled(building_workshop, "枪械工坊")
	_set_building_enabled_style(building_workshop)
	building_workshop.pressed.connect(_on_building_workshop_pressed)

	# 建筑按钮 — 保险柜（可用）
	_set_building_enabled(building_vault, "保险柜")
	_set_building_enabled_style(building_vault)
	building_vault.pressed.connect(_on_building_vault_pressed)

	# 建筑按钮 — 怪物档案室（可用）
	_set_building_enabled(building_archive, "怪物档案室")
	_set_building_enabled_style(building_archive)
	building_archive.pressed.connect(_on_building_archive_pressed)

	# 建筑按钮 — 命运卡牌收藏室（可用）
	_set_building_enabled_style(building_fate_card_collection)
	building_fate_card_collection.pressed.connect(_on_building_fate_card_collection_pressed)

	# 副本入口属于固定大世界，不允许从管理菜单绕过野外路线。
	if level_select_button:
		level_select_button.text = "副本入口位于基地外的野外道路"
		level_select_button.disabled = true
		var style := UIStyleFactory.make_panel_with_border(2, UIPalette.BORDER_ACCENT, 6, 1)
		level_select_button.add_theme_stylebox_override("normal", style)
	if start_button:
		start_button.text = "返回基地与荒野"

	if close_overlay_button:
		close_overlay_button.visible = overlay_mode
		close_overlay_button.pressed.connect(_on_close_overlay_pressed)

	# 显示玩家数据
	_refresh_stats()

func _refresh_stats() -> void:
	# BaseManager 是 Autoload，通过全局名称访问
	if BaseManager == null or BaseManager.data == null:
		return
	var d := BaseManager.data
	if runs_label:
		runs_label.text = "总局数: %d" % d.total_runs
	if extractions_label:
		extractions_label.text = "成功撤离: %d" % d.successful_extractions
	if kills_label:
		kills_label.text = "总击杀: %d" % d.total_kills
	if points_label:
		points_label.text = "资源: %d" % BaseManager.get_extraction_points()
	# 检查撤离战利品
	_check_and_show_extraction_loot()

func _check_and_show_extraction_loot() -> void:
	if BaseManager == null:
		return
	var loot_count := BaseManager.get_extraction_loot_count()
	if loot_count > 0:
		_show_extraction_loot_panel()
	else:
		_hide_extraction_loot_panel()

func _show_extraction_loot_panel() -> void:
	# 如果面板已存在，只刷新内容
	if _loot_panel != null and is_instance_valid(_loot_panel):
		_build_loot_panel_content()
		_loot_panel.visible = true
		return

	# 创建遮罩
	var backdrop := ColorRect.new()
	backdrop.name = "LootBackdrop"
	backdrop.color = Color(0.0, 0.0, 0.0, 0.6)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(backdrop)

	# 创建面板
	_loot_panel = PanelContainer.new()
	_loot_panel.name = "ExtractionLootPanel"
	_loot_panel.custom_minimum_size = Vector2(500, 400)
	_loot_panel.set_anchors_preset(Control.PRESET_CENTER)
	_loot_panel.offset_left = -250
	_loot_panel.offset_top = -200
	_loot_panel.offset_right = 250
	_loot_panel.offset_bottom = 200
	_loot_panel.process_mode = Node.PROCESS_MODE_ALWAYS

	var style := UIStyleFactory.make_panel_with_border(0, UIPalette.BORDER_FOCUS, 8, 2)
	_loot_panel.add_theme_stylebox_override("panel", style)

	_loot_content = VBoxContainer.new()
	_loot_content.name = "LootContent"
	_loot_content.add_theme_constant_override("separation", 10)
	_loot_panel.add_child(_loot_content)

	add_child(_loot_panel)
	_build_loot_panel_content()

func _build_loot_panel_content() -> void:
	if _loot_content == null:
		return
	for child in _loot_content.get_children():
		child.queue_free()

	var title := Label.new()
	title.text = "战利品"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4, 1.0))
	_loot_content.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "选择物品存入仓库"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 14)
	_loot_content.add_child(subtitle)

	_loot_content.add_child(_make_hsep())

	# 物品列表
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(460, 200)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var items_vbox := VBoxContainer.new()
	items_vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(items_vbox)

	var loot_items := BaseManager.get_extraction_loot()
	for i in loot_items.size():
		var item: Dictionary = loot_items[i]
		var row := _make_loot_item_row(i, item)
		items_vbox.add_child(row)

	_loot_content.add_child(scroll)

	_loot_content.add_child(_make_hsep())

	# 按钮行
	var btn_box := HBoxContainer.new()
	btn_box.alignment = HBoxContainer.ALIGNMENT_CENTER
	btn_box.add_theme_constant_override("separation", 20)

	var deposit_all_btn := Button.new()
	deposit_all_btn.text = "一键存入仓库"
	deposit_all_btn.custom_minimum_size = Vector2(160, 44)
	deposit_all_btn.pressed.connect(_on_deposit_all_loot_pressed)
	var deposit_all_styles := UIStyleFactory.make_button_style(UIStyleFactory.make_panel_bg(2).bg_color, UIPalette.STATUS_OK)
	UIStyleFactory.apply_button_style(deposit_all_btn, deposit_all_styles)
	btn_box.add_child(deposit_all_btn)

	var discard_all_btn := Button.new()
	discard_all_btn.text = "全部丢弃"
	discard_all_btn.custom_minimum_size = Vector2(120, 44)
	discard_all_btn.pressed.connect(_on_discard_all_loot_pressed)
	var discard_all_styles := UIStyleFactory.make_button_style(UIStyleFactory.make_panel_bg(2).bg_color, UIPalette.HP_LOW)
	UIStyleFactory.apply_button_style(discard_all_btn, discard_all_styles)
	btn_box.add_child(discard_all_btn)

	_loot_content.add_child(btn_box)

func _make_loot_item_row(index: int, item: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 44)

	var hbox := HBoxContainer.new()
	panel.add_child(hbox)

	var item_type: String = item.get("type", "")
	var border_color := UIPalette.item_border_color(item_type)

	panel.add_theme_stylebox_override(
		"panel",
		UIStyleFactory.make_item_row_style(item_type, Color(0.1, 0.1, 0.12, 0.9), true, 3),
	)

	var name_lbl := Label.new()
	name_lbl.text = item.get("name", "?")
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_color_override("font_color", border_color)
	hbox.add_child(name_lbl)

	var count_lbl := Label.new()
	count_lbl.text = "×%d" % item.get("count", 1)
	count_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1.0))
	hbox.add_child(count_lbl)

	var deposit_btn := Button.new()
	deposit_btn.text = "存入"
	deposit_btn.pressed.connect(_on_deposit_loot_item_pressed.bind(index))
	var deposit_styles := UIStyleFactory.make_button_style(UIStyleFactory.make_panel_bg(2).bg_color, UIPalette.STATUS_OK)
	UIStyleFactory.apply_button_style(deposit_btn, deposit_styles)
	hbox.add_child(deposit_btn)

	var discard_btn := Button.new()
	discard_btn.text = "丢弃"
	discard_btn.pressed.connect(_on_discard_loot_item_pressed.bind(index))
	var discard_styles := UIStyleFactory.make_button_style(UIStyleFactory.make_panel_bg(2).bg_color, UIPalette.HP_LOW)
	UIStyleFactory.apply_button_style(discard_btn, discard_styles)
	hbox.add_child(discard_btn)

	return panel

func _make_hsep() -> HSeparator:
	var sep := HSeparator.new()
	sep.custom_minimum_size = Vector2(0, 6)
	return sep

func _on_deposit_all_loot_pressed() -> void:
	if BaseManager == null:
		return
	var deposited := BaseManager.deposit_all_extraction_loot()
	print("[BaseMenu] 一键存入: %d 件" % deposited)
	_hide_extraction_loot_panel()

func _on_discard_all_loot_pressed() -> void:
	if BaseManager == null:
		return
	BaseManager.clear_extraction_loot()
	_hide_extraction_loot_panel()

func _on_deposit_loot_item_pressed(index: int) -> void:
	if BaseManager == null:
		return
	if BaseManager.deposit_extraction_loot_item(index):
		# 刷新面板
		_build_loot_panel_content()
		# 如果没有物品了，隐藏面板
		if BaseManager.get_extraction_loot_count() <= 0:
			_hide_extraction_loot_panel()

func _on_discard_loot_item_pressed(index: int) -> void:
	if BaseManager == null:
		return
	BaseManager.discard_extraction_loot_item(index)
	_build_loot_panel_content()
	if BaseManager.get_extraction_loot_count() <= 0:
		_hide_extraction_loot_panel()

func _hide_extraction_loot_panel() -> void:
	if _loot_panel != null and is_instance_valid(_loot_panel):
		_loot_panel.queue_free()
		_loot_panel = null
	var backdrop := find_child("LootBackdrop", true, false)
	if backdrop != null:
		backdrop.queue_free()

func _set_building_disabled(btn: Button, name: String) -> void:
	if btn == null:
		return
	btn.disabled = true
	if btn.has_node("DescLabel"):
		var desc: Label = btn.get_node("DescLabel") as Label
		desc.text = name + "\n[功能开发中]"
	# 降低可见度表示不可用
	var style := UIStyleFactory.make_panel_with_border(2, Color(0.3, 0.3, 0.35, 0.5), 6, 1)
	btn.add_theme_stylebox_override("normal", style)

func _set_building_disabled_placeholder(btn: Button, name: String) -> void:
	## 占位方法 - 其他建筑仍为 disabled
	_set_building_disabled(btn, name)

func _set_building_enabled(btn: Button, name: String) -> void:
	if btn == null:
		return
	btn.disabled = false
	var style := UIStyleFactory.make_panel_with_border(2, Color(0.4, 0.55, 0.9, 0.7), 6, 1)
	btn.add_theme_stylebox_override("normal", style)

func _set_building_enabled_style(btn: Button) -> void:
	if btn == null:
		return
	btn.disabled = false
	var style := UIStyleFactory.make_panel_with_border(2, Color(0.4, 0.55, 0.9, 0.7), 6, 1)
	btn.add_theme_stylebox_override("normal", style)

func _on_building_divination_pressed() -> void:
	_show_building_panel(3)

func _on_building_workshop_pressed() -> void:
	_show_building_panel(0)

func _has_workshop_scene() -> bool:
	return FileAccess.file_exists("res://scenes/WorkshopMenu.tscn")

func _on_building_vault_pressed() -> void:
	_show_building_panel(4)

func _on_building_archive_pressed() -> void:
	_show_building_panel(6)

func _on_building_fate_card_collection_pressed() -> void:
	_open_menu_scene("res://scenes/FateCardCollectionMenu.tscn")

func _open_menu_scene(scene_path: String) -> void:
	var menu_scene: PackedScene = load(scene_path)
	if menu_scene:
		var menu: CanvasLayer = menu_scene.instantiate() as CanvasLayer
		get_tree().get_root().add_child(menu)

func _on_level_select_pressed() -> void:
	return

func _on_start_pressed() -> void:
	if overlay_mode:
		queue_free()
		return
	get_tree().change_scene_to_file("res://scenes/BaseWorld.tscn")


func _on_close_overlay_pressed() -> void:
	if overlay_mode:
		queue_free()

## ——— 建筑升级面板 ———

func _show_building_panel(building_type: int) -> void:
	# 已有面板时只刷新
	if _building_panel != null and is_instance_valid(_building_panel):
		_selected_building_type = building_type
		_refresh_building_panel()
		return

	_selected_building_type = building_type

	# 遮罩
	var backdrop := ColorRect.new()
	backdrop.name = "BuildingBackdrop"
	backdrop.color = Color(0.0, 0.0, 0.0, 0.6)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.process_mode = Node.PROCESS_MODE_ALWAYS
	backdrop.gui_input.connect(_on_building_panel_backdrop_input)
	add_child(backdrop)

	# 面板
	_building_panel = PanelContainer.new()
	_building_panel.name = "BuildingUpgradePanel"
	_building_panel.custom_minimum_size = Vector2(380, 280)
	_building_panel.set_anchors_preset(Control.PRESET_CENTER)
	_building_panel.offset_left = -190
	_building_panel.offset_top = -140
	_building_panel.offset_right = 190
	_building_panel.offset_bottom = 140
	_building_panel.process_mode = Node.PROCESS_MODE_ALWAYS

	var style := UIStyleFactory.make_panel_with_border(0, UIPalette.BORDER_FOCUS, 8, 2)
	_building_panel.add_theme_stylebox_override("panel", style)

	add_child(_building_panel)
	_refresh_building_panel()

func _refresh_building_panel() -> void:
	if _building_panel == null or not is_instance_valid(_building_panel):
		return
	for child in _building_panel.get_children():
		child.queue_free()

	var vbox := VBoxContainer.new()
	_building_panel.add_child(vbox)

	var info: Dictionary = BUILDING_INFO.get(_selected_building_type, {})
	var bname: String = info.get("name", "建筑")
	var level: int = BaseManager.get_level(_selected_building_type)
	var cost: int = BaseManager.get_upgrade_cost(_selected_building_type)
	var current_points: int = BaseManager.get_extraction_points()

	# 标题
	var title := Label.new()
	title.text = "%s  Lv.%d" % [bname, level]
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.5, 1.0))
	vbox.add_child(title)

	vbox.add_child(_make_hsep())

	# 当前资源点
	var pts_lbl := Label.new()
	pts_lbl.text = "当前资源: %d" % current_points
	pts_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 1.0, 1.0))
	vbox.add_child(pts_lbl)

	# 升级说明
	var desc_lbl := Label.new()
	desc_lbl.text = info.get("desc", "")
	desc_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65, 1.0))
	vbox.add_child(desc_lbl)

	# 升级费用
	var cost_lbl := Label.new()
	cost_lbl.text = "升级费用: %d 资源点" % cost
	cost_lbl.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4, 1.0))
	vbox.add_child(cost_lbl)

	# 容量信息（保险柜）
	if _selected_building_type == 4:
		var cap_lbl := Label.new()
		cap_lbl.text = "存储容量: %d 格" % BaseManager.get_vault_capacity()
		cap_lbl.add_theme_color_override("font_color", Color(0.6, 0.85, 0.6, 1.0))
		vbox.add_child(cap_lbl)

	vbox.add_child(_make_hsep())

	# 按钮行
	var btn_box := HBoxContainer.new()
	btn_box.alignment = HBoxContainer.ALIGNMENT_CENTER
	btn_box.add_theme_constant_override("separation", 16)

	# 进入功能按钮（如果有对应菜单）
	if BUILDING_ENTRY_SCENES.has(_selected_building_type):
		var enter_btn := Button.new()
		enter_btn.custom_minimum_size = Vector2(110, 44)
		enter_btn.text = "进入功能"
		enter_btn.pressed.connect(_on_enter_building_feature_pressed)
		var enter_styles := UIStyleFactory.make_button_style(UIStyleFactory.make_panel_bg(2).bg_color, UIPalette.BORDER_FOCUS)
		UIStyleFactory.apply_button_style(enter_btn, enter_styles)
		btn_box.add_child(enter_btn)

	var upgrade_btn := Button.new()
	upgrade_btn.custom_minimum_size = Vector2(140, 44)
	var upgrade_styles := UIStyleFactory.make_button_style(UIStyleFactory.make_panel_bg(2).bg_color, UIPalette.TEXT_GOLD)
	UIStyleFactory.apply_button_style(upgrade_btn, upgrade_styles)
	if current_points < cost:
		upgrade_btn.text = "资源不足"
		upgrade_btn.disabled = true
	else:
		upgrade_btn.text = "升级 (+1级)"
		upgrade_btn.pressed.connect(_on_upgrade_building_confirmed)
	btn_box.add_child(upgrade_btn)

	var close_btn := Button.new()
	close_btn.custom_minimum_size = Vector2(80, 44)
	close_btn.text = "关闭"
	close_btn.pressed.connect(_hide_building_panel)
	var close_styles := UIStyleFactory.make_button_style(UIStyleFactory.make_panel_bg(2).bg_color, UIPalette.BORDER_NORMAL)
	UIStyleFactory.apply_button_style(close_btn, close_styles)
	btn_box.add_child(close_btn)

	vbox.add_child(btn_box)

func _on_upgrade_building_confirmed() -> void:
	if _selected_building_type < 0:
		return
	var cost: int = BaseManager.get_upgrade_cost(_selected_building_type)
	if not BaseManager.spend_extraction_points(cost):
		return
	BaseManager.upgrade_building(_selected_building_type)
	_refresh_stats()
	_refresh_building_panel()

func _on_enter_building_feature_pressed() -> void:
	var scene_path: String = String(BUILDING_ENTRY_SCENES.get(_selected_building_type, ""))
	_hide_building_panel()
	if not scene_path.is_empty():
		_open_menu_scene(scene_path)

func _hide_building_panel() -> void:
	if _building_panel != null and is_instance_valid(_building_panel):
		_building_panel.queue_free()
		_building_panel = null
	var backdrop := find_child("BuildingBackdrop", true, false)
	if backdrop != null:
		backdrop.queue_free()
	_selected_building_type = -1

func _on_building_panel_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_hide_building_panel()
