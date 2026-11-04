class_name MonsterArchiveMenu
extends CanvasLayer

@onready var _background: ColorRect = $Backdrop
@onready var _layout: VBoxContainer = $Margin/Layout
@onready var _summary: Label = $Margin/Layout/Summary
@onready var _list_scroll: ScrollContainer = $Margin/Layout/Body/List
@onready var _list: VBoxContainer = $Margin/Layout/Body/List/Entries
@onready var _detail_scroll: ScrollContainer = $Margin/Layout/Body/Detail
@onready var _detail: VBoxContainer = $Margin/Layout/Body/Detail/Content
@onready var _close: Button = $Margin/Layout/CloseButton
@onready var _body: HBoxContainer = $Margin/Layout/Body
@onready var _preview: PanelContainer = $Margin/Layout/Body/Preview
@onready var _preview_layout: VBoxContainer = $Margin/Layout/Body/Preview/Padding/Layout
@onready var _preview_host: SubViewportContainer = _preview_layout.get_node("Stage/ViewportHost")
@onready var _preview_viewport: SubViewport = _preview_host.get_node("ModelViewport")
@onready var _preview_camera: Camera3D = _preview_viewport.get_node("Camera")
@onready var _preview_slot: Node3D = _preview_viewport.get_node("Model")
@onready var _preview_placeholder: Label = _preview_layout.get_node("Stage/Placeholder")
@onready var _preview_state: Label = _preview_layout.get_node("State")
@onready var _preview_outcome: Label = _preview_layout.get_node("Outcome")
@onready var _preview_health: Label = _preview_layout.get_node("Health")
@onready var _preview_health_bar: ProgressBar = _preview_layout.get_node("HealthBar")

const PREVIEW_IDLE := {"state": "idle", "action_id": "idle"}

var _records: Array[Dictionary] = []
var _selected_id := ""
var _entry_buttons := ButtonGroup.new()
var _preview_id := ""
var _preview_model: Node3D
var _preview_bounds := AABB()


func _ready() -> void:
	_background.color = Color(UIPalette.PRISM_DIM.r, UIPalette.PRISM_DIM.g, UIPalette.PRISM_DIM.b, 0.96)
	var header := UIStyleFactory.make_prism_header("怪物档案", "99F  /  精英名录", UIPalette.PRISM_ACCENT, 26)
	_layout.add_child(header)
	_layout.move_child(header, 0)
	UIStyleFactory.apply_prism_label(_summary, "label", 1, 15)
	UIStyleFactory.apply_prism_scrollbar(_list_scroll)
	UIStyleFactory.apply_prism_scrollbar(_detail_scroll)
	_detail_scroll.gui_input.connect(_on_detail_input)
	UIStyleFactory.apply_prism_button(_close, "ghost", 2, 17, 2)
	_close.pressed.connect(request_close)
	_setup_preview()
	EliteRosterService.roster_changed.connect(_on_roster_changed)
	_refresh()
	UiMenuFocus.ensure_focus(self)


func _on_roster_changed(_elite_id: String, _record: Dictionary) -> void:
	_refresh()


func _refresh() -> void:
	var focus := get_viewport().gui_get_focus_owner()
	var focused_id := str(focus.get_meta("elite_id", "")) if is_instance_valid(focus) else ""
	_records = EliteRosterService.get_encountered_elites()
	_summary.text = "已记录  %02d" % _records.size()
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	if _records.is_empty():
		_close.focus_neighbor_top = NodePath()
		_detail_scroll.focus_neighbor_left = NodePath()
		_selected_id = ""
		_add_text(_list, "暂无档案", "faint", 16)
		_show_detail({})
		return
	var selected: Dictionary = _records[0]
	for record in _records:
		if str(record.elite_id) == _selected_id:
			selected = record
	_selected_id = str(selected.elite_id)
	for record in _records:
		var button := Button.new()
		var elite_id := str(record.elite_id)
		button.set_meta("elite_id", elite_id)
		button.text = "%s  ·  Lv.%d" % [record.name, int(record.get("level", 1))]
		button.tooltip_text = button.text
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.toggle_mode = true
		button.button_group = _entry_buttons
		button.custom_minimum_size.y = 46.0
		UIStyleFactory.apply_prism_row_button(button, "ghost", 16, 1, 12.0, false)
		_list.add_child(button)
		button.set_pressed_no_signal(elite_id == _selected_id)
		button.focus_neighbor_right = button.get_path_to(_detail_scroll)
		button.pressed.connect(_select.bind(record))
		if elite_id == focused_id:
			button.grab_focus()
	_detail_scroll.focus_neighbor_left = _detail_scroll.get_path_to(_list.get_child(0))
	_close.focus_neighbor_top = _close.get_path_to(_list.get_child(0))
	_show_detail(selected)


func _select(record: Dictionary) -> void:
	_selected_id = str(record.elite_id)
	_detail_scroll.scroll_vertical = 0
	_show_detail(record)


func _on_detail_input(event: InputEvent) -> void:
	var step := 0
	if event.is_action_pressed("ui_down", true):
		step = 44
	elif event.is_action_pressed("ui_up", true):
		step = -44
	if step != 0 and _detail_scroll.get_v_scroll_bar().visible:
		_detail_scroll.scroll_vertical += step
		_detail_scroll.accept_event()


func _show_detail(record: Dictionary) -> void:
	_show_preview(record)
	for child in _detail.get_children():
		_detail.remove_child(child)
		child.queue_free()
	if record.is_empty():
		_add_text(_detail, "尚未遭遇精英", "value", 28)
		_add_text(_detail, "在行动中首次遭遇精英后，档案会在这里登记。", "label", 17)
		return

	_add_text(_detail, str(record.name), "value", 28)
	_add_text(_detail, "Lv.%d" % int(record.get("level", 1)), "accent", 18)
	var bounty := EliteRosterService.get_bounty_currency(_selected_id)
	var stats := "遭遇 %d 次  ·  逃脱 %d 次" % [int(record.get("encounter_count", 0)), int(record.get("escape_count", 0))]
	var player_kills := int((record.get("history", {}) as Dictionary).get("killed_player_count", 0))
	if player_kills > 0:
		stats += "  ·  击杀玩家 %d 次" % player_kills
	if bounty > 0 and str(record.get("state", "")) != "Killed":
		stats += "  ·  悬赏 %d 金币" % bounty
	_add_text(_detail, stats, "label", 15)
	var growth := str(record.get("growth", ""))
	if not growth.is_empty():
		_add_text(_detail, "成长特性  " + growth, "label", 15)

	_add_section("持有物品")
	var quantities := {}
	for entry: Dictionary in record.get("stolen_items", []):
		var item := entry.get("item", {}) as Dictionary
		var count := int(entry.get("count", 0))
		if item.is_empty() or count <= 0:
			continue
		var item_name := str(item.get("name", item.get("id", "未知物品")))
		if item_name.is_empty():
			item_name = str(item.get("id", "未知物品"))
		quantities[item_name] = int(quantities.get(item_name, 0)) + count
	if quantities.is_empty():
		_add_text(_detail, "暂无持有物品", "faint", 16)
	else:
		for item_name in quantities:
			_add_text(_detail, "%s  ×%d" % [item_name, quantities[item_name]], "value", 17)
	_add_text(_detail, "夺取货币  %d" % int(record.get("stolen_currency", 0)), "warn", 16)

	var modules := record.get("stolen_modules", []) as Array
	if not modules.is_empty():
		_add_section("转译装备")
		for module: Dictionary in modules:
			var item_id := str(module.get("module_id", ""))
			var item := ItemRegistry.get_instance().get_item(item_id)
			_add_text(_detail, "%s  →  %s" % [str(item.get("name", "未识别装备")), _shorten_translation(str(module.get("translated_skill_id", "")))], "label", 16)


func _setup_preview() -> void:
	var panel := UIStyleFactory.make_prism_panel(false, 0.47)
	panel.border_color = UIPalette.PRISM_LINE_FAINT
	panel.set_border_width_all(1)
	_preview.add_theme_stylebox_override("panel", panel)
	UIStyleFactory.apply_prism_label(_preview_layout.get_node("Heading"), "label", 1, 15)
	UIStyleFactory.apply_prism_label(_preview_placeholder, "faint", 1, 15)
	UIStyleFactory.apply_prism_label(_preview_state, "accent", 1, 18)
	UIStyleFactory.apply_prism_label(_preview_outcome, "label", 1, 14)
	UIStyleFactory.apply_prism_label(_preview_health, "label", 1, 14)
	_preview_layout.get_node("Rule").add_theme_stylebox_override("separator", UIStyleFactory.make_prism_separator_style())
	_preview_health_bar.add_theme_stylebox_override("background", UIStyleFactory.make_prism_progress_background())
	_preview_health_bar.add_theme_stylebox_override("fill", UIStyleFactory.make_prism_progress_fill(UIPalette.PRISM_ACCENT))
	_body.resized.connect(_fit_columns)
	_preview_viewport.size_changed.connect(_fit_preview_camera)
	_fit_columns()
	set_process(false)


func _fit_columns() -> void:
	_list_scroll.custom_minimum_size.x = clampf(_body.size.x * 0.25, 140.0, 290.0)
	_preview.custom_minimum_size.x = clampf(_body.size.x * 0.235, 160.0, 272.0)


func _show_preview(record: Dictionary) -> void:
	var elite_id := str(record.get("elite_id", ""))
	_preview_state.text = "档案状态  " + _state_text(str(record.get("state", ""))) if not elite_id.is_empty() else "档案状态  未登记"
	var outcome := str(record.get("last_outcome", ""))
	var outcome_text := str({
		"active": "已确认遭遇", "escaped": "精英逃脱", "killed": "精英已击杀", "despawned": "精英离场",
	}.get(outcome, "暂无结局记录"))
	_preview_outcome.text = "最近结果  " + outcome_text
	_preview_outcome.visible = not elite_id.is_empty()
	var encounter := record.get("roaming_encounter", {}) as Dictionary
	var max_hp := int(encounter.get("max_hp", 0))
	var hp := clampi(int(encounter.get("hp", 0)), 0, maxi(0, max_hp))
	_preview_health.visible = max_hp > 0
	_preview_health_bar.visible = max_hp > 0
	_preview_health.text = "上次记录生命  %d / %d" % [hp, max_hp]
	_preview_health_bar.max_value = maxi(1, max_hp)
	_preview_health_bar.value = hp
	if elite_id == _preview_id:
		_preview_placeholder.text = "尚无可预览的精英" if elite_id.is_empty() else "暂无可用模型"
		return
	_preview_id = elite_id
	if is_instance_valid(_preview_model):
		_preview_slot.remove_child(_preview_model)
		_preview_model.queue_free()
	_preview_model = null
	_preview_bounds = AABB()
	_preview_host.hide()
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_preview_placeholder.show()
	_preview_placeholder.text = "尚无可预览的精英" if elite_id.is_empty() else "暂无可用模型"
	set_process(false)

	var definition := EliteRosterService.get_definition(elite_id)
	var scene_path := str(definition.get("presentation_scene", ""))
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path, "PackedScene"):
		return
	var scene := load(scene_path) as PackedScene
	if scene == null:
		return
	var model := scene.instantiate()
	if not model is Node3D:
		model.free()
		return
	_preview_model = model as Node3D
	_preview_slot.add_child(_preview_model)
	_preview_bounds = _measure_preview_bounds(_preview_model)
	_preview_placeholder.hide()
	_preview_host.show()
	_fit_preview_camera()
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	set_process(_preview_model.has_method("sync_context"))


func _measure_preview_bounds(model: Node3D) -> AABB:
	# A skinned mesh's imported bounds describe its bind pose. Frame the sampled
	# standing pose with the same fitted volumes the visual already provides.
	var bounds := AABB()
	if model.has_method("hit_volume_transforms") and model.has_method("get_hit_volume_spec"):
		var transforms: Array = model.call("hit_volume_transforms")
		var spec: Array = model.call("get_hit_volume_spec")
		for index in mini(transforms.size(), spec.size()):
			var size: Vector3 = spec[index]["size"]
			var transform: Transform3D = transforms[index]
			var segment := transform * AABB(-size * 0.5, size)
			bounds = bounds.merge(segment) if bounds.has_volume() else segment
		if bounds.has_volume():
			return bounds.grow(bounds.size.y * 0.055)
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.mesh != null:
			var segment := mesh.global_transform * mesh.get_aabb()
			bounds = bounds.merge(segment) if bounds.has_volume() else segment
	return bounds


func _fit_preview_camera() -> void:
	if not _preview_bounds.has_volume():
		return
	var center := _preview_bounds.get_center()
	var distance := _preview_bounds.size.length() + 3.0
	_preview_camera.position = center + Vector3(0.32, 0.16, -1.0).normalized() * distance
	_preview_camera.look_at(center)
	var basis := _preview_camera.global_basis.inverse()
	var viewport_size := _preview_viewport.size
	var aspect := float(maxi(1, viewport_size.x)) / float(maxi(1, viewport_size.y))
	var half_width := 0.0
	var half_height := 0.0
	for index in 8:
		var corner := basis * (_preview_bounds.get_endpoint(index) - center)
		half_width = maxf(half_width, absf(corner.x))
		half_height = maxf(half_height, absf(corner.y))
	_preview_camera.size = maxf(half_height, half_width / aspect) * 2.28


func _process(_delta: float) -> void:
	if is_instance_valid(_preview_model):
		_preview_model.call("sync_context", PREVIEW_IDLE, false)


func _add_text(parent: VBoxContainer, value: String, role: String, size: int) -> void:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UIStyleFactory.apply_prism_label(label, role, 1, size)
	parent.add_child(label)


func _add_section(title: String) -> void:
	var line := HSeparator.new()
	line.add_theme_stylebox_override("separator", UIStyleFactory.make_prism_separator_style(0.24))
	_detail.add_child(line)
	_add_text(_detail, title, "label", 15)


func _state_text(state: String) -> String:
	match state:
		"Newborn": return "已登记"
		"Escaped": return "已逃脱"
		"Equipped": return "装备中"
		"Growing": return "成长中"
		"RevengeHunter": return "复仇猎手"
		"RegionalBoss": return "区域霸主"
		"QuasiBoss": return "准首领"
		"Killed": return "已击杀"
		_: return "状态未知"


func _shorten_translation(translation_id: String) -> String:
	return str({
		"gun_body_to_followup_shot": "副枪追射",
		"bullet_to_counter_volley": "反击弹幕",
		"stock_magazine_to_guard_counter": "格挡反击",
		"attachment_to_hive_modifier": "蜂巢增幅",
		"explosive_round_to_mine_field": "爆炸雷区",
		"piercing_optic_to_line_lunge": "穿刺突袭",
		"ricochet_optic_to_reflect_sector": "反射扇区",
		"gun_body_to_phase_skill": "阶段枪技",
		"fate_to_budgeted_rule": "命运规则",
		"attachment_to_summon_echo": "召唤回声",
		"return_round_to_retreat_lunge": "折返突袭",
		"assembly_to_three_phase_bag": "三阶段技能",
	}.get(translation_id, "未知转译"))

func request_close() -> void:
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		request_close()
