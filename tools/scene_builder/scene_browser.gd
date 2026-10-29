@tool
extends AcceptDialog

signal scene_requested(path: String)
signal file_requested
signal whitebox_requested(path: String)
signal runtime_requested(row: Dictionary)
signal runtime_read_requested(scene: String, seed: int)
signal runtime_cancel_requested
const INDEX := preload("res://tools/scene_builder/scene_index.gd")
const COLORS := preload("res://tools/scene_builder/workbench_theme.gd")
var search: LineEdit
var show_whiteboxes: CheckBox
var tree: Tree
var detail: Label
var rows: Array[Dictionary] = []
var extra_paths: Array = []
var displayed_count := 0
var purpose := "open"
var scope: OptionButton
var progress_bar: ProgressBar
var scanning := false
var _scan_thread: Thread
var _scan_started := 0
var _index_valid := false
var _rescan := false
var runtime_rows: Array = []
var runtime_view := false
var runtime_busy := false
var _source_tabs: HBoxContainer
var _runtime_bar: HBoxContainer
var _runtime_button: Button
var _files_button: Button
var _scene_choice: OptionButton
var _seed: SpinBox
var _read: Button
var _cancel_read: Button

func _init() -> void:
	title = "打开场景"
	size = Vector2i(1000, 680)
	theme = COLORS.build()
	get_ok_button().text = "打开选中场景"
	confirmed.connect(_open_selected)
	var body := VBoxContainer.new()
	add_child(body)
	_source_tabs = HBoxContainer.new()
	body.add_child(_source_tabs)
	_runtime_button = Button.new()
	_runtime_button.text = "关卡房间"
	_runtime_button.toggle_mode = true
	_runtime_button.pressed.connect(func(): _set_runtime_view(true))
	_source_tabs.add_child(_runtime_button)
	_files_button = Button.new()
	_files_button.text = "美术场景 / 参考模板"
	_files_button.toggle_mode = true
	_files_button.pressed.connect(func(): _set_runtime_view(false))
	_source_tabs.add_child(_files_button)
	_runtime_bar = HBoxContainer.new()
	body.add_child(_runtime_bar)
	_scene_choice = OptionButton.new()
	for file in DirAccess.get_files_at("res://scenes"):
		if file.begins_with("ExpeditionLevel") and file.ends_with("_3D.tscn"):
			_scene_choice.add_item(file.trim_suffix("_3D.tscn").replace("ExpeditionLevel", "远征"))
			_scene_choice.set_item_metadata(_scene_choice.item_count - 1, "res://scenes/" + file)
	_runtime_bar.add_child(_scene_choice)
	var seed_label := Label.new()
	seed_label.text = "地图种子"
	_runtime_bar.add_child(seed_label)
	_seed = SpinBox.new()
	_seed.max_value = 2147483647
	_seed.value = 77003244
	_seed.custom_minimum_size.x = 145
	_seed.tooltip_text = "使用相同种子复现对应地图；列表来自实际运行生成，并非正在运行会话的实时镜像。"
	_runtime_bar.add_child(_seed)
	_read = Button.new()
	_read.text = "读取关卡"
	_read.pressed.connect(func():
		if _scene_choice.selected >= 0:
			runtime_read_requested.emit(str(_scene_choice.get_selected_metadata()), int(_seed.value)))
	_runtime_bar.add_child(_read)
	_cancel_read = Button.new()
	_cancel_read.text = "取消"
	_cancel_read.pressed.connect(func(): runtime_cancel_requested.emit())
	_cancel_read.visible = false
	_runtime_bar.add_child(_cancel_read)
	var filters := HBoxContainer.new()
	body.add_child(filters)
	search = LineEdit.new()
	search.placeholder_text = "搜索房间名 / room_01 / 模板 / 路径…"
	search.clear_button_enabled = true
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filters.add_child(search)
	search.text_changed.connect(func(_text): rebuild())
	scope = OptionButton.new()
	for label in ["美术场景", "白盒模板", "全部"]:
		scope.add_item(label)
	filters.add_child(scope)
	scope.item_selected.connect(func(index):
		show_whiteboxes.set_pressed_no_signal(index != 0)
		rebuild())
	show_whiteboxes = CheckBox.new()
	show_whiteboxes.text = "包含白盒"
	show_whiteboxes.visible = false
	filters.add_child(show_whiteboxes)
	show_whiteboxes.toggled.connect(func(value): scope.select(2 if value else 0); rebuild())
	var refresh := Button.new()
	refresh.text = "刷新"
	filters.add_child(refresh)
	refresh.pressed.connect(func():
		if runtime_view:
			_read.emit_signal("pressed")
		else:
			_begin_scan())
	var file_button := Button.new()
	file_button.text = "文件…"
	file_button.tooltip_text = "从项目文件中选择其他场景"
	file_button.pressed.connect(func(): hide(); file_requested.emit())
	filters.add_child(file_button)
	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size.y = 4
	progress_bar.show_percentage = false
	progress_bar.indeterminate = true
	progress_bar.editor_preview_indeterminate = true
	progress_bar.visible = false
	body.add_child(progress_bar)
	tree = Tree.new()
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.custom_minimum_size.y = 340
	tree.hide_root = true
	tree.columns = 2
	tree.set_column_title(0, "关卡 / 套件 / 房间名称")
	tree.set_column_title(1, "房间 ID · 模板")
	tree.column_titles_visible = true
	body.add_child(tree)
	tree.item_activated.connect(_open_selected)
	tree.item_selected.connect(_selection_changed)
	detail = Label.new()
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(detail)
	set_process(true)

func open_browser(paths: Array = [], mode: String = "open") -> void:
	purpose = mode
	var choosing_whitebox := purpose != "open"
	title = "新建场景 · 参考模板" if purpose == "new_whitebox" else ("关联白盒参考" if choosing_whitebox else "打开关卡房间")
	get_ok_button().text = "使用选中白盒" if choosing_whitebox else "打开选中场景"
	scope.visible = not choosing_whitebox
	scope.select(2)
	show_whiteboxes.set_pressed_no_signal(true)
	_source_tabs.visible = not choosing_whitebox
	runtime_view = not choosing_whitebox and _scene_choice.item_count > 0
	_sync_source_controls()
	search.placeholder_text = "搜索远征03 / 房型 / 门向 / 路径…" if choosing_whitebox else "搜索房间名 / room_01 / 模板 / 路径…"
	search.text = "远征03" if choosing_whitebox else ""
	if extra_paths != paths:
		_index_valid = false
	extra_paths = paths.duplicate()
	popup_centered_clamped(Vector2i(1000, 680), 0.85)
	if _index_valid:
		rebuild()
	elif not runtime_view:
		_begin_scan()
	search.grab_focus()
	if runtime_view:
		rebuild()

func set_runtime_source(entries: Array, scene: String, seed: int) -> void:
	runtime_rows = entries
	_seed.value = seed
	for i in range(_scene_choice.item_count):
		if str(_scene_choice.get_item_metadata(i)) == scene:
			_scene_choice.select(i)
	if visible and runtime_view:
		rebuild()

func set_runtime_status(label: String, busy: bool, failed: bool) -> void:
	runtime_busy = busy
	_read.disabled = busy
	_read.text = "重试读取" if failed else "读取关卡"
	_cancel_read.visible = busy
	if not visible or not runtime_view:
		return
	progress_bar.visible = busy
	detail.text = label
	detail.add_theme_color_override("font_color", Color("ffaf87") if failed else COLORS.TEXT)
	if busy:
		get_ok_button().disabled = true

func _set_runtime_view(value: bool) -> void:
	runtime_view = value
	search.clear()
	_sync_source_controls()
	if not value and not _index_valid:
		_begin_scan()
	rebuild()

func _sync_source_controls() -> void:
	_runtime_button.set_pressed_no_signal(runtime_view)
	_files_button.set_pressed_no_signal(not runtime_view)
	_runtime_bar.visible = runtime_view
	scope.visible = not runtime_view and purpose == "open"

func invalidate_index() -> void:
	_index_valid = false
	if visible:
		_begin_scan()

func _begin_scan() -> void:
	if scanning:
		_rescan = true
		return
	scanning = true
	_scan_started = Time.get_ticks_msec()
	progress_bar.visible = true
	get_ok_button().disabled = true
	tree.clear()
	detail.text = "正在检索房间…"
	_scan_thread = Thread.new()
	var paths := extra_paths.duplicate()
	_scan_thread.start(func(): return INDEX.scan(paths))

func _process(_delta: float) -> void:
	if not scanning:
		return
	if not runtime_view:
		detail.text = "正在检索房间… %.1fs" % ((Time.get_ticks_msec() - _scan_started) / 1000.0)
	if _scan_thread.is_alive():
		return
	var result: Variant = _scan_thread.wait_to_finish()
	_scan_thread = null
	scanning = false
	progress_bar.visible = runtime_view and runtime_busy
	if result is Array:
		rows.assign(result)
		_index_valid = true
		rebuild()
	else:
		detail.text = "场景目录读取失败，请点刷新重试。"
	if _rescan:
		_rescan = false
		_begin_scan()

func _exit_tree() -> void:
	if _scan_thread != null and _scan_thread.is_started():
		_scan_thread.wait_to_finish()

func refresh_index() -> void:
	# Deterministic entry for pure model tests; user actions use the background scanner.
	rows = INDEX.scan(extra_paths)
	_index_valid = true
	rebuild()

func rebuild() -> void:
	if scanning and not runtime_view:
		return
	tree.clear()
	var root := tree.create_item()
	var levels := {}
	var kits := {}
	displayed_count = 0
	var query := search.text.strip_edges().to_lower()
	for row in (runtime_rows if runtime_view else rows):
		if purpose != "open" and not row["whitebox"]:
			continue
		if purpose == "open" and row["whitebox"] and not show_whiteboxes.button_pressed:
			continue
		if not runtime_view and purpose == "open" and scope.selected == 1 and not row["whitebox"]:
			continue
		if not query.is_empty() and not str(row["search"]).contains(query):
			continue
		var level := str(row["level"])
		var kit_key := level + "/" + str(row["kit"])
		if not levels.has(level):
			var group := tree.create_item(root)
			group.set_text(0, level)
			group.set_selectable(0, false)
			group.set_selectable(1, false)
			levels[level] = group
		if not kits.has(kit_key):
			var group := tree.create_item(levels[level])
			group.set_text(0, row["kit"])
			group.set_selectable(0, false)
			group.set_selectable(1, false)
			kits[kit_key] = group
		var item := tree.create_item(kits[kit_key])
		item.set_text(0, str(row["label"]) + ("  [白盒]" if row["whitebox"] else ""))
		item.set_text(1, str(row["room_id"]) + " · " + str(row["template_id"]))
		item.set_metadata(0, row["path"])
		item.set_meta("whitebox", row["whitebox"])
		item.set_meta("runtime_row", row if runtime_view else {})
		if runtime_view:
			item.set_text(0, str(row["label"]) + "  [游戏内 · %.2fm]" % float(row.get("wall_height_m", 0)))
		item.set_tooltip_text(0, str(row["source_label"]) + "\n尺寸：" + str(row["size_m"]) + "\n" + str(row["path"]))
		if is_inside_tree() and has_theme_icon("PackedScene", "EditorIcons"):
			item.set_icon(0, get_theme_icon("PackedScene", "EditorIcons"))
		displayed_count += 1
	detail.text = "%d 个白盒模板 · 选择后新建美术场景。" % displayed_count if purpose != "open" else "%d 个场景 · 双击打开；白盒模板会另存为新场景。" % displayed_count
	if runtime_view:
		detail.text = "%d 个游戏内房间 · 首次创建可编辑场景，已有美术直接打开；保存后由游戏按尺寸/门位匹配读取。" % displayed_count
	if displayed_count == 0:
		detail.text = "点击“读取关卡”，获取实际运行生成的房间。" if runtime_view else "没有匹配的场景，试试清空搜索或切换分类。"
	get_ok_button().disabled = true

func _selection_changed() -> void:
	var selected := tree.get_selected()
	var path: Variant = selected.get_metadata(0) if selected != null else null
	get_ok_button().disabled = not path is String
	if path is String:
		detail.text = path
		var runtime_row: Dictionary = selected.get_meta("runtime_row", {})
		if not runtime_row.is_empty():
			detail.text = "%s · 尺寸%s · 实测墙高%.2fm\n保存后游戏读取：%s" % [runtime_row["kit"], runtime_row["size_m"], float(runtime_row.get("wall_height_m", 0)), runtime_row["art_path"]]
			get_ok_button().text = "打开关卡房间"
			get_ok_button().disabled = runtime_busy
			return
		get_ok_button().text = "使用模板新建" if bool(selected.get_meta("whitebox", false)) and purpose == "open" else ("使用选中白盒" if purpose != "open" else "打开场景")

func _open_selected() -> void:
	if runtime_view and runtime_busy:
		return
	var selected := tree.get_selected()
	if selected != null and selected.get_metadata(0) is String:
		var path := str(selected.get_metadata(0))
		# Close the modal picker before a listener opens Save As or another dialog.
		hide()
		var runtime_row: Dictionary = selected.get_meta("runtime_row", {})
		if not runtime_row.is_empty():
			runtime_requested.emit(runtime_row)
		elif purpose == "open" and not bool(selected.get_meta("whitebox", false)):
			scene_requested.emit(path)
		else:
			whitebox_requested.emit(path)
