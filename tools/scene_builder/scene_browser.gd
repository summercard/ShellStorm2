@tool
extends AcceptDialog

signal scene_requested(path: String)
signal file_requested
signal whitebox_requested(path: String)
const INDEX := preload("res://tools/scene_builder/scene_index.gd")
const COLORS := preload("res://tools/scene_builder/workbench_theme.gd")
var search: LineEdit
var source_hint: Label
var level_filter: OptionButton
var tree: Tree
var detail: Label
var rows: Array[Dictionary] = []
var extra_paths: Array = []
var displayed_count := 0
var purpose := "open"
var progress_bar: ProgressBar
var scanning := false
var _scan_thread: Thread
var _scan_started := 0
var _scan_purpose := ""
var _index_purpose := ""
var _index_valid := false
var _rescan := false

func _init() -> void:
	title = "打开房间"
	size = Vector2i(1000, 680)
	theme = COLORS.build()
	get_ok_button().text = "打开选中房间"
	confirmed.connect(_open_selected)
	var body := VBoxContainer.new()
	add_child(body)
	source_hint = Label.new()
	source_hint.text = "游戏使用的正式房间文件 · 每个文件只显示一次"
	source_hint.name = "SourceHint"
	body.add_child(source_hint)
	var filters := HBoxContainer.new()
	body.add_child(filters)
	level_filter = OptionButton.new()
	level_filter.custom_minimum_size.x = 140
	level_filter.add_item("全部关卡")
	level_filter.set_item_metadata(0, "")
	level_filter.item_selected.connect(func(_index): rebuild())
	filters.add_child(level_filter)
	search = LineEdit.new()
	search.placeholder_text = "搜索房间名 / 房型 / 文件路径…"
	search.clear_button_enabled = true
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filters.add_child(search)
	search.text_changed.connect(func(_text): rebuild())
	var refresh := Button.new()
	refresh.text = "刷新"
	filters.add_child(refresh)
	refresh.pressed.connect(_begin_scan)
	var file_button := Button.new()
	file_button.text = "文件…"
	file_button.tooltip_text = "使用Godot文件选择器打开其他文件；不改变正式房间登记"
	filters.add_child(file_button)
	file_button.pressed.connect(func(): hide(); file_requested.emit())
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
	tree.add_theme_font_size_override("font_size", 14)
	tree.add_theme_font_size_override("title_button_font_size", 14)
	tree.set_column_title(0, "关卡 / 房间")
	tree.set_column_title(1, "房型 · 尺寸")
	tree.column_titles_visible = true
	body.add_child(tree)
	tree.item_activated.connect(_open_selected)
	tree.item_selected.connect(_selection_changed)
	detail = Label.new()
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(detail)
	set_process(true)

func open_browser(paths: Array = [], mode: String = "open") -> void:
	if purpose != mode:
		level_filter.select(0)
	purpose = mode
	var choosing_whitebox := purpose != "open"
	title = "新建房间 · 选择参考" if purpose == "new_whitebox" else ("关联白盒参考" if choosing_whitebox else "打开房间")
	get_ok_button().text = "使用选中参考" if choosing_whitebox else "打开选中房间"
	source_hint.text = "参考只用于新建或关联，不覆盖原文件" if choosing_whitebox else "游戏使用的正式房间文件 · 每个文件只显示一次"
	search.placeholder_text = "搜索参考模板 / 房型 / 路径…" if choosing_whitebox else "搜索房间名 / 房型 / 文件路径…"
	search.text = "远征03" if choosing_whitebox else ""
	if extra_paths != paths or _index_purpose != purpose:
		_index_valid = false
	extra_paths = paths.duplicate()
	popup_centered_clamped(Vector2i(1000, 680), 0.85)
	if _index_valid:
		rebuild()
	else:
		_begin_scan()
	search.grab_focus()

func invalidate_index() -> void:
	_index_valid = false
	if visible:
		_begin_scan()

func _begin_scan() -> void:
	if scanning:
		_rescan = true
		return
	scanning = true
	_scan_purpose = purpose
	_scan_started = Time.get_ticks_msec()
	progress_bar.visible = true
	get_ok_button().disabled = true
	tree.clear()
	detail.text = "正在检索正式房间…" if purpose == "open" else "正在检索参考模板…"
	_scan_thread = Thread.new()
	var paths := extra_paths.duplicate()
	var opening := purpose == "open"
	_scan_thread.start(func(): return INDEX.game_rooms() if opening else INDEX.scan(paths))

func _process(_delta: float) -> void:
	if not scanning:
		return
	detail.text = ("正在检索正式房间…" if purpose == "open" else "正在检索参考模板…") + " %.1fs" % ((Time.get_ticks_msec() - _scan_started) / 1000.0)
	if _scan_thread.is_alive():
		return
	var result: Variant = _scan_thread.wait_to_finish()
	_scan_thread = null
	scanning = false
	progress_bar.visible = false
	if _scan_purpose == purpose and result is Array:
		rows.assign(result)
		_index_valid = true
		_index_purpose = purpose
		_update_levels()
		rebuild()
	elif _scan_purpose == purpose:
		detail.text = "房间目录读取失败，请点刷新重试。"
	if _rescan or _scan_purpose != purpose:
		_rescan = false
		_begin_scan()

func _exit_tree() -> void:
	if _scan_thread != null and _scan_thread.is_started():
		_scan_thread.wait_to_finish()

func refresh_index() -> void:
	# Deterministic model-test entry; user actions scan metadata in a worker.
	rows = INDEX.game_rooms() if purpose == "open" else INDEX.scan(extra_paths)
	_index_valid = true
	_index_purpose = purpose
	_update_levels()
	rebuild()

func _update_levels() -> void:
	var previous := str(level_filter.get_selected_metadata()) if level_filter.selected >= 0 else ""
	var levels: Array[String] = []
	for row in rows:
		if purpose != "open" and not row["whitebox"]:
			continue
		var level := str(row["level"])
		if not level in levels:
			levels.append(level)
	levels.sort()
	level_filter.clear()
	level_filter.add_item("全部关卡" if purpose == "open" else "全部参考")
	level_filter.set_item_metadata(0, "")
	for level in levels:
		level_filter.add_item(level)
		level_filter.set_item_metadata(level_filter.item_count - 1, level)
		if level == previous:
			level_filter.select(level_filter.item_count - 1)
	if previous.is_empty() or not previous in levels:
		level_filter.select(0)

func rebuild() -> void:
	if scanning:
		return
	tree.clear()
	var root := tree.create_item()
	var levels := {}
	var kits := {}
	var seen := {}
	displayed_count = 0
	var query := search.text.strip_edges().to_lower()
	var chosen := str(level_filter.get_selected_metadata()) if level_filter.selected >= 0 else ""
	for row in rows:
		if purpose != "open" and not row["whitebox"]:
			continue
		if purpose == "open" and row["whitebox"]:
			continue
		if not chosen.is_empty() and chosen != str(row["level"]):
			continue
		if not query.is_empty() and not str(row["search"]).contains(query):
			continue
		var path := str(row["path"])
		if seen.has(path):
			continue
		seen[path] = true
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
		item.set_text(0, str(row["label"]))
		item.set_text(1, "%s · %s" % [str(row["template_id"]), str(row["size_m"])])
		item.set_metadata(0, path)
		item.set_meta("whitebox", row["whitebox"])
		item.set_tooltip_text(0, str(row["source_label"]) + "\n" + path)
		if is_inside_tree() and has_theme_icon("PackedScene", "EditorIcons"):
			item.set_icon(0, get_theme_icon("PackedScene", "EditorIcons"))
		displayed_count += 1
	detail.text = "%d 个正式房间文件 · 双击直接编辑并保存同一文件" % displayed_count if purpose == "open" else "%d 个参考模板 · 用于新建或关联" % displayed_count
	if displayed_count == 0:
		detail.text = "没有匹配的正式房间；可清空筛选或点刷新。新文件须先接入关卡。" if purpose == "open" else "没有匹配的参考模板，试试清空搜索。"
	get_ok_button().disabled = true

func _selection_changed() -> void:
	var selected := tree.get_selected()
	var path: Variant = selected.get_metadata(0) if selected != null else null
	get_ok_button().disabled = not path is String
	if path is String:
		detail.text = "正式房间文件：" + path if purpose == "open" else path
		get_ok_button().text = "打开选中房间" if purpose == "open" else "使用选中参考"

func _open_selected() -> void:
	var selected := tree.get_selected()
	if selected == null:
		return
	var path: Variant = selected.get_metadata(0)
	if not path is String:
		return
	hide()
	if purpose != "open":
		whitebox_requested.emit(str(path))
	else:
		scene_requested.emit(str(path))
