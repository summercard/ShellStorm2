extends Node
## 一次性探针：98F 西侧竖向交通（楼梯井洞口 + 楼梯资产碰撞）与主人的办公室足迹的
## 真实叠压关系。只打印 AABB，不做断言。

const SEED := 990098


func _ready() -> void:
	_watchdog()
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = SEED
	tower.force_new_game_opening_for_test = true
	add_child(tower)
	for index in range(8):
		await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().create_timer(0.35).timeout

	# 关注的平面窗口：主人的办公室 x[-40,-25] z[-5,15] 再向西扩到 x=-52。
	var window := AABB(Vector3(-52.0, -40.0, -14.0), Vector3(32.0, 30.0, 52.0))
	print("PROBE_SHAFT window=", window)
	var bodies: Array[Node] = []
	_collect_static_bodies(tower, bodies)
	bodies.sort_custom(func(a: Node, b: Node) -> bool:
		return str(a.get_path()) < str(b.get_path()))
	for body_value in bodies:
		var body := body_value as CollisionObject3D
		if body == null:
			continue
		var path := str(body.get_path()).replace("/root/ProbeFloor98WestShaft/TowerDescent3D/", "")
		for shape_value in body.get_children():
			var collision := shape_value as CollisionShape3D
			if collision == null or collision.shape == null:
				continue
			var world_aabb := _shape_world_aabb(collision)
			if not window.intersects(world_aabb):
				continue
			print("PROBE_SHAFT aabb path=", path, "/", collision.name,
				" min=(%.2f,%.2f,%.2f)" % [world_aabb.position.x, world_aabb.position.y, world_aabb.position.z],
				" max=(%.2f,%.2f,%.2f)" % [world_aabb.end.x, world_aabb.end.y, world_aabb.end.z],
				" layer=", body.collision_layer)
	print("PROBE_FLOOR98_WEST_SHAFT_DONE")
	get_tree().quit(0)


func _collect_static_bodies(node: Node, out: Array[Node]) -> void:
	for child in node.get_children():
		if child is StaticBody3D:
			out.append(child)
		_collect_static_bodies(child, out)


func _watchdog() -> void:
	await get_tree().create_timer(20.0).timeout
	printerr("PROBE_SHAFT_WATCHDOG_TIMEOUT")
	get_tree().quit(9)


func _shape_world_aabb(collision: CollisionShape3D) -> AABB:
	var shape := collision.shape
	var local := AABB()
	if shape is BoxShape3D:
		local = AABB(-shape.size * 0.5, shape.size)
	elif shape is ConvexPolygonShape3D:
		var points: PackedVector3Array = (shape as ConvexPolygonShape3D).points
		if points.is_empty():
			return AABB()
		local = AABB(points[0], Vector3.ZERO)
		for point in points:
			local = local.expand(point)
		local = local.grow(0.001)
	elif shape is ConcavePolygonShape3D:
		var faces: PackedVector3Array = (shape as ConcavePolygonShape3D).get_faces()
		if faces.is_empty():
			return AABB()
		local = AABB(faces[0], Vector3.ZERO)
		for point in faces:
			local = local.expand(point)
		local = local.grow(0.001)
	else:
		return AABB()
	var xform := collision.global_transform
	var corners: Array[Vector3] = [
		xform * local.position,
		xform * Vector3(local.end.x, local.position.y, local.position.z),
		xform * Vector3(local.position.x, local.end.y, local.position.z),
		xform * Vector3(local.position.x, local.position.y, local.end.z),
		xform * Vector3(local.end.x, local.end.y, local.position.z),
		xform * Vector3(local.end.x, local.position.y, local.end.z),
		xform * Vector3(local.position.x, local.end.y, local.end.z),
		xform * local.end,
	]
	var world := AABB(corners[0], Vector3.ZERO)
	for corner in corners:
		world = world.expand(corner)
	return world
