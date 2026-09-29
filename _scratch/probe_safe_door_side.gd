extends Node
## 临时探针：实测「入口安全屋 -> 第一个房间」那扇门到底在哪一面墙上。
## 口径全部取运行时真值（房表落位 + 装配后节点），不看设计文档。

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"


func _ready() -> void:
	for seed_value in [77001199, 12345, 990095, 20260929, 424242, 7]:
		await _run(seed_value)
	get_tree().quit(0)


func _run(seed_value: int) -> void:
	var scene := load(EXPEDITION_SCENE) as PackedScene
	var tower := scene.instantiate()
	tower.test_mode = true
	tower.run_seed_override = seed_value
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("================ run_seed=%d ================" % seed_value)

	var safe_room: DungeonRoom3D = null
	for key in tower._room_by_id.keys():
		var room := tower._room_by_id.get(key) as DungeonRoom3D
		if room == null:
			continue
		var size_meta = room.get_meta("room_size_m", Vector2.ZERO)
		print("    [房] key=%-14s id=%-16s type=%-14s 中心=%s 尺寸=%s" % [
			str(key), room.room_id, room.room_type,
			str(room.global_position), str(size_meta)
		])
		if str(key) == "f00_entry" or room.room_id == "f00_entry" or room.room_id == "start":
			safe_room = room
	if safe_room == null:
		for key in tower._room_by_id.keys():
			var room := tower._room_by_id.get(key) as DungeonRoom3D
			if room != null and room.room_type in ["SAFE_ROOM", "STAIR_LOBBY"]:
				safe_room = room
				break
	if safe_room == null:
		print("  没有 SAFE_ROOM")
		tower.queue_free()
		return

	print("  安全屋 %s  中心=%s  尺寸=%s  朝向步数=%s" % [
		safe_room.room_id,
		str(safe_room.global_position),
		str(safe_room.get_meta("room_size_m", Vector2.ZERO)),
		str(safe_room.get_meta("safe_room_orientation_steps", "?")),
	])
	print("  doors=%s" % str(safe_room.doors))
	print("  door_targets=%s" % str(safe_room.door_targets))

	var first_room: DungeonRoom3D = null
	var first_key := ""
	for target_key in safe_room.door_targets.values():
		var key := str(target_key)
		if key.is_empty() or key == "facility":
			continue
		first_room = tower._room_by_id.get(key) as DungeonRoom3D
		first_key = key
		break

	for direction in safe_room.doors:
		var face_x := 7.5
		var face_z := 7.5
		var local := Vector3.ZERO
		match direction:
			"north":
				local = Vector3(0, 0, -face_z)
			"south":
				local = Vector3(0, 0, face_z)
			"west":
				local = Vector3(-face_x, 0, 0)
			"east":
				local = Vector3(face_x, 0, 0)
		var world := safe_room.global_transform * local
		print("    门 %-5s -> target=%-10s 世界=%s" % [
			direction, str(safe_room.door_targets.get(direction, "")), str(world)
		])

	if first_room != null:
		print("  第一个房间 %s  中心=%s  朝向步数=%s" % [
			first_key,
			str(first_room.global_position),
			str(first_room.get_meta("authored_layout_alignment_deg", "?")),
		])
		print("    doors=%s" % str(first_room.doors))
		var delta: Vector3 = first_room.global_position - safe_room.global_position
		print("    相对安全屋的平面位移 (x=%.1f, z=%.1f) => 安全屋应朝 %s 开" % [
			delta.x, delta.z, _dominant_side(delta)
		])
	tower.queue_free()


func _dominant_side(delta: Vector3) -> String:
	if absf(delta.x) >= absf(delta.z):
		return "东" if delta.x > 0.0 else "西"
	return "南" if delta.z > 0.0 else "北"
