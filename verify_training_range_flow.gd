extends Node


func _ready() -> void:
	var failures: Array[String] = []
	var progression_before: Dictionary = {}
	if BaseManager != null and BaseManager.data != null:
		progression_before = BaseManager.data._to_dict().duplicate(true)

	var scene := load("res://scenes/TrainingRange.tscn") as PackedScene
	if scene == null:
		_finish(["TrainingRange scene does not load"])
		return
	var training := scene.instantiate() as TrainingRange
	if training == null:
		_finish(["TrainingRange root does not expose its runtime contract"])
		return
	add_child(training)
	await get_tree().process_frame
	await get_tree().create_timer(0.08).timeout

	var tree := training.get_weapon_tree()
	if training.player == null or not training.player.combat_enabled:
		failures.append("Training player cannot move and shoot inside the range")
	if tree == null or not training.is_empty_loadout():
		failures.append("Training player does not enter with an empty temporary weapon tree")
	elif tree.current_ammo != 0 or tree.magazine_size != 0:
		failures.append("Empty training loadout retains stale ammo values")

	var guns := BlueprintRegistry.get_available_gunbodies(99)
	var bullets := BlueprintRegistry.get_available_bullets(99)
	if training.get_gun_selector_count() != guns.size():
		failures.append("Training console does not list every registered gun body")
	if training.get_bullet_selector_count() != bullets.size():
		failures.append("Training console does not list every registered bullet module")
	if training.get_target_count() < 4:
		failures.append("Training range does not expose a useful target suite")

	var combinations_checked := 0
	for gun_entry in guns:
		var gun_id := str(gun_entry["item_id"])
		var expected_gun := BlueprintRegistry.create_assembly_node(gun_id)
		var expected_gun_name := expected_gun.node_name if expected_gun != null else ""
		if expected_gun != null:
			expected_gun.free()
		for bullet_entry in bullets:
			var bullet_id := str(bullet_entry["item_id"])
			var expected_bullet := BlueprintRegistry.create_assembly_node(bullet_id)
			var expected_bullet_name := expected_bullet.node_name if expected_bullet != null else ""
			if expected_bullet != null:
				expected_bullet.free()
			if not training.assemble_combination(gun_id, bullet_id):
				failures.append("Training assembly rejected %s + %s" % [gun_id, bullet_id])
				continue
			var root := tree.get_root()
			var mounted: AssemblyNode = null
			if root != null:
				mounted = root.slots[AssemblyNode.SlotType.BULLET] as AssemblyNode
			if root == null or root.node_name != expected_gun_name:
				failures.append("Training assembly selected the wrong gun for %s" % gun_id)
			elif mounted == null or mounted.node_name != expected_bullet_name:
				failures.append("Training assembly selected the wrong ammo for %s" % bullet_id)
			else:
				combinations_checked += 1

	var display := training.player.get_node_or_null("WeaponAnchor/WeaponDisplay") as WeaponDisplay
	if display == null or str(display.get("_current_gun_name")) != tree.get_root().node_name:
		failures.append("Weapon display does not refresh to the latest training gun body")
	else:
		var body := display.get_node_or_null("GunBody") as Polygon2D
		if body == null or not body.visible or body.polygon.is_empty():
			failures.append("Latest training gun body has no readable visual silhouette")

	training.clear_test_loadout()
	if not training.is_empty_loadout() or tree.current_ammo != 0 or tree.magazine_size != 0:
		failures.append("Clear-loadout action leaves weapon data or ammunition behind")
	if display != null:
		var cleared_body := display.get_node_or_null("GunBody") as Polygon2D
		if cleared_body != null and cleared_body.visible:
			failures.append("Cleared training loadout leaves the old gun visible")

	if not guns.is_empty() and not bullets.is_empty():
		training.set_auto_assemble(true)
		training.select_gun(str(guns[0]["item_id"]))
		training.select_bullet(str(bullets[0]["item_id"]))
		if training.is_empty_loadout():
			failures.append("Combination switch does not auto-assemble selected gun and ammo")

	var standard: TrainingTarget = null
	var armored: TrainingTarget = null
	var runner: TrainingTarget = null
	for target in training.get_targets():
		match target.target_type:
			TrainingTarget.TargetType.STANDARD:
				if standard == null:
					standard = target
			TrainingTarget.TargetType.ARMORED:
				armored = target
			TrainingTarget.TargetType.RUNNER:
				runner = target
	if standard == null or armored == null or runner == null:
		failures.append("Standard, armored, and moving target identities are not all present")
	else:
		standard.take_damage(100, false, Vector2.RIGHT)
		armored.take_damage(100, false, Vector2.RIGHT)
		if armored.last_applied_damage >= standard.last_applied_damage:
			failures.append("Armored target does not reduce incoming test damage")
		var runner_before := runner.position
		await get_tree().create_timer(0.12).timeout
		if runner.position.distance_to(runner_before) < 1.0:
			failures.append("Moving target does not create an aim-tracking test")
		var metrics := training.get_session_metrics()
		if int(metrics.get("hits", 0)) != 2 or float(metrics.get("applied_damage", 0.0)) <= 0.0:
			failures.append("Target hits do not feed the live training session metrics")
		training.reset_session()
		metrics = training.get_session_metrics()
		if int(metrics.get("hits", -1)) != 0 or float(metrics.get("applied_damage", -1.0)) != 0.0:
			failures.append("Reset action does not clear the training session metrics")

	if not training.is_progression_unchanged():
		failures.append("Training actions mutated persistent base progression")
	training.prepare_exit()
	if not training.is_empty_loadout() or training.player.combat_enabled:
		failures.append("Training exit does not destroy the temporary loadout before transition")
	if BaseManager != null and BaseManager.data != null and BaseManager.data._to_dict() != progression_before:
		failures.append("Training lifecycle changed BaseData")

	training.queue_free()
	await get_tree().process_frame
	if combinations_checked != guns.size() * bullets.size():
		failures.append("Not every registered gun/ammo matrix combination was verified")
	_finish(failures, combinations_checked)


func _finish(failures: Array[String], combinations := 0) -> void:
	if failures.is_empty():
		print(
			"TRAINING_RANGE_FLOW_OK: empty isolated entry, %d gun/ammo combinations, three target behaviors, live metrics, and clean exit"
			% combinations
		)
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
