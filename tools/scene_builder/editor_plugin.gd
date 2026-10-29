@tool
extends EditorPlugin

const LOADER := preload("res://tools/scene_builder/asset_loader.gd")
const MODEL := preload("res://tools/scene_builder/layout_model.gd")
const DOCK := preload("res://tools/scene_builder/builder_dock.gd")
const EXPORT_GUARD := preload("res://tools/scene_builder/export_guard.gd")
const THUMBNAILS := preload("res://tools/scene_builder/thumbnail_service.gd")
const SCENE_BROWSER := preload("res://tools/scene_builder/scene_browser.gd")
const PREVIEW_STAGE := preload("res://tools/scene_builder/preview_stage.gd")
const RUNTIME_SOURCE := preload("res://tools/scene_builder/runtime_source_service.gd")
const MODE_SELECT := 0
const MODE_SINGLE := 1
const MODE_BRUSH := 2
const MODE_RECT := 3
const MODE_LINE := 4
const MODE_ERASE := 5
const MODE_OMNI := 6
const MODE_SPOT := 7

var dock: DOCK
var _root: Node3D
var _helper: Node3D
var _ghost: MeshInstance3D
var _asset_ghost: Node3D
var _valid_ghost_material: StandardMaterial3D
var _invalid_ghost_material: StandardMaterial3D
var _ghost_is_valid := true
var _reference: Node3D
var _stroke_mesh: MultiMeshInstance3D
var _camera: Camera3D
var _row: Dictionary = {}
var _mode := 0
var _point := Vector3.ZERO
var _point_valid := false
var _drawing := false
var _stroke: Dictionary = {}
var _last_point := Vector3.INF
var _anchor := Vector3.INF
var _save_dialog: EditorFileDialog
var _open_dialog: EditorFileDialog
var _file_task := ""
var _pending_whitebox := ""
var _export_guard: EditorExportPlugin
var _thumbnails: THUMBNAILS
var _scene_browser: SCENE_BROWSER
var _extra_scenes: Array = []
var _reference_path := ""
var _reference_material: StandardMaterial3D
var _loader: LOADER
var _component_resource: PackedScene
var _reference_resource: PackedScene
var _opening_resource: PackedScene
var _opening_path := ""
var _open_phase := ""
var _open_started := 0
var _foreground_channel := ""
var _retry_task: Dictionary = {}
var _pending_output := ""
var _rebuilding := false
var _queued_command := ""
var _focus_after_layout := true
var _runtime_source: RUNTIME_SOURCE
var _pending_runtime: Dictionary = {}
var _editor_test_runner: RefCounted


func _enter_tree() -> void:
	name = "ShellStormSceneBuilder"
	_export_guard = EXPORT_GUARD.new()
	add_export_plugin(_export_guard)
	_extra_scenes = EditorInterface.get_editor_settings().get_project_metadata("scene_builder", "extra_scenes", [])
	_construct_workspace()
	set_input_event_forwarding_always_enabled()
	scene_changed.connect(_scene_changed)
	scene_closed.connect(func(_path): _cancel_stroke())
	_scene_changed.call_deferred(EditorInterface.get_edited_scene_root())
	set_process(true)
	set_process_input(true)
	if "--scene-builder-test" in OS.get_cmdline_user_args():
		_run_editor_tests.call_deferred()

func _construct_workspace() -> void:
	var previous := _capture_ui_state()
	_ensure_services()
	if is_instance_valid(dock):
		remove_control_from_docks(dock)
		dock.queue_free()
	dock = DOCK.new()
	_focus_after_layout = true
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)
	_focus_workspace.call_deferred()
	dock.component_selected.connect(_component_selected)
	dock.mode_changed.connect(_mode_changed)
	dock.settings_changed.connect(_settings_changed)
	dock.command_requested.connect(_command)
	dock.list_refreshed.connect(_request_previews)
	dock.shelf.get_v_scroll_bar().value_changed.connect(func(_value): _request_previews())
	dock.suite_shelf.get_v_scroll_bar().value_changed.connect(func(_value): _request_previews())
	var data := MODEL.catalog()
	var favorites: Array = EditorInterface.get_editor_settings().get_project_metadata("scene_builder", "favorites", [])
	dock.selected_row = _row
	dock.set_catalog(data["rows"], favorites)
	_restore_ui_state(previous)
	if not _row.is_empty():
		dock.selection_info.text = str(_row.get("label", "组件"))
	dock.set_scene_available(false)
	dock.set_mode(_mode)
	if not (data["errors"] as Array).is_empty():
		dock.message("组件库读取失败：%s" % str(data["errors"]), true)
	_ensure_dialogs()
	_request_previews.call_deferred()

func _capture_ui_state() -> Dictionary:
	var result := {}
	if not is_instance_valid(dock):
		return result
	for property in ["grid", "elevation", "yaw", "brush_size", "reference_opacity", "light_energy", "light_range"]:
		var control: Variant = dock.get(property)
		if control is Range:
			result[property] = control.value
	for property in ["snap_enabled", "cell_centers", "clip_room", "protect_ports", "replace_tiles", "surface_snap", "show_reference", "light_shadows", "favorites_only"]:
		var control: Variant = dock.get(property)
		if control is BaseButton:
			result[property] = control.button_pressed
	var search: Variant = dock.get("search")
	if search is LineEdit:
		result["query"] = search.text
	for property in ["group_filter", "type_filter"]:
		var control: Variant = dock.get(property)
		if control is OptionButton and control.selected >= 0:
			result[property] = control.get_item_text(control.selected)
	var split: Variant = dock.get("library_split")
	if split is VSplitContainer:
		result["split"] = split.split_offset
	return result

func _restore_ui_state(state: Dictionary) -> void:
	for property in ["grid", "elevation", "yaw", "brush_size", "reference_opacity", "light_energy", "light_range"]:
		if state.has(property):
			(dock.get(property) as Range).set_value_no_signal(state[property])
	for property in ["snap_enabled", "cell_centers", "clip_room", "protect_ports", "replace_tiles", "surface_snap", "show_reference", "light_shadows", "favorites_only"]:
		if state.has(property):
			(dock.get(property) as BaseButton).set_pressed_no_signal(state[property])
	for property in ["group_filter", "type_filter"]:
		var control := dock.get(property) as OptionButton
		for i in range(control.item_count):
			if control.get_item_text(i) == str(state.get(property, "")):
				control.select(i)
		if property == "group_filter":
			dock._refresh_types()
	dock.search.text = str(state.get("query", ""))
	dock.cell_centers.disabled = not dock.snap_enabled.button_pressed
	dock._update_placement_hint()
	if state.has("split"):
		dock.library_split.split_offset = int(state["split"])
	dock.refresh_list()

func _ensure_services() -> void:
	if not is_instance_valid(_runtime_source):
		_runtime_source = RUNTIME_SOURCE.new()
		_runtime_source.changed.connect(func(entries):
			if is_instance_valid(_scene_browser):
				_scene_browser.set_runtime_source(entries, _runtime_source.scene_path, _runtime_source.seed_value))
		_runtime_source.status.connect(func(label, busy, failed):
			if is_instance_valid(_scene_browser):
				_scene_browser.set_runtime_status(label, busy, failed))
		add_child(_runtime_source)
	if not is_instance_valid(_loader):
		_loader = LOADER.new()
		add_child(_loader)
		_loader.progress.connect(_load_progress)
		_loader.completed.connect(_load_completed)
		_loader.failed.connect(_load_failed)
	if is_instance_valid(_thumbnails) and str(_thumbnails.get_meta("workbench_revision", "")) != DOCK.UI_BUILD:
		_thumbnails.free()
	if not is_instance_valid(_thumbnails):
		_thumbnails = THUMBNAILS.new()
		_thumbnails.set_meta("workbench_revision", DOCK.UI_BUILD)
		add_child(_thumbnails)
		_thumbnails.thumbnail_ready.connect(_thumbnail_ready)
		_thumbnails.thumbnail_failed.connect(_thumbnail_failed)
		_thumbnails.page_progress.connect(_thumbnail_progress)
	if is_instance_valid(_scene_browser) and str(_scene_browser.get_meta("workbench_revision", "")) != DOCK.UI_BUILD:
		_scene_browser.queue_free()
		_scene_browser = null
	if not is_instance_valid(_scene_browser):
		_scene_browser = SCENE_BROWSER.new()
		_scene_browser.set_meta("workbench_revision", DOCK.UI_BUILD)
		_scene_browser.scene_requested.connect(_open_scene)
		_scene_browser.file_requested.connect(_browser_file_requested)
		_scene_browser.whitebox_requested.connect(_whitebox_chosen)
		_scene_browser.runtime_requested.connect(_open_runtime_room)
		_scene_browser.runtime_read_requested.connect(_runtime_source.refresh)
		_scene_browser.runtime_cancel_requested.connect(_runtime_source.cancel)
		EditorInterface.get_base_control().add_child(_scene_browser)
		_scene_browser.set_runtime_source(_runtime_source.rows, _runtime_source.scene_path, _runtime_source.seed_value)
	var filesystem := EditorInterface.get_resource_filesystem()
	if not filesystem.resources_reimported.is_connected(_assets_reimported):
		filesystem.resources_reimported.connect(_assets_reimported)

func _ensure_dialogs() -> void:
	if not is_instance_valid(_save_dialog):
		_save_dialog = EditorFileDialog.new()
		_save_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
		_save_dialog.access = EditorFileDialog.ACCESS_RESOURCES
		_save_dialog.add_filter("*.tscn", "Godot 场景")
		_save_dialog.file_selected.connect(_save_file)
		EditorInterface.get_base_control().add_child(_save_dialog)
	if not is_instance_valid(_open_dialog):
		_open_dialog = EditorFileDialog.new()
		_open_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
		_open_dialog.access = EditorFileDialog.ACCESS_RESOURCES
		_open_dialog.add_filter("*.tscn", "Godot 场景")
		_open_dialog.file_selected.connect(_open_file)
		EditorInterface.get_base_control().add_child(_open_dialog)

func _workspace_current() -> bool:
	return is_instance_valid(dock) and dock.has_node("Frame/WorkbenchR5") and str(dock.get_meta("workbench_ui_build", "")) == DOCK.UI_BUILD and is_instance_valid(_loader)

func _focus_workspace() -> void:
	if is_instance_valid(dock):
		var parent := dock.get_parent()
		if parent != null and parent.has_method("make_visible"):
			parent.call("make_visible")

func _focus_workspace_after_layout() -> void:
	await get_tree().create_timer(0.25).timeout
	if _focus_after_layout and is_instance_valid(dock):
		_focus_after_layout = false
		_focus_workspace()

func _rebuild_workspace() -> void:
	_cancel_stroke()
	_clear_helper()
	_construct_workspace()
	_scene_changed(EditorInterface.get_edited_scene_root())
	_rebuilding = false
	if not _row.is_empty():
		_component_selected(_row)
	if not _queued_command.is_empty():
		var command := _queued_command
		_queued_command = ""
		_command.call_deferred(command)

func _thumbnail_ready(path: String, texture: Texture2D) -> void:
	if is_instance_valid(dock):
		dock.apply_thumbnail(path, texture)

func _thumbnail_failed(path: String) -> void:
	if is_instance_valid(dock):
		dock.mark_thumbnail_failed(path)

func _thumbnail_progress(ready: int, total: int) -> void:
	if is_instance_valid(dock):
		dock.thumbnail_info.text = "缩略图 %d/%d" % [ready, total] if ready < total else ""

func _run_editor_tests() -> void:
	_editor_test_runner = load("res://tools/scene_builder/test_editor_actions.gd").new()
	await _editor_test_runner.run(self)

func _exit_tree() -> void:
	if is_instance_valid(_thumbnails) and _thumbnails.has_method("stop"):
		_thumbnails.stop()
	if DisplayServer.get_name() != "headless":
		RenderingServer.force_sync()
	_cancel_stroke()
	_clear_helper()
	if _export_guard != null:
		remove_export_plugin(_export_guard)
		_export_guard = null
	if is_instance_valid(_save_dialog):
		_save_dialog.queue_free()
	if is_instance_valid(_open_dialog):
		_open_dialog.queue_free()
	if is_instance_valid(_scene_browser):
		_scene_browser.queue_free()
	# These services are children of this plugin; Node owns their destruction.
	if is_instance_valid(_runtime_source):
		_runtime_source.cancel()
	if is_instance_valid(dock):
		remove_control_from_docks(dock)
		dock.queue_free()

func _settle_preview_shutdown() -> void:
	if is_instance_valid(_thumbnails):
		_thumbnails.stop()
	if is_instance_valid(dock):
		dock.preview.stage.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var start := Time.get_ticks_msec()
	while is_instance_valid(_thumbnails) and _thumbnails._working and Time.get_ticks_msec() - start < 2000:
		await get_tree().create_timer(0.02).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		RenderingServer.force_sync()

func _handles(object: Object) -> bool:
	return object is Node3D

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if not event.ctrl_pressed or event.shift_pressed or event.alt_pressed or (event.keycode != KEY_S and event.physical_keycode != KEY_S):
		return
	if not is_instance_valid(_root) or not _root.has_meta("scene_builder_schema") or not is_instance_valid(dock) or not dock.is_visible_in_tree():
		return
	if EditorInterface.get_script_editor().is_visible_in_tree():
		return
	var base := EditorInterface.get_base_control()
	var modal := base.get_last_exclusive_window()
	if modal != null and modal != base.get_window() and modal.visible:
		return
	get_viewport().set_input_as_handled()
	_command.call_deferred("save")

func _apply_changes() -> void:
	if is_instance_valid(_root):
		_update_count(_root)

func _process(_delta: float) -> void:
	if not _workspace_current():
		if not _rebuilding:
			_rebuilding = true
			_rebuild_workspace.call_deferred()
		return
	if not _opening_path.is_empty() and _open_phase == "opening":
		var current := EditorInterface.get_edited_scene_root()
		if current != null and current.scene_file_path == _opening_path:
			_scene_changed(current)
		elif Time.get_ticks_msec() - _open_started > 30000:
			_load_failed("scene", _opening_path, "编辑器尚未切换到目标场景；请检查导入或错误提示后重试。")
	# A stroke is committed on release, never left attached to another scene's history.
	if _drawing and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_commit_stroke()
	if is_instance_valid(_root) and not _root.is_inside_tree():
		_cancel_stroke()
		_clear_helper()
		_root = null
	if is_instance_valid(_root) and str(_root.get_meta("whitebox_reference", "")) != _reference_path:
		_reload_reference()

func _scene_changed(scene_root: Node) -> void:
	if not _workspace_current():
		return
	if is_instance_valid(_root) and scene_root == _root and is_instance_valid(_helper):
		_confirm_scene_open()
		return
	_cancel_stroke()
	_clear_helper()
	_root = scene_root as Node3D
	if _root == null:
		dock.room_info.text = "请打开一个 3D 场景，或从白盒新建。"
		dock.reference_info.text = "白盒参考：未打开3D场景"
		dock.set_scene_available(false)
		return
	_helper = Node3D.new()
	_helper.name = "_SceneBuilderEditorOnly"
	_helper.set_meta("_edit_lock_", true)
	_root.add_child(_helper, false, Node.INTERNAL_MODE_BACK)
	# No owner on editor helpers: native Save / Save As cannot serialize them.
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_ghost = MeshInstance3D.new()
	_ghost.mesh = box
	_ghost.material_override = _preview_material(Color(0.2, 0.9, 0.65, 0.25))
	_helper.add_child(_ghost)
	_ghost.visible = false
	_stroke_mesh = MultiMeshInstance3D.new()
	_helper.add_child(_stroke_mesh)
	_refresh_asset_ghost()
	_reload_reference()
	var size: Variant = _root.get_meta("size_m", [])
	dock.room_info.text = "%s · %s" % [_root.name, str(size)]
	dock.room_info.tooltip_text = _root.scene_file_path
	if _focus_after_layout:
		_focus_workspace_after_layout.call_deferred()
	dock.set_scene_available(_opening_path.is_empty() or _root.scene_file_path == _opening_path)
	_confirm_scene_open()

func _confirm_scene_open() -> void:
	if not _opening_path.is_empty() and _root.scene_file_path == _opening_path:
		var opened := _opening_path
		_opening_path = ""
		_open_phase = ""
		_opening_resource = null
		_foreground_channel = ""
		dock.set_scene_available(true)
		dock.finish_task("已打开 · " + opened.get_file())
		_remember_scene(opened)
		EditorInterface.set_main_screen_editor("3D")


func _clear_helper() -> void:
	if is_instance_valid(_loader):
		_loader.cancel("reference")
	if is_instance_valid(_helper):
		_helper.free()
	_helper = null
	_ghost = null
	_asset_ghost = null
	_reference = null
	_reference_path = ""
	_reference_material = null
	_stroke_mesh = null
	_point_valid = false

func _reload_reference(source: PackedScene = null) -> void:
	if not is_instance_valid(_helper):
		return
	if is_instance_valid(_reference):
		_reference.free()
	_reference = null
	_reference_resource = null
	var path := str(_root.get_meta("whitebox_reference", ""))
	_reference_path = path
	_loader.cancel("reference")
	if path.is_empty():
		if _root.has_meta("runtime_room_source_schema"):
			_reference_status("游戏内实际壳体 · %.2fm · 种子%s" % [float(_root.get_meta("wall_height_m", 0)), _root.get_meta("runtime_source_seed", "")])
			return
		var is_whitebox := bool(_root.get_meta("whitebox", false)) or str(_root.get_meta("schema", "")).contains("whitebox")
		_reference_status("当前场景就是白盒" if is_whitebox else "未关联 · 在选项中关联参考")
		return
	if path == _root.scene_file_path:
		_reference_status("引用了当前场景自身，请更换参考", true)
		return
	if not FileAccess.file_exists(path):
		_reference_status("路径不存在，请重新关联", true)
		return
	_reference_status("正在读取…")
	if source != null:
		_apply_reference(source, path)
	else:
		_loader.request("reference", path)

func _apply_reference(packed: PackedScene, path: String) -> void:
	if not is_instance_valid(_root) or path != str(_root.get_meta("whitebox_reference", "")):
		return
	_reference_resource = packed
	var instance := packed.instantiate()
	if not instance is Node3D:
		if instance != null:
			instance.free()
		_reference_status("参考不是3D场景", true)
		return
	_reference = instance as Node3D
	_reference.name = "WhiteboxReference"
	PREVIEW_STAGE.sanitize_instance(_reference)
	_reference_material = _preview_material(Color(0.4, 0.65, 0.8, dock.reference_opacity.value))
	_prepare_reference(_reference)
	_helper.add_child(_reference)
	_reference.visible = dock.show_reference.button_pressed
	_reference_status("已加载" if _reference.visible else "已隐藏")

func _reference_status(text: String, failed: bool = false) -> void:
	dock.reference_info.text = "白盒参考：" + text
	dock.reference_info.tooltip_text = _reference_path
	dock.reference_info.add_theme_color_override("font_color", Color(1, 0.65, 0.45) if failed else Color(0.5, 0.82, 0.73))

func _prepare_reference(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if node is GeometryInstance3D:
		node.material_override = _reference_material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if node is CollisionObject3D:
		node.collision_layer = 0
		node.collision_mask = 0
	if node is NavigationRegion3D:
		node.enabled = false
	for child in node.get_children():
		_prepare_reference(child)

func _preview_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _component_selected(row: Dictionary) -> void:
	_cancel_stroke()
	_row = row
	_component_resource = null
	if is_instance_valid(_asset_ghost):
		_asset_ghost.free()
	_asset_ghost = null
	if row.is_empty():
		dock.set_mode(MODE_SELECT)
		return
	dock.preview.set_pending(row)
	_begin_load("component", str(row["prefab_path"]), "读取组件 " + str(row.get("label", "")))
	if _mode == MODE_SELECT:
		dock.set_mode(MODE_SINGLE)
	_update_ghost()

func _refresh_asset_ghost() -> void:
	if is_instance_valid(_asset_ghost):
		_asset_ghost.free()
	_asset_ghost = null
	if not is_instance_valid(_helper) or _row.is_empty():
		return
	var packed := _component_resource
	if packed == null:
		return
	_asset_ghost = packed.instantiate() as Node3D
	if _asset_ghost == null:
		return
	PREVIEW_STAGE.sanitize_instance(_asset_ghost)
	_asset_ghost.set_meta("_edit_lock_", true)
	_valid_ghost_material = _preview_material(Color(0.2, 0.9, 0.65, 0.4))
	_invalid_ghost_material = _preview_material(Color(1, 0.25, 0.15, 0.45))
	_tint_ghost(_asset_ghost, _valid_ghost_material)
	_helper.add_child(_asset_ghost)
	_asset_ghost.visible = false
	_ghost_is_valid = true

func _tint_ghost(node: Node, material: Material) -> void:
	if node is GeometryInstance3D:
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_tint_ghost(child, material)

func _mode_changed(index: int) -> void:
	_cancel_stroke()
	_mode = index
	_update_ghost()
	if index != MODE_SELECT:
		EditorInterface.set_main_screen_editor("3D")
		dock.message("在 3D 视图左键操作；Esc 返回选择，Q/E 旋转。")

func _settings_changed() -> void:
	# Changing a brush setting starts a fresh gesture; it cannot mutate half a stroke.
	_cancel_stroke()
	if is_instance_valid(_reference):
		_reference.visible = dock.show_reference.button_pressed
		_reference_material.albedo_color = Color(0.4, 0.65, 0.8, dock.reference_opacity.value)
		_reference_status("已加载" if _reference.visible else "已隐藏")
	_update_ghost()

func _request_previews() -> void:
	if not is_inside_tree() or not is_instance_valid(_thumbnails):
		return
	# Render visible cards lazily; suite cards request one representative asset each.
	var paths: Array[String] = []
	if dock.library_tabs.current_tab == 1:
		for row in dock.suite_rows:
			paths.append(str(row["prefab_path"]))
	else:
		var first := maxi(0, dock.shelf.get_item_at_position(Vector2(5, 5), false) - 2)
		for index in range(first, mini(first + 16, dock.visible_rows.size())):
			paths.append(str(dock.visible_rows[index]["prefab_path"]))
	_thumbnails.request_page(paths)

func _assets_reimported(_paths: PackedStringArray) -> void:
	_thumbnails.invalidate()
	_request_previews()
	if not _row.is_empty():
		_component_selected(_row)
	_scene_browser.invalidate_index()

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if _mode == MODE_SELECT or not is_instance_valid(_root) or not _opening_path.is_empty():
		return AFTER_GUI_INPUT_PASS
	if (_loader.has_request("component") or _component_resource == null) and _mode in [MODE_SINGLE, MODE_BRUSH, MODE_RECT, MODE_LINE]:
		if event is InputEventMouseButton and event.pressed:
			dock.message("组件尚未就绪，请等待读取完成或点重试。", true)
		return AFTER_GUI_INPUT_STOP
	_camera = camera
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			dock.set_mode(MODE_SELECT)
			return AFTER_GUI_INPUT_STOP
		if event.ctrl_pressed or event.meta_pressed or event.alt_pressed:
			return AFTER_GUI_INPUT_PASS
		if event.keycode in [KEY_Q, KEY_E]:
			dock.yaw.value = wrapf(dock.yaw.value + (90 if event.keycode == KEY_E else -90), -360, 360)
			return AFTER_GUI_INPUT_STOP
	if event is InputEventMouse:
		if event.alt_pressed:
			return AFTER_GUI_INPUT_PASS
		if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_RIGHT or event.button_mask & MOUSE_BUTTON_MASK_MIDDLE):
			return AFTER_GUI_INPUT_PASS
		_resolve_cursor(camera, event.position)
		if event is InputEventMouseButton:
			_update_ghost()
	if event is InputEventMouseMotion:
		if _drawing and _point_valid:
			_collect_to(_point)
		elif _anchor.is_finite() and _point_valid:
			_show_region_preview()
		_update_ghost()
		return AFTER_GUI_INPUT_PASS
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if not _point_valid:
				return AFTER_GUI_INPUT_STOP
			if _mode in [MODE_BRUSH, MODE_ERASE]:
				_drawing = true
				_collect_to(_point)
			elif _mode in [MODE_RECT, MODE_LINE]:
				if not _anchor.is_finite():
					_anchor = _point
					dock.message("起点已记录，点击终点完成。")
				else:
					var points := _region_points()
					if points.is_empty():
						dock.message("范围超过 %d 个实例，请缩小区域。" % MODEL.MAX_BATCH, true)
					else:
						_place_points(points)
					_cancel_stroke()
			elif _mode in [MODE_OMNI, MODE_SPOT]:
				_add_light(_point)
			else:
				_place_points([_point])
		else:
			_commit_stroke()
		return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS

func _resolve_cursor(camera: Camera3D, screen: Vector2) -> void:
	_point_valid = false
	var ray_origin := camera.project_ray_origin(screen)
	var ray_direction := camera.project_ray_normal(screen)
	var hit: Variant = null
	if dock.surface_snap.button_pressed:
		var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_direction * 10000.0)
		var result := _root.get_world_3d().direct_space_state.intersect_ray(query)
		if not result.is_empty():
			hit = _root.to_local(result["position"])
	if hit == null:
		var inverse := _root.global_transform.affine_inverse()
		var local_origin := inverse * ray_origin
		var local_direction := inverse.basis * ray_direction
		hit = Plane(Vector3.UP, float(dock.elevation.value)).intersects_ray(local_origin, local_direction)
	if hit == null:
		return
	_point = hit as Vector3
	if dock.snap_enabled.button_pressed:
		_point = MODEL.snap_point(_point, dock.grid.value,
			MODEL.component_phase(_root, dock.grid.value, dock.cell_centers.button_pressed, _row, deg_to_rad(dock.yaw.value)))
	_point_valid = true

func _update_ghost() -> void:
	if not is_instance_valid(_ghost):
		return
	var active := _mode != MODE_SELECT and _point_valid
	var show_asset := active and _mode in [MODE_SINGLE, MODE_BRUSH, MODE_RECT, MODE_LINE] and is_instance_valid(_asset_ghost)
	if is_instance_valid(_asset_ghost):
		_asset_ghost.visible = show_asset
		if show_asset:
			_asset_ghost.position = _point
			_asset_ghost.rotation.y = deg_to_rad(dock.yaw.value)
			var outline := MODEL.polygon(_root) if dock.clip_room.button_pressed else PackedVector2Array()
			var allowed := MODEL.fits(_point, _row, _asset_ghost.rotation.y, outline) and not (dock.protect_ports.button_pressed and MODEL.blocks_port(_root, _point, _row, _asset_ghost.rotation.y))
			if allowed != _ghost_is_valid:
				_tint_ghost(_asset_ghost, _valid_ghost_material if allowed else _invalid_ghost_material)
				_ghost_is_valid = allowed
	_ghost.visible = active and not show_asset
	if not _ghost.visible:
		return
	var size := MODEL.component_size(_row) if not _row.is_empty() else Vector3(1, 1, 1)
	if _mode in [MODE_OMNI, MODE_SPOT]:
		size = Vector3(0.5, 0.5, 0.5)
	_ghost.position = _point + Vector3(0, size.y * 0.5, 0)
	_ghost.rotation.y = deg_to_rad(dock.yaw.value)
	(_ghost.mesh as BoxMesh).size = size.max(Vector3(0.05, 0.05, 0.05))

func _collect_to(point: Vector3) -> void:
	var path: Array[Vector3] = []
	if not _last_point.is_finite():
		path.append(point)
	elif dock.snap_enabled.button_pressed:
		path = MODEL.line_points(_last_point, point, dock.grid.value)
	else:
		var delta := point - _last_point
		var count := int(delta.length() / dock.grid.value)
		if count == 0:
			return
		if count > MODEL.MAX_BATCH:
			_cancel_stroke()
			dock.message("本笔跨度超过上限。", true)
			return
		for i in range(1, count + 1):
			path.append(_last_point + delta.normalized() * dock.grid.value * i)
	if path.is_empty():
		dock.message("本笔跨度超过上限，请分段绘制。", true)
		_cancel_stroke()
		return
	for center in path:
		for spot in MODEL.brush_points(center, int(dock.brush_size.value), dock.grid.value):
			if _stroke.size() >= MODEL.MAX_BATCH and not _stroke.has(spot):
				dock.message("本笔超过 %d 格，已取消，请分批绘制。" % MODEL.MAX_BATCH, true)
				_cancel_stroke()
				return
			_stroke[spot] = true
	_last_point = path.back()
	_show_points(_stroke.keys())

func _region_points() -> Array[Vector3]:
	return MODEL.rectangle_points(_anchor, _point, dock.grid.value) if _mode == MODE_RECT else MODEL.line_points(_anchor, _point, dock.grid.value)

func _show_region_preview() -> void:
	_show_points(_region_points())

func _show_points(points: Array) -> void:
	if not is_instance_valid(_stroke_mesh):
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3(dock.grid.value * 0.9, 0.04, dock.grid.value * 0.9)
	mesh.material = _preview_material(Color(0.95, 0.4, 0.2, 0.4) if _mode == MODE_ERASE else Color(0.2, 0.85, 0.65, 0.4))
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = points.size()
	for i in range(points.size()):
		multi.set_instance_transform(i, Transform3D(Basis.IDENTITY, points[i] + Vector3(0, 0.05, 0)))
	_stroke_mesh.multimesh = multi

func _commit_stroke() -> void:
	if not _drawing:
		return
	_drawing = false
	var points: Array[Vector3] = []
	for value in _stroke.keys():
		points.append(value)
	if not points.is_empty() and is_instance_valid(_root):
		if _mode == MODE_ERASE:
			_erase_points(points)
		else:
			_place_points(points)
	_cancel_stroke()

func _cancel_stroke() -> void:
	_drawing = false
	_stroke.clear()
	_last_point = Vector3.INF
	_anchor = Vector3.INF
	if is_instance_valid(_stroke_mesh):
		_stroke_mesh.multimesh = null

func _place_points(points: Array[Vector3]) -> void:
	if not is_instance_valid(_root) or _row.is_empty():
		dock.message("请先选择一个共享组件。", true)
		return
	if points.size() > MODEL.MAX_BATCH:
		dock.message("单批最多 %d 件。" % MODEL.MAX_BATCH, true)
		return
	var existing := MODEL.spatial_index(_root)
	var outline := MODEL.polygon(_root) if dock.clip_room.button_pressed else PackedVector2Array()
	var angle := deg_to_rad(dock.yaw.value)
	var added: Array[Node3D] = []
	var removed: Array[Node3D] = []
	var skipped := 0
	var unique := {}
	for point in points:
		if unique.has(point):
			continue
		unique[point] = true
		if not MODEL.fits(point, _row, angle, outline) or (dock.protect_ports.button_pressed and MODEL.blocks_port(_root, point, _row, angle)):
			skipped += 1
			continue
		var duplicate := false
		for node in MODEL.nearby(existing, point):
			if not MODEL.same_cell(node, _root, point):
				continue
			if str(node.get_meta("component_id", "")) == str(_row["component_id"]) and absf(wrapf(node.rotation.y - angle, -PI, PI)) < 0.01:
				duplicate = true
			elif dock.replace_tiles.button_pressed and MODEL.surface_component(_row) and MODEL.surface_component({"slot_role": node.get_meta("slot_role", "")}):
				if not node in removed:
					removed.append(node)
		if duplicate:
			skipped += 1
			continue
		var instance := MODEL.instantiate_component(_row)
		if instance == null:
			for node in added:
				node.free()
			dock.message("组件无法实例化，整批未写入。", true)
			return
		instance.position = point
		instance.rotation.y = angle
		added.append(instance)
	if added.is_empty():
		dock.message("没有新增：%d 格重复、越界或占用门口。" % skipped)
		return
	# The created nodes are still detached. The entire gesture is one native undo action.
	var undo := get_undo_redo()
	undo.create_action("组件拼装：放置 %d 件" % added.size(), UndoRedo.MERGE_DISABLE, _root, true)
	var before := MODEL.managed_components(_root).size()
	if _root.has_meta("scene_builder_schema"):
		undo.add_undo_method(_root, "set_meta", "layout_instance_total", before)
	for node in removed:
		_record_remove(undo, node)
	for node in added:
		_record_add(undo, node, "ArtComponents")
	if _root.has_meta("scene_builder_schema"):
		undo.add_do_method(_root, "set_meta", "layout_instance_total", before + added.size() - removed.size())
	undo.commit_action()
	dock.message("放置 %d 件，替换 %d 件，跳过 %d 格；Ctrl+Z 撤销整批。" % [added.size(), removed.size(), skipped])

func _record_add(undo: EditorUndoRedoManager, node: Node3D, group_name: String) -> void:
	var parent := _root.get_node_or_null(NodePath(group_name)) as Node3D
	if parent == null:
		# For existing scenes without an ArtComponents group, use the scene root.
		parent = _root
	var local_transform := parent.global_transform.affine_inverse() * _root.global_transform * node.transform
	# Store actions on scene nodes, never on this plugin: undo remains valid after disabling it.
	undo.add_do_method(parent, "add_child", node, true)
	undo.add_do_property(node, "transform", local_transform)
	undo.add_do_property(node, "owner", _root)
	undo.add_undo_method(parent, "remove_child", node)
	undo.add_do_reference(node)

func _record_remove(undo: EditorUndoRedoManager, node: Node3D) -> void:
	var parent := node.get_parent()
	undo.add_do_method(parent, "remove_child", node)
	# Undo operations execute backwards: attach first, then restore index and owner.
	undo.add_undo_property(node, "owner", node.owner)
	undo.add_undo_method(parent, "move_child", node, node.get_index())
	undo.add_undo_method(parent, "add_child", node, true)
	undo.add_undo_reference(node)

func _update_count(root: Node3D) -> void:
	if root.has_meta("scene_builder_schema"):
		root.set_meta("layout_instance_total", MODEL.managed_components(root).size())

func _erase_points(points: Array[Vector3]) -> void:
	var removed: Array[Node3D] = []
	var index := MODEL.spatial_index(_root)
	for point in points:
		for node in MODEL.nearby(index, point):
			if MODEL.same_cell(node, _root, point) and not node in removed:
				removed.append(node)
	if removed.is_empty():
		dock.message("该格没有可擦除的组件。")
		return
	var undo := get_undo_redo()
	undo.create_action("组件拼装：擦除 %d 件" % removed.size(), UndoRedo.MERGE_DISABLE, _root, true)
	var before := MODEL.managed_components(_root).size()
	if _root.has_meta("scene_builder_schema"):
		undo.add_undo_method(_root, "set_meta", "layout_instance_total", before)
	for node in removed:
		_record_remove(undo, node)
	if _root.has_meta("scene_builder_schema"):
		undo.add_do_method(_root, "set_meta", "layout_instance_total", before - removed.size())
	undo.commit_action()
	dock.message("擦除 %d 件；Ctrl+Z 可恢复。" % removed.size())

func _add_light(point: Vector3) -> void:
	var light: Light3D = SpotLight3D.new() if _mode == MODE_SPOT else OmniLight3D.new()
	light.name = "ArtSpotLight" if _mode == MODE_SPOT else "ArtOmniLight"
	light.position = point + Vector3(0, 6, 0)
	light.light_color = Color(1, 0.87, 0.69)
	light.light_energy = dock.light_energy.value
	light.shadow_enabled = dock.light_shadows.button_pressed
	if light is OmniLight3D:
		light.omni_range = dock.light_range.value
	else:
		light.spot_range = dock.light_range.value
		light.rotation_degrees.x = -90
	var undo := get_undo_redo()
	undo.create_action("组件拼装：添加灯光", UndoRedo.MERGE_DISABLE, _root, true)
	_record_add(undo, light, "Lighting")
	undo.commit_action()
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(light)
	dock.set_mode(MODE_SELECT)
	dock.message("灯光已选中：W 移动，检查器调整颜色、范围和阴影。")

func _command(command: String) -> void:
	if not _workspace_current():
		_queued_command = command
		if not _rebuilding:
			_rebuilding = true
			_rebuild_workspace.call_deferred()
		return
	match command:
		"rebuild_workspace":
			_rebuilding = true
			_rebuild_workspace.call_deferred()
		"rotate_left", "rotate_right":
			dock.yaw.value = wrapf(dock.yaw.value + (-90 if command == "rotate_left" else 90), -360, 360)
		"cancel_task":
			_cancel_task()
		"retry_task":
			_retry_load()
		"help":
			dock.message("先打开场景，选组件后左键放置；Q/E旋转，Esc选择，Ctrl+Z撤销。")
		"reload_catalog":
			var catalog := MODEL.catalog()
			_thumbnails.invalidate()
			dock.set_catalog(catalog["rows"], dock.favorites)
			dock.message("已刷新 %d 件共享组件。" % dock.rows.size() if (catalog["errors"] as Array).is_empty() else str(catalog["errors"]), not (catalog["errors"] as Array).is_empty())
		"favorite":
			if _row.is_empty():
				return
			var id := str(_row["component_id"])
			if id in dock.favorites:
				dock.favorites.erase(id)
			else:
				dock.favorites.append(id)
			EditorInterface.get_editor_settings().set_project_metadata("scene_builder", "favorites", dock.favorites)
			dock.refresh_list()
		"new_room":
			_show_browser("new_whitebox")
		"browse_whiteboxes", "bind_whitebox":
			_show_browser("new_whitebox" if command == "browse_whiteboxes" else "bind_whitebox")
		"reload_reference":
			_foreground_channel = "reference"
			_retry_task = {"channel": "reference", "path": _reference_path}
			dock.begin_task("重载白盒参考")
			_reload_reference()
			if _reference_path.is_empty() or not FileAccess.file_exists(_reference_path):
				dock.finish_task(dock.reference_info.text, true)
		"open_scene":
			_show_browser("open")
		"custom_whitebox", "open_scene_file":
			_file_task = command
			_open_dialog.title = "选择白盒参考" if command == "custom_whitebox" else "打开美术场景"
			_open_dialog.popup_centered_ratio(0.7)
		"save_variant":
			if not is_instance_valid(_root):
				return
			_file_task = "save_variant"
			_save_dialog.title = "另存为美术变体（保留当前场景）"
			_save_dialog.current_path = _root.scene_file_path.get_basename() + "_variant.tscn"
			_save_dialog.popup_centered_ratio(0.7)
		"save":
			if is_instance_valid(_root):
				var path := _root.scene_file_path
				if path.is_empty():
					dock.message("当前场景未命名，请使用更多中的另存为。", true)
					return
				# 4.7.2 preview capture can corrupt the editor's render update list even
				# with this plugin disabled. Native save without its thumbnail is stable.
				EditorInterface.save_scene_as(path, false)
				var saved := FileAccess.file_exists(path)
				dock.message("已保存 · " + path.get_file() if saved else "保存失败，请检查输出目录。", not saved)
				if saved:
					_remember_scene(_root.scene_file_path)
		"omni_mode":
			dock.set_mode(MODE_OMNI)
		"spot_mode":
			dock.set_mode(MODE_SPOT)
		"fill_floor":
			_fill_floor()
		"validate":
			if is_instance_valid(_root):
				var issues := MODEL.validate(_root)
				dock.message("布局检查通过：%d 件组件。" % MODEL.managed_components(_root).size() if issues.is_empty() else "\n".join(issues.slice(0, 8)), not issues.is_empty())

func _fill_floor() -> void:
	if not is_instance_valid(_root) or not _root.has_meta("size_m") or not MODEL.surface_component(_row):
		dock.message("请先打开带尺寸的房间并选择地砖组件。", true)
		return
	var size: Variant = _root.get_meta("size_m")
	var step: float = dock.grid.value
	var origin := MODEL.phase(_root, step, true)
	var a := Vector3(origin.x, dock.elevation.value, origin.y)
	var b := Vector3(float(size[0]) * 0.5 - step * 0.5, dock.elevation.value, float(size[1]) * 0.5 - step * 0.5)
	var points := MODEL.rectangle_points(a, b, step)
	if points.is_empty():
		dock.message("地面格数超过单批上限，请增大网格或分区铺放。", true)
		return
	_place_points(points)

func _new_room_dialog(path: String) -> void:
	if path.is_empty():
		dock.message("没有可用白盒。", true)
		return
	_pending_whitebox = path
	_file_task = "new_room"
	_save_dialog.title = "保存新的美术房间（不会覆盖白盒）"
	_save_dialog.current_path = MODEL.default_art_path(path)
	_save_dialog.popup_centered_ratio(0.7)

func _browser_file_requested() -> void:
	if _scene_browser.purpose == "open":
		_command("open_scene_file")
	else:
		_file_task = "bind_whitebox" if _scene_browser.purpose == "bind_whitebox" else "custom_whitebox"
		_open_dialog.title = "选择白盒参考"
		_open_dialog.popup_centered_ratio(0.7)

func _show_browser(purpose: String) -> void:
	_cancel_stroke()
	var base := EditorInterface.get_base_control()
	var blocking := base.get_last_exclusive_window()
	if blocking != null and blocking != base.get_window() and blocking != _scene_browser and blocking.visible:
		_retry_task = {"channel": "browser", "path": "", "purpose": purpose}
		dock.finish_task("请先处理Godot弹窗“%s”，然后重试打开。" % blocking.title, true, true)
		return
	_scene_browser.set_runtime_source(_runtime_source.rows, _runtime_source.scene_path, _runtime_source.seed_value)
	_scene_browser.open_browser(_extra_scenes, purpose)
	if purpose == "open" and _scene_browser.runtime_view and _runtime_source.rows.is_empty() and not _runtime_source.busy:
		_runtime_source.refresh(_runtime_source.scene_path, _runtime_source.seed_value)

func _open_runtime_room(row: Dictionary) -> void:
	var target := str(row.get("art_path", ""))
	if target.is_empty() or not target.begins_with(MODEL.SCENE_INDEX.ROOT + "/") or not target.contains("/runtime_rooms/"):
		dock.message("关卡房间来源无效，请重新读取关卡。", true)
		return
	if FileAccess.file_exists(target):
		_open_scene(target)
		return
	_pending_runtime = row.duplicate(true)
	_begin_load("runtime_room", str(row["path"]), "打开实际关卡房间")

func _finish_runtime_room(source: PackedScene) -> void:
	var target := str(_pending_runtime.get("art_path", ""))
	if target.is_empty():
		return
	# A second editor may have created the same formal scene while reading.
	if FileAccess.file_exists(target):
		_open_scene(target)
		return
	var room := source.instantiate() as Node3D
	if room == null or str(room.get_meta("runtime_room_signature", "")) != str(_pending_runtime.get("signature", "")):
		if room != null:
			room.free()
		_load_failed("runtime_room", target, "关卡缓存已过期，请重新读取关卡。")
		return
	var error := DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	var packed := PackedScene.new()
	if error == OK:
		error = packed.pack(room)
	if error == OK:
		error = ResourceSaver.save(packed, target)
	room.free()
	if error != OK:
		_load_failed("runtime_room", target, "正式房间保存失败：" + error_string(error))
		return
	EditorInterface.get_resource_filesystem().update_file(target)
	_remember_scene(target)
	dock.set_mode(MODE_SELECT)
	_open_scene(target)

func _whitebox_chosen(path: String) -> void:
	if _scene_browser.purpose == "bind_whitebox":
		_bind_reference(path)
	else:
		_new_room_dialog(path)

func _bind_reference(path: String) -> void:
	if not is_instance_valid(_root) or path == _root.scene_file_path:
		dock.message("请先打开场景，并选择另一份白盒参考。", true)
		return
	_begin_load("bind_reference", path, "关联白盒参考")

func _apply_reference_binding(path: String, packed: PackedScene) -> void:
	if not is_instance_valid(_root):
		return
	if not _packed_is_3d(packed):
		_load_failed("bind_reference", path, "白盒必须是3D场景。")
		return
	var undo := get_undo_redo()
	undo.create_action("组件拼装：关联白盒参考", UndoRedo.MERGE_DISABLE, _root, true)
	undo.add_do_method(_root, "set_meta", "whitebox_reference", path)
	if _root.has_meta("whitebox_reference"):
		undo.add_undo_method(_root, "set_meta", "whitebox_reference", _root.get_meta("whitebox_reference"))
	else:
		undo.add_undo_method(_root, "remove_meta", "whitebox_reference")
	undo.commit_action()
	_reload_reference(packed)
	dock.message("白盒参考已关联；Ctrl+Z可撤销，组件摆位保持原样。")

func _open_file(path: String) -> void:
	if _file_task == "custom_whitebox":
		_new_room_dialog(path)
	elif _file_task == "bind_whitebox":
		_bind_reference(path)
	else:
		_open_scene(path)

func _remember_scene(path: String) -> void:
	if path.is_empty():
		return
	if not path in _extra_scenes:
		_extra_scenes.append(path)
	EditorInterface.get_editor_settings().set_project_metadata("scene_builder", "extra_scenes", _extra_scenes)
	_scene_browser.extra_paths = _extra_scenes.duplicate()
	_scene_browser.invalidate_index()

func _save_file(path: String) -> void:
	if FileAccess.file_exists(path):
		dock.message("该文件已存在，请换个名字；当前场景可直接保存。", true)
		return
	if _file_task == "save_variant":
		EditorInterface.save_scene_as(path, false)
		if FileAccess.file_exists(path):
			_remember_scene(path)
			dock.message("已另存 · " + path.get_file())
		else:
			dock.message("另存失败，请检查目标目录。", true)
		return
	_pending_output = path
	_begin_load("new_room", _pending_whitebox, "读取白盒模板")

func _finish_new_room(source: PackedScene) -> void:
	var path := _pending_output
	var room := MODEL.create_room(_pending_whitebox, source)
	if room == null:
		_load_failed("new_room", _pending_whitebox, "白盒必须是可用的3D场景。")
		return
	if FileAccess.file_exists(path):
		room.free()
		_load_failed("new_room", path, "目标文件已存在，请换个名字。")
		return
	var packed := PackedScene.new()
	var error := packed.pack(room)
	if error == OK:
		error = ResourceSaver.save(packed, path)
	room.free()
	if error != OK:
		_load_failed("new_room", path, "保存失败：" + error_string(error))
		return
	EditorInterface.get_resource_filesystem().update_file(path)
	_remember_scene(path)
	dock.set_mode(MODE_SELECT)
	_open_scene(path)

func _packed_is_3d(packed: PackedScene) -> bool:
	if packed == null or not packed.can_instantiate():
		return false
	var type := str(packed.get_state().get_node_type(0))
	return type.is_empty() or type == "Node3D" or ClassDB.is_parent_class(type, "Node3D")

func _begin_load(channel: String, path: String, label: String) -> void:
	if channel == "scene" or _opening_path.is_empty():
		_foreground_channel = channel
		_retry_task = {"channel": channel, "path": path, "label": label}
		dock.begin_task(label)
	_loader.request(channel, path)

func _open_scene(path: String) -> void:
	_cancel_stroke()
	_opening_path = path
	_open_phase = "loading"
	_open_started = Time.get_ticks_msec()
	dock.set_scene_available(false)
	# Native open tabs own mutable PackedScene state during Save. Re-loading that
	# same resource on a worker races the editor's save/reimport bookkeeping.
	if path in EditorInterface.get_open_scenes():
		_loader.cancel("scene")
		_foreground_channel = "scene"
		_retry_task = {"channel": "scene", "path": path}
		_open_phase = "opening"
		dock.begin_task("切换到已打开场景 " + path.get_file())
		dock.cancel_button.visible = false
		_perform_open.call_deferred(path)
		return
	_begin_load("scene", path, "读取场景 " + path.get_file())

func _load_progress(channel: String, path: String, ratio: float, elapsed: float) -> void:
	if channel == _foreground_channel:
		dock.task_progress(str(_retry_task.get("label", "正在读取")), ratio)
	if channel == "component" and path == str(_row.get("prefab_path", "")):
		dock.preview.caption.text = "正在读取 · %d%% · %.0fs" % [ratio * 100, elapsed]

func _load_completed(channel: String, path: String, resource: Resource) -> void:
	var packed := resource as PackedScene
	if not _packed_is_3d(packed):
		_load_failed(channel, path, "这不是可用的3D场景，请选择房间或组件场景。")
		return
	match channel:
		"scene":
			if path != _opening_path:
				return
			_opening_resource = packed
			_open_phase = "opening"
			_open_started = Time.get_ticks_msec()
			dock.task_progress("正在打开 " + path.get_file())
			dock.cancel_button.visible = false
			_perform_open.call_deferred(path)
		"component":
			if path != str(_row.get("prefab_path", "")):
				return
			_component_resource = packed
			dock.preview.show_resource(_row, packed)
			_refresh_asset_ghost()
			_update_ghost()
			_finish_foreground(channel, "已选择 · " + str(_row.get("label", "组件")))
		"reference":
			_apply_reference(packed, path)
			_finish_foreground(channel, dock.reference_info.text)
		"bind_reference":
			_apply_reference_binding(path, packed)
			_finish_foreground(channel, "已关联白盒参考 · Ctrl+Z撤销")
		"new_room":
			_finish_new_room(packed)
		"runtime_room":
			_finish_runtime_room(packed)

func _perform_open(path: String) -> void:
	# Yield two frames so feedback is drawn before Godot's native scene instantiation.
	await get_tree().process_frame
	await get_tree().process_frame
	# Save/scene-tree gizmo updates are deferred independently of rendering frames.
	await get_tree().create_timer(0.15).timeout
	var filesystem := EditorInterface.get_resource_filesystem()
	while filesystem.is_scanning() and path == _opening_path:
		await get_tree().create_timer(0.05).timeout
	if path != _opening_path:
		return
	EditorInterface.set_main_screen_editor("3D")
	EditorInterface.open_scene_from_path(path)
	_focus_workspace.call_deferred()
	var current := EditorInterface.get_edited_scene_root()
	if current != null and current.scene_file_path == path:
		_scene_changed(current)

func _finish_foreground(channel: String, text: String) -> void:
	if channel == _foreground_channel:
		_foreground_channel = ""
		dock.finish_task(text)

func _load_failed(channel: String, path: String, reason: String) -> void:
	if channel == "component":
		dock.preview.show_failure(reason)
	if channel == "reference":
		_reference_status(reason, true)
	if channel == "scene":
		_opening_path = ""
		_open_phase = ""
		_opening_resource = null
		dock.set_scene_available(is_instance_valid(_root))
	if channel == _foreground_channel or channel == "scene":
		_foreground_channel = ""
		dock.finish_task(reason, true, true)

func _cancel_task() -> void:
	if _foreground_channel.is_empty():
		return
	var channel := _foreground_channel
	_loader.cancel(channel)
	_foreground_channel = ""
	if channel == "scene":
		_opening_path = ""
		_open_phase = ""
		dock.set_scene_available(is_instance_valid(_root))
	elif channel == "reference":
		_reference_status("已取消读取，可点重载")
	elif channel == "component":
		dock.preview.show_failure("已取消读取，重新选择组件或重试")
	dock.finish_task("已取消后续操作 · 当前场景保留")
	dock.retry_button.visible = true

func _retry_load() -> void:
	if _retry_task.is_empty():
		return
	var channel := str(_retry_task["channel"])
	var path := str(_retry_task["path"])
	if channel == "scene":
		_open_scene(path)
	elif channel == "browser":
		_show_browser(str(_retry_task.get("purpose", "open")))
	elif channel == "reference":
		_command("reload_reference")
	else:
		_begin_load(channel, path, str(_retry_task.get("label", "重新读取")))
