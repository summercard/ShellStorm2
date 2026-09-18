extends CanvasLayer
class_name RogueMapSelectMenu
## 远征情报室菜单：展示一张 Rogue 独立副本地图，可点击传送进入，
## 关闭按钮正常退出并恢复基地输入。

const TARGET_SCENE := "res://scenes/RogueMap01TowerSegment3D.tscn"

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
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -320.0
	panel.offset_top = -230.0
	panel.offset_right = 320.0
	panel.offset_bottom = 230.0
	panel.custom_minimum_size = Vector2(640, 460)
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
	title.text = "远征情报室 · 独立副本"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if title.label_settings == null:
		var settings := LabelSettings.new()
		settings.font_size = 26
		title.label_settings = settings
	vbox.add_child(title)

	var desc := Label.new()
	desc.name = "Description"
	desc.text = (
		"RogueMap01：塔楼 98—95 四层独立区段，95F 为终端 Boss。\n"
		+ "从基地外入口进入；成功撤离或死亡均按独立副本结算，返回 99F 基地。"
	)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(desc)

	# 地图展示：四层区段竖向堆叠，最底为终端 Boss。
	var map_view := VBoxContainer.new()
	map_view.name = "MapView"
	map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_view.add_theme_constant_override("separation", 8)
	vbox.add_child(map_view)

	var floor_specs := [
		{"label": "98F · 入口安全房", "color": Color(0.36, 0.66, 0.92)},
		{"label": "97F · 探索区", "color": Color(0.40, 0.74, 0.56)},
		{"label": "96F · 探索区", "color": Color(0.86, 0.74, 0.34)},
		{"label": "95F · 终端 Boss", "color": Color(0.92, 0.36, 0.30)},
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
	teleport.text = "传送进入副本"
	teleport.custom_minimum_size = Vector2(220, 52)
	teleport.pressed.connect(_on_teleport_pressed)
	button_row.add_child(teleport)

	var close := Button.new()
	close.name = "CloseButton"
	close.text = "关闭"
	close.custom_minimum_size = Vector2(160, 52)
	close.pressed.connect(_on_close_pressed)
	button_row.add_child(close)


func _on_teleport_pressed() -> void:
	# 远征情报室是基地到新行动地图的正式边界。不能只切场景，必须先
	# 把基地当前玩家状态按“下线/场景卸载”规则同步落盘，再登记入口意图。
	if BaseManager != null and not BaseManager.flush_runtime_checkpoint("mission_operations_teleport_departure"):
		push_error("[RogueMapSelectMenu] 传送前运行态存档失败")
		return
	var entry_request_id := GameEntryFlow.request_gameplay_entry(
		GameEntryFlow.REASON_MISSION_OPERATIONS_TELEPORT,
		GameEntryFlow.SPAWN_SAVED_PROGRESS
	)
	var error := get_tree().change_scene_to_file(TARGET_SCENE)
	if error != OK:
		if entry_request_id > 0:
			GameEntryFlow.cancel_request(entry_request_id)
		push_error("[RogueMapSelectMenu] 传送失败: %s" % error_string(error))


func _on_close_pressed() -> void:
	queue_free()
