extends Node
## 真渲染截图探针：逐关灯色（01 灰蓝 / 02 淡黄 / 03 玫红 + 99 兜底金）。
## 必须用**带窗口**的方式运行（headless 无渲染）：
##   GODOT --path . --scene res://tests/verification/probe_loading_lamp_colors_shot.tscn --resolution 1280x720
## 产物落在项目根 _scratch_logs/loading_lamp_*.png。
##
## 只验证颜色，不跑真实资源读取：入树后立刻把 `_resource_warmup_active` 置真，
## 让 `_start_resource_request()` 在守卫处早退，于是兔子舞台与色块正常起、关卡不会被真的装配。

const LOADING_SCENE := "res://scenes/ExpeditionLoadingScreen.tscn"
const OUT_DIR := "res://_scratch_logs"
const STEM := "loading_lamp"
## 截图前等多久：入场淡入 0.28s + 兔子视口首帧 & 色块交错走到可见位置。
const SETTLE_SECONDS := 0.9
const CASES: Array[Array] = [
	["expedition_01", "01_grey_blue"],
	["expedition_02", "02_pale_yellow"],
	["expedition_03", "03_rose"],
	["99", "99_fallback_gold"],
]


func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	_ensure_out_dir()
	for entry in CASES:
		await _capture(str(entry[0]), str(entry[1]))
	print("SHOT_DONE %s" % OUT_DIR)
	get_tree().quit(0)


func _capture(level_id: String, tag: String) -> void:
	GameDesignConfig.pending_expedition_level_id = level_id
	var packed := load(LOADING_SCENE) as PackedScene
	var screen := packed.instantiate() as CanvasLayer
	add_child(screen)
	# 保住视觉、掐掉真实读取：入场淡入照常跑，资源预热在守卫处早退。
	screen.set("_resource_warmup_active", true)
	await _wait(SETTLE_SECONDS)
	await _shot(tag)
	screen.queue_free()
	await _wait(0.15)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null:
		printerr("SHOT_FAIL %s: 无渲染目标" % tag)
		return
	var path := "%s/%s_%s.png" % [OUT_DIR, STEM, tag]
	var err := image.save_png(path)
	if err != OK:
		printerr("SHOT_FAIL %s: %s" % [path, error_string(err)])
	else:
		print("SHOT_OK %s" % path)


func _ensure_out_dir() -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(OUT_DIR)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
