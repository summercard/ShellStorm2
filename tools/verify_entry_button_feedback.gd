extends SceneTree
## 一次性验证：启动页两个按钮的 hover / press 反馈（UIFX 缩放 + 自绘状态）与设置菜单能否拉起。
## 用法：godot --path . -s tools/verify_entry_button_feedback.gd
##
## 视觉用「强制状态」拍照（确定性）：操作系统光标会逐帧覆盖合成的 motion 事件，
## 用真实鼠标截 hover 图会时好时坏，不能当证据。
## 接线用合成信号验证：mouse_entered / button_down 是否真的把 scale 推到 1.014 / 0.988。

const OUT_DIR := "res://outputs"


func _initialize() -> void:
	# 主入口是"一次性冷启动意图"：显式声明，别依赖上一进程残留的状态。
	var flow := root.get_node_or_null("GameEntryFlow")
	if flow != null and flow.has_method("request_main_entry"):
		flow.call("request_main_entry")
	var packed := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var world := packed.instantiate()
	root.add_child(world)
	for i in 240:
		await process_frame
	var entry := world.get_node_or_null("MainEntryScreen3D")
	if entry == null:
		print("[verify] FAIL no MainEntryScreen3D")
		quit(2)
		return
	var start := entry.get_node("Screen/MenuPanel/Margin/Content/StartButton") as Button
	var settings := entry.get_node("Screen/MenuPanel/Margin/Content/SettingsButton") as Button
	print("[verify] start=%s settings=%s" % [start.get_global_rect(), settings.get_global_rect()])

	# ---------- 1. 接线：合成信号 → UIFX 缩放 ----------
	start.emit_signal("mouse_entered")
	await _wait(0.20)
	print("[verify] start   enter -> scale=%s (expect 1.014)" % start.scale)
	start.emit_signal("mouse_exited")
	await _wait(0.20)
	print("[verify] start   exit  -> scale=%s (expect 1.000)" % start.scale)
	settings.emit_signal("mouse_entered")
	await _wait(0.20)
	print("[verify] set     enter -> scale=%s (expect 1.014)" % settings.scale)
	settings.emit_signal("button_down")
	await _wait(0.10)
	print("[verify] set     down  -> scale=%s (expect 0.988)" % settings.scale)
	settings.emit_signal("button_up")
	await _wait(0.20)
	print("[verify] set     up    -> scale=%s" % settings.scale)
	settings.emit_signal("mouse_exited")
	await _wait(0.20)

	# ---------- 2. 音效接线是否存在（不真播，只看有没有连） ----------
	for btn in [start, settings]:
		print("[verify] %s audio_bound=%s uifx=%s" % [
			btn.name, str(btn.has_meta("_tactical_audio_bound")), str(btn.has_meta("_uifx_attached"))
		])

	# ---------- 3. 视觉：强制三态拍照 ----------
	await _shot("normal")
	_force(start, false, false, 0.0, 0.0)
	_force(settings, true, false, 1.0, 0.0)
	await _shot("settings_hover")
	_force(settings, true, true, 1.0, 1.0)
	await _shot("settings_press")
	_force(settings, false, false, 0.0, 0.0)
	_force(start, true, false, 1.0, 0.0)
	await _shot("start_hover")
	_force(start, true, true, 1.0, 1.0)
	await _shot("start_press")
	_force(start, false, false, 0.0, 0.0)

	# ---------- 4. 功能：设置按钮能否真的拉起设置菜单 ----------
	entry.call("_open_settings")
	for i in 12:
		await process_frame
	var overlay := entry.get_node_or_null("PauseOverlay")
	print("[verify] settings_open=%s overlay_visible=%s" % [
		str(entry.get("_settings_open")),
		"null" if overlay == null else str((overlay as CanvasItem).visible),
	])
	quit(0)


func _force(btn: Button, hover: bool, pressed: bool, focus_blend: float, press_blend: float) -> void:
	btn.set("_hover", hover)
	btn.set("_pressed", pressed)
	btn.set("_focus_blend", focus_blend)
	btn.set("_press_blend", press_blend)
	btn.queue_redraw()


func _wait(seconds: float) -> void:
	for i in int(maxf(1.0, seconds * 60.0)):
		await process_frame


func _shot(tag: String) -> void:
	for i in 3:
		await process_frame
	var img := root.get_texture().get_image()
	if img == null:
		print("[verify] no image for %s" % tag)
		return
	var path := "%s/verify_entry_%s.png" % [OUT_DIR, tag]
	print("[verify] shot %s err=%d" % [path, img.save_png(ProjectSettings.globalize_path(path))])
