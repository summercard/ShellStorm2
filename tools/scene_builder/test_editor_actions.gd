@tool
extends RefCounted

const MODEL := preload("res://tools/scene_builder/layout_model.gd")
var checks := 0
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("SCENE_BUILDER_EDITOR_FAIL " + message)

func run(plugin: EditorPlugin) -> void:
	# Startup scans and scene restoration are asynchronous. Frames can run much faster
	# than the filesystem, so wait for the actual scene instead of counting 120 frames.
	for i in range(600):
		await plugin.get_tree().create_timer(0.1).timeout
		var current := EditorInterface.get_edited_scene_root() as Node3D
		if is_instance_valid(current) and current.is_inside_tree() and current.scene_file_path == "res://tools/scene_builder/examples/component_room_demo.tscn":
			if plugin._root != current:
				plugin._scene_changed(current)
			break
	var room: Node3D = plugin._root
	check(is_instance_valid(room), "no 3D scene opened")
	if room == null:
		finish(plugin)
		return
	await _verify_reference(plugin, room)
	if "--scene-builder-runtime-probe" in OS.get_cmdline_user_args():
		await _verify_runtime_flow(plugin)
	if not "--scene-builder-no-open-probe" in OS.get_cmdline_user_args():
		await _verify_open_flow(plugin)
	else:
		print("SCENE_BUILDER_OPEN_FLOW_SKIPPED source_render_without_extra_scene_tabs")
	await _capture_render(plugin)
	room = plugin._root
	check(is_instance_valid(room), "edited scene lost after browser capture")
	if room == null:
		finish(plugin)
		return
	plugin.dock.clip_room.button_pressed = false
	plugin.dock.protect_ports.button_pressed = false
	var rows: Array[Dictionary] = plugin.dock.rows
	var a: Dictionary = {}
	var b: Dictionary = {}
	for row in rows:
		if str(row["component_id"]) == "ENV-SHARED-GENERIC-FLOOR-TILE-R01-C01":
			a = row
		if str(row["component_id"]) == "ENV-SHARED-GENERIC-FLOOR-TILE-R01-C02":
			b = row
	var initial := MODEL.managed_components(room).size()
	var point := Vector3(1000, 0.08, 1000)
	var first_points: Array[Vector3] = [point]
	plugin._row = a
	plugin._place_points(first_points)
	check(MODEL.managed_components(room).size() == initial + 1, "native placement failed")
	var history := plugin.get_undo_redo().get_history_undo_redo(plugin.get_undo_redo().get_object_history_id(room))
	history.undo()
	check(MODEL.managed_components(room).size() == initial, "undo did not remove placement")
	history.redo()
	check(MODEL.managed_components(room).size() == initial + 1, "redo did not restore placement")
	plugin._place_points(first_points)
	check(MODEL.managed_components(room).size() == initial + 1, "duplicate stroke stacked a tile")
	plugin._row = b
	plugin._place_points(first_points)
	check(MODEL.managed_components(room).size() == initial + 1, "replacement stacked old and new tile")
	history.undo()
	var undo_tile := _at(room, point)
	check(undo_tile != null and undo_tile.get_meta("component_id") == a["component_id"], "replacement undo lost original tile")
	history.redo()
	var redo_tile := _at(room, point)
	check(redo_tile != null and redo_tile.get_meta("component_id") == b["component_id"], "replacement redo wrong")
	plugin._erase_points(first_points)
	check(MODEL.managed_components(room).size() == initial, "erase failed")
	history.undo()
	check(MODEL.managed_components(room).size() == initial + 1, "erase undo failed")
	var group := room.get_node("ArtComponents") as Node3D
	group.position = Vector3(3, 0, 2)
	var second := point + Vector3(5, 0, 0)
	var second_points: Array[Vector3] = [second]
	plugin._place_points(second_points)
	check(_at(room, second) != null, "transformed component group misplaced new node")
	history.undo()
	history.redo()
	check(_at(room, second) != null, "redo applied group transform twice")
	group.position = Vector3.ZERO
	var lights_before := room.get_node("Lighting").get_child_count()
	plugin._mode = plugin.MODE_OMNI
	plugin._add_light(Vector3.ZERO)
	check(room.get_node("Lighting").get_child_count() == lights_before + 1, "light insertion failed")
	history.undo()
	check(room.get_node("Lighting").get_child_count() == lights_before, "light undo failed")
	history.redo()
	check(room.get_node("Lighting").get_child_count() == lights_before + 1, "light redo failed")
	# Exercise the actual 3D input callback, including fast drag interpolation and two-click fill.
	var camera := Camera3D.new()
	room.add_child(camera)
	camera.position = Vector3(1500, 50, 1500)
	camera.look_at(room.to_global(Vector3(1500, 0, 1500)), Vector3.FORWARD)
	plugin.dock.grid.value = 5
	plugin.dock.elevation.value = 0.08
	plugin._row = a
	plugin._component_selected(a)
	await _settle_load(plugin, "component")
	plugin.dock.snap_enabled.button_pressed = false
	plugin.dock.set_mode(plugin.MODE_SINGLE)
	var free_point := Vector3(1500.37, 0.08, 1502.91)
	_mouse(plugin, camera, free_point, true)
	_mouse(plugin, camera, free_point, false)
	check(is_instance_valid(plugin._asset_ghost) and plugin._asset_ghost.position.distance_to(free_point) < 0.005, "component placement preview drifted from free cursor")
	var free_node := _at(room, free_point)
	check(free_node != null, "free placement forced to grid")
	if free_node != null:
		check(room.to_local(free_node.global_position).distance_to(free_point) < 0.005, "free placement changed cursor position")
	history.undo()
	plugin.dock.set_mode(plugin.MODE_BRUSH)
	var before_free := MODEL.managed_components(room).size()
	_mouse(plugin, camera, free_point, true)
	var free_motion := InputEventMouseMotion.new()
	free_motion.position = camera.unproject_position(room.to_global(free_point + Vector3(10.2, 0, 0)))
	free_motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	plugin._forward_3d_gui_input(camera, free_motion)
	_mouse(plugin, camera, free_point + Vector3(10.2, 0, 0), false)
	check(MODEL.managed_components(room).size() == before_free + 3 and _at(room, free_point + Vector3(10, 0, 0)) != null, "free brush lost its relative origin or spacing")
	history.undo()
	check(MODEL.managed_components(room).size() == before_free, "free brush undo was not atomic")
	plugin.dock.snap_enabled.button_pressed = true
	plugin.dock.cell_centers.button_pressed = false
	plugin._resolve_cursor(camera, camera.unproject_position(room.to_global(free_point)))
	check(plugin._point.distance_to(Vector3(1500, 0.08, 1505)) < 0.005, "grid origin snap wrong")
	plugin.dock.set_mode(plugin.MODE_BRUSH)
	var before_brush := MODEL.managed_components(room).size()
	var from := Vector3(1500, 0.08, 1500)
	var to := from + Vector3(10, 0, 0)
	_mouse(plugin, camera, from, true)
	var motion := InputEventMouseMotion.new()
	motion.position = camera.unproject_position(room.to_global(to))
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	plugin._forward_3d_gui_input(camera, motion)
	_mouse(plugin, camera, to, false)
	check(MODEL.managed_components(room).size() == before_brush + 3, "viewport brush drag missed cells")
	history.undo()
	check(MODEL.managed_components(room).size() == before_brush, "viewport stroke did not undo atomically")
	plugin.dock.set_mode(plugin.MODE_RECT)
	_mouse(plugin, camera, from, true)
	_mouse(plugin, camera, from, false)
	_mouse(plugin, camera, from + Vector3(10, 0, 10), true)
	_mouse(plugin, camera, from + Vector3(10, 0, 10), false)
	check(MODEL.managed_components(room).size() == before_brush + 9, "viewport rectangle fill failed")
	history.undo()
	check(MODEL.managed_components(room).size() == before_brush, "rectangle fill did not undo atomically")
	var batch := MODEL.rectangle_points(Vector3(2000, 0.08, 2000), Vector3(2095, 0.08, 2095), 5)
	var started := Time.get_ticks_msec()
	plugin._place_points(batch)
	var elapsed := Time.get_ticks_msec() - started
	check(MODEL.managed_components(room).size() == before_brush + 400, "400-component batch lost instances")
	check(int(room.get_meta("layout_instance_total")) == before_brush + 400, "batch metadata count stale")
	history.undo()
	check(MODEL.managed_components(room).size() == before_brush, "large batch undo failed")
	check(int(room.get_meta("layout_instance_total")) == before_brush, "undo metadata count stale")
	print("SCENE_BUILDER_BATCH count=400 elapsed_ms=%d" % elapsed)
	camera.free()
	var packed := PackedScene.new()
	check(packed.pack(room) == OK, "editor scene cannot be packed")
	var state := packed.get_state()
	var helpers := 0
	for i in range(state.get_node_count()):
		if str(state.get_node_name(i)).contains("SceneBuilderEditorOnly"):
			helpers += 1
	check(helpers == 0, "editor reference leaked into packed scene")
	plugin._drawing = true
	plugin._stroke[Vector3.ZERO] = true
	plugin._scene_changed(null)
	check(plugin._stroke.is_empty() and not plugin._drawing and plugin._helper == null, "scene switch retained pending stroke or reference")
	history.clear_history()
	finish(plugin)

func _verify_reference(plugin: EditorPlugin, room: Node3D) -> void:
	await _settle_load(plugin, "reference")
	var original := str(room.get_meta("whitebox_reference", ""))
	check(is_instance_valid(plugin._reference) and plugin.dock.reference_info.text.contains("已加载"), "existing room whitebox was not loaded")
	if not is_instance_valid(plugin._reference):
		return
	if is_instance_valid(plugin._reference):
		check(plugin._reference.owner == null and not plugin._reference.find_children("*", "MeshInstance3D", true, false).is_empty(), "loaded whitebox has no geometry or has a scene owner")
		for collision in plugin._reference.find_children("*", "CollisionObject3D", true, false):
			check(collision.collision_layer == 0 and collision.collision_mask == 0, "reference collision was enabled")
	plugin.dock.show_reference.button_pressed = false
	check(not plugin._reference.visible and plugin.dock.reference_info.text.contains("已隐藏"), "whitebox visibility / status did not update")
	plugin.dock.show_reference.button_pressed = true
	plugin.dock.reference_opacity.value = 0.45
	check(is_equal_approx(plugin._reference_material.albedo_color.a, 0.45), "whitebox opacity did not update")
	plugin.dock.reference_opacity.value = 0.3
	var egt_path := MODEL.SCENE_INDEX.ROOT.path_join("egt_room_types/egt_entrance_S1_static_layout.tscn")
	plugin._bind_reference(egt_path)
	await _settle_load(plugin, "bind_reference")
	check(plugin._reference_path == egt_path and is_instance_valid(plugin._reference), "cannot associate an EGT whitebox")
	var history := plugin.get_undo_redo().get_history_undo_redo(plugin.get_undo_redo().get_object_history_id(room))
	history.undo()
	plugin._process(0)
	await _settle_load(plugin, "reference")
	check(plugin._reference_path == original and is_instance_valid(plugin._reference), "reference undo did not restore preview")
	history.redo()
	plugin._process(0)
	await _settle_load(plugin, "reference")
	check(plugin._reference_path == egt_path, "reference redo did not reload preview")
	history.undo()
	plugin._process(0)
	await _settle_load(plugin, "reference")
	history.clear_history()
	room.set_meta("whitebox_reference", "res://tools/scene_builder/missing_reference_probe.tscn")
	plugin._reload_reference()
	check(plugin._reference == null and plugin.dock.reference_info.text.contains("路径不存在"), "missing reference was silently ignored")
	room.set_meta("whitebox_reference", original)
	plugin._reload_reference()
	await _settle_load(plugin, "reference")
	check(is_instance_valid(plugin._reference), "reference did not recover after fixing the path")
	print("SCENE_BUILDER_REFERENCE loaded=1 missing_path_feedback=1 undo_redo=1")

func _settle_load(plugin: EditorPlugin, channel: String) -> void:
	var start := Time.get_ticks_msec()
	while plugin._loader.has_request(channel) and Time.get_ticks_msec() - start < 15000:
		await plugin.get_tree().create_timer(0.02).timeout

func _settle_browser(plugin: EditorPlugin) -> void:
	var start := Time.get_ticks_msec()
	while plugin._scene_browser.scanning and Time.get_ticks_msec() - start < 15000:
		await plugin.get_tree().create_timer(0.02).timeout

func _settle_open(plugin: EditorPlugin) -> void:
	var start := Time.get_ticks_msec()
	while not plugin._opening_path.is_empty() and Time.get_ticks_msec() - start < 15000:
		await plugin.get_tree().create_timer(0.02).timeout

func _verify_open_flow(plugin: EditorPlugin) -> void:
	var original := str(plugin._root.scene_file_path)
	var room := MODEL.create_room(MODEL.WHITEBOX_DIR.path_join("rt_std_25x25_static_layout.tscn"))
	room.name = "SceneOpenProbe"
	var path := "res://.godot/editor/scene_builder_tests/open_%d.tscn" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var packed := PackedScene.new()
	check(packed.pack(room) == OK and ResourceSaver.save(packed, path) == OK, "cannot build scene opening fixture")
	room.free()
	plugin._extra_scenes.append(path)
	plugin._scene_browser.invalidate_index()
	var modal := AcceptDialog.new()
	modal.title = "Scene Builder Modal Probe"
	modal.transient = true
	modal.exclusive = true
	EditorInterface.get_base_control().add_child(modal)
	modal.popup_centered(Vector2i(250, 120))
	plugin.dock.open_button.emit_signal("pressed")
	check(not plugin._scene_browser.visible and plugin.dock.retry_button.visible and plugin.dock.status.text.contains("弹窗"), "blocking editor dialog produced a silent open failure")
	modal.hide()
	modal.queue_free()
	plugin._retry_load()
	check(plugin._scene_browser.visible, "top Open button did not show scene browser")
	await _settle_browser(plugin)
	plugin._scene_browser._set_runtime_view(false)
	await _settle_browser(plugin)
	plugin._scene_browser.search.text = path.get_file()
	plugin._scene_browser.rebuild()
	check(plugin._scene_browser.displayed_count == 1, "scene opening search did not isolate the fixture")
	var tree: Tree = plugin._scene_browser.tree
	var leaf: TreeItem = tree.get_root().get_first_child().get_first_child().get_first_child()
	leaf.select(0)
	plugin._scene_browser._open_selected()
	check(plugin.dock.progress_bar.visible and not plugin._opening_path.is_empty(), "scene selection supplied no immediate loading feedback")
	await _settle_open(plugin)
	check(plugin._root != null and plugin._root.scene_file_path == path and plugin._root.name == "SceneOpenProbe", "scene browser did not actually open the selected scene")
	plugin._open_scene("res://tools/scene_builder/missing_scene_probe.tscn")
	await _settle_open(plugin)
	check(plugin.dock.retry_button.visible and plugin.dock.status.text.contains("找不到"), "missing scene has no readable failure / retry")
	check(plugin._root.scene_file_path == path, "failed open replaced the active scene")
	plugin._open_scene(original)
	plugin._cancel_task()
	await plugin.get_tree().create_timer(0.05).timeout
	check(plugin._root.scene_file_path == path and plugin._opening_path.is_empty(), "cancelled open applied a stale result")
	plugin._retry_load()
	await _settle_open(plugin)
	check(plugin._root != null and plugin._root.scene_file_path == original, "retry did not reopen the original scene")
	var before: int = plugin.dock.get_instance_id()
	plugin.dock.grid.value = 2.5
	plugin._command("rebuild_workspace")
	await plugin.get_tree().create_timer(0.1).timeout
	check(plugin._workspace_current() and plugin.dock.get_instance_id() != before and plugin._root.scene_file_path == original, "workspace rebuild lost the scene or retained old controls")
	check(is_equal_approx(plugin.dock.grid.value, 2.5), "workspace rebuild discarded placement settings")
	plugin.dock.grid.value = 5
	plugin.dock.set_meta("workbench_ui_build", "legacy-ui-probe")
	plugin._process(0)
	await plugin.get_tree().create_timer(0.1).timeout
	check(plugin._workspace_current(), "outdated in-memory UI was not rebuilt automatically")
	plugin.dock.mode_buttons[3].emit_signal("pressed")
	check(plugin._mode == plugin.MODE_RECT and plugin.dock.mode_buttons[3].button_pressed, "compact mode button did not activate / highlight")
	plugin.dock.mode_buttons[0].emit_signal("pressed")
	await _settle_load(plugin, "reference")
	print("SCENE_BUILDER_OPEN_FLOW opened=1 failure_feedback=1 cancel=1 retry=1 rebuild=1")

func _mouse(plugin: EditorPlugin, camera: Camera3D, point: Vector3, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = camera.unproject_position(plugin._root.to_global(point))
	plugin._forward_3d_gui_input(camera, event)

func _verify_runtime_flow(plugin: EditorPlugin) -> void:
	print("SCENE_BUILDER_RUNTIME_STAGE list")
	var original: String = plugin._root.scene_file_path
	var target_id := "hub_01" if "--scene-builder-runtime-first-create" in OS.get_cmdline_user_args() else "boss_foyer"
	plugin.dock.open_button.emit_signal("pressed")
	check(plugin._scene_browser.runtime_view, "Open did not default to actual level rooms")
	check(plugin._scene_browser.displayed_count == 28, "actual level list includes old templates or misses rooms")
	plugin._scene_browser.search.text = target_id
	plugin._scene_browser.rebuild()
	# Partial-name search also includes the two connected corridors; select the exact room ID.
	check(plugin._scene_browser.displayed_count == (2 if target_id == "hub_01" else 3), "actual room search lost the room or its connected corridors")
	var leaf: TreeItem = plugin._scene_browser.tree.get_root()
	while leaf != null:
		var entry: Dictionary = leaf.get_meta("runtime_row", {})
		if str(entry.get("room_id", "")) == target_id:
			break
		leaf = leaf.get_next_in_tree()
	check(leaf != null, "exact actual room ID not selectable")
	if leaf == null:
		plugin._scene_browser.hide()
		return
	var row: Dictionary = leaf.get_meta("runtime_row")
	print("SCENE_BUILDER_RUNTIME_STAGE selected ", row["room_id"])
	leaf.select(0)
	plugin._scene_browser._open_selected()
	print("SCENE_BUILDER_RUNTIME_STAGE opening")
	await _settle_load(plugin, "runtime_room")
	await _settle_open(plugin)
	print("SCENE_BUILDER_RUNTIME_STAGE opened")
	check(plugin._root.scene_file_path == str(row["art_path"]), "actual room was not opened as the formal game-readable scene")
	check(plugin._root.has_node("WhiteboxShell") and plugin._root.has_node("ArtComponents"), "actual editable shell or art group missing")
	check(is_equal_approx(float(plugin._root.get_meta("wall_height_m", 0)), 2.8), "editor opened tall legacy walls again")
	check(plugin.dock.reference_info.text.contains("游戏内"), "actual source was mislabeled as missing whitebox")
	var receipt := Marker3D.new()
	receipt.name = "NativeOpenPreserveProbe"
	plugin._root.get_node("ArtComponents").add_child(receipt)
	receipt.owner = plugin._root
	plugin.dock.save_button.emit_signal("pressed")
	check(FileAccess.get_file_as_string(plugin._root.scene_file_path).contains("NativeOpenPreserveProbe"), "actual room edit could not save")
	if DisplayServer.get_name() != "headless":
		receipt.set_meta("shortcut_receipt", "saved_by_ctrl_s")
		EditorInterface.set_main_screen_editor("3D")
		var shortcut := InputEventKey.new()
		shortcut.keycode = KEY_S
		shortcut.physical_keycode = KEY_S
		shortcut.ctrl_pressed = true
		shortcut.pressed = true
		Input.parse_input_event(shortcut)
		await plugin.get_tree().create_timer(0.2).timeout
		shortcut.pressed = false
		Input.parse_input_event(shortcut)
		check(FileAccess.get_file_as_string(plugin._root.scene_file_path).contains("saved_by_ctrl_s"), "Ctrl+S did not dispatch the stable native save")
	print("SCENE_BUILDER_RUNTIME_STAGE saved")
	plugin._open_scene(original)
	await _settle_open(plugin)
	print("SCENE_BUILDER_RUNTIME_STAGE returned")
	plugin._open_runtime_room(row)
	await _settle_open(plugin)
	print("SCENE_BUILDER_RUNTIME_STAGE reopened")
	check(plugin._root.find_child("NativeOpenPreserveProbe", true, false) != null, "reopen recreated actual room and lost edits")
	plugin._open_scene(original)
	await _settle_open(plugin)
	print("SCENE_BUILDER_RUNTIME_FLOW actual_open=1 saved=1 reopened_preserved=1")

func _capture_render(plugin: EditorPlugin) -> void:
	var arguments := OS.get_cmdline_user_args()
	var index := arguments.find("--scene-builder-capture")
	if index < 0 or index + 1 >= arguments.size() or DisplayServer.get_name() == "headless":
		return
	EditorInterface.set_main_screen_editor("3D")
	plugin._focus_workspace()
	plugin.dock.show()
	var parent: Node = plugin.dock.get_parent()
	if parent is TabContainer:
		parent.current_tab = plugin.dock.get_index()
	print("SCENE_BUILDER_RENDER_PARENT ", parent.get_class())
	for i in range(4):
		await _draw_frame(plugin)
	# Require real GPU thumbnails, an interactive orbit change and scene browser pixels.
	for i in range(150):
		if plugin._thumbnails.cache.size() >= 4:
			break
		await plugin.get_tree().create_timer(0.1).timeout
	check(plugin._thumbnails.cache.size() >= 4, "thumbnail renderer produced no asset images")
	plugin.dock._select_item(0)
	await _settle_load(plugin, "component")
	var stage = plugin.dock.preview.stage
	var original: Basis = stage.camera.basis
	var drag := InputEventMouseMotion.new()
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	drag.relative = Vector2(55, 10)
	plugin.dock.preview._input_preview(drag)
	check(not stage.camera.basis.is_equal_approx(original), "3D preview orbit did not rotate")
	for i in range(3):
		await _draw_frame(plugin)
	var image := EditorInterface.get_base_control().get_viewport().get_texture().get_image()
	check(image != null and image.get_width() > 500, "native editor rendered no pixels")
	if image != null:
		var error := image.save_png(arguments[index + 1])
		check(error == OK, "native editor render capture could not save")
		print("SCENE_BUILDER_RENDER ", arguments[index + 1])
	plugin.dock.open_button.emit_signal("pressed")
	await _settle_browser(plugin)
	check(plugin._scene_browser.visible and plugin._scene_browser.displayed_count > 0, "scene list did not open")
	for i in range(3):
		await _draw_frame(plugin)
	var browser_image: Image = plugin._scene_browser.get_texture().get_image()
	check(browser_image != null and browser_image.get_width() > 500, "scene list rendered no pixels")
	if browser_image != null:
		browser_image.save_png(arguments[index + 1].get_basename() + "_scenes.png")
	plugin._scene_browser.hide()
	plugin.dock.new_button.emit_signal("pressed")
	await _settle_browser(plugin)
	check(plugin._scene_browser.visible and plugin._scene_browser.displayed_count == MODEL.whiteboxes().size(), "whitebox picker did not expose all sources")
	for i in range(3):
		await _draw_frame(plugin)
	var whitebox_image: Image = plugin._scene_browser.get_texture().get_image()
	if whitebox_image != null:
		whitebox_image.save_png(arguments[index + 1].get_basename() + "_whiteboxes.png")
	plugin._scene_browser.search.text = "egt_entrance_S1_static_layout.tscn"
	plugin._scene_browser.rebuild()
	var leaf: TreeItem = plugin._scene_browser.tree.get_root().get_first_child().get_first_child().get_first_child()
	leaf.select(0)
	plugin._scene_browser._open_selected()
	check(not plugin._scene_browser.visible and plugin._save_dialog.visible, "whitebox selection did not proceed to Save As")
	check(plugin._save_dialog.current_path.begins_with(MODEL.WHITEBOX_DIR + "/art_egt_"), "whitebox picker targets the shared source directory")
	plugin._save_dialog.hide()

func _draw_frame(plugin: EditorPlugin) -> void:
	await plugin.get_tree().process_frame
	RenderingServer.force_draw(false)

func _at(room: Node3D, point: Vector3) -> Node3D:
	for node in MODEL.managed_components(room):
		if MODEL.same_cell(node, room, point):
			return node
	return null

func finish(plugin: EditorPlugin) -> void:
	_finish_after_preview.call_deferred(plugin)

func _finish_after_preview(plugin: EditorPlugin) -> void:
	print("SCENE_BUILDER_SHUTDOWN begin")
	await plugin._settle_preview_shutdown()
	print("SCENE_BUILDER_SHUTDOWN settled")
	for failure in failures:
		printerr("SCENE_BUILDER_EDITOR_FAIL " + failure)
	print("SCENE_BUILDER_EDITOR_%s checks=%d failures=%d" % ["OK" if failures.is_empty() else "FAILED", checks, failures.size()])
	plugin.get_tree().quit(0 if failures.is_empty() else 1)
