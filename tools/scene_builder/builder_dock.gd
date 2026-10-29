@tool
extends VBoxContainer

signal component_selected(row: Dictionary)
signal mode_changed(index: int)
signal settings_changed
signal command_requested(command: String)
signal list_refreshed

const PREVIEW := preload("res://tools/scene_builder/asset_preview.gd")
const COLORS := preload("res://tools/scene_builder/workbench_theme.gd")
const UI_REVISION := "r6"
const UI_BUILD := "r6-runtime-20261029-1.2.0"

var rows: Array[Dictionary] = []
var visible_rows: Array[Dictionary] = []
var favorites: Array = []
var selected_row: Dictionary = {}
var search: LineEdit
var group_filter: OptionButton
var type_filter: OptionButton
var suite_shelf: ItemList
var suite_rows: Array[Dictionary] = []
var library_tabs: TabContainer
var preview: PREVIEW
var snap_enabled: CheckBox
var _placeholder: Texture2D
var _failed_placeholder: Texture2D
var placement_hint: Label
var result_count: Label
var _search_timer: Timer
var favorites_only: CheckBox
var shelf: ItemList
var selection_info: Label
var mode: OptionButton
var grid: SpinBox
var elevation: SpinBox
var yaw: SpinBox
var brush_size: SpinBox
var cell_centers: CheckBox
var clip_room: CheckBox
var protect_ports: CheckBox
var replace_tiles: CheckBox
var surface_snap: CheckBox
var show_reference: CheckBox
var whitebox_choice: OptionButton
var status: Label
var room_info: Label
var reference_info: Label
var reference_opacity: SpinBox
var light_energy: SpinBox
var light_range: SpinBox
var light_shadows: CheckBox
var _whiteboxes: Array[Dictionary] = []
var _body: VBoxContainer
var _background: StyleBoxFlat
var mode_grid: GridContainer
var mode_buttons: Array[Button] = []
var library_area: VBoxContainer
var library_split: VSplitContainer
var options_panel: TabContainer
var open_button: Button
var new_button: Button
var save_button: Button
var progress_bar: ProgressBar
var retry_button: Button
var cancel_button: Button
var thumbnail_info: Label
var _busy := false
var _task_text := ""
var _task_started := 0


func _init() -> void:
	name = "场景工坊"
	set_meta("workbench_ui_build", UI_BUILD)
	custom_minimum_size.x = 340
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	theme = COLORS.build()
	_background = COLORS.box(Color("111d26"), Color("365260"), 8, 0)
	resized.connect(queue_redraw)
	var frame := MarginContainer.new()
	frame.name = "Frame"
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		frame.add_theme_constant_override(side, 8)
	add_child(frame)
	_body = VBoxContainer.new()
	_body.name = "WorkbenchR5"
	frame.add_child(_body)
	var heading := HBoxContainer.new()
	_body.add_child(heading)
	var title := _label("场景工坊", heading)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_font_size_override("font_size", 16)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var revision := _label(UI_REVISION, heading)
	revision.autowrap_mode = TextServer.AUTOWRAP_OFF
	revision.custom_minimum_size.x = 22
	revision.add_theme_color_override("font_color", COLORS.ACCENT)
	open_button = _button(heading, "打开", "open_scene")
	open_button.tooltip_text = "打开已有场景 · 也可浏览白盒模板"
	open_button.add_theme_stylebox_override("normal", COLORS.box(Color("245e5b"), COLORS.ACCENT.darkened(0.3)))
	new_button = _button(heading, "新建", "browse_whiteboxes")
	new_button.tooltip_text = "从白盒模板新建美术场景"
	save_button = _button(heading, "保存", "save")
	save_button.tooltip_text = "保存当前场景 · Ctrl+S"
	var more := MenuButton.new()
	more.text = "···"
	more.tooltip_text = "场景与工作台操作"
	heading.add_child(more)
	var menu := more.get_popup()
	var commands := ["open_scene_file", "save_variant", "reload_catalog", "rebuild_workspace", "help"]
	for label in ["从文件打开…", "另存为…", "刷新组件库", "重新载入工作台", "操作提示"]:
		menu.add_item(label)
	menu.id_pressed.connect(func(index): command_requested.emit(commands[index]))
	room_info = _label("先打开场景，再选择组件拼装", _body)
	room_info.autowrap_mode = TextServer.AUTOWRAP_OFF
	room_info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	room_info.add_theme_color_override("font_color", COLORS.MUTED)
	# Keep the public mode value for command/test consumers; users operate the buttons.
	mode = OptionButton.new()
	mode.visible = false
	_body.add_child(mode)
	mode_grid = GridContainer.new()
	mode_grid.columns = 4
	_body.add_child(mode_grid)
	var mode_group := ButtonGroup.new()
	var labels := ["选择", "放置", "笔刷", "矩形", "直线", "擦除", "点光", "聚光"]
	var tips := ["原生选择与移动 · Esc", "单件放置", "按住左键连续刷组件", "点击两角矩形铺放", "点击两端直线铺放", "仅擦除工具登记的组件", "放置点光源", "放置聚光灯"]
	for i in range(labels.size()):
		mode.add_item(labels[i])
		var button := Button.new()
		button.text = labels[i]
		button.tooltip_text = tips[i]
		button.toggle_mode = true
		button.button_group = mode_group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mode_grid.add_child(button)
		mode_buttons.append(button)
		button.pressed.connect(set_mode.bind(i))
	mode_buttons[0].button_pressed = true
	resized.connect(_fit_modes)
	library_area = VBoxContainer.new()
	library_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(library_area)
	var search_row := HBoxContainer.new()
	library_area.add_child(search_row)
	search = LineEdit.new()
	search.placeholder_text = "搜索组件 / 编号 / 用途"
	search.clear_button_enabled = true
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_row.add_child(search)
	favorites_only = CheckBox.new()
	favorites_only.text = "★"
	favorites_only.tooltip_text = "只显示收藏"
	search_row.add_child(favorites_only)
	favorites_only.toggled.connect(func(_value): refresh_list())
	_search_timer = Timer.new()
	_search_timer.wait_time = 0.15
	_search_timer.one_shot = true
	add_child(_search_timer)
	_search_timer.timeout.connect(refresh_list)
	search.text_changed.connect(func(_value): _search_timer.start())
	var filters := HBoxContainer.new()
	library_area.add_child(filters)
	group_filter = OptionButton.new()
	group_filter.fit_to_longest_item = false
	group_filter.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	group_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group_filter.size_flags_stretch_ratio = 1.5
	filters.add_child(group_filter)
	group_filter.item_selected.connect(func(_value): _refresh_types(); refresh_list())
	type_filter = OptionButton.new()
	type_filter.fit_to_longest_item = false
	type_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filters.add_child(type_filter)
	type_filter.item_selected.connect(func(_value): refresh_list())
	var count_row := HBoxContainer.new()
	library_area.add_child(count_row)
	result_count = _label("", count_row)
	result_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_count.add_theme_color_override("font_color", COLORS.MUTED)
	thumbnail_info = _label("", count_row)
	thumbnail_info.add_theme_color_override("font_color", COLORS.MUTED)
	var preview_toggle := CheckButton.new()
	preview_toggle.text = "3D"
	preview_toggle.button_pressed = true
	preview_toggle.tooltip_text = "显示 / 收起3D预览"
	count_row.add_child(preview_toggle)
	library_split = VSplitContainer.new()
	library_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	library_split.split_offset = 35
	library_area.add_child(library_split)
	library_tabs = TabContainer.new()
	library_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	library_split.add_child(library_tabs)
	library_tabs.tab_changed.connect(func(_index): list_refreshed.emit())
	shelf = _shelf("组件")
	library_tabs.add_child(shelf)
	shelf.item_selected.connect(_select_item)
	shelf.item_activated.connect(func(_index): set_mode(1))
	suite_shelf = _shelf("套件")
	library_tabs.add_child(suite_shelf)
	suite_shelf.item_selected.connect(_select_suite)
	preview = PREVIEW.new()
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.surface.custom_minimum_size.y = 170
	library_split.add_child(preview)
	preview_toggle.toggled.connect(func(enabled): preview.visible = enabled)
	var component_actions := HBoxContainer.new()
	_body.add_child(component_actions)
	selection_info = _label("选择组件后，点击3D视图放置", component_actions)
	selection_info.autowrap_mode = TextServer.AUTOWRAP_OFF
	selection_info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	selection_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(component_actions, "☆", "favorite").tooltip_text = "收藏 / 取消收藏当前组件"
	_button(component_actions, "↶", "rotate_left").tooltip_text = "逆时针旋转90° · Q"
	_button(component_actions, "↷", "rotate_right").tooltip_text = "顺时针旋转90° · E"
	snap_enabled = _check(component_actions, "吸附", false)
	snap_enabled.tooltip_text = "关闭时自由放置；开启后按间距吸附"
	var options_button := Button.new()
	options_button.text = "选项"
	options_button.toggle_mode = true
	options_button.tooltip_text = "放置参数 / 白盒参考 / 灯光"
	component_actions.add_child(options_button)
	_build_options()
	options_button.toggled.connect(func(expanded): options_panel.visible = expanded)
	snap_enabled.toggled.connect(func(enabled): cell_centers.disabled = not enabled; _update_placement_hint())
	var feedback := HBoxContainer.new()
	_body.add_child(feedback)
	status = _label("就绪 · 先打开场景", feedback)
	status.autowrap_mode = TextServer.AUTOWRAP_OFF
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.add_theme_color_override("font_color", COLORS.ACCENT)
	retry_button = _button(feedback, "重试", "retry_task")
	retry_button.visible = false
	cancel_button = _button(feedback, "取消", "cancel_task")
	cancel_button.visible = false
	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size.y = 4
	progress_bar.show_percentage = false
	progress_bar.editor_preview_indeterminate = true
	progress_bar.visible = false
	_body.add_child(progress_bar)
	set_process(true)

func _draw() -> void:
	if _background != null:
		draw_style_box(_background, Rect2(Vector2.ZERO, size))

func _fit_modes() -> void:
	mode_grid.columns = 8 if size.x >= 520 else 4
	if is_instance_valid(preview):
		preview.surface.custom_minimum_size.y = 140 if size.y < 780 else 170
	if is_instance_valid(shelf):
		shelf.custom_minimum_size.y = 150 if size.y < 780 else 160

func _shelf(title: String) -> ItemList:
	var list := ItemList.new()
	list.name = title
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.custom_minimum_size.y = 150
	list.max_columns = 0
	list.same_column_width = true
	list.fixed_column_width = 124
	list.fixed_icon_size = Vector2i(100, 100)
	list.icon_mode = ItemList.ICON_MODE_TOP
	list.max_text_lines = 2
	return list

func _build_options() -> void:
	options_panel = TabContainer.new()
	options_panel.visible = false
	_body.add_child(options_panel)
	var placement := VBoxContainer.new()
	placement.name = "放置"
	options_panel.add_child(placement)
	var form := GridContainer.new()
	form.columns = 4
	placement.add_child(form)
	grid = _number(form, "间距 m", 0.1, 20, 0.1, 5)
	elevation = _number(form, "标高 m", -100, 100, 0.01, 0.08)
	yaw = _number(form, "角度 °", -360, 360, 15, 0)
	brush_size = _number(form, "笔刷", 1, 9, 2, 1)
	cell_centers = _check(placement, "地砖格心 / 墙边", true)
	cell_centers.disabled = true
	var flags := HBoxContainer.new()
	placement.add_child(flags)
	clip_room = _check(flags, "房内裁切", true)
	protect_ports = _check(flags, "保护门口", true)
	replace_tiles = _check(placement, "同格替换地砖", true)
	surface_snap = _check(placement, "贴合碰撞表面", false)
	placement_hint = _label("自由放置 · 鼠标落点不取整", placement)
	grid.value_changed.connect(func(_value): _update_placement_hint())
	surface_snap.toggled.connect(func(_value): _update_placement_hint())
	var tools := HBoxContainer.new()
	placement.add_child(tools)
	_button(tools, "铺满地面", "fill_floor")
	_button(tools, "检查布局", "validate")
	var reference := VBoxContainer.new()
	reference.name = "参考"
	options_panel.add_child(reference)
	reference_info = _label("白盒参考：等待打开场景", reference)
	show_reference = _check(reference, "显示白盒参考", true)
	var opacity := GridContainer.new()
	opacity.columns = 2
	reference.add_child(opacity)
	reference_opacity = _number(opacity, "透明度", 0.05, 0.65, 0.05, 0.3)
	var reference_actions := HBoxContainer.new()
	reference.add_child(reference_actions)
	_button(reference_actions, "关联 / 更换", "bind_whitebox")
	_button(reference_actions, "重载", "reload_reference")
	var lights := VBoxContainer.new()
	lights.name = "灯光"
	options_panel.add_child(lights)
	var light_form := GridContainer.new()
	light_form.columns = 4
	lights.add_child(light_form)
	light_energy = _number(light_form, "能量", 0, 32, 0.1, 2)
	light_range = _number(light_form, "范围 m", 0.1, 100, 0.5, 15)
	light_shadows = _check(lights, "阴影", true)
	_label("顶部点光 / 聚光按钮放置，原生工具移动，检查器改颜色。", lights)
	# Backward compatible query surface; creation now lives in the top scene toolbar.
	whitebox_choice = OptionButton.new()
	whitebox_choice.visible = false
	_body.add_child(whitebox_choice)

func begin_task(text: String, cancellable: bool = true) -> void:
	_busy = true
	_task_text = text
	_task_started = Time.get_ticks_msec()
	progress_bar.visible = true
	progress_bar.indeterminate = true
	retry_button.visible = false
	cancel_button.visible = cancellable
	status.text = text
	status.tooltip_text = text
	status.add_theme_color_override("font_color", COLORS.ACCENT)

func task_progress(text: String, ratio: float = -1.0) -> void:
	_task_text = text
	progress_bar.indeterminate = ratio < 0
	if ratio >= 0:
		progress_bar.value = clampf(ratio * 100, 0, 100)

func finish_task(text: String, failed: bool = false, retryable: bool = false) -> void:
	_busy = false
	progress_bar.visible = false
	cancel_button.visible = false
	retry_button.visible = failed and retryable
	message(text, failed)

func _process(_delta: float) -> void:
	if _busy:
		var elapsed := (Time.get_ticks_msec() - _task_started) / 1000.0
		status.text = "%s · %.0fs" % [_task_text, elapsed]

func set_scene_available(available: bool) -> void:
	save_button.disabled = not available
	for button in mode_buttons:
		button.disabled = not available

func _label(text: String, parent: Node = null) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	(parent if parent != null else _body).add_child(label)
	return label

func _button(parent: Node, text: String, command: String) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	parent.add_child(button)
	button.pressed.connect(func(): command_requested.emit(command))
	return button

func _number(parent: Node, text: String, minimum: float, maximum: float, step_value: float, value: float) -> SpinBox:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 48
	parent.add_child(label)
	return _compact_number(parent, minimum, maximum, step_value, value)

func _compact_number(parent: Node, minimum: float, maximum: float, step_value: float, value: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step_value
	spin.value = value
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(spin)
	spin.value_changed.connect(func(_v): settings_changed.emit())
	return spin

func _check(parent: Node, text: String, initial: bool) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	check.button_pressed = initial
	parent.add_child(check)
	check.toggled.connect(func(_v): settings_changed.emit())
	return check

func set_catalog(value: Array[Dictionary], favorite_ids: Array) -> void:
	rows = value
	favorites = favorite_ids.duplicate()
	group_filter.clear()
	group_filter.add_item("全部套件 · %d 件" % rows.size())
	var groups: Array[String] = []
	for row in rows:
		if not str(row["group"]) in groups:
			groups.append(str(row["group"]))
	groups.sort()
	for group_name in groups:
		group_filter.add_item(group_name)
	_refresh_types()
	suite_shelf.clear()
	suite_rows.clear()
	for group_name in groups:
		for row in rows:
			if row["group"] == group_name:
				suite_rows.append(row)
				var index := suite_shelf.add_item(group_name, placeholder())
				suite_shelf.set_item_tooltip(index, group_name + " · 代表组件缩略图，点击查看套件")
				break
	refresh_list()

func set_whiteboxes(value: Array[Dictionary]) -> void:
	_whiteboxes = value
	whitebox_choice.clear()
	for row in value:
		whitebox_choice.add_item(str(row["label"]))
	for i in range(value.size()):
		if str(value[i].get("template_id", "")) == "std_25x25":
			whitebox_choice.select(i)

func selected_whitebox() -> String:
	return str(_whiteboxes[whitebox_choice.selected]["path"]) if whitebox_choice.selected >= 0 else ""

func refresh_list() -> void:
	shelf.clear()
	visible_rows.clear()
	var query := search.text.strip_edges().to_lower()
	for row in rows:
		if group_filter.selected > 0 and str(row["group"]) != group_filter.get_item_text(group_filter.selected):
			continue
		if type_filter.selected > 0 and str(row["type_tag"]) != type_filter.get_item_text(type_filter.selected):
			continue
		if favorites_only.button_pressed and not row["component_id"] in favorites:
			continue
		var searchable := "%s %s %s %s" % [row["component_id"], str(row.get("label", "")) + " " + str(row.get("category", "")) + " " + str(row.get("type_tag", "")) + " " + str(row.get("group", "")) + " " + str(row.get("aliases", [])), row.get("slug", ""), row.get("note", "")]
		if not query.is_empty() and not searchable.to_lower().contains(query):
			continue
		visible_rows.append(row)
		var label := str(row["label"])
		if row["component_id"] in favorites:
			label = "★ " + label
		var index := shelf.add_item(label, placeholder())
		shelf.set_item_tooltip(index, "%s\n%s / %s\n%s\n%s" % [row.get("category", row["label"]), row["group"], row["type_tag"], row["component_id"], row["prefab_path"]])
		if row.get("component_id") == selected_row.get("component_id", ""):
			shelf.select(index)
	result_count.text = "%d / %d 件组件" % [visible_rows.size(), rows.size()]
	if visible_rows.is_empty():
		result_count.text += " · 换个标签或清空搜索"
	list_refreshed.emit()

func _select_item(index: int) -> void:
	selected_row = visible_rows[index]
	selection_info.text = "%s · %s" % [selected_row["label"], selected_row.get("type_tag", "")]
	preview.set_pending(selected_row)
	component_selected.emit(selected_row)

func set_mode(index: int) -> void:
	mode.select(index)
	for i in range(mode_buttons.size()):
		mode_buttons[i].set_pressed_no_signal(i == index)
	mode_changed.emit(index)

func message(text: String, error: bool = false) -> void:
	if _busy and not error:
		return
	status.text = text
	status.tooltip_text = text
	status.add_theme_color_override("font_color", Color(1, 0.65, 0.45) if error else Color(0.5, 0.82, 0.73))

func _refresh_types() -> void:
	var previous := type_filter.get_item_text(type_filter.selected) if type_filter.selected > 0 else ""
	type_filter.clear()
	type_filter.add_item("全部类型")
	var types: Array[String] = []
	for row in rows:
		if group_filter.selected > 0 and row["group"] != group_filter.get_item_text(group_filter.selected):
			continue
		if not str(row["type_tag"]) in types:
			types.append(str(row["type_tag"]))
	types.sort()
	for tag in types:
		type_filter.add_item(tag)
		if tag == previous:
			type_filter.select(type_filter.item_count - 1)

func _select_suite(index: int) -> void:
	var group_name := str(suite_rows[index]["group"])
	for i in range(1, group_filter.item_count):
		if group_filter.get_item_text(i) == group_name:
			group_filter.select(i)
			break
	_refresh_types()
	type_filter.select(0)
	search.text = ""
	refresh_list()
	library_tabs.current_tab = 0

func placeholder() -> Texture2D:
	if _placeholder == null:
		var picture := Image.create(104, 104, false, Image.FORMAT_RGBA8)
		picture.fill(Color(0.15, 0.18, 0.21))
		for x in range(24, 80):
			for y in range(24, 80):
				if x < 28 or x > 75 or y < 28 or y > 75 or absi(x - y) < 2:
					picture.set_pixel(x, y, Color(0.4, 0.55, 0.6))
		_placeholder = ImageTexture.create_from_image(picture)
	return _placeholder

func apply_thumbnail(path: String, texture: Texture2D) -> void:
	for i in range(visible_rows.size()):
		if visible_rows[i]["prefab_path"] == path:
			shelf.set_item_icon(i, texture)
	for i in range(suite_rows.size()):
		if suite_rows[i]["prefab_path"] == path:
			suite_shelf.set_item_icon(i, texture)

func mark_thumbnail_failed(path: String) -> void:
	if _failed_placeholder == null:
		var picture := placeholder().get_image()
		for i in range(28, 76):
			for offset in range(-2, 3):
				picture.set_pixel(i, i + offset, Color(1, 0.45, 0.3))
				picture.set_pixel(i, 103 - i + offset, Color(1, 0.45, 0.3))
		_failed_placeholder = ImageTexture.create_from_image(picture)
	apply_thumbnail(path, _failed_placeholder)
	for i in range(visible_rows.size()):
		if visible_rows[i]["prefab_path"] == path:
			shelf.set_item_tooltip(i, "缩略图生成失败，可选中检查3D预览或刷新目录。\n" + path)

func _update_placement_hint() -> void:
	if placement_hint == null:
		return
	placement_hint.text = "网格吸附 · %.2fm" % grid.value if snap_enabled.button_pressed else "自由放置 · 鼠标落点不取整"
	if surface_snap != null and surface_snap.button_pressed:
		placement_hint.text += " · 贴表面"
