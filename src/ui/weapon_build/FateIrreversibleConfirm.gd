extends Control

signal completed(accepted: bool)
var message := "购买后该枪械命运卡不可更换！"
var weapon_instance_id := ""
var _done := false
var _previous_focus: WeakRef

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_meta("ui_prism_exempt", true)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 200
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null:
		_previous_focus = weakref(focused)
	var dim := ColorRect.new()
	dim.color = UIPalette.PRISM_DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -260
	panel.offset_right = 260
	panel.offset_top = -110
	panel.offset_bottom = 110
	panel.add_theme_stylebox_override("panel", UIStyleFactory.make_prism_slot_style(false))
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 22)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(column)
	var label := Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", UIPalette.PRISM_TEXT)
	column.add_child(label)
	var target := Label.new()
	target.text = "目标枪械 #%s" % weapon_instance_id.right(6).to_upper()
	target.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	target.add_theme_color_override("font_color", UIPalette.PRISM_LABEL)
	column.add_child(target)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 24)
	column.add_child(actions)
	var yes := Button.new()
	yes.text = "是"
	yes.custom_minimum_size = Vector2(160, 44)
	UIStyleFactory.apply_prism_button(yes, "ghost", 0, 22, 1, "none")
	actions.add_child(yes)
	yes.pressed.connect(_finish.bind(true))
	var no := Button.new()
	no.text = "否"
	no.custom_minimum_size = Vector2(160, 44)
	UIStyleFactory.apply_prism_button(no, "primary", 0, 22, 1, "none")
	actions.add_child(no)
	no.pressed.connect(cancel)
	for button in [yes, no]:
		var other: Button = no if button == yes else yes
		for direction in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			button.set_focus_neighbor(direction, button.get_path_to(other))
		button.focus_next = button.get_path_to(other)
		button.focus_previous = button.get_path_to(other)
	no.grab_focus()

func _input(event: InputEvent) -> void:
	if not _done and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		get_viewport().set_input_as_handled()
		cancel()

func cancel() -> void:
	_finish(false)

func _finish(accepted: bool) -> void:
	if _done:
		return
	_done = true
	hide()
	if _previous_focus != null:
		var focused := _previous_focus.get_ref() as Control
		if is_instance_valid(focused) and focused.is_inside_tree() and focused.is_visible_in_tree():
			focused.grab_focus()
	completed.emit(accepted)
	queue_free()

func _exit_tree() -> void:
	if not _done:
		_done = true
		completed.emit(false)
