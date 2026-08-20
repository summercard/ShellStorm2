class_name BaseRecoveryMenu
extends CanvasLayer
## 状态恢复舱设施面板。只组合现有 Player3D.heal、
## PlayerFlashlight3D.restore_charge 与 BaseManager 能源事务，不改角色战斗逻辑。

var _energy_label: Label
var _time_label: Label
var _hp_label: Label
var _flashlight_label: Label
var _cost_label: Label
var _status_label: Label
var _restore_button: Button
var _player: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_build_interface()
	_player = get_tree().get_first_node_in_group("player_3d")
	var time_source := get_node_or_null("/root/GameTimeManager")
	if time_source != null and time_source.has_signal("minute_changed"):
		time_source.minute_changed.connect(_on_minute_changed)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		queue_free()


func _build_interface() -> void:
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.004, 0.014, 0.018, 0.94)
	add_child(backdrop)

	var frame := PanelContainer.new()
	frame.set_anchors_preset(Control.PRESET_CENTER)
	frame.offset_left = -370.0
	frame.offset_top = -286.0
	frame.offset_right = 370.0
	frame.offset_bottom = 286.0
	frame.add_theme_stylebox_override(
		"panel", _panel_style(Color(0.22, 0.86, 0.62), 3, Color(0.018, 0.052, 0.050, 0.98))
	)
	add_child(frame)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	frame.add_child(root)
	var title := Label.new()
	title.text = "基地状态恢复舱"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.44, 1.0, 0.76))
	root.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "恢复生命与手电电量 · 基地内不会自动补充手电"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color(0.58, 0.76, 0.73))
	root.add_child(subtitle)

	var energy_panel := PanelContainer.new()
	energy_panel.add_theme_stylebox_override(
		"panel", _panel_style(Color(0.18, 0.62, 0.52), 2, Color(0.025, 0.095, 0.085, 0.96))
	)
	root.add_child(energy_panel)
	var energy_box := VBoxContainer.new()
	energy_box.add_theme_constant_override("separation", 5)
	energy_panel.add_child(energy_box)
	_energy_label = _make_label("基地电量 --/--", 24, Color(0.54, 1.0, 0.74))
	energy_box.add_child(_energy_label)
	_time_label = _make_label("2075-01-01  17:00", 16, Color(0.48, 0.78, 0.86))
	energy_box.add_child(_time_label)

	var state_panel := PanelContainer.new()
	state_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	state_panel.add_theme_stylebox_override(
		"panel", _panel_style(Color(0.12, 0.42, 0.46), 1, Color(0.014, 0.040, 0.052, 0.96))
	)
	root.add_child(state_panel)
	var state_box := VBoxContainer.new()
	state_box.add_theme_constant_override("separation", 12)
	state_panel.add_child(state_box)
	_hp_label = _make_label("生命  -- / --", 22, Color(1.0, 0.52, 0.48))
	state_box.add_child(_hp_label)
	_flashlight_label = _make_label("手电  --%", 22, Color(0.72, 0.94, 1.0))
	state_box.add_child(_flashlight_label)
	_cost_label = _make_label("本次消耗  -- 基地电量", 20, Color(1.0, 0.80, 0.32))
	state_box.add_child(_cost_label)

	_restore_button = Button.new()
	_restore_button.text = "恢复全部状态"
	_restore_button.custom_minimum_size.y = 58.0
	_restore_button.pressed.connect(_on_restore_pressed)
	_restore_button.add_theme_font_size_override("font_size", 20)
	_restore_button.add_theme_stylebox_override(
		"normal", _panel_style(Color(0.22, 0.86, 0.62), 2, Color(0.035, 0.18, 0.13))
	)
	root.add_child(_restore_button)

	_status_label = _make_label("", 16, Color(0.66, 0.84, 0.82))
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.custom_minimum_size.y = 32.0
	root.add_child(_status_label)
	var close := Button.new()
	close.text = "关闭  ESC"
	close.custom_minimum_size.y = 44.0
	close.pressed.connect(queue_free)
	root.add_child(close)
	UIStyleFactory.apply_tactical_tree(self)


func _refresh(status_override := "") -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player_3d")
	var snapshot := BaseManager.get_recovery_facility_snapshot(_player)
	var energy := snapshot.get("energy", {}) as Dictionary
	var plan := snapshot.get("plan", {}) as Dictionary
	_energy_label.text = "基地电量  %.0f / %.0f" % [
		float(energy.get("current", 0.0)), float(energy.get("capacity", 100.0))
	]
	_energy_label.tooltip_text = "每游戏小时恢复 %.1f；接口可扩展到发电机、天气与设施升级。" % float(energy.get("regen_per_game_hour", 0.0))
	_hp_label.text = "生命  %d / %d  （缺失 %d）" % [
		int(snapshot.get("current_hp", 0)),
		int(snapshot.get("max_hp", 0)),
		int(plan.get("missing_hp", 0)),
	]
	var charge := float(snapshot.get("flashlight_charge_ratio", 0.0))
	_flashlight_label.text = "手电  %d%%  （缺失 %d%%）" % [
		int(round(charge * 100.0)),
		int(round(float(plan.get("missing_flashlight_ratio", 0.0)) * 100.0)),
	]
	_cost_label.text = "本次消耗  %d 基地电量" % int(plan.get("cost", 0))
	_restore_button.disabled = not bool(snapshot.get("available", false))
	_restore_button.text = "恢复全部状态  ·  消耗 %d" % int(plan.get("cost", 0))
	_status_label.text = status_override if not status_override.is_empty() else str(snapshot.get("reason", ""))
	var time_source := get_node_or_null("/root/GameTimeManager")
	if time_source != null and time_source.has_method("get_time_snapshot"):
		var time_snapshot := time_source.call("get_time_snapshot") as Dictionary
		_time_label.text = "%s  ·  +%.1f电量/游戏时" % [
			str(time_snapshot.get("display_text", "2075-01-01  17:00")),
			float(energy.get("regen_per_game_hour", 0.0)),
		]


func _on_restore_pressed() -> void:
	var result := BaseManager.recover_player_state_at_facility(_player)
	if bool(result.get("success", false)):
		if AudioManager != null:
			AudioManager.play_sfx("flashlight_charge_up", -2.0)
		_refresh("恢复完成：生命 +%d，手电 +%d%%，剩余基地电量 %.0f。" % [
			int(result.get("hp_restored", 0)),
			int(round(float(result.get("flashlight_restored_ratio", 0.0)) * 100.0)),
			float(result.get("energy_remaining", 0.0)),
		])
	else:
		if AudioManager != null:
			AudioManager.play_sfx("ui_error", -4.0)
		_refresh("恢复失败：%s" % str(result.get("reason", "未知原因")))


func _on_minute_changed(_snapshot: Dictionary) -> void:
	_refresh(_status_label.text if _status_label != null else "")


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _panel_style(border: Color, width: int, background: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(8)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	return style
