class_name ExtractionProgressUI
## 撤离进度UI — 显示撤离点选择、读条进度
## 挂在 CanvasLayer 下

extends Control

signal extraction_type_selected(extraction_type: String, countdown: float)

@export var extraction_types: Array[String] = ["STANDARD", "BEACON", "BOSS_KILL", "ELITE_KILL", "TRADE"]

var _extraction_director: Node = null
var _extraction_module: Node = null
var _is_extraction_panel_visible: bool = false
var _beacon_count: int = 0

@onready var panel: PanelContainer = get_node_or_null(".")
@onready var extraction_type_label: Label = get_node_or_null("VBox/ExtractionTypeLabel")
@onready var countdown_bar: ProgressBar = get_node_or_null("VBox/CountdownBar")
@onready var countdown_label: Label = get_node_or_null("VBox/CountdownLabel")
@onready var extraction_buttons_container: VBoxContainer = get_node_or_null("VBox/ExtractionButtons")
@onready var beacon_label: Label = get_node_or_null("VBox/BeaconLabel")
@onready var abort_button: Button = get_node_or_null("VBox/AbortButton")

func _ready() -> void:
	if panel == null or extraction_type_label == null:
		return
	panel.visible = false
	countdown_bar.max_value = 1.0
	countdown_bar.value = 0.0
	if abort_button:
		abort_button.pressed.connect(_on_abort_pressed)
		# 中断按钮使用红色 accent 区分
		var abort_styles := UIStyleFactory.make_button_style(UIStyleFactory.make_panel_bg(2).bg_color, UIPalette.HP_LOW)
		UIStyleFactory.apply_button_style(abort_button, abort_styles)
	UIStyleFactory.apply_tactical_tree(self)

## 绑定 extraction director 和 module
func set_extraction_director(director: Node) -> void:
	_extraction_director = director
	_build_extraction_buttons()

func set_extraction_module(module: Node) -> void:
	_extraction_module = module

func set_beacon_count(count: int) -> void:
	_beacon_count = count
	_update_beacon_label()

## 显示撤离选择面板
func show_extraction_panel() -> void:
	_is_extraction_panel_visible = true
	panel.visible = true
	countdown_bar.visible = false
	abort_button.visible = false
	_update_beacon_label()
	_update_extraction_buttons()

## 隐藏撤离面板
func hide_extraction_panel() -> void:
	_is_extraction_panel_visible = false
	panel.visible = false

## 构建撤离类型按钮
func _build_extraction_buttons() -> void:
	for child in extraction_buttons_container.get_children():
		child.queue_free()

	for etype in extraction_types:
		var btn := Button.new()
		btn.text = _get_extraction_button_text(etype)
		btn.custom_minimum_size = Vector2(220, 36)
		btn.pressed.connect(_on_extraction_type_button_pressed.bind(etype))
		# 撤离类型按钮统一使用 BORDER_FOCUS 蓝色高亮
		var styles := UIStyleFactory.make_button_style(UIStyleFactory.make_panel_bg(2).bg_color, UIPalette.BORDER_FOCUS)
		UIStyleFactory.apply_button_style(btn, styles)
		extraction_buttons_container.add_child(btn)

func _get_extraction_button_text(etype: String) -> String:
	match etype:
		"STANDARD": return "撤离点 (安全但偏远)"
		"BEACON": return "信标撤离 (消耗道具)"
		"BOSS_KILL": return "Boss撤离 (需击败Boss)"
		"ELITE_KILL": return "精英撤离 (需击败精英)"
		"TRADE": return "交易撤离 (消耗资源)"
	return etype

func _update_extraction_buttons() -> void:
	for i in extraction_buttons_container.get_children().size():
		var btn: Button = extraction_buttons_container.get_child(i) as Button
		var etype: String = extraction_types[i]
		btn.disabled = not _can_use_extraction_type(etype)
		btn.modulate = Color.WHITE if not btn.disabled else Color.GRAY

func _can_use_extraction_type(etype: String) -> bool:
	match etype:
		"BEACON": return _beacon_count > 0
		"BOSS_KILL": return _extraction_director != null and _extraction_director.get_points_by_type(ExtractionDirector.ExtractionType.BOSS_KILL).size() > 0
		"ELITE_KILL": return _extraction_director != null and _extraction_director.get_points_by_type(ExtractionDirector.ExtractionType.ELITE_KILL).size() > 0
	return true

func _update_beacon_label() -> void:
	if beacon_label:
		beacon_label.text = "信标数量: %d" % _beacon_count

## 撤离类型按钮点击
func _on_extraction_type_button_pressed(etype: String) -> void:
	var countdown: float = 5.0
	match etype:
		"STANDARD": countdown = 8.0
		"BEACON": countdown = 10.0
		"BOSS_KILL": countdown = 3.0  # Boss撤离更快
		"ELITE_KILL": countdown = 5.0
		"TRADE": countdown = 5.0
	
	extraction_type_selected.emit(etype, countdown)
	hide_extraction_panel()

## 开始撤离读条UI
func start_extraction_countdown(extraction_type: String, duration: float) -> void:
	panel.visible = true
	countdown_bar.visible = true
	abort_button.visible = true
	extraction_type_label.text = "撤离中: %s" % extraction_type
	countdown_bar.max_value = 1.0
	countdown_bar.value = 0.0
	_update_countdown_label(duration, duration)

## 更新读条进度
func update_countdown(progress: float, remaining: float) -> void:
	countdown_bar.value = progress
	_update_countdown_label(remaining, countdown_bar.max_value)

func _update_countdown_label(remaining: float, total: float) -> void:
	if countdown_label:
		countdown_label.text = "%.1f 秒" % remaining

## 撤离完成
func show_extraction_success() -> void:
	panel.visible = true
	countdown_bar.visible = false
	abort_button.visible = false
	extraction_type_label.text = "撤离成功！"
	countdown_label.text = "战利品已保存"

## 撤离中断
func show_extraction_aborted() -> void:
	panel.visible = true
	countdown_bar.visible = false
	abort_button.visible = false
	extraction_type_label.text = "撤离中断！"

func _on_abort_pressed() -> void:
	abort_button.disabled = true
	extraction_type_label.text = "撤离已中断"
	await get_tree().create_timer(1.5).timeout
	hide_extraction_panel()
	abort_button.disabled = false
