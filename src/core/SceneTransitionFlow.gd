extends Node
## 全局统一场景切换与加载流程。
##
## 先等待遮罩真实绘制，再拓扑预热静态依赖（逐项主线程读取、逐项让出绘制）。
## ResourceLoader 不返回 GDScript preload/extends，须在读取脚本之前补扫源码。
## 场景实例化仍是主线程操作，可能出现尖峰；scene_changed 不等于运行时就绪。
## 遮罩保持到目标明确就绪且再次绘制后，活动扫描动画不代表加载进度。
## 结算、存档和 GameEntryFlow 意图仍由调用方负责，本节点不碰存档。

signal transition_started(scene_path: String, title: String)
signal transition_progress_changed(progress: float, status: String)
signal transition_finished(scene_path: String)
signal transition_failed(scene_path: String, reason: String)
signal transition_failure_dismissed(scene_path: String)

const DEFAULT_TITLE := "正在切换战区"
const OVERLAY_LAYER := 2000
const RESOURCE_PROGRESS_END := 0.75
# 便宜的缓存命中/依赖扫描按时间预算批处理，不强迫每个条目单独等一帧。
const LOADING_SLICE_USEC := 4000
const STATE_IDLE := "idle"
const STATE_PREPARING := "preparing"
const STATE_LOADING := "loading"
const STATE_SWITCHING := "switching"
const STATE_BOOTSTRAPPING := "bootstrapping"
const STATE_FAILED := "failed"

var _state := STATE_IDLE
var _target_scene_path := ""
var _target_title := DEFAULT_TITLE
var _request_token := 0
var _overlay: CanvasLayer
var _progress: ProgressBar
var _title_label: Label
var _status_label: Label
var _error_label: Label
var _dismiss_button: Button
var _activity: ColorRect
var _activity_phase := 0.0
var _held_resources: Array[Resource] = []
var _pause_before_transition := false
var _switch_committed := false
var _target_progress := 0.0
var _script_classes: Dictionary = {}
var _source_tokens := RegEx.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	get_tree().scene_changed.connect(_on_scene_changed)
	# 先吃掉注释和完整字符串，避免注释/字符串中的 preload 被误认为代码。
	_source_tokens.compile("(?s)#[^\\n]*|\"\"\".*?\"\"\"|'''.*?'''|\"(?:\\\\.|[^\"\\\\])*\"|'(?:\\\\.|[^'\\\\])*'|[A-Za-z_][A-Za-z_0-9]*|[().]")
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		_script_classes[String(entry["class"])] = String(entry["path"])
	_build_overlay()
	_overlay.hide()


func present_loading_frame(title: String = DEFAULT_TITLE) -> Error:
	if _state != STATE_IDLE:
		return ERR_BUSY
	_acquire_overlay(title)
	_state = STATE_PREPARING
	_update_overlay(0.0, "正在准备切换，请稍候…")
	var token := _request_token
	await _await_loading_draw()
	return OK if token == _request_token and _state == STATE_PREPARING else ERR_BUSY


func dismiss_preparation() -> void:
	if _state == STATE_PREPARING:
		_release_overlay()


func request_scene_change(scene_path: String, title: String = DEFAULT_TITLE) -> Error:
	if _state != STATE_IDLE and _state != STATE_PREPARING:
		return ERR_BUSY
	var error := _validate_scene_path(scene_path)
	if error != OK:
		return error
	if _state == STATE_IDLE:
		_acquire_overlay(title)
	_start_request(scene_path.strip_edges(), title)
	return OK


func redirect_scene_change(scene_path: String, title: String = DEFAULT_TITLE) -> Error:
	# 包含目标 _ready 内的窗口；此时 current_scene 可能尚未赋值。
	if _state != STATE_BOOTSTRAPPING or _find_target_root() == null:
		return ERR_BUSY
	var error := _validate_scene_path(scene_path)
	if error != OK:
		return error
	_start_request(scene_path.strip_edges(), title)
	return OK


func report_target_progress(target: Node, ratio: float, status: String) -> void:
	if not _accept_target(target) or not is_finite(ratio):
		return
	_target_progress = maxf(_target_progress, clampf(ratio, 0.0, 1.0))
	# 报告 100% 也不能代替真实 ready gate。
	_update_overlay(RESOURCE_PROGRESS_END + _target_progress * 0.24, status)


func report_target_failure(target: Node, reason: String) -> void:
	if _accept_target(target):
		_fail_transition(reason, _request_token)


func is_transition_active() -> bool:
	return _state != STATE_IDLE


func get_transition_state() -> String:
	return _state


func dismiss_failure() -> void:
	if _state != STATE_FAILED:
		return
	var failed_scene := _target_scene_path
	_release_overlay()
	transition_failure_dismissed.emit(failed_scene)


func _validate_scene_path(path: String) -> Error:
	if path.strip_edges().is_empty():
		return ERR_INVALID_PARAMETER
	if not ResourceLoader.exists(path.strip_edges(), "PackedScene"):
		return ERR_FILE_NOT_FOUND
	return OK


func _acquire_overlay(title: String) -> void:
	_request_token += 1
	_pause_before_transition = get_tree().paused
	_switch_committed = false
	_target_scene_path = ""
	_target_title = title if not title.strip_edges().is_empty() else DEFAULT_TITLE
	_activity_phase = 0.0
	_overlay.show()
	set_process(true)
	_dismiss_button.hide()
	_error_label.hide()


func _start_request(path: String, title: String) -> void:
	_request_token += 1
	_state = STATE_LOADING
	_target_scene_path = path
	_target_title = title if not title.strip_edges().is_empty() else DEFAULT_TITLE
	_target_progress = 0.0
	_update_overlay(0.0, "正在扫描静态依赖…")
	var token := _request_token
	transition_started.emit(path, _target_title)
	call_deferred("_begin_resource_load", token)


func _release_overlay() -> void:
	_request_token += 1
	_state = STATE_IDLE
	_overlay.hide()
	set_process(false)
	_held_resources.clear()
	if not _switch_committed:
		get_tree().paused = _pause_before_transition
	_error_label.hide()
	_dismiss_button.hide()


func _input(event: InputEvent) -> void:
	if _state == STATE_IDLE:
		return
	if _state == STATE_FAILED:
		# 失败界面仍能接收鼠标；底层 GUI 被全屏 STOP 遮罩拦截。
		if event is InputEventMouse:
			return
		if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
			dismiss_failure()
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_activity_phase = fmod(_activity_phase + delta * 0.7, 1.0)
	_activity.position.x = _activity_phase * 432.0


func _await_loading_draw() -> void:
	# process_frame 本身不证明绘制已完成；headless 没有真实绘制，只用于逻辑验证。
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw


func _begin_resource_load(token: int) -> void:
	await _await_loading_draw()
	if not _loading_token_valid(token):
		return
	var visits: Dictionary = {}
	var order: Array[String] = []
	var stack: Array[Dictionary] = [{"path": _target_scene_path, "exit": false}]
	var slice_started := Time.get_ticks_usec()
	# 非递归 DFS：按短时间预算让出绘制，不按资源数量人为延长过场。
	while not stack.is_empty():
		if not _loading_token_valid(token):
			return
		var item: Dictionary = stack.pop_back()
		var path: String = item["path"]
		if bool(item["exit"]):
			visits[path] = 2
			order.append(path)
			continue
		var visit: int = visits.get(path, 0)
		if visit == 2:
			continue
		if visit == 1:
			_fail_transition("静态依赖存在循环：%s" % path, token)
			return
		visits[path] = 1
		stack.append({"path": path, "exit": true})
		var dependencies := _get_static_dependencies(path)
		for index in range(dependencies.size() - 1, -1, -1):
			stack.append({"path": dependencies[index], "exit": false})
		if Time.get_ticks_usec() - slice_started >= LOADING_SLICE_USEC:
			_update_overlay(0.0, "正在扫描静态依赖：已发现 %d 项" % visits.size())
			await _await_loading_draw()
			slice_started = Time.get_ticks_usec()
	_update_overlay(0.0, "静态依赖扫描完成：%d 项" % order.size())
	await _await_loading_draw()
	slice_started = Time.get_ticks_usec()
	# 局部强引用随协程保留；重定向不能在旧 load 栈上释放它们。
	var held: Array[Resource] = []
	var packed: PackedScene
	for index in range(order.size()):
		if not _loading_token_valid(token):
			return
		var path := order[index]
		var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
		if resource == null or (resource is GDScript and not resource.can_instantiate()):
			_fail_transition("静态依赖读取失败：%s" % path, token)
			return
		held.append(resource)
		if path == _target_scene_path:
			packed = resource as PackedScene
		_update_overlay(RESOURCE_PROGRESS_END * float(index + 1) / float(order.size()),
			"正在预热资源：%d / %d · %s" % [index + 1, order.size(), path.get_file()])
		if Time.get_ticks_usec() - slice_started >= LOADING_SLICE_USEC or index == order.size() - 1:
			await _await_loading_draw()
			slice_started = Time.get_ticks_usec()
	if not _loading_token_valid(token):
		return
	_held_resources = held
	_finish_resource_load(packed, token)


func _loading_token_valid(token: int) -> bool:
	return _state == STATE_LOADING and token == _request_token


func _get_static_dependencies(path: String) -> Array[String]:
	var result: Array[String] = []
	for raw: String in ResourceLoader.get_dependencies(path):
		# Godot 返回 path、uid 或 uid::type::fallback；优先有效的文本路径。
		var parts := raw.split("::", true)
		var dependency := parts[parts.size() - 1]
		if dependency.is_empty():
			dependency = parts[0]
		# GDScript 的 ResourceLoader 依赖会展开所有 preload 的模型、材质
		# 和设施场景。脚本读取时这些 preload 已由引擎解析；逐项再预热
		# 会把远征运行时不需要的基地/主塔视觉资源拖进 loading 队列。
		# 脚本依赖仍保留，目标场景和静态布局场景的 ext_resource 不受影响。
		if path.get_extension().to_lower() == "gd":
			var normalized := dependency
			if normalized.begins_with("uid://"):
				var uid := ResourceUID.text_to_id(normalized)
				if ResourceUID.has_id(uid):
					normalized = ResourceUID.get_id_path(uid)
			if normalized.get_extension().to_lower() != "gd":
				continue
		_add_dependency(result, dependency, path)
	if path.get_extension().to_lower() == "gd" and FileAccess.file_exists(path):
		var tokens: Array[String] = []
		for match_result: RegExMatch in _source_tokens.search_all(FileAccess.get_file_as_string(path)):
			var text := match_result.get_string()
			if not text.begins_with("#"):
				tokens.append(text)
		for index in range(tokens.size()):
			if tokens[index] == "preload" and (index == 0 or tokens[index - 1] != "."):
				if index + 3 < tokens.size() and tokens[index + 1] == "(" and tokens[index + 3] == ")":
					var literal_token := tokens[index + 2]
					if literal_token.length() >= 2 and (
						literal_token.begins_with("\"") or literal_token.begins_with("'")
					):
						var literal := literal_token.substr(1, literal_token.length() - 2)
						if literal.get_extension().to_lower() == "gd":
							_add_dependency(result, literal, path)
			elif tokens[index] == "extends" and index + 1 < tokens.size():
				var base := tokens[index + 1]
				if _script_classes.has(base):
					_add_dependency(result, String(_script_classes[base]), path)
				else:
					_add_literal_dependency(result, base, path)
	return result


func _add_literal_dependency(result: Array[String], literal: String, owner: String) -> void:
	if literal.length() < 2 or (not literal.begins_with('"') and not literal.begins_with("'")):
		return
	_add_dependency(result, literal.substr(1, literal.length() - 2), owner)


func _add_dependency(result: Array[String], dependency: String, owner: String) -> void:
	var path := dependency
	if path.begins_with("uid://"):
		var uid := ResourceUID.text_to_id(path)
		if ResourceUID.has_id(uid):
			path = ResourceUID.get_id_path(uid)
	elif not path.begins_with("res://") and not path.begins_with("user://"):
		path = owner.get_base_dir().path_join(path).simplify_path()
	if not result.has(path):
		result.append(path)


func _finish_resource_load(packed: PackedScene, token: int) -> void:
	if not _loading_token_valid(token):
		return
	if packed == null:
		_fail_transition("目标资源不是有效场景", token)
		return
	_state = STATE_SWITCHING
	_update_overlay(RESOURCE_PROGRESS_END, "正在实例化目标场景…")
	# 旧暂停菜单不能让新目标的分帧 _process 初始化永远停住。
	# 不在 finish 强制 unpause：目标自己的菜单/演出可以重新取得暂停权。
	get_tree().paused = false
	var error: Error = get_tree().change_scene_to_packed(packed)
	if error != OK:
		if not _switch_committed:
			get_tree().paused = _pause_before_transition
		_fail_transition("场景切换失败：%s" % error_string(error), token)
	else:
		_switch_committed = true


func _find_target_root() -> Node:
	var current := get_tree().current_scene
	if current != null and current.scene_file_path == _target_scene_path:
		return current
	if _state == STATE_SWITCHING:
		for child: Node in get_tree().root.get_children():
			if child.scene_file_path == _target_scene_path:
				return child
	return null


func _accept_target(target: Node) -> bool:
	return (_state == STATE_SWITCHING or _state == STATE_BOOTSTRAPPING) and is_instance_valid(target) and target == _find_target_root()


func _target_has_gate(target: Node) -> bool:
	if target.has_method("is_transition_runtime_ready"):
		return true
	for property: Dictionary in target.get_property_list():
		if property["name"] == "_transition_runtime_ready":
			return true
	return false


func _target_is_ready(target: Node) -> bool:
	if target.has_method("is_transition_runtime_ready"):
		return bool(target.call("is_transition_runtime_ready"))
	return bool(target.get("_transition_runtime_ready"))


func _on_scene_changed() -> void:
	if _state != STATE_SWITCHING:
		return
	var target := _find_target_root()
	if target == null:
		return
	_state = STATE_BOOTSTRAPPING
	if _target_progress == 0.0:
		_update_overlay(RESOURCE_PROGRESS_END, "正在初始化并恢复目标战区…")
	call_deferred("_complete_transition", _request_token, target)


func _complete_transition(token: int, target: Node) -> void:
	var has_gate := _target_has_gate(target)
	while token == _request_token and _state == STATE_BOOTSTRAPPING:
		# 无接口场景也至少给目标真正绘制一帧；gate 变 true 后仍确认一次绘制。
		await _await_loading_draw()
		if token != _request_token or _state != STATE_BOOTSTRAPPING:
			return
		if not is_instance_valid(target) or target != get_tree().current_scene:
			_fail_transition("初始化期间目标场景被移除", token)
			return
		if has_gate and not _target_is_ready(target):
			continue
		if has_gate:
			await _await_loading_draw()
			if token != _request_token or not _accept_target(target):
				return
			if not _target_is_ready(target):
				continue
		_update_overlay(1.0, "战区已就绪")
		var finished_path := _target_scene_path
		_release_overlay()
		transition_finished.emit(finished_path)
		return


func _fail_transition(reason: String, token: int) -> void:
	if _state == STATE_IDLE or _state == STATE_FAILED or token != _request_token:
		return
	_state = STATE_FAILED
	_error_label.text = reason
	_error_label.show()
	_dismiss_button.show()
	_status_label.text = "场景切换失败，请返回并重试"
	transition_failed.emit(_target_scene_path, reason)
	push_error("[SceneTransitionFlow] %s：%s" % [_target_scene_path, reason])


func _update_overlay(progress_value: float, status: String) -> void:
	_progress.value = clampf(progress_value, 0.0, 1.0) * 100.0
	_title_label.text = _target_title
	_status_label.text = status
	_error_label.hide()
	transition_progress_changed.emit(clampf(progress_value, 0.0, 1.0), status)


func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.name = "SceneTransitionOverlay"
	_overlay.layer = OVERLAY_LAYER
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_overlay)

	var root := Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(root)

	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.006, 0.012, 0.020, 0.98)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(backdrop)

	_activity = ColorRect.new()
	_activity.name = "ActivityScan"
	_activity.position = Vector2(-216.0, 176.0)
	_activity.size = Vector2(72.0, 2.0)
	_activity.color = Color(0.28, 0.86, 0.92, 0.85)
	_activity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_activity)

	var panel := VBoxContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -270.0
	panel.offset_top = -105.0
	panel.offset_right = 270.0
	panel.offset_bottom = 105.0
	panel.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_theme_constant_override("separation", 14)
	root.add_child(panel)

	var eyebrow := Label.new()
	eyebrow.text = "SHELLSTORM 2  ·  SCENE TRANSITION"
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eyebrow.add_theme_font_size_override("font_size", 12)
	eyebrow.add_theme_color_override("font_color", Color(0.30, 0.74, 0.84))
	panel.add_child(eyebrow)

	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 30)
	_title_label.add_theme_color_override("font_color", Color(0.82, 0.95, 1.0))
	panel.add_child(_title_label)

	_progress = ProgressBar.new()
	_progress.name = "Progress"
	_progress.custom_minimum_size = Vector2(480.0, 16.0)
	_progress.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_progress.min_value = 0.0
	_progress.max_value = 100.0
	_progress.show_percentage = false
	var progress_background := StyleBoxFlat.new()
	progress_background.bg_color = Color(0.04, 0.08, 0.11, 1.0)
	progress_background.border_color = Color(0.14, 0.40, 0.50, 1.0)
	progress_background.set_border_width_all(1)
	progress_background.set_corner_radius_all(4)
	_progress.add_theme_stylebox_override("background", progress_background)
	var progress_fill := StyleBoxFlat.new()
	progress_fill.bg_color = Color(0.22, 0.78, 0.88, 1.0)
	progress_fill.set_corner_radius_all(4)
	_progress.add_theme_stylebox_override("fill", progress_fill)
	panel.add_child(_progress)

	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 15)
	_status_label.add_theme_color_override("font_color", Color(0.66, 0.80, 0.84))
	panel.add_child(_status_label)

	_error_label = Label.new()
	_error_label.name = "Error"
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error_label.add_theme_font_size_override("font_size", 14)
	_error_label.add_theme_color_override("font_color", Color(1.0, 0.38, 0.30))
	_error_label.hide()
	panel.add_child(_error_label)

	_dismiss_button = Button.new()
	_dismiss_button.name = "DismissFailure"
	_dismiss_button.text = "返回当前战区"
	_dismiss_button.custom_minimum_size = Vector2(180.0, 38.0)
	_dismiss_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_dismiss_button.hide()
	_dismiss_button.pressed.connect(dismiss_failure)
	panel.add_child(_dismiss_button)
