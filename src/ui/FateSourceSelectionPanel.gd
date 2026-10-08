extends Window

signal completed(result: Dictionary)
var _finished := false

func _ready() -> void:
	name = "FateSourceSelectionPanel"
	process_mode = Node.PROCESS_MODE_ALWAYS
	transient = true
	exclusive = true
	unresizable = true
	close_requested.connect(cancel)

func open_choices(heading: String, entries: Array[Dictionary]) -> void:
	title = heading
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var box := VBoxContainer.new()
	margin.add_child(box)
	var hint := Label.new()
	hint.text = heading
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var choices := VBoxContainer.new()
	choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(choices)
	for entry in entries:
		var button := Button.new()
		button.text = str(entry.get("label", "来源"))
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size.y = 48
		button.set_meta("fate_source", entry.get("source"))
		button.pressed.connect(func() -> void: _finish({"success": true, "entry": entry}))
		choices.add_child(button)
	var back := Button.new()
	back.name = "Cancel"
	back.text = "取消 · 保留卡片"
	back.pressed.connect(cancel)
	box.add_child(back)
	UIStyleFactory.apply_tactical_tree(margin)
	popup_centered(Vector2i(560, 360))
	back.grab_focus()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		cancel()

func cancel() -> void:
	_finish({"success": false, "reason": "source_selection_cancelled", "message": "已取消来源选择；卡片保留"})

func _finish(result: Dictionary) -> void:
	if _finished:
		return
	_finished = true
	hide()
	completed.emit(result)
