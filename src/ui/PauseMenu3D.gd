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

@onready var resume_button: Button = $Center/Panel/Margin/MainPage/ResumeButton
@onready var graphics_button: Button = $Center/Panel/Margin/MainPage/GraphicsButton
@onready var return_to_base_button: Button = $Center/Panel/Margin/MainPage/ReturnToBaseButton
@onready var return_to_base_hint: Label = $Center/Panel/Margin/MainPage/ReturnToBaseHint
@onready var reset_game_save_button: Button = $Center/Panel/Margin/MainPage/ResetGameSaveButton
@onready var reset_game_save_hint: Label = $Center/Panel/Margin/MainPage/ResetGameSaveHint
@onready var reset_game_save_dialog: ConfirmationDialog = $ResetGameSaveDialog
@onready var main_page: VBoxContainer = $Center/Panel/Margin/MainPage
@onready var graphics_page: VBoxContainer = $Center/Panel/Margin/GraphicsPage
@onready var renderer_label: Label = $Center/Panel/Margin/GraphicsPage/Header/RendererLabel
@onready var aa_option: OptionButton = $Center/Panel/Margin/GraphicsPage/AASection/AAOption
@onready var shadow_option: OptionButton = $Center/Panel/Margin/GraphicsPage/Scroll/Grid/Shadows/ShadowOption
@onready var high_defaults_button: Button = $Center/Panel/Margin/GraphicsPage/PresetRow/HighDefaultsButton
@onready var back_button: Button = $Center/Panel/Margin/GraphicsPage/Footer/BackButton
@onready var status_label: Label = $Center/Panel/Margin/GraphicsPage/Footer/Status
@onready var dim: ColorRect = $Dim
@onready var center: CenterContainer = $Center

var _toggle_nodes: Dictionary = {}
var _syncing_controls := false
var _reset_in_progress := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = true
	add_to_group("pause_input_guard")
	if Global != null and not Global.game_paused.is_connected(_on_global_pause_changed):
		Global.game_paused.connect(_on_global_pause_changed)
	_apply_pause_visual(Global != null and Global.has_pause_reason("manual"))
	resume_button.pressed.connect(resume_game)
	graphics_button.pressed.connect(_show_graphics_page)
	return_to_base_button.pressed.connect(_request_return_to_base)
	reset_game_save_button.pressed.connect(_request_game_save_reset)
	reset_game_save_dialog.confirmed.connect(_confirm_game_save_reset)
	back_button.pressed.connect(_show_main_page)
	high_defaults_button.pressed.connect(_restore_high_defaults)
	_setup_graphics_controls()
	UIStyleFactory.apply_tactical_tree(self)


func try_consume_pause_input() -> bool:
	if Global != null and Global.has_pause_reason("manual"):
		if reset_game_save_dialog.visible:
			reset_game_save_dialog.hide()
			reset_game_save_button.grab_focus()
			return true
		if graphics_page.visible:
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
		"sdfgi": $Center/Panel/Margin/GraphicsPage/Scroll/Grid/SDFGI,
		"volumetric_fog": $Center/Panel/Margin/GraphicsPage/Scroll/Grid/VolumetricFog,
		"distance_fog": $Center/Panel/Margin/GraphicsPage/Scroll/Grid/DistanceFog,
		"color_grading": $Center/Panel/Margin/GraphicsPage/Scroll/Grid/ColorGrading,
	}
	for index in AA_LABELS.size():
		aa_option.add_item(AA_LABELS[index], index)
	aa_option.item_selected.connect(_on_aa_selected)
	for index in SHADOW_LABELS.size():
		shadow_option.add_item(SHADOW_LABELS[index], index)
	shadow_option.item_selected.connect(_on_shadow_quality_selected)
	for key in _toggle_nodes.keys():
		(_toggle_nodes[key] as CheckButton).toggled.connect(_on_effect_toggled.bind(str(key)))
	if not GraphicsSettingsManager.settings_changed.is_connected(_on_graphics_settings_changed):
		GraphicsSettingsManager.settings_changed.connect(_on_graphics_settings_changed)
	_sync_graphics_controls()


func _show_graphics_page() -> void:
	main_page.visible = false
	graphics_page.visible = true
	renderer_label.text = GraphicsSettingsManager.get_renderer_summary()
	_sync_graphics_controls()
	aa_option.grab_focus()


func _show_main_page() -> void:
	graphics_page.visible = false
	main_page.visible = true
	_refresh_return_to_base_action()
	if center.visible:
		graphics_button.grab_focus()


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


func _on_graphics_settings_changed(_settings: Dictionary) -> void:
	_sync_graphics_controls()


func _sync_graphics_controls() -> void:
	_syncing_controls = true
	var settings := GraphicsSettingsManager.get_settings_snapshot()
	var aa_index := AA_MODES.find(str(settings.get("anti_aliasing", "taa")))
	aa_option.select(maxi(0, aa_index))
	var shadow_index := SHADOW_MODES.find(str(settings.get("shadow_quality", "high")))
	shadow_option.select(maxi(0, shadow_index))
	for key in _toggle_nodes.keys():
		(_toggle_nodes[key] as CheckButton).button_pressed = bool(settings.get(key, true))
	_syncing_controls = false
