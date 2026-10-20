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
	BaseManager.base_power_changed.connect(_on_base_power_changed)
	_refresh()
	# 手柄通路：十字键/摇杆导航与 A 键确认都需要一个「焦点持有者」，
	# 打开菜单时先抓焦点，否则手柄在子界面里没有入口。
	UiMenuFocus.ensure_focus(self)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		queue_free()


func _build_interface() -> void:
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 冷蓝压暗（非纯黑）：棱镜模态的标准遮罩。
	backdrop.color = Color(UIPalette.PRISM_DIM.r, UIPalette.PRISM_DIM.g, UIPalette.PRISM_DIM.b, 0.72)
	add_child(backdrop)

	var frame := PanelContainer.new()
	frame.set_anchors_preset(Control.PRESET_CENTER)
	frame.offset_left = -370.0
	frame.offset_top = -286.0
	frame.offset_right = 370.0
	frame.offset_bottom = 286.0
	frame.add_theme_stylebox_override("panel", _prism_panel_style(0.62, 24))
	# 四角括号 = 本风格唯一的"选框"手段（全屏只此一处，不与其他线框打架）。
	UIStyleFactory.attach_prism_bracket_frame(frame, "solid", 26.0, 2.0, 0.0)
	add_child(frame)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	frame.add_child(root)
	var title := Label.new()
	title.text = "基地状态恢复舱"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIStyleFactory.apply_prism_label(title, "value", 5, 26)
	root.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "恢复生命与手电电量 · 基地内不会自动补充手电"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIStyleFactory.apply_prism_label(subtitle, "faint", 2, 13)
	root.add_child(subtitle)

	var energy_panel := PanelContainer.new()
	energy_panel.add_theme_stylebox_override("panel", _prism_panel_style(0.30, 14))
	root.add_child(energy_panel)
	var energy_box := VBoxContainer.new()
	energy_box.add_theme_constant_override("separation", 5)
	energy_panel.add_child(energy_box)
	_energy_label = _make_label("基地电量 --/--", 22, "value", 3)
	energy_box.add_child(_energy_label)
	_time_label = _make_label("2075-01-01  09:00", 15, "faint", 1)
	energy_box.add_child(_time_label)

	var state_panel := PanelContainer.new()
	state_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	state_panel.add_theme_stylebox_override("panel", _prism_panel_style(0.24, 14))
	root.add_child(state_panel)
	var state_box := VBoxContainer.new()
	state_box.add_theme_constant_override("separation", 12)
	state_panel.add_child(state_box)
	_hp_label = _make_label("生命  -- / --", 22, "value", 3)
	state_box.add_child(_hp_label)
	_flashlight_label = _make_label("手电  --%", 22, "value", 3)
	state_box.add_child(_flashlight_label)
	# 消耗 = 需要留意但非毁灭性 → 琥珀语义色。
	_cost_label = _make_label("本次消耗  -- 基地电量", 20, "warn", 3)
	state_box.add_child(_cost_label)

	_restore_button = Button.new()
	_restore_button.text = "恢复全部状态"
	_restore_button.custom_minimum_size.y = 58.0
	_restore_button.pressed.connect(_on_restore_pressed)
	# 主行动：实心近白底 + 深墨字（棱镜默认焦点铁律：安全侧永远是实心白钮）。
	UIStyleFactory.apply_prism_button(_restore_button, "primary", 2, 20, 3)
	root.add_child(_restore_button)

	_status_label = _make_label("", 16, "faint", 2)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.custom_minimum_size.y = 32.0
	root.add_child(_status_label)
	var close := Button.new()
	# 命名成 CloseButton：UiMenuFocus 按这个名字挑「打开即被 A 触发的安全默认焦点」。
	close.name = "CloseButton"
	close.text = "关闭  ESC"
	close.custom_minimum_size.y = 44.0
	close.pressed.connect(queue_free)
	UIStyleFactory.apply_prism_button(close, "ghost", 2, 17, 2)
	root.add_child(close)


## 棱镜面板底衬：深蓝半透 + 1px 次级白线，方角；内边距用参数控制（不依赖样式盒的零边距）。
func _prism_panel_style(alpha: float, margin: float) -> StyleBoxFlat:
	var style := UIStyleFactory.make_prism_panel(true, alpha)
	style.border_color = UIPalette.PRISM_LINE_SOFT
	style.set_border_width_all(1)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin * 0.75
	style.content_margin_bottom = margin * 0.75
	return style


func _refresh(status_override := "") -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player_3d")
	var snapshot := BaseManager.get_recovery_facility_snapshot(_player)
	var energy := snapshot.get("energy", {}) as Dictionary
	var plan := snapshot.get("plan", {}) as Dictionary
	_energy_label.text = "基地电量  %.0f / %.0f" % [
		float(energy.get("current", 0.0)), float(energy.get("capacity", 100.0))
	]
	_energy_label.tooltip_text = "天台发电机开启时每游戏小时恢复 %.1f；关闭时停止供电和恢复。" % float(energy.get("regen_per_game_hour", 0.0))
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
			str(time_snapshot.get("display_text", "2075-01-01  09:00")),
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


func _make_label(text: String, font_size: int, role: String = "value", spacing: int = 2) -> Label:
	var label := Label.new()
	label.text = text
	UIStyleFactory.apply_prism_label(label, role, spacing, font_size)
	return label


func _on_base_power_changed(_enabled: bool) -> void:
	_refresh()
