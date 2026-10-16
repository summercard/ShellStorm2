extends Node
## 暂停菜单「训练靶场」入口验收：基地可用、靶场自身不可用。
##
## 第二条断言不是洁癖 —— 靶场自己也在用同一个暂停面板（TrainingRange3D.tscn
## 引用了 ui_pause_overlay_screen.tscn）。若入口只按"面板存在"判定，
## 玩家在靶场里按 Esc 就会看到通往靶场的按钮，点下去等于靶场进靶场。

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var failures: Array[String] = []
	# 基地：入口必须可用
	var base_scene := load("res://scenes/BaseWorld3D.tscn") as PackedScene
	if base_scene == null:
		_finish(["BaseWorld3D scene does not load"])
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
			failures.append("training range entry is not available in the base")
		var button := base_pause.get_node_or_null(
			"Center/Panel/Margin/MainPage/TrainingRangeButton"
		) as Button
		if button == null:
			failures.append("pause menu has no training range button")
		elif button.visible and button.disabled:
			failures.append("training range button is disabled while in the base")
	# 基地的靶场设施牌应当已经撤掉
	for facility in get_tree().get_nodes_in_group("base_facility"):
		if not base.is_ancestor_of(facility):
			continue
		if facility.get("facility_id") == "training_range":
			failures.append("base still shows the ground-level training range facility plate")
	base.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	# 靶场：入口必须不可用（防套娃）
	var range_scene := load("res://scenes/TrainingRange3D.tscn") as PackedScene
	if range_scene == null:
		_finish(["TrainingRange3D scene does not load"])
		return
	var training := range_scene.instantiate() as TrainingRange3D
	training.test_mode = true
	add_child(training)
	await get_tree().process_frame
	await get_tree().physics_frame
	var range_pause := training.get_node_or_null("HUD/PauseOverlay") as PauseMenu3D
	if range_pause == null:
		failures.append("TrainingRange3D has no reusable pause overlay")
	else:
		if range_pause.is_training_range_available():
			failures.append("training range entry is available inside the training range itself (nesting)")
	training.queue_free()
	await get_tree().process_frame
	_finish(failures)


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print(
			"PAUSE_MENU_TRAINING_ENTRY_OK: entry available in base, unavailable inside the range, ground facility plate removed"
		)
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
