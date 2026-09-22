extends Node
## 探针：手柄在设施子界面（CanvasLayer 菜单）里的完整通路。
## **必须带窗口跑**（--headless 下 GUI 的「输入派发」不工作：grab_focus() 能成功，
## 但合成事件不会走到按钮的 pressed，见下方 _note_headless）。
##
## 覆盖两段：
##   1) 方向键挪焦点：ui_up 把焦点从默认焦点挪到相邻可聚焦控件；
##   2) 确认键触发焦点：手柄 A / 物理回车 命中当前焦点按钮 → 菜单自行 queue_free()。
##
## 事件形状与真机一致（Input 缓冲 → flush → Viewport 派发）；
## 其中「物理回车」必须用 physical_keycode —— ui_accept 绑的是 physical_keycode，
## 只填 keycode 不会命中（已实测：keycode Enter 命中 0，physical Enter 命中 1）。

const WATCHDOG_SECONDS := 30.0
const MULTI_BUTTON_MENU_PATH := "res://scenes/WorkshopMenu.tscn"
const MENU_PATH := "res://scenes/RogueMapSelectMenu.tscn"

func _note_headless() -> void:
	## 记录口径：headless 下只能验「焦点锚点是否建立」（见 probe_submenu_gamepad_focus），
	## 不能验「确认键是否触发按钮」——后者必须带窗口。
	pass


func _ready() -> void:
	_watchdog()
	InputSettings.set_value("gamepad_enabled", true, false)
	InputSettings.set_value("device_mode", InputSettings.DEVICE_MODE_AUTO, false)
	print("=== 子界面手柄通路探针（窗口模式）===")
	await _probe_direction()
	await _probe_accept("手柄A(物理按键)")
	await _probe_accept("回车(物理键)")
	print("=== 探针结束 ===")
	await _settle()
	await _settle()
	get_tree().quit(0)


func _watchdog() -> void:
	await get_tree().create_timer(WATCHDOG_SECONDS).timeout
	push_error("探针超时未结束")
	get_tree().quit(2)


## 方向导航：ui_up 应把焦点从默认焦点挪到另一个可聚焦控件。
func _probe_direction() -> void:
	var menu := (load(MULTI_BUTTON_MENU_PATH) as PackedScene).instantiate()
	add_child(menu)
	await _settle()
	var before_ctrl := get_viewport().gui_get_focus_owner()
	if before_ctrl == null:
		print("[方向] 无焦点（默认焦点未建立）")
		menu.queue_free()
		await _settle()
		return
	var before_name := String(before_ctrl.name)

	var press := InputEventAction.new()
	press.action = "ui_up"
	press.pressed = true
	press.strength = 1.0
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	await _settle()

	var after_ctrl := get_viewport().gui_get_focus_owner()
	var after_name := "<无>" if after_ctrl == null else String(after_ctrl.name)
	print("[方向] ui_up: %s → %s   焦点移动=%s" % [
		before_name, after_name, str(after_name != before_name)])

	var release := InputEventAction.new()
	release.action = "ui_up"
	release.pressed = false
	release.strength = 0.0
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	menu.queue_free()
	await _settle()


## 确认键：ui_accept 应命中当前焦点按钮。
## RogueMapSelectMenu 的 CloseButton → queue_free()，因此「菜单已销毁」就是命中证据。
## 同时在按钮上挂一个计数，把「命中」与「菜单自行销毁」分开观察，避免再出现
## 「按钮其实按到了、只是销毁判定写错」这类假阴性。
func _probe_accept(variant: String) -> void:
	var menu := (load(MENU_PATH) as PackedScene).instantiate()
	add_child(menu)
	await _settle()

	var focus_ctrl := get_viewport().gui_get_focus_owner() as Button
	if focus_ctrl == null:
		print("[确认/%s] 无焦点" % variant)
		menu.queue_free()
		await _settle()
		return
	var focus_name := String(focus_ctrl.name)

	var hits := [0]
	var on_pressed := func() -> void: hits[0] += 1
	focus_ctrl.pressed.connect(on_pressed)

	if variant.begins_with("手柄"):
		var down := InputEventJoypadButton.new()
		down.device = 0
		down.button_index = JOY_BUTTON_A
		down.pressed = true
		down.pressure = 1.0
		Input.parse_input_event(down)
		Input.flush_buffered_events()
		await _settle()
		var up := InputEventJoypadButton.new()
		up.device = 0
		up.button_index = JOY_BUTTON_A
		up.pressed = false
		up.pressure = 0.0
		Input.parse_input_event(up)
		Input.flush_buffered_events()
	else:
		var key_down := InputEventKey.new()
		key_down.physical_keycode = KEY_ENTER
		key_down.pressed = true
		Input.parse_input_event(key_down)
		Input.flush_buffered_events()
		await _settle()
		var key_up := InputEventKey.new()
		key_up.physical_keycode = KEY_ENTER
		key_up.pressed = false
		Input.parse_input_event(key_up)
		Input.flush_buffered_events()

	await _settle()
	await _settle()
	print("[确认/%s] 按下前焦点=%s  命中次数=%d  菜单已销毁=%s" % [
		variant, focus_name, hits[0], str(not is_instance_valid(menu))])

	if is_instance_valid(menu):
		menu.queue_free()
		await _settle()


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
