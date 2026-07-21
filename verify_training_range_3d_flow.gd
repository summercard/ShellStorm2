extends Node


func _ready() -> void:
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
	if int(snapshot.get("gun_count", 0)) != 7 or int(snapshot.get("bullet_count", 0)) != 8:
		failures.append("3D training racks do not expose all 7 guns and 8 bullets")
	if int(snapshot.get("combination_count", 0)) != 56:
		failures.append("3D training matrix is not 56 combinations")
	var target_types: Array = snapshot.get("target_types", [])
	for type_id in ["standard", "armored", "runner"]:
		if not target_types.has(type_id):
			failures.append("3D training target missing: %s" % type_id)
	var environment: Dictionary = snapshot.get("environment", {})
	if not bool(environment.get("has_shooting_lanes", false)) or not bool(environment.get("has_equipment_wall", false)) or int(environment.get("light_count", 0)) < 6:
		failures.append("3D training environment is incomplete")
	if not bool(snapshot.get("has_reset_station", false)) or not bool(snapshot.get("has_exit", false)):
		failures.append("3D training reset/exit lifecycle is incomplete")
	var rack_ids: Dictionary = {}
	for rack in get_tree().get_nodes_in_group("training_rack_3d"):
		if not training.is_ancestor_of(rack):
			continue
		if rack.item_id.is_empty() or rack_ids.has(rack.item_id):
			failures.append("3D training rack has empty or duplicated id: %s" % rack.item_id)
		rack_ids[rack.item_id] = true
	var combinations := 0
	for gun in BlueprintRegistry.get_available_gunbodies(99):
		for bullet in BlueprintRegistry.get_available_bullets(99):
			if training.equip_combination_for_test(str(gun["item_id"]), str(bullet["item_id"])):
				combinations += 1
	if combinations != 56:
		failures.append("Not all 56 combinations can be equipped in TrainingRange3D")
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
		print("TRAINING_RANGE_3D_FLOW_OK: 15 racks, 56 combinations, three target behaviors, lighting, reset, exit, and BaseData isolation pass (%d combinations)" % combinations)
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
