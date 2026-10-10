extends Node

const PANEL_SCRIPT := "res://src/ui/FateSourceSelectionPanel.gd"
var _failed := 0
var _dispatching := false
var _signal_count := 0
var _panel: Window
var _case := ""

func _check(ok: bool, label: String) -> void:
	print(("WINDOW_INPUT_OK " if ok else "WINDOW_INPUT_FAIL "), _case, " | ", label)
	if not ok:
		_failed += 1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(30.0, true).timeout.connect(_watchdog)
	await get_tree().process_frame
	for case_name in ["escape", "source_mouse", "source_enter", "cancel_mouse", "window_close", "repeat_cancel", "host_exit", "icon_escape"]:
		_case = case_name
		_signal_count = 0
		var entries: Array[Dictionary] = [{"source": null, "supported": true, "label": "测试来源"}]
		if case_name == "icon_escape":
			entries[0]["icon_item"] = ItemRegistry.get_instance().get_item("weapon_sprinkler").duplicate(true)
			entries[0]["title"] = "花洒机枪"
		var host := Node.new()
		add_child(host)
		call_deferred("_exercise_case", host)
		var result: Dictionary = await FateCardGameBridge._choose_entry("输入生命周期回归", entries, host, case_name)
		_check(_signal_count == 1, "完成信号恰好一次")
		_check(not _dispatching, "Bridge await 在输入派发返回后恢复")
		var expects_success: bool = case_name in ["source_mouse", "source_enter"]
		_check(bool(result.get("success", false)) == expects_success, "选择或取消结果符合契约")
		_check(not FateCardGameBridge._source_selection_busy, "来源选择 busy 已复位")
		_check(not get_tree().paused, "原始暂停状态已恢复")
		if is_instance_valid(host):
			host.queue_free()
		await get_tree().process_frame
		_check(FateCardGameBridge.get_node_or_null("FateSourceSelectionPanel") == null, "Window 已清理且无残留")
	print("PROBE_FATE_WINDOW_INPUT_%s failed=%d" % ["OK" if _failed == 0 else "FAILED", _failed])
	get_tree().quit(0 if _failed == 0 else 1)

func _exercise_case(host: Node) -> void:
	_panel = FateCardGameBridge.get_node_or_null("FateSourceSelectionPanel") as Window
	_check(_panel != null and _panel.is_inside_tree(), "输入前 Window 在树内")
	if _panel == null:
		get_tree().quit(1)
		return
	_panel.completed.connect(_on_completed)
	await get_tree().process_frame
	await get_tree().process_frame
	var choice := _panel.find_child("TextChoice", true, false) as Button
	var cancel_button := _panel.find_child("Cancel", true, false) as Button
	_dispatching = true
	match _case:
		"escape", "icon_escape":
			_send_key(KEY_ESCAPE)
		"source_mouse", "source_enter":
			_check(choice != null, "来源按钮存在")
			if choice != null:
				choice.pressed.emit()
		"cancel_mouse":
			_check(cancel_button != null, "取消按钮存在")
			if cancel_button != null:
				cancel_button.pressed.emit()
		"window_close":
			_panel.close_requested.emit()
		"repeat_cancel":
			_send_key(KEY_ESCAPE)
			_panel.cancel()
			_panel.close_requested.emit()
		"host_exit":
			remove_child(host)
			host.queue_free()
	_dispatching = false
	_check(_signal_count == 0, "输入回调返回前不发完成信号")
	_check(is_instance_valid(_panel) and _panel.is_inside_tree(), "当前派发结束时 Window 仍在树内")
	_check(is_instance_valid(_panel) and _panel.visible, "当前派发结束时 Window 尚未同步 hide")

func _on_completed(_result: Dictionary) -> void:
	_signal_count += 1
	_check(not _dispatching, "completed 不在原始输入栈内发射")
	_check(_panel.is_inside_tree(), "完成信号时 Window 仍在树内")
	_check(not _panel.visible, "完成信号前 Window 已隐藏")

func _send_key(key: Key) -> void:
	var pressed := InputEventKey.new()
	pressed.keycode = key
	pressed.physical_keycode = key
	pressed.pressed = true
	_panel.push_input(pressed, true)
	var released := InputEventKey.new()
	released.keycode = key
	released.physical_keycode = key
	released.pressed = false
	_panel.push_input(released, true)

func _send_click(button: Button) -> void:
	_check(button != null, "目标按钮存在")
	if button == null:
		return
	var point := button.get_global_rect().get_center()
	print("WINDOW_INPUT_RECT ", _case, " | rect=", button.get_global_rect(), " visible=", button.is_visible_in_tree(), " mouse_filter=", button.mouse_filter)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	_panel.push_input(motion, true)
	var pressed := InputEventMouseButton.new()
	pressed.button_index = MOUSE_BUTTON_LEFT
	pressed.button_mask = MOUSE_BUTTON_MASK_LEFT
	pressed.position = point
	pressed.global_position = point
	pressed.pressed = true
	_panel.push_input(pressed, true)
	var released := InputEventMouseButton.new()
	released.button_index = MOUSE_BUTTON_LEFT
	released.position = point
	released.global_position = point
	released.pressed = false
	_panel.push_input(released, true)

func _watchdog() -> void:
	push_error("PROBE_FATE_WINDOW_INPUT_TIMEOUT case=" + _case)
	get_tree().quit(1)
