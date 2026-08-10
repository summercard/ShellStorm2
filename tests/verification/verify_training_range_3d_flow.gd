extends Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var failures: Array[String] = []
	var scene := load("res://scenes/TrainingRange3D.tscn") as PackedScene
	if scene == null:
		_finish(["TrainingRange3D scene does not load"], 0)
		return
	var training := scene.instantiate() as TrainingRange3D
	training.test_mode = true
	add_child(training)
	await get_tree().process_frame
	await get_tree().physics_frame
	var snapshot := training.get_training_snapshot()
	if (
		int(snapshot.get("gun_count", 0)) != 10
		or int(snapshot.get("ranged_weapon_count", 0)) != 7
		or int(snapshot.get("melee_weapon_count", 0)) != 3
		or int(snapshot.get("bullet_count", 0)) != 8
	):
		failures.append("3D training racks do not expose all 7 ranged, 3 melee and 8 bullet entries")
	if int(snapshot.get("combination_count", 0)) != 59:
		failures.append("3D training matrix is not 59 valid ranged/melee combinations")
	var target_types: Array = snapshot.get("target_types", [])
	for type_id in ["standard", "armored", "runner"]:
		if not target_types.has(type_id):
			failures.append("3D training target missing: %s" % type_id)
	var environment: Dictionary = snapshot.get("environment", {})
	if not bool(environment.get("has_shooting_lanes", false)) or not bool(environment.get("has_equipment_wall", false)) or int(environment.get("light_count", 0)) < 6:
		failures.append("3D training environment is incomplete")
	if not bool(snapshot.get("has_reset_station", false)) or not bool(snapshot.get("has_exit", false)):
		failures.append("3D training reset/exit lifecycle is incomplete")
	var control_hint := training.get_node_or_null("HUD/ControlHint") as Label
	if control_hint == null or "Shift 冲刺" not in control_hint.text or "Esc 暂停" not in control_hint.text:
		failures.append("3D training HUD does not teach the actual combat controls")
	var pause_overlay := training.get_node_or_null("HUD/PauseOverlay") as PauseMenu3D
	if pause_overlay == null:
		failures.append("TrainingRange3D has no reusable visible pause overlay")
	else:
		await _tap_action("pause")
		if not get_tree().paused or not pause_overlay.is_pause_open():
			failures.append("TrainingRange3D Esc does not open a visible real pause")
		await _tap_action("pause")
		if get_tree().paused or pause_overlay.is_pause_open():
			failures.append("TrainingRange3D second Esc does not resume")
	var rack_ids: Dictionary = {}
	for rack in get_tree().get_nodes_in_group("training_rack_3d"):
		if not training.is_ancestor_of(rack):
			continue
		if rack.item_id.is_empty() or rack_ids.has(rack.item_id):
			failures.append("3D training rack has empty or duplicated id: %s" % rack.item_id)
		rack_ids[rack.item_id] = true
	var combinations := 0
	for gun in BlueprintRegistry.get_available_gunbodies(99):
		if "melee" in (gun.get("tags", []) as Array):
			if training.equip_combination_for_test(str(gun["item_id"]), ""):
				var melee_snapshot := training.player.get_weapon_snapshot()
				if bool(melee_snapshot.get("melee", false)) and not bool(melee_snapshot.get("uses_ammo", true)):
					combinations += 1
			continue
		for bullet in BlueprintRegistry.get_available_bullets(99):
			if training.equip_combination_for_test(str(gun["item_id"]), str(bullet["item_id"])):
				combinations += 1
	if combinations != 59:
		failures.append("Not all 59 valid ranged/melee combinations can be equipped in TrainingRange3D")
	var standard: TrainingTarget3D
	var armored: TrainingTarget3D
	var runner: TrainingTarget3D
	for target in get_tree().get_nodes_in_group("training_target_3d"):
		if not training.is_ancestor_of(target):
			continue
		match target.target_type:
			"standard": standard = target
			"armored": armored = target
			"runner": runner = target
	if standard != null and armored != null and runner != null:
		standard.take_damage(40)
		armored.take_damage(40)
		if armored.max_hp - armored.current_hp >= standard.max_hp - standard.current_hp:
			failures.append("Armored 3D target does not mitigate damage")
		var before := runner.position
		await get_tree().create_timer(0.15).timeout
		if runner.position.distance_to(before) <= 0.02:
			failures.append("Runner 3D target does not move")
	else:
		failures.append("3D target suite cannot be inspected")
	if not training.is_base_data_unchanged():
		failures.append("TrainingRange3D mutated BaseData")
	training.queue_free()
	await get_tree().process_frame
	_finish(failures, combinations)


func _finish(failures: Array[String], combinations: int) -> void:
	if failures.is_empty():
		print("TRAINING_RANGE_3D_FLOW_OK: 18 racks, 59 valid ranged/melee combinations, three target behaviors, lighting, reset, exit, and BaseData isolation pass (%d combinations)" % combinations)
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _tap_action(action: StringName) -> void:
	var pressed := InputEventAction.new()
	pressed.action = action
	pressed.pressed = true
	Input.parse_input_event(pressed)
	await get_tree().process_frame
	var released := InputEventAction.new()
	released.action = action
	released.pressed = false
	Input.parse_input_event(released)
	await get_tree().process_frame
