extends Node

var _flow: Node
var _last_frame_usec := 0
var _max_frame_interval_usec := 0
var _frame_count := 0
var _probe_started := false
var _finished_seen := false
var _transition_runtime_ready := false


func is_transition_runtime_ready() -> bool:
	return _transition_runtime_ready


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_transition_runtime_ready = false
	call_deferred("_mark_runtime_ready")
	_flow = get_node_or_null("/root/SceneTransitionFlow")
	if _flow == null:
		_fail("找不到 SceneTransitionFlow autoload")
		return
	if _flow.get_transition_state() != "idle":
		_connect_finished()
		print("LOADING_PROBE_TARGET_REENTRY state=", _flow.get_transition_state())
		return
	_run_probe()


func _mark_runtime_ready() -> void:
	for _index in range(3):
		await get_tree().process_frame
	_transition_runtime_ready = true
	print("LOADING_TARGET_GATE_TRUE frame=", _frame_count)


func _process(_delta: float) -> void:
	var now_usec := Time.get_ticks_usec()
	if _last_frame_usec != 0:
		_max_frame_interval_usec = max(_max_frame_interval_usec, now_usec - _last_frame_usec)
	_last_frame_usec = now_usec
	_frame_count += 1
	if _frame_count > 300 and not _finished_seen:
		_fail("等待 transition_finished 超时")


func _run_probe() -> void:
	if _probe_started:
		return
	_probe_started = true
	var target_path := "res://tests/verification/verify_scene_transition_loading.tscn"
	for path: String in ["res://src/world3d/TowerDescent3D.gd", "res://src/world3d/Dungeon3D.gd", "res://scenes/TowerDescent3D.tscn"]:
		var dependencies: PackedStringArray = ResourceLoader.get_dependencies(path)
		print("LOADING_DEPENDENCIES ", path, " count=", dependencies.size(), " raw=", dependencies)
	var static_dependencies: Array[String] = _flow.call("_get_static_dependencies", "res://src/world3d/TowerDescent3D.gd")
	if static_dependencies.is_empty():
		_fail("静态 preload/extends 扫描为空")
		return
	print("LOADING_STATIC_SCRIPT_DEPENDENCIES count=", static_dependencies.size())
	var present_error: Error = await _flow.present_loading_frame("加载控制器验证")
	if present_error != OK:
		_fail("present_loading_frame 返回 %s" % error_string(present_error))
		return
	if _flow.get_transition_state() != "preparing":
		_fail("present_loading_frame 未保持 preparation 状态")
		return
	print("LOADING_FRAME_PRESENTED state=", _flow.get_transition_state())
	_connect_finished()
	var request_error: Error = _flow.request_scene_change(target_path, "加载控制器验证")
	if request_error != OK:
		_fail("request_scene_change 返回 %s" % error_string(request_error))
		return
	print("LOADING_REQUEST_ACCEPTED state=", _flow.get_transition_state())


func _connect_finished() -> void:
	if not _flow.transition_finished.is_connected(_on_transition_finished):
		_flow.transition_finished.connect(_on_transition_finished)


func _on_transition_finished(path: String) -> void:
	if path != "res://tests/verification/verify_scene_transition_loading.tscn":
		_fail("finished 路径错误：%s" % path)
		return
	_finished_seen = true
	print("LOADING_MAX_FRAME_INTERVAL_MS %.3f" % (float(_max_frame_interval_usec) / 1000.0))
	print("LOADING_FINISHED_RESULT PASS path=", path)
	print("[PASS] SCENE_TRANSITION_LOADING_CONTROLLER")
	call_deferred("_quit_ok")


func _quit_ok() -> void:
	get_tree().quit(0)


func _fail(reason: String) -> void:
	print("[FAIL] SCENE_TRANSITION_LOADING_CONTROLLER ", reason)
	get_tree().quit(1)
