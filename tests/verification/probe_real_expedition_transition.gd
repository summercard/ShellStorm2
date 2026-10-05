extends Node

const TARGET_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"

var _flow: Node
var _started_usec := 0
var _last_frame_usec := 0
var _max_frame_interval_usec := 0
var _frame_count := 0
var _last_progress := -1.0
var _finished := false
var _failed := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_flow = get_node_or_null("/root/SceneTransitionFlow")
	if _flow == null:
		_fail("SceneTransitionFlow 不可用")
		return
	_flow.transition_started.connect(_on_transition_started)
	_flow.transition_progress_changed.connect(_on_transition_progress)
	_flow.transition_finished.connect(_on_transition_finished)
	_flow.transition_failed.connect(_on_transition_failed)
	await get_tree().process_frame
	# 监测器不能留在 current_scene：change_scene 会释放它，随后所有
	# finished/failed 监听与超时检查消失，形成“永远没有完成日志”的假卡死。
	get_tree().current_scene = null
	reparent(_flow)
	var error: Error = _flow.request_scene_change(TARGET_SCENE, "远征关卡01")
	if error != OK:
		_fail("request_scene_change: %s" % error_string(error))


func _process(_delta: float) -> void:
	var now_usec := Time.get_ticks_usec()
	if _last_frame_usec != 0:
		_max_frame_interval_usec = maxi(_max_frame_interval_usec, now_usec - _last_frame_usec)
	_last_frame_usec = now_usec
	_frame_count += 1
	if _frame_count > 900 and not _finished and not _failed:
		_fail("等待 transition_finished 超时，state=%s" % _flow.get_transition_state())


func _on_transition_started(path: String, title: String) -> void:
	_started_usec = Time.get_ticks_usec()
	print("REAL_LOADING_STARTED path=", path, " title=", title)


func _on_transition_progress(progress: float, status: String) -> void:
	if progress + 0.0001 < _last_progress:
		_fail("进度倒退 %.3f -> %.3f" % [_last_progress, progress])
		return
	_last_progress = progress
	print("REAL_LOADING_PROGRESS %.3f %s" % [progress, status])


func _on_transition_finished(path: String) -> void:
	if path != TARGET_SCENE:
		_fail("完成路径错误: %s" % path)
		return
	_finished = true
	var elapsed_ms := float(Time.get_ticks_usec() - _started_usec) / 1000.0
	print("REAL_LOADING_FINISHED elapsed_ms=%.1f frames=%d max_frame_interval_ms=%.3f state=%s" % [
		elapsed_ms, _frame_count, float(_max_frame_interval_usec) / 1000.0,
		_flow.get_transition_state(),
	])
	print("[PASS] REAL_EXPEDITION_SCENE_TRANSITION")
	call_deferred("_quit_ok")


func _on_transition_failed(path: String, reason: String) -> void:
	print("REAL_LOADING_FAILED path=", path, " reason=", reason)
	_fail("transition_failed")


func _quit_ok() -> void:
	get_tree().quit(0)


func _fail(reason: String) -> void:
	if _finished or _failed:
		return
	_failed = true
	print("[FAIL] REAL_EXPEDITION_SCENE_TRANSITION ", reason)
	get_tree().quit(1)
