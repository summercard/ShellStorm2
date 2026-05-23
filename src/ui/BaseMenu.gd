class_name BaseMenu
extends CanvasLayer

## 基地主界面 - 游戏入口 Hub
## 显示玩家长期进度、建筑解锁状态，提供开始任务按钮
##
## BaseManager 通过 Autoload 直接访问（已在 project.godot 注册）

@onready var runs_label: Label = $VBox/StatsPanel/VBox/RunsLabel
@onready var extractions_label: Label = $VBox/StatsPanel/VBox/ExtractionsLabel
@onready var kills_label: Label = $VBox/StatsPanel/VBox/KillsLabel
@onready var start_button: Button = $VBox/StartButton
@onready var building_workshop: Button = $VBox/BuildingsPanel/VBox/BuildingWorkshop
@onready var building_divination: Button = $VBox/BuildingsPanel/VBox/BuildingDivination
@onready var building_vault: Button = $VBox/BuildingsPanel/VBox/BuildingVault
@onready var building_archive: Button = $VBox/BuildingsPanel/VBox/BuildingArchive

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

	# 其他建筑按钮框架
	_set_building_disabled(building_archive, "怪物档案室")

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

func _set_building_disabled(btn: Button, name: String) -> void:
	if btn == null:
		return
	btn.disabled = true
	if btn.has_node("DescLabel"):
		var desc: Label = btn.get_node("DescLabel") as Label
		desc.text = name + "\n[功能开发中]"
	# 降低可见度表示不可用
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.18, 0.8)
	style.set_border_width_all(1)
	style.set_border_color(Color(0.3, 0.3, 0.35, 0.5))
	style.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", style)

func _set_building_disabled_placeholder(btn: Button, name: String) -> void:
	## 占位方法 - 其他建筑仍为 disabled
	_set_building_disabled(btn, name)

func _set_building_enabled(btn: Button, name: String) -> void:
	if btn == null:
		return
	btn.disabled = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.22, 0.35, 0.9)
	style.set_border_width_all(1)
	style.set_border_color(Color(0.4, 0.55, 0.9, 0.7))
	style.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", style)

func _set_building_enabled_style(btn: Button) -> void:
	if btn == null:
		return
	btn.disabled = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.22, 0.35, 0.9)
	style.set_border_width_all(1)
	style.set_border_color(Color(0.4, 0.55, 0.9, 0.7))
	style.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", style)

func _on_building_divination_pressed() -> void:
	var menu_scene: PackedScene = load("res://scenes/DivinationMenu.tscn")
	if menu_scene:
		var menu: CanvasLayer = menu_scene.instantiate() as CanvasLayer
		get_tree().get_root().add_child(menu)

func _on_building_workshop_pressed() -> void:
	# 加载 WorkshopMenu 场景文件并实例化，而非直接 new() 脚本
	var menu_scene: PackedScene = load("res://scenes/WorkshopMenu.tscn")
	if menu_scene:
		var menu: CanvasLayer = menu_scene.instantiate() as CanvasLayer
		get_tree().get_root().add_child(menu)

func _on_building_vault_pressed() -> void:
	var menu_scene: PackedScene = load("res://scenes/VaultMenu.tscn")
	if menu_scene:
		var menu: CanvasLayer = menu_scene.instantiate() as CanvasLayer
		get_tree().get_root().add_child(menu)

func _on_start_pressed() -> void:
	# 清理基地界面，过渡到游戏主场景
	get_tree().change_scene_to_file("res://scenes/Main.tscn")
