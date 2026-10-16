class_name PauseMenu3D
extends Control
## 三张 3D 游戏地图共用的暂停覆盖层。只有本节点在暂停时继续接收输入；
## 世界、AI、射弹和计时器继续遵守 Pausable，不会暗中推进。

signal pause_changed(paused: bool)
signal return_to_base_requested()
signal return_to_base_resolved(result: Dictionary)
signal game_save_reset_requested()
signal game_save_reset_resolved(result: Dictionary)

const ReturnAction = preload("res://src/ui/unstuck/ReturnToBaseAction.gd")
const TRAINING_RANGE_SCENE_PATH := "res://scenes/TrainingRange3D.tscn"

const AA_MODES := ["off", "fxaa", "msaa_2x", "msaa_4x", "msaa_8x", "taa"]
const AA_LABELS := ["关闭", "FXAA（快速）", "MSAA 2×", "MSAA 4×", "MSAA 8×", "TAA（高档推荐）"]
const SHADOW_MODES := ["low", "medium", "high"]
const SHADOW_LABELS := ["低 · 1024", "中 · 2048", "高 · 4096（当前）"]
const INDIRECT_DIFFUSE_MODES := ["low", "medium", "high"]
const INDIRECT_DIFFUSE_LABELS := ["低 · 近域", "中 · 平衡", "高 · 完整"]
const DEVICE_MODE_LABELS := ["自动跟随", "锁定键鼠", "锁定手柄"]

## 主页左栏宽度（逻辑像素）。参考图的菜单只占屏宽约三分之一，
## 右半边留给实景；把细线铺满整屏就失去了"左栏"这个语义。
const PRISM_RAIL_WIDTH := 820.0

@onready var resume_button: Button = $Center/Panel/Margin/MainPage/ResumeButton
@onready var graphics_button: Button = $Center/Panel/Margin/MainPage/GraphicsButton
@onready var return_to_base_button: Button = $Center/Panel/Margin/MainPage/ReturnToBaseButton
@onready var return_to_base_hint: Label = $Center/Panel/Margin/MainPage/ReturnToBaseHint
@onready var reset_game_save_button: Button = $Center/Panel/Margin/MainPage/ResetGameSaveButton
@onready var reset_game_save_hint: Label = $Center/Panel/Margin/MainPage/ResetGameSaveHint
@onready var training_range_button: Button = $Center/Panel/Margin/MainPage/TrainingRangeButton
@onready var training_range_hint: Label = $Center/Panel/Margin/MainPage/TrainingRangeHint
@onready var reset_game_save_dialog: ConfirmationDialog = $ResetGameSaveDialog
@onready var main_page: VBoxContainer = $Center/Panel/Margin/MainPage
@onready var graphics_page: VBoxContainer = $Center/Panel/Margin/GraphicsPage
@onready var controls_button: Button = $Center/Panel/Margin/MainPage/ControlsButton
@onready var controls_page: VBoxContainer = $Center/Panel/Margin/ControlsPage
@onready var device_status_label: Label = $Center/Panel/Margin/ControlsPage/Header/DeviceStatusLabel
@onready var device_mode_option: OptionButton = $Center/Panel/Margin/ControlsPage/DeviceRow/DeviceModeOption
@onready var gamepad_enabled_toggle: CheckButton = $Center/Panel/Margin/ControlsPage/GamepadEnabled
@onready var move_deadzone_slider: HSlider = $Center/Panel/Margin/ControlsPage/MoveDeadzoneRow/MoveDeadzoneSlider
@onready var move_deadzone_value: Label = $Center/Panel/Margin/ControlsPage/MoveDeadzoneRow/MoveDeadzoneValue
@onready var aim_deadzone_slider: HSlider = $Center/Panel/Margin/ControlsPage/AimDeadzoneRow/AimDeadzoneSlider
@onready var aim_deadzone_value: Label = $Center/Panel/Margin/ControlsPage/AimDeadzoneRow/AimDeadzoneValue
@onready var aim_smoothing_slider: HSlider = $Center/Panel/Margin/ControlsPage/AimSmoothingRow/AimSmoothingSlider
@onready var aim_smoothing_value: Label = $Center/Panel/Margin/ControlsPage/AimSmoothingRow/AimSmoothingValue
@onready var left_stick_aim_toggle: CheckButton = $Center/Panel/Margin/ControlsPage/LeftStickAim
@onready var aim_assist_toggle: CheckButton = $Center/Panel/Margin/ControlsPage/AimAssist
@onready var vibration_toggle: CheckButton = $Center/Panel/Margin/ControlsPage/Vibration
@onready var controls_back_button: Button = $Center/Panel/Margin/ControlsPage/Footer/BackButton
@onready var controls_status_label: Label = $Center/Panel/Margin/ControlsPage/Footer/Status
@onready var renderer_label: Label = $Center/Panel/Margin/GraphicsPage/Header/RendererLabel
@onready var aa_option: OptionButton = $Center/Panel/Margin/GraphicsPage/AASection/AAOption
@onready var shadow_option: OptionButton = $Center/Panel/Margin/GraphicsPage/Scroll/Grid/Shadows/ShadowOption
@onready var indirect_diffuse_option: OptionButton = $Center/Panel/Margin/GraphicsPage/Scroll/Grid/IndirectDiffuse/QualityOption
@onready var high_defaults_button: Button = $Center/Panel/Margin/GraphicsPage/PresetRow/HighDefaultsButton
@onready var back_button: Button = $Center/Panel/Margin/GraphicsPage/Footer/BackButton
@onready var status_label: Label = $Center/Panel/Margin/GraphicsPage/Footer/Status
@onready var dim: ColorRect = $Dim
@onready var center: CenterContainer = $Center
@onready var main_page_title: Label = $Center/Panel/Margin/MainPage/Title

var _toggle_nodes: Dictionary = {}
var _syncing_controls := false
var _reset_in_progress := false
var _return_to_base_request_in_progress := false
var _main_entry_request_id := -1
## 是否以「主页设置」上下文复用本覆盖层（主代理临时 reparent 到主页 CanvasLayer）。
var _entry_settings_context := false
var _main_page_title_default_text := "行动暂停"
var _resume_button_default_text := "继续行动  [Esc]"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = true
	add_to_group("pause_input_guard")
	if Global != null and not Global.game_paused.is_connected(_on_global_pause_changed):
		Global.game_paused.connect(_on_global_pause_changed)
	_apply_pause_visual(Global != null and Global.has_pause_reason("manual"))
	resume_button.pressed.connect(resume_game)
	graphics_button.pressed.connect(_show_graphics_page)
	controls_button.pressed.connect(_show_controls_page)
	# 失败态返城会替换整个场景；等 GUI 输入派发结束后再执行。
	return_to_base_button.pressed.connect(_request_return_to_base, CONNECT_DEFERRED)
	training_range_button.pressed.connect(_request_training_range, CONNECT_DEFERRED)
	reset_game_save_button.pressed.connect(_request_game_save_reset)
	reset_game_save_dialog.confirmed.connect(_confirm_game_save_reset)
	back_button.pressed.connect(_show_main_page)
	controls_back_button.pressed.connect(_show_main_page)
	high_defaults_button.pressed.connect(_restore_high_defaults)
	_setup_graphics_controls()
	_setup_input_controls()
	_apply_prism_pause_style()
	_main_page_title_default_text = main_page_title.text
	_resume_button_default_text = resume_button.text



func try_consume_pause_input() -> bool:
	if Global != null and Global.has_pause_reason("manual"):
		if reset_game_save_dialog.visible:
			reset_game_save_dialog.hide()
			reset_game_save_button.grab_focus()
			return true
		if graphics_page.visible or controls_page.visible:
			_show_main_page()
			return true
		return false
	var game_root := get_parent().get_parent()
	return (
		game_root != null
		and game_root.has_method("try_close_modal_for_pause")
		and bool(game_root.call("try_close_modal_for_pause"))
	)


func set_paused(paused: bool) -> void:
	if Global != null:
		if paused:
			Global.acquire_pause("manual")
		else:
			Global.release_pause("manual")
	else:
		get_tree().paused = paused
		_on_global_pause_changed(paused)


func resume_game() -> void:
	set_paused(false)


## 以「主页设置」上下文打开本覆盖层：标题改为设置、resume 改为返回主界面，
## 隐藏返回基地 / 复位存档相关按钮，画面与操作设置仍可用。
func open_entry_settings() -> void:
	if _entry_settings_context:
		return
	_entry_settings_context = true
	set_paused(true)
	# Global 总暂停状态可能本已为 true（例如从暂停模式切来），
	# _on_global_pause_changed 不会重新触发，因此显式刷新一次视觉与主页面。
	_apply_pause_visual(true)
	_show_main_page()
	_apply_entry_settings_overrides()


## 退出「主页设置」上下文：先复位上下文标记（幂等、防递归），再解除暂停，
## 最后把主页面标题 / resume 文案 / 隐藏按钮恢复原状并交回原刷新方法。
func close_entry_settings() -> void:
	if not _entry_settings_context:
		return
	_entry_settings_context = false
	set_paused(false)
	main_page_title.text = _main_page_title_default_text
	resume_button.text = _resume_button_default_text
	return_to_base_button.visible = true
	return_to_base_hint.visible = true
	training_range_button.visible = true
	training_range_hint.visible = true
	reset_game_save_button.visible = true
	reset_game_save_hint.visible = true
	_refresh_return_to_base_action()
	_refresh_training_range_action()


## 套用「主页设置」上下文的视觉覆盖：隐藏与战局 / 存档相关的按钮与提示，
## 并将标题与 resume 文案改为设置语义。
func _apply_entry_settings_overrides() -> void:
	return_to_base_button.visible = false
	return_to_base_hint.visible = false
	training_range_button.visible = false
	training_range_hint.visible = false
	reset_game_save_button.visible = false
	reset_game_save_hint.visible = false
	main_page_title.text = "设置"
	resume_button.text = "返回主界面"

func is_pause_open() -> bool:
	return center.visible and Global != null and Global.has_pause_reason("manual")


func _on_global_pause_changed(_paused: bool) -> void:
	var manual_paused := Global != null and Global.has_pause_reason("manual")
	_apply_pause_visual(manual_paused)
	if manual_paused:
		_show_main_page()
		_refresh_return_to_base_action()
		resume_button.grab_focus()
	else:
		reset_game_save_dialog.hide()
	pause_changed.emit(manual_paused)


func _apply_pause_visual(paused: bool) -> void:
	dim.visible = paused
	center.visible = paused
	mouse_filter = Control.MOUSE_FILTER_STOP if paused else Control.MOUSE_FILTER_IGNORE
	if paused:
		var panel := get_node_or_null("Center/Panel") as Control
		if panel != null:
			UIFX.pop_in_modal(panel)


## 「棱镜线框」全量装配（2026-10-16 业主第二轮指定参考图）：
## 深色徽章标题 + 白色延长细线 + 下折角提示；主行动 = 实心近白高对比；
## 次行动 = 四角括号线框；复位存档 = 平红危险；设置行 = 方角箭头 + 大号近白值；
## 全方角、无辉光、无渐变。所有节点名 / 路径 / 类型保持不变。
func _apply_prism_pause_style() -> void:
	set_meta("ui_style_exempt", true)
	_build_prism_pause_chrome()
	_style_prism_main_page()
	_style_prism_graphics_page()
	_style_prism_controls_page()
	_style_prism_reset_dialog()


## 外壳：极淡底衬，**不加外框**。参考图整屏没有一处"卡片边框"——
## 结构感全部来自贯穿细线与那一个括号选框，外面再套一圈大括号会立刻回到上一轮的乱线感。
## 压暗也收得比上一轮浅：参考图的实景是主角，UI 只是浮在上面的线。
func _build_prism_pause_chrome() -> void:
	var panel := get_node_or_null("Center/Panel") as PanelContainer
	if panel != null:
		panel.add_theme_stylebox_override("panel", UIStyleFactory.make_prism_panel(true, 0.30))
		panel.custom_minimum_size = Vector2(1040, 700)
	if dim != null:
		dim.color = Color(UIPalette.PRISM_DIM.r, UIPalette.PRISM_DIM.g, UIPalette.PRISM_DIM.b, 0.70)


## 深色徽章（参考图左上 NEW GAME 的形态）。Label 自带 `normal` 样式盒，正好当胶囊底用，
## 因此无需新增节点、也不必改动既有节点树。
## 参考图的徽章是**纯深色实块**（没有白色描边），描边会把胶囊变成"按钮"。
func _apply_prism_badge_to_label(
	label: Label,
	font_size: int = 26,
	spacing: int = 6,
	align_left: bool = true
) -> void:
	if label == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.039, 0.059, 0.086, 0.94)
	style.border_color = Color(0, 0, 0, 0)
	style.set_border_width_all(0)
	style.set_corner_radius_all(6)
	style.shadow_size = 0
	style.content_margin_left = 30.0
	style.content_margin_right = 30.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	label.add_theme_stylebox_override("normal", style)
	label.add_theme_constant_override("outline_size", 0)
	label.size_flags_horizontal = (
		Control.SIZE_SHRINK_BEGIN if align_left else Control.SIZE_SHRINK_CENTER
	)
	label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_LEFT if align_left else HORIZONTAL_ALIGNMENT_CENTER
	)
	UIStyleFactory.apply_prism_label(label, "value", spacing, font_size)


## 把白色键帽骑到按钮右端（参考图所有快捷键都是实体白方块）。
## 统一走工厂版本，这样"给文本让位"的右内边距补偿也会一起生效。
func _attach_prism_keycap(btn: Button, key_text: String) -> void:
	UIStyleFactory.attach_prism_keycap(btn, key_text, 12, 20.0)


## 在 VBox 页里紧贴某个控件下方插入一条左对齐的下折角（参考图徽章底部的 ⌄）。
func _insert_prism_chevron_below(page: VBoxContainer, anchor: Control, alpha: float = 0.5) -> void:
	if page == null or anchor == null or page.get_node_or_null("PrismHeaderChevron") != null:
		return
	var chevron := UIStyleFactory.make_prism_chevron(
		"down", Color(1.0, 1.0, 1.0, alpha), Vector2(16, 10), 2.0
	)
	chevron.name = "PrismHeaderChevron"
	chevron.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	page.add_child(chevron)
	page.move_child(chevron, anchor.get_index() + 1)


## 在 VBox 页里紧贴某个控件下方插入一条 1px 白色细分割线。
func _insert_prism_rule_below(page: VBoxContainer, anchor: Control, alpha: float = 0.30) -> void:
	if page == null or anchor == null or page.get_node_or_null("PrismHeaderRule") != null:
		return
	var rule := UIStyleFactory.make_prism_rule(Color(1.0, 1.0, 1.0, alpha), 1.0)
	rule.name = "PrismHeaderRule"
	page.add_child(rule)
	page.move_child(rule, anchor.get_index() + 1)


# ---------- 主页 ----------

## 主页 = 参考图的左栏结构，而不是"一列居中按钮 + 每个按钮一圈括号"。
##   徽章标题 → ⌄ → 一组贯穿细线分隔的左对齐行动行 → 一个括号选框（CONTINUE 位）。
## 括号只出现在唯一的那一个"当前选框"上，其余行动一律是行。
func _style_prism_main_page() -> void:
	# 标题 = 深色徽章（参考图 NEW GAME）。文字里的 [Esc] 交给实体白键帽承担，
	# 因此这里先剥掉，_ready 随后捕获的 _resume_button_default_text 也是剥好的版本。
	main_page_title.text = main_page_title.text.strip_edges()
	_apply_prism_badge_to_label(main_page_title, 26, 6)
	_insert_prism_chevron_below(main_page, main_page_title, 0.5)
	# 左栏自上而下排，不垂直居中 —— 参考图的菜单占据左上区域，不是屏幕正中。
	main_page.alignment = BoxContainer.ALIGNMENT_BEGIN
	main_page.add_theme_constant_override("separation", 6)

	var info := get_node_or_null("Center/Panel/Margin/MainPage/Info") as Label
	if info != null:
		UIStyleFactory.apply_prism_label(info, "label", 2, 13)
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		info.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	# 五条行动行：左栏宽、左对齐大字、行尾折角，行与行之间由上方细线切开。
	var row_specs: Array = [
		[graphics_button, "ghost"],
		[controls_button, "ghost"],
		[training_range_button, "ghost"],
		[return_to_base_button, "muted"],
		[reset_game_save_button, "danger"],
	]
	for spec in row_specs:
		var row_button := spec[0] as Button
		if row_button == null:
			continue
		UIStyleFactory.apply_prism_row_button(row_button, str(spec[1]), 22, 5)
		row_button.custom_minimum_size = Vector2(PRISM_RAIL_WIDTH, 52)
		row_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	# 主行动 = 参考图底部那个四角括号选框（CONTINUE 位）：不填充，靠括号表达"当前选框"。
	# 文案左对齐、贴着括号左臂排，这是参考图 CONTINUE 的排印方式。
	resume_button.text = "继续行动"
	resume_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	resume_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	resume_button.custom_minimum_size = Vector2(PRISM_RAIL_WIDTH * 0.50, 74)
	UIStyleFactory.apply_prism_button(resume_button, "ghost", 0, 26, 6, "solid", 26.0, 2.0)
	_attach_prism_keycap(resume_button, "ESC")
	var resume_style := resume_button.get_theme_stylebox("normal")
	if resume_style is StyleBoxFlat:
		for state in ["normal", "hover", "pressed", "focus"]:
			var flat := (resume_button.get_theme_stylebox(state) as StyleBoxFlat)
			if flat == null:
				continue
			var clone := flat.duplicate() as StyleBoxFlat
			clone.content_margin_left = 34.0
			resume_button.add_theme_stylebox_override(state, clone)

	# 细线必须**从后往前**插：插入会挪动同容器内后续节点的索引。
	UIStyleFactory.attach_prism_row_rule(resume_button, 0.34, "ResumeButton", PRISM_RAIL_WIDTH)
	for i in range(row_specs.size() - 1, -1, -1):
		var row_button := row_specs[i][0] as Button
		if row_button == null:
			continue
		UIStyleFactory.attach_prism_row_rule(
			row_button, 0.20, str(row_button.name), PRISM_RAIL_WIDTH
		)

	for hint in [training_range_hint, return_to_base_hint, reset_game_save_hint]:
		if hint != null:
			UIStyleFactory.apply_prism_label(hint, "faint", 1, 12)
			hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			hint.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var performance_hint := get_node_or_null("Center/Panel/Margin/MainPage/PerformanceHint") as Label
	if performance_hint != null:
		UIStyleFactory.apply_prism_label(performance_hint, "faint", 1, 12)
		performance_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		performance_hint.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN


## 主页行错峰入场：悬挂式细线列表"自上而下逐条点亮"。
## 只动 alpha —— 整行 900+px 宽，缩放式入场会让行在水平方向抽动。
## 挂在"每次打开"而不是 _ready：首次构建时控件尺寸还是 0，第一帧没有意义。
func _stagger_main_page_rows() -> void:
	UIFX.prism_fade_stagger([
		graphics_button, controls_button, training_range_button,
		return_to_base_button, reset_game_save_button, resume_button,
	], 0.028, 0.14)


# ---------- 画面设置页 ----------

func _style_prism_graphics_page() -> void:
	var header := get_node_or_null("Center/Panel/Margin/GraphicsPage/Header") as HBoxContainer
	if header != null:
		var title := header.get_node_or_null("Title") as Label
		if title != null:
			title.text = "画面设置"
			_apply_prism_badge_to_label(title, 22, 4)
			# 徽章靠左，右侧接一条白色细延长线（参考图 NEW GAME 右侧那条线）
			title.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if header != null and header.get_node_or_null("PrismHeaderLine") == null:
		var line := UIStyleFactory.make_prism_rule(Color(1.0, 1.0, 1.0, 0.50), 1.0)
		line.name = "PrismHeaderLine"
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.custom_minimum_size = Vector2(60, 1)
		header.add_child(line)
		header.move_child(line, 1)
	if renderer_label != null:
		UIStyleFactory.apply_prism_label(renderer_label, "accent", 2, 13)
		renderer_label.add_theme_color_override("font_color", UIPalette.PRISM_ACCENT)
		renderer_label.custom_minimum_size.x = 190.0

	var page := graphics_page
	_insert_prism_chevron_below(page, header)
	var rule_node := page.get_node_or_null("Rule") as HSeparator
	if rule_node != null:
		rule_node.add_theme_stylebox_override("separator", _make_prism_separator_style(0.28))

	var preset_label := get_node_or_null("Center/Panel/Margin/GraphicsPage/PresetRow/PresetLabel") as Label
	if preset_label != null:
		UIStyleFactory.apply_prism_label(preset_label, "label", 1, 13)
	UIStyleFactory.apply_prism_button(high_defaults_button, "ghost", 2, 15, 2)
	high_defaults_button.custom_minimum_size = Vector2(210, 44)

	# 抗锯齿行：弱标签 + 方角箭头 + 大号近白当前值 + 右侧说明
	var aa_row := get_node_or_null("Center/Panel/Margin/GraphicsPage/AASection") as HBoxContainer
	var aa_label := aa_row.get_node_or_null("Label") as Label if aa_row != null else null
	if aa_label != null:
		UIStyleFactory.apply_prism_label(aa_label, "label", 2, 13)
		aa_label.custom_minimum_size = Vector2(190, 44)
	var aa_hint := aa_row.get_node_or_null("AAHint") as Label if aa_row != null else null
	if aa_hint != null:
		UIStyleFactory.apply_prism_label(aa_hint, "faint", 1, 12)
		aa_hint.custom_minimum_size = Vector2(210, 44)
	# 抗锯齿行占据整条通栏，可以承担 [◀] 值 [▶] 的参考图行式样。
	_install_prism_option_row(aa_row, aa_option)

	# 但 Scroll/Grid 里的两行是**半栏**（两列网格），塞进箭头会把网格最小宽度
	# 从 905 撑到 1236，直接顶穿 972 的面板内宽 —— 因此这两行只把字号收小、不加箭头。
	# 注意不能给说明文字开自动折行：这两行高度只有 58，折到第三行会溢出并压住下一行。
	for opt in [shadow_option, indirect_diffuse_option]:
		UIStyleFactory.apply_prism_option_button(opt, 17, 3)
		if opt != null:
			opt.custom_minimum_size = Vector2(maxf(opt.custom_minimum_size.x, 150.0), 44.0)
	for row_path in [
		"Center/Panel/Margin/GraphicsPage/Scroll/Grid/Shadows",
		"Center/Panel/Margin/GraphicsPage/Scroll/Grid/IndirectDiffuse",
	]:
		var row := get_node_or_null(row_path) as HBoxContainer
		if row == null:
			continue
		var caption := row.get_node_or_null("Label") as Label
		if caption != null:
			UIStyleFactory.apply_prism_label(caption, "label", 1, 13)
			caption.autowrap_mode = TextServer.AUTOWRAP_OFF
			caption.custom_minimum_size = Vector2(0, 0)
			caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# 网格两列都要能吸收余量，否则右列会在面板右侧留下一条空档。
	for key in _toggle_nodes.keys():
		var chk := _toggle_nodes[key] as CheckButton
		if chk != null:
			UIStyleFactory.apply_prism_check_button(chk, 15)
			chk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for row_path in [
		"Center/Panel/Margin/GraphicsPage/Scroll/Grid/Shadows",
		"Center/Panel/Margin/GraphicsPage/Scroll/Grid/IndirectDiffuse",
	]:
		var row := get_node_or_null(row_path) as Control
		if row != null:
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	if status_label != null:
		UIStyleFactory.apply_prism_label(status_label, "label", 1, 13)
	UIStyleFactory.apply_prism_button(back_button, "ghost", 2, 16, 3)
	back_button.text = "返回"
	back_button.custom_minimum_size = Vector2(210, 46)
	_attach_prism_keycap(back_button, "ESC")


func _make_prism_separator_style(alpha: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 1.0, 1.0, alpha)
	style.set_border_width_all(0)
	style.set_corner_radius_all(0)
	style.shadow_size = 0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	return style


# ---------- 操作设置页 ----------

func _style_prism_controls_page() -> void:
	var header := get_node_or_null("Center/Panel/Margin/ControlsPage/Header") as HBoxContainer
	if header != null:
		var title := header.get_node_or_null("Title") as Label
		if title != null:
			title.text = "操作设置"
			_apply_prism_badge_to_label(title, 22, 4)
			title.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		if header.get_node_or_null("PrismHeaderLine") == null:
			var line := UIStyleFactory.make_prism_rule(Color(1.0, 1.0, 1.0, 0.50), 1.0)
			line.name = "PrismHeaderLine"
			line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			line.custom_minimum_size = Vector2(60, 1)
			header.add_child(line)
			header.move_child(line, 1)
	if device_status_label != null:
		UIStyleFactory.apply_prism_label(device_status_label, "accent", 2, 13)

	var page := controls_page
	_insert_prism_chevron_below(page, header)
	var rule_node := page.get_node_or_null("Rule") as HSeparator
	if rule_node != null:
		rule_node.add_theme_stylebox_override("separator", _make_prism_separator_style(0.28))

	_install_prism_option_row(
		get_node_or_null("Center/Panel/Margin/ControlsPage/DeviceRow") as HBoxContainer,
		device_mode_option
	)
	var device_row := get_node_or_null("Center/Panel/Margin/ControlsPage/DeviceRow") as HBoxContainer
	if device_row != null:
		var caption := device_row.get_node_or_null("Label") as Label
		if caption != null:
			UIStyleFactory.apply_prism_label(caption, "label", 1, 13)

	# 三条摇杆参数：细白线轨道 + 方把手 + 右侧白线方角数值框
	for row_path in [
		"Center/Panel/Margin/ControlsPage/MoveDeadzoneRow",
		"Center/Panel/Margin/ControlsPage/AimDeadzoneRow",
		"Center/Panel/Margin/ControlsPage/AimSmoothingRow",
	]:
		var row := get_node_or_null(row_path) as HBoxContainer
		if row == null:
			continue
		var caption := row.get_node_or_null("Label") as Label
		if caption != null:
			UIStyleFactory.apply_prism_label(caption, "label", 1, 13)
	for slider in [move_deadzone_slider, aim_deadzone_slider, aim_smoothing_slider]:
		UIStyleFactory.apply_prism_slider(slider)
	var value_box := UIStyleFactory.make_prism_value_box_style()
	for value_label in [move_deadzone_value, aim_deadzone_value, aim_smoothing_value]:
		if value_label == null:
			continue
		value_label.add_theme_stylebox_override("normal", value_box)
		UIStyleFactory.apply_prism_label(value_label, "value", 2, 16)
		value_label.custom_minimum_size = Vector2(84, 34)

	for chk in [gamepad_enabled_toggle, left_stick_aim_toggle, aim_assist_toggle, vibration_toggle]:
		if chk != null:
			UIStyleFactory.apply_prism_check_button(chk, 15)

	var binding_hint := get_node_or_null("Center/Panel/Margin/ControlsPage/BindingHint") as Label
	if binding_hint != null:
		UIStyleFactory.apply_prism_label(binding_hint, "faint", 1, 12)
	if controls_status_label != null:
		UIStyleFactory.apply_prism_label(controls_status_label, "label", 1, 13)
	UIStyleFactory.apply_prism_button(controls_back_button, "ghost", 2, 16, 3)
	controls_back_button.text = "返回"
	controls_back_button.custom_minimum_size = Vector2(210, 46)
	_attach_prism_keycap(controls_back_button, "ESC")


# ---------- 复位存档二次确认弹窗 ----------

func _style_prism_reset_dialog() -> void:
	if reset_game_save_dialog == null:
		return
	# 这是 Window 系弹窗（`ConfirmationDialog`），外观由 `panel` + `embedded_border` +
	# 标题栏主题项共同绘制 —— 只覆盖 `panel` 压不住系统灰底与圆角标题栏，必须走整套 chrome。
	# 注意：本引擎版本下 `title_height` 不会改变内容框从窗口顶边下移的距离，
	# 标题因此稳定地浮在白线框正上方，形成"带标签的线框"。
	UIStyleFactory.apply_prism_window_chrome(reset_game_save_dialog, 18, 28, 16)
	var ok_btn := reset_game_save_dialog.get_ok_button()
	var cancel_btn := reset_game_save_dialog.get_cancel_button()
	if ok_btn != null:
		ok_btn.custom_minimum_size = Vector2(150, 42)
		UIStyleFactory.apply_prism_button(ok_btn, "danger", 2, 15, 2)
	if cancel_btn != null:
		cancel_btn.custom_minimum_size = Vector2(150, 42)
		UIStyleFactory.apply_prism_button(cancel_btn, "primary", 2, 15, 2)
		UIStyleFactory.attach_prism_keycap(cancel_btn, "ESC", 12, 14.0)


# ---------- 通用：把 OptionButton 变成"方角箭头选择行" ----------

## 在既有 HBox 行内就地插入 [◀] 与 [▶] 两个方角箭头钮，夹住 OptionButton，
## 并把 OptionButton 本身极简化（去底、去框、去自带箭头、大号近白字）。
## 全过程不移动、不新增、不替换任何既有节点的路径。
func _install_prism_option_row(row: HBoxContainer, opt: OptionButton) -> void:
	if row == null or opt == null:
		return
	UIStyleFactory.apply_prism_option_button(opt, 22, 3)
	if opt.custom_minimum_size.y < 46.0:
		opt.custom_minimum_size = Vector2(opt.custom_minimum_size.x, 46.0)
	if row.get_node_or_null("PrismPrev") == null:
		var prev := UIStyleFactory.make_prism_arrow_button("left", 46.0)
		prev.name = "PrismPrev"
		prev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(prev)
		row.move_child(prev, opt.get_index())
		var next := UIStyleFactory.make_prism_arrow_button("right", 46.0)
		next.name = "PrismNext"
		next.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(next)
		row.move_child(next, opt.get_index() + 1)
		UIStyleFactory.bind_prism_option_stepping(opt, prev, next)



func _setup_graphics_controls() -> void:
	_toggle_nodes = {
		"bloom": $Center/Panel/Margin/GraphicsPage/Scroll/Grid/Bloom,
		"ssao": $Center/Panel/Margin/GraphicsPage/Scroll/Grid/SSAO,
		"ssil": $Center/Panel/Margin/GraphicsPage/Scroll/Grid/SSIL,
		"ssr": $Center/Panel/Margin/GraphicsPage/Scroll/Grid/SSR,
		"volumetric_fog": $Center/Panel/Margin/GraphicsPage/Scroll/Grid/VolumetricFog,
		"distance_fog": $Center/Panel/Margin/GraphicsPage/Scroll/Grid/DistanceFog,
		"color_grading": $Center/Panel/Margin/GraphicsPage/Scroll/Grid/ColorGrading,
		"scene_particles": $Center/Panel/Margin/GraphicsPage/Scroll/Grid/SceneParticles,
	}
	for index in AA_LABELS.size():
		aa_option.add_item(AA_LABELS[index], index)
	aa_option.item_selected.connect(_on_aa_selected)
	for index in SHADOW_LABELS.size():
		shadow_option.add_item(SHADOW_LABELS[index], index)
	shadow_option.item_selected.connect(_on_shadow_quality_selected)
	for index in INDIRECT_DIFFUSE_LABELS.size():
		indirect_diffuse_option.add_item(INDIRECT_DIFFUSE_LABELS[index], index)
	indirect_diffuse_option.item_selected.connect(_on_indirect_diffuse_quality_selected)
	for key in _toggle_nodes.keys():
		(_toggle_nodes[key] as CheckButton).toggled.connect(_on_effect_toggled.bind(str(key)))
	if not GraphicsSettingsManager.settings_changed.is_connected(_on_graphics_settings_changed):
		GraphicsSettingsManager.settings_changed.connect(_on_graphics_settings_changed)
	_sync_graphics_controls()


func _show_graphics_page() -> void:
	_hide_sub_pages()
	main_page.visible = false
	graphics_page.visible = true
	UIFX.switch_page_fade(graphics_page)
	renderer_label.text = GraphicsSettingsManager.get_renderer_summary()
	_sync_graphics_controls()
	aa_option.grab_focus()


func _show_main_page() -> void:
	_hide_sub_pages()
	main_page.visible = true
	UIFX.switch_page_fade(main_page)
	_refresh_return_to_base_action()
	_refresh_training_range_action()
	if center.visible:
		graphics_button.grab_focus()
		_stagger_main_page_rows()
	if _entry_settings_context:
		_apply_entry_settings_overrides()


func _show_controls_page() -> void:
	_hide_sub_pages()
	main_page.visible = false
	controls_page.visible = true
	UIFX.switch_page_fade(controls_page)
	_sync_input_controls()
	_refresh_device_status()
	device_mode_option.grab_focus()



func _hide_sub_pages() -> void:
	graphics_page.visible = false
	controls_page.visible = false


## 页头状态行：只描述「现在是谁在操作」，不参与任何输入判定。
func _refresh_device_status() -> void:
	var device := InputDevice.get_active_device()
	var label := "键盘与鼠标"
	if device == InputDevice.DEVICE_GAMEPAD:
		var pad_name := InputDevice.get_active_gamepad_name()
		label = "手柄" if pad_name.is_empty() else "手柄 · %s" % pad_name
	elif device == InputDevice.DEVICE_TOUCH:
		label = "触屏"
	var suffix := "" if InputDevice.has_connected_gamepad() else "（未检测到手柄）"
	device_status_label.text = "当前输入：%s%s" % [label, suffix]
	device_status_label.modulate = (
		Color(0.45, 0.9, 0.68) if device == InputDevice.DEVICE_GAMEPAD else Color(0.58, 0.76, 0.84)
	)


func _setup_input_controls() -> void:
	for index in DEVICE_MODE_LABELS.size():
		device_mode_option.add_item(DEVICE_MODE_LABELS[index], index)
	device_mode_option.item_selected.connect(_on_device_mode_selected)
	gamepad_enabled_toggle.toggled.connect(_on_gamepad_enabled_toggled)
	left_stick_aim_toggle.toggled.connect(_on_left_stick_aim_toggled)
	aim_assist_toggle.toggled.connect(_on_aim_assist_toggled)
	vibration_toggle.toggled.connect(_on_vibration_toggled)
	move_deadzone_slider.value_changed.connect(
		_on_deadzone_changed.bind("gamepad_move_deadzone")
	)
	aim_deadzone_slider.value_changed.connect(
		_on_deadzone_changed.bind("gamepad_aim_deadzone")
	)
	aim_smoothing_slider.value_changed.connect(_on_aim_smoothing_changed)
	if not InputSettings.settings_changed.is_connected(_on_input_settings_changed):
		InputSettings.settings_changed.connect(_on_input_settings_changed)
	if not InputDevice.active_device_changed.is_connected(_on_active_device_changed):
		InputDevice.active_device_changed.connect(_on_active_device_changed)
	_sync_input_controls()


func _on_device_mode_selected(index: int) -> void:
	if _syncing_controls or index < 0 or index >= InputSettings.DEVICE_MODES.size():
		return
	var mode: String = str(InputSettings.DEVICE_MODES[index])
	InputSettings.set_value("device_mode", mode)
	if mode == InputSettings.DEVICE_MODE_GAMEPAD and not InputDevice.has_connected_gamepad():
		controls_status_label.text = "已锁定手柄，但当前未检测到手柄，暂时回落键鼠"
		controls_status_label.modulate = Color(1.0, 0.72, 0.42)
	else:
		controls_status_label.text = "操控方式已切换为%s · 设置已保存" % DEVICE_MODE_LABELS[index]
		controls_status_label.modulate = Color(0.45, 0.9, 0.68)
	_refresh_device_status()


func _on_gamepad_enabled_toggled(enabled: bool) -> void:
	if _syncing_controls:
		return
	InputSettings.set_value("gamepad_enabled", enabled)
	controls_status_label.text = "手柄操控已%s · 设置已保存" % ("启用" if enabled else "关闭")
	controls_status_label.modulate = Color(0.45, 0.9, 0.68)
	_refresh_device_status()


func _on_left_stick_aim_toggled(enabled: bool) -> void:
	if _syncing_controls:
		return
	InputSettings.set_value("gamepad_left_stick_aim", enabled)
	controls_status_label.text = "左摇杆同控朝向已%s · 设置已保存" % ("开启" if enabled else "关闭")
	controls_status_label.modulate = Color(0.45, 0.9, 0.68)


func _on_aim_assist_toggled(enabled: bool) -> void:
	if _syncing_controls:
		return
	InputSettings.set_value("gamepad_aim_assist", enabled)
	controls_status_label.text = "瞄准辅助已%s · 设置已保存" % ("开启" if enabled else "关闭")
	controls_status_label.modulate = Color(0.45, 0.9, 0.68)


func _on_vibration_toggled(enabled: bool) -> void:
	if _syncing_controls:
		return
	InputSettings.set_value("gamepad_vibration", enabled)
	if not enabled and GamepadInput != null:
		GamepadInput.stop_rumble()
	controls_status_label.text = "手柄震动已%s · 设置已保存" % ("开启" if enabled else "关闭")
	controls_status_label.modulate = Color(0.45, 0.9, 0.68)


func _on_deadzone_changed(value: float, key: String) -> void:
	if _syncing_controls:
		return
	InputSettings.set_value(key, value)
	var formatted := "%.2f" % value
	if key == "gamepad_move_deadzone":
		move_deadzone_value.text = formatted
	else:
		aim_deadzone_value.text = formatted
	controls_status_label.text = "摇杆死区已调整为 %s · 设置已保存" % formatted
	controls_status_label.modulate = Color(0.45, 0.9, 0.68)


func _on_aim_smoothing_changed(value: float) -> void:
	if _syncing_controls:
		return
	InputSettings.set_value("gamepad_aim_smoothing", value)
	aim_smoothing_value.text = "%.2f" % value
	controls_status_label.text = "瞄准平滑已调整为 %.2f · 设置已保存" % value
	controls_status_label.modulate = Color(0.45, 0.9, 0.68)


func _on_input_settings_changed(_settings: Dictionary) -> void:
	_sync_input_controls()
	_refresh_device_status()


func _on_active_device_changed(_device: String) -> void:
	_refresh_device_status()


func _sync_input_controls() -> void:
	_syncing_controls = true
	var settings := InputSettings.get_settings_snapshot()
	var mode_index := InputSettings.DEVICE_MODES.find(
		str(settings.get("device_mode", InputSettings.DEVICE_MODE_AUTO))
	)
	device_mode_option.select(maxi(0, mode_index))
	gamepad_enabled_toggle.button_pressed = bool(settings.get("gamepad_enabled", true))
	left_stick_aim_toggle.button_pressed = bool(settings.get("gamepad_left_stick_aim", false))
	aim_assist_toggle.button_pressed = bool(settings.get("gamepad_aim_assist", true))
	vibration_toggle.button_pressed = bool(settings.get("gamepad_vibration", true))
	var move_deadzone := float(settings.get("gamepad_move_deadzone", 0.20))
	var aim_deadzone := float(settings.get("gamepad_aim_deadzone", 0.12))
	var smoothing := float(settings.get("gamepad_aim_smoothing", 0.15))
	move_deadzone_slider.value = move_deadzone
	aim_deadzone_slider.value = aim_deadzone
	aim_smoothing_slider.value = smoothing
	move_deadzone_value.text = "%.2f" % move_deadzone
	aim_deadzone_value.text = "%.2f" % aim_deadzone
	aim_smoothing_value.text = "%.2f" % smoothing
	_syncing_controls = false


func get_return_to_base_availability() -> Dictionary:
	return ReturnAction.get_availability(_get_game_root())


func _request_return_to_base() -> void:
	if _return_to_base_request_in_progress:
		return
	_return_to_base_request_in_progress = true
	return_to_base_button.disabled = true
	return_to_base_requested.emit()
	var result := ReturnAction.request(_get_game_root())
	if not is_inside_tree():
		return
	return_to_base_resolved.emit(result)
	if bool(result.get("success", false)):
		_return_to_base_request_in_progress = false
		resume_game()
		return
	_return_to_base_request_in_progress = false
	return_to_base_button.disabled = false
	return_to_base_hint.text = str(result.get("reason", "返回基地中心失败"))
	return_to_base_hint.modulate = Color(1.0, 0.48, 0.34)


func _request_game_save_reset() -> void:
	if _reset_in_progress:
		return
	game_save_reset_requested.emit()
	reset_game_save_dialog.dialog_text = (
		"这会清除基地、蓝图、物品、角色外观、世界时间以及当前行动进度。\n"
		+ "画面设置会保留。复位后将从全新游戏重新开始。"
	)
	reset_game_save_dialog.popup_centered(Vector2i(590, 240))


func _confirm_game_save_reset() -> void:
	if _reset_in_progress:
		return
	_reset_in_progress = true
	reset_game_save_button.disabled = true
	var result: Dictionary = (
		BaseManager.reset_game_save()
		if BaseManager != null
		else {"success": false, "reason": "存档服务不可用"}
	)
	game_save_reset_resolved.emit((result as Dictionary).duplicate(true))
	if not bool((result as Dictionary).get("success", false)):
		_reset_in_progress = false
		reset_game_save_button.disabled = false
		reset_game_save_hint.text = str((result as Dictionary).get("reason", "游戏存档复位失败"))
		reset_game_save_hint.modulate = Color(1.0, 0.40, 0.30)
		return
	reset_game_save_hint.text = "存档已复位，正在重新开始……"
	reset_game_save_hint.modulate = Color(0.44, 0.94, 0.72)
	_reset_runtime_singletons_for_new_profile()
	_main_entry_request_id = GameEntryFlow.request_main_entry(GameEntryFlow.REASON_NEW_GAME_RESET)
	call_deferred("_restart_from_main_scene")


func _reset_runtime_singletons_for_new_profile() -> void:
	if GameTimeManager != null:
		GameTimeManager.set_elapsed_game_seconds(0.0, false)
	if LevelSelect != null:
		LevelSelect.reset()
	if FateCardGameBridge != null:
		FateCardGameBridge.reset_run_state()
	if GameplaySpatialRegistry3D != null:
		GameplaySpatialRegistry3D.clear_runtime_records()
	if Global != null:
		Global.start_game()


func _restart_from_main_scene() -> void:
	var main_scene_path := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	var error: Error = (
		get_tree().change_scene_to_file(main_scene_path)
		if not main_scene_path.is_empty()
		else get_tree().reload_current_scene()
	)
	if error == OK:
		return
	if _main_entry_request_id > 0:
		GameEntryFlow.cancel_request(_main_entry_request_id)
		_main_entry_request_id = -1
	_reset_in_progress = false
	reset_game_save_button.disabled = false
	reset_game_save_hint.text = "存档已复位，但主场景重新载入失败：%s" % error_string(error)
	reset_game_save_hint.modulate = Color(1.0, 0.40, 0.30)


func _refresh_return_to_base_action() -> void:
	if return_to_base_button == null or return_to_base_hint == null:
		return
	var availability := get_return_to_base_availability()
	var available := bool(availability.get("available", false))
	return_to_base_button.disabled = not available
	return_to_base_button.text = "返回基地中心" if available else "返回基地中心（不可用）"
	return_to_base_hint.text = str(availability.get("reason", ""))
	return_to_base_hint.modulate = Color(0.48, 0.84, 0.92) if available else Color(0.70, 0.58, 0.48)


func _get_game_root() -> Node:
	var hud := get_parent()
	return hud.get_parent() if hud != null else null


## 训练靶场入口只在基地开放。
##
## 「在基地」的权威口径是**场景根自己的 `is_player_inside_facility()`**，
## 不能按类名判断：玩家的基地是 `TowerDescent3D`（主场景，99F 基地营地，
## 基地安全区以建筑壳体为准），而 `BaseWorld3D` 只是历史「兼容基地」——
## 照类名判会让按钮在真正的基地里永远显示"仅基地可用"。
##
## 靶场内部复用同一个暂停面板，因此这条判据同时负责防套娃：
## 在靶场里按 Esc 不该看到"进入训练靶场"。
func is_training_range_available() -> bool:
	var root := _get_game_root()
	if root == null:
		return false
	# 兼容基地（历史场景）整场都是基地；保留它可用，避免回退路径被一起关掉。
	if root is BaseWorld3D:
		return true
	if root.has_method("is_player_inside_facility"):
		return bool(root.call("is_player_inside_facility"))
	return false


## 当前场景文件路径；用于把来源场景交给靶场，退出时原路返回。
func _current_scene_path() -> String:
	var scene := get_tree().current_scene
	return scene.scene_file_path if scene != null else ""


func _refresh_training_range_action() -> void:
	if training_range_button == null or training_range_hint == null:
		return
	var available := is_training_range_available()
	training_range_button.disabled = not available
	training_range_button.text = "进入训练靶场" if available else "进入训练靶场（仅基地可用）"
	training_range_hint.text = (
		"靶场内可自由取用全部枪械、刷怪实战与装配任意命运卡；离开后装备与物品原样还原"
		if available
		else "仅 99F 基地内可用；进入塔楼行动或战局后不可用"
	)
	training_range_hint.modulate = Color(0.44, 0.78, 0.74) if available else Color(0.70, 0.58, 0.48)


func _request_training_range() -> void:
	if not is_training_range_available():
		training_range_hint.text = "只能在基地里进入训练靶场。"
		training_range_hint.modulate = Color(1.0, 0.48, 0.34)
		return
	if not ResourceLoader.exists(TRAINING_RANGE_SCENE_PATH, "PackedScene"):
		training_range_hint.text = "训练靶场场景缺失。"
		training_range_hint.modulate = Color(1.0, 0.48, 0.34)
		return
	# 登记来源场景：靶场退出时原路返回。绝不能靠 BaseWorld3D 兜底 ——
	# 那是历史「兼容基地」，玩家不是从那出发的。
	TrainingRange3D.set_origin_scene_path(_current_scene_path())
	# 必须先解除暂停：get_tree().paused 是全局的，会原样带进新场景，
	# 靶场的 _ready 与物理帧就都不跑了 —— 表现为"点进去直接卡死"。
	set_paused(false)
	var change_error := get_tree().change_scene_to_file(TRAINING_RANGE_SCENE_PATH)
	if change_error != OK:
		training_range_hint.text = "进入训练靶场失败：%s" % error_string(change_error)
		training_range_hint.modulate = Color(1.0, 0.40, 0.30)


func _restore_high_defaults() -> void:
	GraphicsSettingsManager.apply_high_quality_defaults()
	status_label.text = "高档默认已恢复 · 设置已保存"


func _on_aa_selected(index: int) -> void:
	if _syncing_controls or index < 0 or index >= AA_MODES.size():
		return
	GraphicsSettingsManager.set_value("anti_aliasing", AA_MODES[index])
	status_label.text = "抗锯齿已切换为 %s · 设置已保存" % AA_LABELS[index]


func _on_effect_toggled(enabled: bool, key: String) -> void:
	if _syncing_controls:
		return
	GraphicsSettingsManager.set_value(key, enabled)
	status_label.text = "%s · 设置已保存" % ("效果已开启" if enabled else "效果已关闭")


func _on_shadow_quality_selected(index: int) -> void:
	if _syncing_controls or index < 0 or index >= SHADOW_MODES.size():
		return
	GraphicsSettingsManager.set_value("shadow_quality", SHADOW_MODES[index])
	status_label.text = "动态阴影已切换为%s · 投影功能保持完整" % SHADOW_LABELS[index]


func _on_indirect_diffuse_quality_selected(index: int) -> void:
	if _syncing_controls or index < 0 or index >= INDIRECT_DIFFUSE_MODES.size():
		return
	GraphicsSettingsManager.set_value(
		"indirect_diffuse_quality", INDIRECT_DIFFUSE_MODES[index]
	)
	status_label.text = "太阳间接漫反射已切换为%s · 功能保持开启" % INDIRECT_DIFFUSE_LABELS[index]


func _on_graphics_settings_changed(_settings: Dictionary) -> void:
	_sync_graphics_controls()


func _sync_graphics_controls() -> void:
	_syncing_controls = true
	var settings := GraphicsSettingsManager.get_settings_snapshot()
	var aa_index := AA_MODES.find(str(settings.get("anti_aliasing", "taa")))
	aa_option.select(maxi(0, aa_index))
	var shadow_index := SHADOW_MODES.find(str(settings.get("shadow_quality", "high")))
	shadow_option.select(maxi(0, shadow_index))
	var indirect_index := INDIRECT_DIFFUSE_MODES.find(
		str(settings.get("indirect_diffuse_quality", "high"))
	)
	indirect_diffuse_option.select(maxi(0, indirect_index))
	for key in _toggle_nodes.keys():
		(_toggle_nodes[key] as CheckButton).button_pressed = bool(settings.get(key, true))
	_syncing_controls = false
