class_name PauseMenu3D
extends Control
## 三张 3D 游戏地图共用的暂停覆盖层。只有本节点在暂停时继续接收输入；
## 世界、AI、射弹和计时器继续遵守 Pausable，不会暗中推进。

signal pause_changed(paused: bool)
signal return_to_base_requested()
signal return_to_base_resolved(result: Dictionary)
signal game_save_reset_requested()
signal game_save_reset_resolved(result: Dictionary)

const ReturnAction = preload("res://src/ui/unstuck/ReturnToBaseAction.gd")

const AA_MODES := ["off", "fxaa", "msaa_2x", "msaa_4x", "msaa_8x", "taa"]
const AA_LABELS := ["关闭", "FXAA（快速）", "MSAA 2×", "MSAA 4×", "MSAA 8×", "TAA（高档推荐）"]
const SHADOW_MODES := ["low", "medium", "high"]
const SHADOW_LABELS := ["低 · 1024", "中 · 2048", "高 · 4096（当前）"]
const INDIRECT_DIFFUSE_MODES := ["low", "medium", "high"]
const INDIRECT_DIFFUSE_LABELS := ["低 · 近域", "中 · 平衡", "高 · 完整"]
const DEVICE_MODE_LABELS := ["自动跟随", "锁定键鼠", "锁定手柄"]

@onready var resume_button: Button = $Center/Panel/Margin/MainPage/ResumeButton
@onready var graphics_button: Button = $Center/Panel/Margin/MainPage/GraphicsButton
@onready var return_to_base_button: Button = $Center/Panel/Margin/MainPage/ReturnToBaseButton
@onready var return_to_base_hint: Label = $Center/Panel/Margin/MainPage/ReturnToBaseHint
@onready var reset_game_save_button: Button = $Center/Panel/Margin/MainPage/ResetGameSaveButton
@onready var reset_game_save_hint: Label = $Center/Panel/Margin/MainPage/ResetGameSaveHint
@onready var reset_game_save_dialog: ConfirmationDialog = $ResetGameSaveDialog
@onready var main_page: VBoxContainer = $Center/Panel/Margin/MainPage
@onready var graphics_page: VBoxContainer = $Center/Panel/Margin/GraphicsPage
@onready var controls_button: Button = $Center/Panel/Margin/MainPage/ControlsButton
@onready var controls_page: VBoxContainer = $Center/Panel/Margin/ControlsPage
@onready var device_status_label: Label = $Center/Panel/Margin/ControlsPage/Header/DeviceStatusLabel
@onready var device_mode_option: OptionButton = $Center/Panel/Margin/ControlsPage/DeviceRow/DeviceModeOption
@onready var gamepad_enabled_toggle: CheckButton = $Center/Panel/Margin/ControlsPage/GamepadEnabled
@onready var move_deadzone_slider: HSlider = $Center/Panel/Margin/ControlsPage/MoveDeadzoneRow/MoveDeadzoneSlider
@onready var move_deadzone_value: Label = $Center/Panel/Margin/ControlsPage/MoveDeadzoneRow/MoveDeadzoneValue
@onready var aim_deadzone_slider: HSlider = $Center/Panel/Margin/ControlsPage/AimDeadzoneRow/AimDeadzoneSlider
@onready var aim_deadzone_value: Label = $Center/Panel/Margin/ControlsPage/AimDeadzoneRow/AimDeadzoneValue
@onready var aim_smoothing_slider: HSlider = $Center/Panel/Margin/ControlsPage/AimSmoothingRow/AimSmoothingSlider
@onready var aim_smoothing_value: Label = $Center/Panel/Margin/ControlsPage/AimSmoothingRow/AimSmoothingValue
@onready var left_stick_aim_toggle: CheckButton = $Center/Panel/Margin/ControlsPage/LeftStickAim
@onready var vibration_toggle: CheckButton = $Center/Panel/Margin/ControlsPage/Vibration
@onready var controls_back_button: Button = $Center/Panel/Margin/ControlsPage/Footer/BackButton
@onready var controls_status_label: Label = $Center/Panel/Margin/ControlsPage/Footer/Status
@onready var renderer_label: Label = $Center/Panel/Margin/GraphicsPage/Header/RendererLabel
@onready var aa_option: OptionButton = $Center/Panel/Margin/GraphicsPage/AASection/AAOption
@onready var shadow_option: OptionButton = $Center/Panel/Margin/GraphicsPage/Scroll/Grid/Shadows/ShadowOption
@onready var indirect_diffuse_option: OptionButton = $Center/Panel/Margin/GraphicsPage/Scroll/Grid/IndirectDiffuse/QualityOption
@onready var high_defaults_button: Button = $Center/Panel/Margin/GraphicsPage/PresetRow/HighDefaultsButton
@onready var back_button: Button = $Center/Panel/Margin/GraphicsPage/Footer/BackButton
@onready var status_label: Label = $Center/Panel/Margin/GraphicsPage/Footer/Status
@onready var dim: ColorRect = $Dim
@onready var center: CenterContainer = $Center

var _toggle_nodes: Dictionary = {}
var _syncing_controls := false
var _reset_in_progress := false
var _main_entry_request_id := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = true
	add_to_group("pause_input_guard")
	if Global != null and not Global.game_paused.is_connected(_on_global_pause_changed):
		Global.game_paused.connect(_on_global_pause_changed)
	_apply_pause_visual(Global != null and Global.has_pause_reason("manual"))
	resume_button.pressed.connect(resume_game)
	graphics_button.pressed.connect(_show_graphics_page)
	controls_button.pressed.connect(_show_controls_page)
	return_to_base_button.pressed.connect(_request_return_to_base)
	reset_game_save_button.pressed.connect(_request_game_save_reset)
	reset_game_save_dialog.confirmed.connect(_confirm_game_save_reset)
	back_button.pressed.connect(_show_main_page)
	controls_back_button.pressed.connect(_show_main_page)
	high_defaults_button.pressed.connect(_restore_high_defaults)
	_setup_graphics_controls()
	_setup_input_controls()
	UIStyleFactory.apply_tactical_tree(self)


func try_consume_pause_input() -> bool:
	if Global != null and Global.has_pause_reason("manual"):
		if reset_game_save_dialog.visible:
			reset_game_save_dialog.hide()
			reset_game_save_button.grab_focus()
			return true
		if graphics_page.visible or controls_page.visible:
			_show_main_page()
			return true
		return false
	var game_root := get_parent().get_parent()
	return (
		game_root != null
		and game_root.has_method("try_close_modal_for_pause")
		and bool(game_root.call("try_close_modal_for_pause"))
	)


func set_paused(paused: bool) -> void:
	if Global != null:
		if paused:
			Global.acquire_pause("manual")
		else:
			Global.release_pause("manual")
	else:
		get_tree().paused = paused
		_on_global_pause_changed(paused)


func resume_game() -> void:
	set_paused(false)


func is_pause_open() -> bool:
	return center.visible and Global != null and Global.has_pause_reason("manual")


func _on_global_pause_changed(_paused: bool) -> void:
	var manual_paused := Global != null and Global.has_pause_reason("manual")
	_apply_pause_visual(manual_paused)
	if manual_paused:
		_show_main_page()
		_refresh_return_to_base_action()
		resume_button.grab_focus()
	else:
		reset_game_save_dialog.hide()
	pause_changed.emit(manual_paused)


func _apply_pause_visual(paused: bool) -> void:
	dim.visible = paused
	center.visible = paused
	mouse_filter = Control.MOUSE_FILTER_STOP if paused else Control.MOUSE_FILTER_IGNORE


func _setup_graphics_controls() -> void:
	_toggle_nodes = {
		"bloom": $Center/Panel/Margin/GraphicsPage/Scroll/Grid/Bloom,
		"ssao": $Center/Panel/Margin/GraphicsPage/Scroll/Grid/SSAO,
		"ssil": $Center/Panel/Margin/GraphicsPage/Scroll/Grid/SSIL,
		"ssr": $Center/Panel/Margin/GraphicsPage/Scroll/Grid/SSR,
		"volumetric_fog": $Center/Panel/Margin/GraphicsPage/Scroll/Grid/VolumetricFog,
		"distance_fog": $Center/Panel/Margin/GraphicsPage/Scroll/Grid/DistanceFog,
		"color_grading": $Center/Panel/Margin/GraphicsPage/Scroll/Grid/ColorGrading,
		"scene_particles": $Center/Panel/Margin/GraphicsPage/Scroll/Grid/SceneParticles,
	}
	for index in AA_LABELS.size():
		aa_option.add_item(AA_LABELS[index], index)
	aa_option.item_selected.connect(_on_aa_selected)
	for index in SHADOW_LABELS.size():
		shadow_option.add_item(SHADOW_LABELS[index], index)
	shadow_option.item_selected.connect(_on_shadow_quality_selected)
	for index in INDIRECT_DIFFUSE_LABELS.size():
		indirect_diffuse_option.add_item(INDIRECT_DIFFUSE_LABELS[index], index)
	indirect_diffuse_option.item_selected.connect(_on_indirect_diffuse_quality_selected)
	for key in _toggle_nodes.keys():
		(_toggle_nodes[key] as CheckButton).toggled.connect(_on_effect_toggled.bind(str(key)))
	if not GraphicsSettingsManager.settings_changed.is_connected(_on_graphics_settings_changed):
		GraphicsSettingsManager.settings_changed.connect(_on_graphics_settings_changed)
	_sync_graphics_controls()


func _show_graphics_page() -> void:
	_hide_sub_pages()
	main_page.visible = false
	graphics_page.visible = true
	renderer_label.text = GraphicsSettingsManager.get_renderer_summary()
	_sync_graphics_controls()
	aa_option.grab_focus()


func _show_main_page() -> void:
	_hide_sub_pages()
	main_page.visible = true
	_refresh_return_to_base_action()
	if center.visible:
		graphics_button.grab_focus()


func _show_controls_page() -> void:
	_hide_sub_pages()
	main_page.visible = false
	controls_page.visible = true
	_sync_input_controls()
	_refresh_device_status()
	device_mode_option.grab_focus()


func _hide_sub_pages() -> void:
	graphics_page.visible = false
	controls_page.visible = false


## 页头状态行：只描述「现在是谁在操作」，不参与任何输入判定。
func _refresh_device_status() -> void:
	var device := InputDevice.get_active_device()
	var label := "键盘与鼠标"
	if device == InputDevice.DEVICE_GAMEPAD:
		var pad_name := InputDevice.get_active_gamepad_name()
		label = "手柄" if pad_name.is_empty() else "手柄 · %s" % pad_name
	elif device == InputDevice.DEVICE_TOUCH:
		label = "触屏"
	var suffix := "" if InputDevice.has_connected_gamepad() else "（未检测到手柄）"
	device_status_label.text = "当前输入：%s%s" % [label, suffix]
	device_status_label.modulate = (
		Color(0.45, 0.9, 0.68) if device == InputDevice.DEVICE_GAMEPAD else Color(0.58, 0.76, 0.84)
	)


func _setup_input_controls() -> void:
	for index in DEVICE_MODE_LABELS.size():
		device_mode_option.add_item(DEVICE_MODE_LABELS[index], index)
	device_mode_option.item_selected.connect(_on_device_mode_selected)
	gamepad_enabled_toggle.toggled.connect(_on_gamepad_enabled_toggled)
	left_stick_aim_toggle.toggled.connect(_on_left_stick_aim_toggled)
	vibration_toggle.toggled.connect(_on_vibration_toggled)
	move_deadzone_slider.value_changed.connect(
		_on_deadzone_changed.bind("gamepad_move_deadzone")
	)
	aim_deadzone_slider.value_changed.connect(
		_on_deadzone_changed.bind("gamepad_aim_deadzone")
	)
	aim_smoothing_slider.value_changed.connect(_on_aim_smoothing_changed)
	if not InputSettings.settings_changed.is_connected(_on_input_settings_changed):
		InputSettings.settings_changed.connect(_on_input_settings_changed)
	if not InputDevice.active_device_changed.is_connected(_on_active_device_changed):
		InputDevice.active_device_changed.connect(_on_active_device_changed)
	_sync_input_controls()


func _on_device_mode_selected(index: int) -> void:
	if _syncing_controls or index < 0 or index >= InputSettings.DEVICE_MODES.size():
		return
	var mode: String = str(InputSettings.DEVICE_MODES[index])
	InputSettings.set_value("device_mode", mode)
	if mode == InputSettings.DEVICE_MODE_GAMEPAD and not InputDevice.has_connected_gamepad():
		controls_status_label.text = "已锁定手柄，但当前未检测到手柄，暂时回落键鼠"
		controls_status_label.modulate = Color(1.0, 0.72, 0.42)
	else:
		controls_status_label.text = "操控方式已切换为%s · 设置已保存" % DEVICE_MODE_LABELS[index]
		controls_status_label.modulate = Color(0.45, 0.9, 0.68)
	_refresh_device_status()


func _on_gamepad_enabled_toggled(enabled: bool) -> void:
	if _syncing_controls:
		return
	InputSettings.set_value("gamepad_enabled", enabled)
	controls_status_label.text = "手柄操控已%s · 设置已保存" % ("启用" if enabled else "关闭")
	controls_status_label.modulate = Color(0.45, 0.9, 0.68)
	_refresh_device_status()


func _on_left_stick_aim_toggled(enabled: bool) -> void:
	if _syncing_controls:
		return
	InputSettings.set_value("gamepad_left_stick_aim", enabled)
	controls_status_label.text = "左摇杆同控朝向已%s · 设置已保存" % ("开启" if enabled else "关闭")
	controls_status_label.modulate = Color(0.45, 0.9, 0.68)


func _on_vibration_toggled(enabled: bool) -> void:
	if _syncing_controls:
		return
	InputSettings.set_value("gamepad_vibration", enabled)
	if not enabled and GamepadInput != null:
		GamepadInput.stop_rumble()
	controls_status_label.text = "手柄震动已%s · 设置已保存" % ("开启" if enabled else "关闭")
	controls_status_label.modulate = Color(0.45, 0.9, 0.68)


func _on_deadzone_changed(value: float, key: String) -> void:
	if _syncing_controls:
		return
	InputSettings.set_value(key, value)
	var formatted := "%.2f" % value
	if key == "gamepad_move_deadzone":
		move_deadzone_value.text = formatted
	else:
		aim_deadzone_value.text = formatted
	controls_status_label.text = "摇杆死区已调整为 %s · 设置已保存" % formatted
	controls_status_label.modulate = Color(0.45, 0.9, 0.68)


func _on_aim_smoothing_changed(value: float) -> void:
	if _syncing_controls:
		return
	InputSettings.set_value("gamepad_aim_smoothing", value)
	aim_smoothing_value.text = "%.2f" % value
	controls_status_label.text = "瞄准平滑已调整为 %.2f · 设置已保存" % value
	controls_status_label.modulate = Color(0.45, 0.9, 0.68)


func _on_input_settings_changed(_settings: Dictionary) -> void:
	_sync_input_controls()
	_refresh_device_status()


func _on_active_device_changed(_device: String) -> void:
	_refresh_device_status()


func _sync_input_controls() -> void:
	_syncing_controls = true
	var settings := InputSettings.get_settings_snapshot()
	var mode_index := InputSettings.DEVICE_MODES.find(
		str(settings.get("device_mode", InputSettings.DEVICE_MODE_AUTO))
	)
	device_mode_option.select(maxi(0, mode_index))
	gamepad_enabled_toggle.button_pressed = bool(settings.get("gamepad_enabled", true))
	left_stick_aim_toggle.button_pressed = bool(settings.get("gamepad_left_stick_aim", true))
	vibration_toggle.button_pressed = bool(settings.get("gamepad_vibration", true))
	var move_deadzone := float(settings.get("gamepad_move_deadzone", 0.20))
	var aim_deadzone := float(settings.get("gamepad_aim_deadzone", 0.20))
	var smoothing := float(settings.get("gamepad_aim_smoothing", 0.35))
	move_deadzone_slider.value = move_deadzone
	aim_deadzone_slider.value = aim_deadzone
	aim_smoothing_slider.value = smoothing
	move_deadzone_value.text = "%.2f" % move_deadzone
	aim_deadzone_value.text = "%.2f" % aim_deadzone
	aim_smoothing_value.text = "%.2f" % smoothing
	_syncing_controls = false


func get_return_to_base_availability() -> Dictionary:
	return ReturnAction.get_availability(_get_game_root())


func _request_return_to_base() -> void:
	return_to_base_requested.emit()
	var result := ReturnAction.request(_get_game_root())
	return_to_base_resolved.emit(result)
	if bool(result.get("success", false)):
		resume_game()
		return
	return_to_base_hint.text = str(result.get("reason", "返回基地中心失败"))
	return_to_base_hint.modulate = Color(1.0, 0.48, 0.34)


func _request_game_save_reset() -> void:
	if _reset_in_progress:
		return
	game_save_reset_requested.emit()
	reset_game_save_dialog.dialog_text = (
		"这会清除基地、蓝图、物品、角色外观、世界时间以及当前行动进度。\n"
		+ "画面设置会保留。复位后将从全新游戏重新开始。"
	)
	reset_game_save_dialog.popup_centered(Vector2i(590, 240))


func _confirm_game_save_reset() -> void:
	if _reset_in_progress:
		return
	_reset_in_progress = true
	reset_game_save_button.disabled = true
	var result: Dictionary = (
		BaseManager.reset_game_save()
		if BaseManager != null
		else {"success": false, "reason": "存档服务不可用"}
	)
	game_save_reset_resolved.emit((result as Dictionary).duplicate(true))
	if not bool((result as Dictionary).get("success", false)):
		_reset_in_progress = false
		reset_game_save_button.disabled = false
		reset_game_save_hint.text = str((result as Dictionary).get("reason", "游戏存档复位失败"))
		reset_game_save_hint.modulate = Color(1.0, 0.40, 0.30)
		return
	reset_game_save_hint.text = "存档已复位，正在重新开始……"
	reset_game_save_hint.modulate = Color(0.44, 0.94, 0.72)
	_reset_runtime_singletons_for_new_profile()
	_main_entry_request_id = GameEntryFlow.request_main_entry(GameEntryFlow.REASON_NEW_GAME_RESET)
	call_deferred("_restart_from_main_scene")


func _reset_runtime_singletons_for_new_profile() -> void:
	if GameTimeManager != null:
		GameTimeManager.set_elapsed_game_seconds(0.0, false)
	if LevelSelect != null:
		LevelSelect.reset()
	if FateCardGameBridge != null:
		FateCardGameBridge.reset_run_state()
	if GameplaySpatialRegistry3D != null:
		GameplaySpatialRegistry3D.clear_runtime_records()
	if Global != null:
		Global.start_game()


func _restart_from_main_scene() -> void:
	var main_scene_path := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	var error: Error = (
		get_tree().change_scene_to_file(main_scene_path)
		if not main_scene_path.is_empty()
		else get_tree().reload_current_scene()
	)
	if error == OK:
		return
	if _main_entry_request_id > 0:
		GameEntryFlow.cancel_request(_main_entry_request_id)
		_main_entry_request_id = -1
	_reset_in_progress = false
	reset_game_save_button.disabled = false
	reset_game_save_hint.text = "存档已复位，但主场景重新载入失败：%s" % error_string(error)
	reset_game_save_hint.modulate = Color(1.0, 0.40, 0.30)


func _refresh_return_to_base_action() -> void:
	if return_to_base_button == null or return_to_base_hint == null:
		return
	var availability := get_return_to_base_availability()
	var available := bool(availability.get("available", false))
	return_to_base_button.disabled = not available
	return_to_base_button.text = "返回基地中心" if available else "返回基地中心（不可用）"
	return_to_base_hint.text = str(availability.get("reason", ""))
	return_to_base_hint.modulate = Color(0.48, 0.84, 0.92) if available else Color(0.70, 0.58, 0.48)


func _get_game_root() -> Node:
	var hud := get_parent()
	return hud.get_parent() if hud != null else null


func _restore_high_defaults() -> void:
	GraphicsSettingsManager.apply_high_quality_defaults()
	status_label.text = "高档默认已恢复 · 设置已保存"


func _on_aa_selected(index: int) -> void:
	if _syncing_controls or index < 0 or index >= AA_MODES.size():
		return
	GraphicsSettingsManager.set_value("anti_aliasing", AA_MODES[index])
	status_label.text = "抗锯齿已切换为 %s · 设置已保存" % AA_LABELS[index]


func _on_effect_toggled(enabled: bool, key: String) -> void:
	if _syncing_controls:
		return
	GraphicsSettingsManager.set_value(key, enabled)
	status_label.text = "%s · 设置已保存" % ("效果已开启" if enabled else "效果已关闭")


func _on_shadow_quality_selected(index: int) -> void:
	if _syncing_controls or index < 0 or index >= SHADOW_MODES.size():
		return
	GraphicsSettingsManager.set_value("shadow_quality", SHADOW_MODES[index])
	status_label.text = "动态阴影已切换为%s · 投影功能保持完整" % SHADOW_LABELS[index]


func _on_indirect_diffuse_quality_selected(index: int) -> void:
	if _syncing_controls or index < 0 or index >= INDIRECT_DIFFUSE_MODES.size():
		return
	GraphicsSettingsManager.set_value(
		"indirect_diffuse_quality", INDIRECT_DIFFUSE_MODES[index]
	)
	status_label.text = "太阳间接漫反射已切换为%s · 功能保持开启" % INDIRECT_DIFFUSE_LABELS[index]


func _on_graphics_settings_changed(_settings: Dictionary) -> void:
	_sync_graphics_controls()


func _sync_graphics_controls() -> void:
	_syncing_controls = true
	var settings := GraphicsSettingsManager.get_settings_snapshot()
	var aa_index := AA_MODES.find(str(settings.get("anti_aliasing", "taa")))
	aa_option.select(maxi(0, aa_index))
	var shadow_index := SHADOW_MODES.find(str(settings.get("shadow_quality", "high")))
	shadow_option.select(maxi(0, shadow_index))
	var indirect_index := INDIRECT_DIFFUSE_MODES.find(
		str(settings.get("indirect_diffuse_quality", "high"))
	)
	indirect_diffuse_option.select(maxi(0, indirect_index))
	for key in _toggle_nodes.keys():
		(_toggle_nodes[key] as CheckButton).button_pressed = bool(settings.get(key, true))
	_syncing_controls = false
