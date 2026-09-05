extends Node

const PLAYER_SCENE := preload("res://scenes/Player3D.tscn")


func _ready() -> void:
	var failures: Array[String] = []
	var tower := (load("res://scenes/TowerDescent3D.tscn") as PackedScene).instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990099
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	var facility := (tower.get("_room_by_id") as Dictionary).get("facility") as DungeonRoom3D
	if facility == null:
		failures.append("99层基地没有生成")
	else:
		var mezzanine := facility.find_child("V021东墙阁楼主体结构", true, false) as Node3D
		var collision := mezzanine.get_node_or_null("StaticCollision") if mezzanine else null
		if collision == null:
			failures.append("阁楼栏杆碰撞节点缺失")
		else:
			_expect_guardrail(collision.get_node_or_null("Blocker_001") as CollisionShape3D, Vector3(19.4, 1.2, 0.14), failures)
			_expect_guardrail(collision.get_node_or_null("Blocker_006") as CollisionShape3D, Vector3(0.14, 1.2, 7.390001), failures)
			var player := PLAYER_SCENE.instantiate() as Player3D
			player.start_with_weapon = false
			add_child(player)
			await get_tree().physics_frame
			await _push_player(player, facility, Vector3(5.0, 6.08, -7.0), Vector3(0, 0, 1), 180)
			if facility.to_local(player.global_position).z > -5.34:
				failures.append("南侧阁楼栏杆未阻挡角色")
			player.global_position = facility.global_position + Vector3(0.0, 6.08, -8.0)
			player.velocity = Vector3.ZERO
			await _push_player(player, facility, Vector3.ZERO, Vector3(-1, 0, 0), 180)
			if facility.to_local(player.global_position).x < -4.90:
				failures.append("西侧阁楼栏杆未阻挡角色")
			player.queue_free()
	tower.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("BASE99_LOFT_GUARDRAIL_COLLISION_OK: south/west rail guards block Player3D; northwest stair entry remains unblocked")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _expect_guardrail(shape_node: CollisionShape3D, expected: Vector3, failures: Array[String]) -> void:
	if shape_node == null or not shape_node.shape is BoxShape3D:
		failures.append("阁楼栏杆没有BoxShape3D阻挡")
		return
	var size := (shape_node.shape as BoxShape3D).size
	if not is_equal_approx(size.y, expected.y) or size.x < expected.x - 0.01 or size.z < expected.z - 0.01:
		failures.append("阁楼栏杆阻挡规格错误: %s" % size)


func _push_player(player: Player3D, facility: Node3D, start: Vector3, direction: Vector3, frames: int) -> void:
	if start != Vector3.ZERO:
		player.global_position = facility.global_position + start
		player.velocity = Vector3.ZERO
	for _frame in range(frames):
		player.set_test_move_direction(direction)
		await get_tree().physics_frame
	player.set_test_move_direction(Vector3.ZERO)
