extends Node
## 暂停菜单「训练靶场」入口验收。
##
## 会话背景：这条入口曾按 `root is BaseWorld3D` 判"在基地"，而玩家的基地其实是
## TowerDescent3D（99F 基地营地，主场景），BaseWorld3D 只是历史兼容基地 ——
## 于是按钮在真正的基地里永远显示"仅基地可用"。本脚本把正确口径钉住：
## **在基地 = 场景根自己的 is_player_inside_facility()**。
##
## 四个用例：
##   A. 兼容基地 BaseWorld3D 可用
##   B. 靶场内部不可用（防套娃：靶场复用同一个暂停面板）
##   C. 判据必须跟着 is_player_inside_facility() 走，而不是跟着类名走
##   D. 真基地 TowerDescent3D 必须仍然提供该方法（改名即红）
##   E. 基地地面不再有靶场设施牌

const PAUSE_SCENE_PATH := "res://assets/art/ui/pause_3d/ui_pause_overlay_screen.tscn"
const TOWER_SCRIPT_PATH := "res://src/world3d/TowerDescent3D.gd"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var failures: Array[String] = []
	await _check_compat_base(failures)
	await _check_training_range(failures)
	await _check_predicate_follows_base_volume(failures)
	_check_real_base_exposes_predicate(failures)
	await _check_return_routing(failures)
	_finish(failures)


## A + E：兼容基地可用，且地面设施牌已撤
func _check_compat_base(failures: Array[String]) -> void:
	var base_scene := load("res://scenes/BaseWorld3D.tscn") as PackedScene
	if base_scene == null:
		failures.append("BaseWorld3D scene does not load")
		return
	var base := base_scene.instantiate()
	add_child(base)
	await get_tree().process_frame
	await get_tree().physics_frame
	var base_pause := base.get_node_or_null("HUD/PauseOverlay") as PauseMenu3D
	if base_pause == null:
		failures.append("BaseWorld3D has no reusable pause overlay")
	else:
		if not base_pause.is_training_range_available():
			failures.append("training range entry is not available in the compat base")
		var button := base_pause.get_node_or_null(
			"Center/Panel/Margin/MainPage/TrainingRangeButton"
		) as Button
		if button == null:
			failures.append("pause menu has no training range button")
		elif button.visible and button.disabled:
			failures.append("training range button is disabled while in the compat base")
	for facility in get_tree().get_nodes_in_group("base_facility"):
		if not base.is_ancestor_of(facility):
			continue
		if facility.get("facility_id") == "training_range":
			failures.append("base still shows the ground-level training range facility plate")
	base.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


## B：靶场内部不可用（防套娃）
func _check_training_range(failures: Array[String]) -> void:
	var range_scene := load("res://scenes/TrainingRange3D.tscn") as PackedScene
	if range_scene == null:
		failures.append("TrainingRange3D scene does not load")
		return
	var training := range_scene.instantiate() as TrainingRange3D
	training.test_mode = true
	add_child(training)
	await get_tree().process_frame
	await get_tree().physics_frame
	var range_pause := training.get_node_or_null("HUD/PauseOverlay") as PauseMenu3D
	if range_pause == null:
		failures.append("TrainingRange3D has no reusable pause overlay")
	elif range_pause.is_training_range_available():
		failures.append("training range entry is available inside the training range itself (nesting)")
	training.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


## C：判据必须由 is_player_inside_facility() 驱动。
## 用一个最小替身场景根复现真基地的接口形状，检查可用性随它翻转 ——
## 这样即使有人把 BaseWorld3D 换掉，只要基地仍提供该接口，入口就不会再失灵。
func _check_predicate_follows_base_volume(failures: Array[String]) -> void:
	var pause_scene := load(PAUSE_SCENE_PATH) as PackedScene
	if pause_scene == null:
		failures.append("pause overlay scene does not load")
		return
	var stub_script := GDScript.new()
	stub_script.source_code = (
		"extends Node3D\n"
		+ "\n"
		+ "var inside_facility := false\n"
		+ "\n"
		+ "func is_player_inside_facility() -> bool:\n"
		+ "\treturn inside_facility\n"
	)
	stub_script.reload()
	var stub := Node3D.new()
	stub.set_script(stub_script)
	add_child(stub)
	var hud := CanvasLayer.new()
	hud.name = "HUD"
	stub.add_child(hud)
	var overlay := pause_scene.instantiate() as PauseMenu3D
	hud.add_child(overlay)
	await get_tree().process_frame
	stub.set("inside_facility", false)
	if overlay.is_training_range_available():
		failures.append("training range entry stays available while the player is outside the base volume")
	stub.set("inside_facility", true)
	if not overlay.is_training_range_available():
		failures.append(
			"training range entry does not follow is_player_inside_facility(): the real base (TowerDescent3D) would be rejected"
		)
	stub.queue_free()
	await get_tree().process_frame


## D：真基地必须仍然提供该方法，否则上面那条判据会静默失效。
func _check_real_base_exposes_predicate(failures: Array[String]) -> void:
	var tower_script := load(TOWER_SCRIPT_PATH) as GDScript
	if tower_script == null:
		failures.append("TowerDescent3D script does not load")
		return
	var found := false
	for method in tower_script.get_script_method_list():
		if str(method.get("name", "")) == "is_player_inside_facility":
			found = true
			break
	if not found:
		failures.append(
			"TowerDescent3D no longer exposes is_player_inside_facility(); the training range entry loses its in-base predicate"
		)


## F + G：退出必须原路返回，且回 99F 基地时要登记入口意图。
## 这里钉的是"绝不把玩家送去历史兼容基地"：没有登记来源时回落到主场景基地，
## 而不是 GameDesignConfig.BASE_SCENE_3D。
func _check_return_routing(failures: Array[String]) -> void:
	var range_scene := load("res://scenes/TrainingRange3D.tscn") as PackedScene
	if range_scene == null:
		failures.append("TrainingRange3D scene does not load")
		return
	var training := range_scene.instantiate() as TrainingRange3D
	training.test_mode = true
	add_child(training)
	await get_tree().process_frame
	var main_scene := GameDesignConfig.MAIN_SCENE
	var compat_base := GameDesignConfig.BASE_SCENE_3D
	# F1：从 99F 基地来 → 回 99F 基地
	TrainingRange3D.set_origin_scene_path(main_scene)
	_expect_resolved(training, main_scene, "origin = 99F base", failures)
	# F2：从兼容基地来 → 仍回兼容基地，不擅自改道
	TrainingRange3D.set_origin_scene_path(compat_base)
	_expect_resolved(training, compat_base, "origin = compat base", failures)
	# F3：未登记来源 → 回主场景基地，绝不能是历史兼容基地
	TrainingRange3D.set_origin_scene_path("")
	_expect_resolved(training, main_scene, "no origin", failures)
	# G1：目标为主场景基地时必须登记入口意图，否则会被当成冷启动/普通恢复
	TrainingRange3D.set_origin_scene_path(main_scene)
	var request_id := int(training.call("_register_return_entry_intent", main_scene))
	if request_id <= 0:
		failures.append("returning to the 99F base did not register a GameEntryFlow entry intent")
	else:
		var pending := GameEntryFlow.peek_pending_entry()
		if str(pending.get("reason", "")) != GameEntryFlow.REASON_ABORT_RETURN_99F:
			failures.append(
				"99F base return registered the wrong entry reason: %s" % str(pending.get("reason", ""))
			)
		if str(pending.get("spawn_target", "")) != GameEntryFlow.SPAWN_BASE_99F:
			failures.append(
				"99F base return registered the wrong spawn target: %s" % str(pending.get("spawn_target", ""))
			)
		GameEntryFlow.cancel_request(request_id)
	# G2：回兼容基地不需要、也不该登记主场景入口意图
	if int(training.call("_register_return_entry_intent", compat_base)) != 0:
		failures.append("returning to the compat base registered a main-scene entry intent")
	training.queue_free()
	await get_tree().process_frame


func _expect_resolved(
	training: TrainingRange3D, expected: String, label: String, failures: Array[String]
) -> void:
	var resolved := str(training.call("_resolve_return_scene_path"))
	if resolved != expected:
		failures.append("training range exit routing wrong for %s: got %s, expected %s" % [label, resolved, expected])


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print(
			"PAUSE_MENU_TRAINING_ENTRY_OK: available in base (follows is_player_inside_facility), unavailable inside the range, real base exposes the predicate, ground facility plate removed"
		)
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
