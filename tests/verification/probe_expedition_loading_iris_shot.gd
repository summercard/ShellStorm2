extends Node
## 单跑渲染截图探针：远征读条（黑白兔子版）+ 光圈收拢/展开的实际画面证据。
## 必须用**带窗口**的方式运行（headless 无渲染）：
##   GODOT --path . --scene res://tests/verification/probe_expedition_loading_iris_shot.tscn --resolution 1280x720
## 产物落在项目根 _scratch_logs/loading_iris_shot_*.png。

const LOADING_SCENE := "res://scenes/ExpeditionLoadingScreen.tscn"
const OUT_DIR := "res://_scratch_logs"
const STEM := "loading_iris_shot"

var _screen: CanvasLayer


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	_ensure_out_dir()
	var packed := load(LOADING_SCENE) as PackedScene
	_screen = packed.instantiate() as CanvasLayer
	add_child(_screen)
	# 读条总时长 1.35s：先抓两帧间隔足够长的画面，用腿/手臂位置差验证剪影确实在跑动。
	await _wait(0.22)
	await _shot("01a_loading_t022")
	await _wait(0.60)
	await _shot("01b_loading_t082")
	await _wait(0.13)
	await _shot("01c_loading_t095")
	# 冻住读取界面自身推进（避免它在 1.35s 处 change_scene 把探针场景换掉）。
	_screen.set("_advanced", true)

	# —— 收拢：黑圈从四边往中心合 ——
	IrisTransition.clear_now()
	await _shot("02_before_close")
	IrisTransition.iris_close(0.7)
	await _wait(0.32)
	await _shot("03_close_mid")
	await _wait(0.45)
	await _shot("04_closed")

	# —— 展开：黑圈从中心往四边退 ——
	IrisTransition.iris_open(0.7)
	await _wait(0.32)
	await _shot("05_open_mid")
	await _wait(0.45)
	await _shot("06_open_done")

	# —— 亮底演示：黑圈压在亮画面上才看得清"像动画片一样"的观感 ——
	# 真实流程里收拢时压在亮色全息城市、展开时压在关卡画面上，
	# 这里用一块暖色亮底 + 几个白块模拟"有画面的场景"。
	_screen.visible = false
	_build_bright_stage()
	await _wait(0.1)
	await _shot("07_bright_before")
	IrisTransition.iris_close(0.72)
	await _wait(0.30)
	await _shot("08_bright_close_mid")
	await _wait(0.48)
	await _shot("09_bright_closed")
	IrisTransition.iris_open(0.72)
	await _wait(0.30)
	await _shot("10_bright_open_mid")
	await _wait(0.48)
	await _shot("11_bright_open_done")

	print("SHOT_DONE %s" % OUT_DIR)
	get_tree().quit(0)


func _build_bright_stage() -> void:
	var layer := CanvasLayer.new()
	layer.name = "BrightStage"
	layer.layer = 100
	add_child(layer)
	var base := ColorRect.new()
	base.color = Color(0.94, 0.52, 0.16, 1.0)
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(base)
	var band := ColorRect.new()
	band.color = Color(0.16, 0.42, 0.62, 1.0)
	band.set_anchors_preset(Control.PRESET_CENTER)
	band.offset_left = -420.0
	band.offset_top = -70.0
	band.offset_right = 420.0
	band.offset_bottom = 70.0
	layer.add_child(band)
	var caption := Label.new()
	caption.text = "关卡画面"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 46)
	caption.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(caption)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null:
		printerr("SHOT_FAIL %s: 无渲染目标" % name)
		return
	var path := "%s/%s_%s.png" % [OUT_DIR, STEM, name]
	var err := image.save_png(path)
	if err != OK:
		printerr("SHOT_FAIL %s: %s" % [path, error_string(err)])
	else:
		print("SHOT_OK %s" % path)


func _ensure_out_dir() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(OUT_DIR)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
