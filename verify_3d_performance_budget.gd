extends Node


func _ready() -> void:
	var failures: Array[String] = []
	var scene := load("res://scenes/levels3d/AbyssArchive3D.tscn") as PackedScene
	var started := Time.get_ticks_usec()
	var dungeon := scene.instantiate() as Dungeon3D
	dungeon.test_mode = true
	dungeon.run_seed_override = 4242
	add_child(dungeon)
	await get_tree().process_frame
	await get_tree().physics_frame
	var generation_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var initial_nodes := _count_nodes(dungeon)
	if generation_ms > 500.0:
		failures.append("Worst-theme initial generation exceeded 500ms: %.1fms" % generation_ms)
	if initial_nodes > 800:
		failures.append("Initial streamed scene exceeded 800 nodes: %d" % initial_nodes)

	var generation := dungeon.get_generation_snapshot()
	var max_room_build_ms := 0.0
	var max_active_rooms := 0
	var max_active_lights := 0
	for record in generation.get("records", []):
		var room_id := str(record.get("id", ""))
		var parent_id := str(record.get("parent", ""))
		if not parent_id.is_empty():
			dungeon.force_open_edge_for_test(parent_id, room_id)
		var room_started := Time.get_ticks_usec()
		dungeon.force_enter_room_for_test(room_id)
		await get_tree().process_frame
		var room_build_ms := float(Time.get_ticks_usec() - room_started) / 1000.0
		max_room_build_ms = maxf(max_room_build_ms, room_build_ms)
		var runtime := dungeon.get_runtime_snapshot()
		max_active_rooms = maxi(max_active_rooms, int(runtime.get("active_rooms", 0)))
		max_active_lights = maxi(max_active_lights, int(runtime.get("active_lights", 0)))
		# 压测房间构造而不是让已访问房的 AI 永久堆积；真实运行中远房 AI 同样会冻结。
		for value in get_tree().get_nodes_in_group("enemy_3d"):
			var enemy := value as Enemy3D
			if enemy != null and dungeon.is_ancestor_of(enemy) and enemy.room_id == room_id:
				enemy.queue_free()
		await get_tree().process_frame
	if max_room_build_ms > 120.0:
		failures.append("Single-room streamed build spike exceeded 120ms: %.1fms" % max_room_build_ms)
	if max_active_rooms > 5:
		failures.append("Streaming activated too many rooms at once: %d" % max_active_rooms)
	if max_active_lights > 14:
		failures.append("Runtime local-light budget exceeded: %d" % max_active_lights)

	var explored_nodes := _count_nodes(dungeon)
	if explored_nodes > 3500:
		failures.append("Fully explored worst-theme scene exceeded 3500 nodes: %d" % explored_nodes)

	var pool := dungeon.get_node("ProjectilePool3D") as ProjectilePool3D
	var config := {
		"direction": Vector3.FORWARD, "speed": 0.0, "damage": 1, "hostile": false,
		"tags": [], "color": Color.WHITE, "shooter": dungeon.player,
	}
	var batch: Array[Projectile3D] = []
	var pool_started := Time.get_ticks_usec()
	for index in range(96):
		batch.append(pool.acquire(config, Vector3(index * 0.03, 5.0, 0.0)))
	for projectile in batch:
		projectile.call("_retire")
	await get_tree().process_frame
	var first_created := int(pool.get_snapshot().get("created", 0))
	batch.clear()
	for index in range(96):
		batch.append(pool.acquire(config, Vector3(index * 0.03, 5.0, 0.0)))
	var second_created := int(pool.get_snapshot().get("created", 0))
	var pool_stress_ms := float(Time.get_ticks_usec() - pool_started) / 1000.0
	if first_created != 96 or second_created != first_created:
		failures.append("96-projectile stress batch was not fully reused (%d -> %d)" % [first_created, second_created])
	if pool_stress_ms > 150.0:
		failures.append("Projectile pool stress exceeded 150ms: %.1fms" % pool_stress_ms)
	for projectile in batch:
		projectile.call("_retire")

	var vision := dungeon.player.get_node_or_null("PlayerVision3D") as PlayerVision3D
	# 先允许刚切房后的遮挡边界完成一次向外舒展，再检查稳定状态是否仍重复重建。
	for _settle_frame in range(120):
		await get_tree().process_frame
	var stable_redraw_start := int(vision.get_snapshot().get("mesh_redraw_count", 0)) if vision != null else 0
	var sustained_started := Time.get_ticks_usec()
	for _frame in range(120):
		await get_tree().process_frame
	var sustained_ms_per_frame := float(Time.get_ticks_usec() - sustained_started) / 1000.0 / 120.0
	var stable_redraw_end := int(vision.get_snapshot().get("mesh_redraw_count", 0)) if vision != null else 999
	if stable_redraw_end - stable_redraw_start > 3:
		failures.append("Stable vision mesh still rebuilds every frame: %d redraws" % (stable_redraw_end - stable_redraw_start))
	if sustained_ms_per_frame > 16.0:
		failures.append("Sustained 3D runtime exceeded 16ms script/physics budget: %.2fms" % sustained_ms_per_frame)

	if failures.is_empty():
		print("3D_PERFORMANCE_BUDGET_OK: generation_ms=%.1f max_room_build_ms=%.1f initial_nodes=%d explored_nodes=%d max_active_rooms=%d max_active_lights=%d projectile_stress_ms=%.1f sustained_ms=%.2f stable_vision_redraws=%d" % [
			generation_ms, max_room_build_ms, initial_nodes, explored_nodes,
			max_active_rooms, max_active_lights, pool_stress_ms, sustained_ms_per_frame,
			stable_redraw_end - stable_redraw_start,
		])
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _count_nodes(root: Node) -> int:
	var count := 1
	for child in root.get_children():
		count += _count_nodes(child)
	return count
