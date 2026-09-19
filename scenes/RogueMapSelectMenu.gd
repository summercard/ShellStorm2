extends CanvasLayer
class_name RogueMapSelectMenu
## 远征情报室菜单：展示「远征关卡01」的地图构成，可点击传送进入，
## 关闭按钮正常退出并恢复基地输入。
##
## 传送链路：基地 →（本菜单）→ 读取界面 ExpeditionLoadingScreen →
## 正式关卡 ExpeditionLevel01_3D。基地落盘与入口登记在本菜单完成，
## 之后的读取界面与关卡场景都不再改存档。

const LOADING_SCENE := "res://scenes/ExpeditionLoadingScreen.tscn"
## 到达关卡路径**不在此处硬编码**：终点真源统一为 GameDesignConfig.EXPEDITION_LEVEL_SCENE_3D，
## 避免换场景时漏改某一跳（基地设施目录 / 本菜单 / 读取界面 / 续局路由）。
const LEVEL_SCENE := GameDesignConfig.EXPEDITION_LEVEL_SCENE_3D

var _player = null


func set_player(value) -> void:
	_player = value


func _ready() -> void:
	var control := Control.new()
	control.name = "Control"
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(control)

	# 半透明遮罩，覆盖基地 HUD。
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.03, 0.05, 0.78)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	control.add_child(backdrop)

	var panel := Panel.new()
	panel.name = "Panel"
	# 仅设置 CENTER 锚点会让控件左上角落在画面中心，
	# 从而导致整个面板向右下偏移。显式设置中心点两侧的偏移，
	# 让面板几何中心与视口中心重合。
	# 高度要容下「默认关卡版图 + 其余关卡入口」两段；只加内容不加高度会让
	# 下半截溢到面板外，看起来像贴图错位。
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -340.0
	panel.offset_top = -300.0
	panel.offset_right = 340.0
	panel.offset_bottom = 300.0
	panel.custom_minimum_size = Vector2(680, 600)
	control.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.name = "VBoxContainer"
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 28.0
	vbox.offset_top = 28.0
	vbox.offset_right = -28.0
	vbox.offset_bottom = -28.0
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title := Label.new()
	title.name = "Title"
	title.text = "远征情报室 · 远征关卡01"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if title.label_settings == null:
		var settings := LabelSettings.new()
		settings.font_size = 26
		title.label_settings = settings
	vbox.add_child(title)

	var desc := Label.new()
	desc.name = "Description"
	desc.text = (
		"远征关卡01：单层独立行动。入口安全屋 → 01—05 号房 → 终点撤离房。\n"
		+ "五间 25×25 内容房的房型与朝向按种子随机排列，门后照常触发命运卡牌。\n"
		+ "成功撤离或退出战局均按独立副本结算，返回 99F 基地。"
	)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc)

	# 地图展示：单层线性推进，入口安全屋在最上，终点撤离房在最下。
	var map_view := VBoxContainer.new()
	map_view.name = "MapView"
	map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_view.add_theme_constant_override("separation", 8)
	vbox.add_child(map_view)

	var floor_specs := [
		{"label": "入口 · 安全屋 15×15m（含退出战局门）", "color": Color(0.36, 0.66, 0.92)},
		{"label": "01 — 02 号房 · 25×25m（房型按种子随机）", "color": Color(0.40, 0.74, 0.56)},
		{"label": "03 — 04 号房 · 25×25m（门后选择命运卡牌）", "color": Color(0.86, 0.74, 0.34)},
		{"label": "05 号房 · 25×25m（主通道末间）", "color": Color(0.74, 0.58, 0.86)},
		{"label": "终点 · 撤离房 25×25m（携带战利品返航）", "color": Color(0.92, 0.36, 0.30)},
	]
	for spec in floor_specs:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(28, 28)
		swatch.color = spec["color"]
		row.add_child(swatch)
		var label := Label.new()
		label.text = spec["label"]
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(label)
		map_view.add_child(row)

	var button_row := HBoxContainer.new()
	button_row.name = "ButtonRow"
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 24)
	vbox.add_child(button_row)

	var teleport := Button.new()
	teleport.name = "TeleportButton"
	teleport.text = "传送进入远征关卡"
	teleport.custom_minimum_size = Vector2(220, 52)
	teleport.pressed.connect(_on_teleport_pressed)
	button_row.add_child(teleport)

	var close := Button.new()
	close.name = "CloseButton"
	close.text = "关闭"
	close.custom_minimum_size = Vector2(160, 52)
	close.pressed.connect(_on_close_pressed)
	button_row.add_child(close)

	# 关卡清单里的其余关卡：每登记一条就多一个入口，不另做菜单。
	# 名单从 GameDesignConfig 取，这里不写任何关卡名或路径 —— 否则加一关就要改本文件。
	for level_id in GameDesignConfig.expedition_level_ids():
		if level_id == GameDesignConfig.default_expedition_level_id():
			continue
		var entry := GameDesignConfig.expedition_level(level_id)
		if entry.is_empty():
			continue
		_add_alternate_level_row(vbox, level_id, entry)


## 追加一条「其他远征关卡」的说明行 + 进入按钮。
func _add_alternate_level_row(vbox: VBoxContainer, level_id: String, entry: Dictionary) -> void:
	var separator := HSeparator.new()
	vbox.add_child(separator)

	var heading := Label.new()
	heading.name = "AlternateLevelHeading_%s" % level_id
	heading.text = str(entry.get("display_name", level_id))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 18)
	vbox.add_child(heading)

	var desc := Label.new()
	desc.name = "AlternateLevelDescription_%s" % level_id
	desc.text = str(entry.get("subtitle", ""))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(desc)

	var row := HBoxContainer.new()
	row.name = "AlternateLevelRow_%s" % level_id
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(row)

	var enter := Button.new()
	# 节点名必须能被「按关卡 id 找按钮」的验收脚本稳定命中，所以不写成固定字面量。
	enter.name = "EnterLevelButton_%s" % level_id
	enter.text = "进入%s" % str(entry.get("display_name", level_id))
	enter.custom_minimum_size = Vector2(260, 52)
	enter.pressed.connect(_on_alternate_level_pressed.bind(level_id))
	row.add_child(enter)


func _on_teleport_pressed() -> void:
	_enter_level(GameDesignConfig.default_expedition_level_id())


func _on_alternate_level_pressed(level_id: String) -> void:
	_enter_level(level_id)


## 基地 → 关卡 的唯一出发口。两张入场券（默认关卡与清单里的其余关卡）共用本函数，
## 保证「先落盘、再登记入口意图、最后切读取界面」这串契约只有一处实现。
func _enter_level(level_id: String) -> void:
	# 未登记的关卡在这里就被挡下：宁可报错退回菜单，也不要把玩家静默丢进默认关卡。
	if not GameDesignConfig.select_expedition_level(level_id):
		push_error("[RogueMapSelectMenu] 拒绝进入未登记的远征关卡: %s" % level_id)
		return
	# 远征情报室是基地到新行动地图的正式边界。不能只切场景，必须先
	# 把基地当前玩家状态按“下线/场景卸载”规则同步落盘，再登记入口意图。
	if BaseManager != null and not BaseManager.flush_runtime_checkpoint("mission_operations_teleport_departure"):
		push_error("[RogueMapSelectMenu] 传送前运行态存档失败")
		return
	var entry_request_id := GameEntryFlow.request_gameplay_entry(
		GameEntryFlow.REASON_MISSION_OPERATIONS_TELEPORT,
		GameEntryFlow.SPAWN_SAVED_PROGRESS
	)
	# 先读盘，再进读取界面；读取界面只做过场，不再改存档，最后由它切进关卡场景。
	var error := get_tree().change_scene_to_file(LOADING_SCENE)
	if error != OK:
		if entry_request_id > 0:
			GameEntryFlow.cancel_request(entry_request_id)
		push_error(
			"[RogueMapSelectMenu] 进入读取界面失败，关卡场景 %s 未被加载: %s"
			% [GameDesignConfig.expedition_level_scene(level_id), error_string(error)]
		)


func _on_close_pressed() -> void:
	queue_free()
