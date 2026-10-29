extends SceneTree

const DOCK := preload("res://tools/scene_builder/builder_dock.gd")
const MODEL := preload("res://tools/scene_builder/layout_model.gd")
const LOADER := preload("res://tools/scene_builder/asset_loader.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, reason: String) -> void:
	checks += 1
	if not value:
		failures.append(reason)
		printerr("SCENE_BUILDER_WORKBENCH_FAIL " + reason)

func _run() -> void:
	# Measure the dock independently of the game's canvas_items stretch policy.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(460, 900)
	root.add_child(viewport)
	var dock := DOCK.new()
	viewport.add_child(dock)
	dock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dock.set_catalog(MODEL.catalog()["rows"], [])
	for i in range(4):
		await process_frame
	print("SCENE_BUILDER_LAYOUT large dock=%s library=%s split=%s preview=%s minimum=%s" % [dock.size, dock.library_area.size, dock.library_split.size, dock.preview.surface.size, dock.get_combined_minimum_size()])
	check(not dock.mode.visible and dock.mode_buttons.size() == 8, "operation modes still use a dropdown")
	check(not dock.options_panel.visible, "advanced settings crowd the initial workspace")
	check(dock.library_split.size.y / dock.size.y >= 0.6, "component grid and 3D preview occupy less than 60% of a 900px workspace")
	check(dock.preview.surface.size.y >= 160, "interactive preview is too small")
	check(dock.open_button.get_global_rect().position.y < dock.library_area.get_global_rect().position.y, "Open is buried below component controls")
	dock.mode_buttons[4].emit_signal("pressed")
	check(dock.mode.selected == 4 and dock.mode_buttons[4].button_pressed, "mode button did not update / highlight")
	dock.begin_task("读取场景")
	check(dock.progress_bar.visible and dock.cancel_button.visible, "no immediate loading / cancel feedback")
	dock.finish_task("找不到场景", true, true)
	check(dock.retry_button.visible and not dock.progress_bar.visible, "failed load has no retry feedback")
	viewport.size = Vector2i(340, 700)
	for i in range(4):
		await process_frame
	print("SCENE_BUILDER_LAYOUT compact dock=%s viewport=%s status_end=%s minimum=%s" % [dock.size, viewport.size, dock.status.get_global_rect().end, dock.get_combined_minimum_size()])
	check(dock.get_combined_minimum_size().x <= 340, "compact workspace overflows horizontally")
	check(dock.mode_grid.columns == 4, "narrow mode toolbar did not wrap into two rows")
	check(dock.status.get_global_rect().end.y <= viewport.size.y + 1, "compact workspace clips its feedback")
	viewport.size = Vector2i(650, 1000)
	for i in range(4):
		await process_frame
	check(dock.mode_grid.columns == 8, "wide mode toolbar did not fit one row")
	var loader := LOADER.new()
	root.add_child(loader)
	var events: Array[Dictionary] = []
	var errors: Array[String] = []
	loader.completed.connect(func(channel, path, resource): events.append({"channel": channel, "path": path, "resource": resource}))
	loader.failed.connect(func(_channel, _path, reason): errors.append(reason))
	loader.request("missing", "res://tools/scene_builder/absent_workbench_probe.tscn")
	await _settle(loader)
	check(errors.size() == 1 and errors[0].contains("找不到"), "missing resource did not report a readable error")
	var rows: Array[Dictionary] = MODEL.catalog()["rows"]
	var first := str(rows[0]["prefab_path"])
	var second := str(rows[1]["prefab_path"])
	var switched := [false]
	loader.progress.connect(func(channel, _path, _ratio, _elapsed):
		if channel == "selection" and not switched[0]:
			switched[0] = true
			loader.request("selection", second))
	loader.request("selection", first)
	await _settle(loader)
	check(events.size() == 1 and events[0]["path"] == second, "old resource result overwrote a newer selection")
	events.clear()
	loader.request("cancelled", first)
	loader.cancel("cancelled")
	await _settle(loader)
	check(events.is_empty(), "cancelled load still emitted a result")
	loader.free()
	dock.free()
	viewport.free()
	print("SCENE_BUILDER_WORKBENCH_%s checks=%d failures=%d" % ["OK" if failures.is_empty() else "FAILED", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _settle(loader: LOADER) -> void:
	var start := Time.get_ticks_msec()
	while (not loader._latest.is_empty() or not loader._active.is_empty() or not loader._queue.is_empty()) and Time.get_ticks_msec() - start < 15000:
		await create_timer(0.02).timeout
