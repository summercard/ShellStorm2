extends Node
## 真实Forward+截图：高档画面设置页与0键性能面板。

const OUTPUT_DIR := "res://outputs/verification"
const PAUSE_MAIN_PATH := OUTPUT_DIR + "/pause_menu_profile_reset.png"
const RESET_CONFIRM_PATH := OUTPUT_DIR + "/pause_menu_profile_reset_confirm.png"
const SETTINGS_PATH := OUTPUT_DIR + "/graphics_settings_high_end.png"
const PERFORMANCE_PATH := OUTPUT_DIR + "/performance_overlay_key0.png"
const RANGE_SCENE: PackedScene = preload("res://scenes/TrainingRange3D.tscn")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var failures: Array[String] = []
	var range := RANGE_SCENE.instantiate() as TrainingRange3D
	range.test_mode = true
	add_child(range)
	await _settle()
	var pause := range.get_node("HUD/PauseOverlay") as PauseMenu3D
	pause.set_paused(true)
	await _settle()
	_capture(PAUSE_MAIN_PATH, "带存档复位的ESC暂停主页截图失败", failures)
	pause.call("_request_game_save_reset")
	await _settle()
	_capture(RESET_CONFIRM_PATH, "存档复位二次确认截图失败", failures)
	(pause.get_node("ResetGameSaveDialog") as ConfirmationDialog).hide()
	pause.call("_show_graphics_page")
	await _settle()
	_capture(SETTINGS_PATH, "高档画面设置页截图失败", failures)
	pause.set_paused(false)
	var overlay := pause.get_node("PerformanceOverlay") as PerformanceOverlay
	var event := InputEventKey.new()
	event.keycode = KEY_0
	event.pressed = true
	overlay.call("_unhandled_input", event)
	await _settle()
	_capture(PERFORMANCE_PATH, "0键性能面板截图失败", failures)
	if failures.is_empty():
		print("GRAPHICS_SETTINGS_VISUAL_OK: high-end settings and key-0 performance previews saved")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _settle() -> void:
	await get_tree().process_frame
	RenderingServer.force_draw()
	await RenderingServer.frame_post_draw
	await get_tree().create_timer(0.20, true, false, true).timeout


func _capture(path: String, failure: String, failures: Array[String]) -> void:
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(path) != OK:
		failures.append(failure)
