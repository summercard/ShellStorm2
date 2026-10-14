extends Node
## 门洞通行实测 v2：**先关掉门扇本体碰撞**，再用一个「门洞体积盒」
## （门宽 × 2.5m 高 × 0.8m 厚）在实际门位做重叠检测。
## 有东西压住这个盒 = 玩家过不去 —— 这就是「被墙挡住」的直接物证。
##
## 与 v1 的差别：v1 的射线被「关着的门扇」挡在 0.21m 处，永远看不到门扇后面的墙。

const EXP01_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const SEEDS: Array[int] = [286648852, 3198984856, 20260919, 77001199, 11111, 22222, 33333, 77777, 123456, 987654, 42424242, 1357911, 8888, 55555]
const KEYS: Array[String] = [
	"start", "room_01", "room_02", "room_03", "room_04", "room_05",
	"room_06", "room_07", "room_08", "room_09", "room_10", "boss", "extraction",
]
const DOOR_W := 1.4
const DOOR_H := 1.9
const DOOR_D := 0.4


func _ready() -> void:
	call_deferred("probe")


func probe() -> void:
	for seed_value in SEEDS:
		await _one(seed_value)
	print("EXP01_DOOR_BLOCK2_DONE")
	get_tree().quit(0)


func _one(seed_value: int) -> void:
	var tower := EXP01_SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = seed_value
	add_child(tower)
	for _i in range(8):
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	var disabled := _disable_door_collision(tower)
	print("")
	print("========== SEED %d 门洞体积盒实测（已关 %d 个门扇碰撞） ==========" % [seed_value, disabled])
	var space := get_viewport().world_3d.direct_space_state
	var seen: Array[String] = []
	var blocked := 0
	var total := 0
	for key in KEYS:
		var room := tower._room_by_id.get(key) as DungeonRoom3D
		if room == null:
			continue
		var dims := room.get_dimensions()
		var center := room.global_position
		var half := dims * 0.5
		for port_value in room.connection_ports:
			var port := port_value as Dictionary
			var side := str(port.get("side", ""))
			var lane := float(port.get("lane_m", 0.0))
			var target := str(port.get("target_room_id", ""))
			if target.is_empty() or side.is_empty():
				continue
			if "%s|%s" % [key, target] in seen:
				continue
			seen.append("%s|%s" % [key, target])
			seen.append("%s|%s" % [target, key])
			total += 1
			var door := _door_world(center, half, side, lane)
			var normal := _normal(side)
			var shape := BoxShape3D.new()
			shape.size = (
				Vector3(DOOR_D, DOOR_H, DOOR_W) if normal.x != 0.0
				else Vector3(DOOR_W, DOOR_H, DOOR_D)
			)
			var params := PhysicsShapeQueryParameters3D.new()
			params.shape = shape
			params.transform = Transform3D(
				Basis(Vector3.UP, deg_to_rad(float(room.get_meta("template_rotation_deg", 0.0)))),
				door + Vector3(0, 0.35 + DOOR_H * 0.5, 0)
			)
			params.collision_mask = 0xFFFFFFFF
			params.collide_with_bodies = true
			params.collide_with_areas = false
			var hits := space.intersect_shape(params, 12)
			var names: Array[String] = []
			for hit_value in hits:
				var collider := (hit_value as Dictionary).get("collider") as Node
				var desc := _describe(collider)
				if _ignored(desc):
					continue
				names.append(desc)
			if names.is_empty():
				print("  %-10s→%-10s %-5s 洞口(%7.2f,%7.2f) 畅通✅" % [
					key, target, side, door.x, door.z,
				])
				continue
			blocked += 1
			print("  %-10s→%-10s %-5s 洞口(%7.2f,%7.2f) 🔴被挡: %s" % [
				key, target, side, door.x, door.z, " | ".join(names),
			])
	print("  >>> 实测 %d 个门，被挡 %d 个" % [total, blocked])
	tower.free()
	await get_tree().process_frame
	await get_tree().process_frame


## 关掉「门扇本体」的碰撞。门扇在 Blocks/Door_* 下，名字含 Door 且带 StaticBody3D。
func _disable_door_collision(root: Node) -> int:
	var count := 0
	for value in root.find_children("*", "StaticBody3D", true, false):
		var body := value as StaticBody3D
		if body == null:
			continue
		var chain := _describe(body)
		var is_door := false
		for part in chain.split("/"):
			if part.begins_with("Door_") or part.contains("DoorLeaf") or part.contains("RoomDoor"):
				is_door = true
				break
		if not is_door:
			continue
		body.collision_layer = 0
		body.collision_mask = 0
		count += 1
	return count


## 地面/地砖/地板承重/相机代理——与「能不能走过去」无关，全部忽略。
func _ignored(desc: String) -> bool:
	var low := desc.to_lower()
	return (
		low.contains("floortile")
		or low.contains("floorsupport")
		or low.contains("tilecollision")
		or low.contains("cameraonly")
		or low.contains("walk_surface")
		or low.contains("ceiling")
	)


func _describe(node: Node) -> String:
	if node == null:
		return "<null>"
	var chain: Array[String] = []
	var cursor: Node = node
	var depth := 0
	while cursor != null and depth < 4:
		chain.append(str(cursor.name))
		cursor = cursor.get_parent()
		depth += 1
	return "/".join(chain)


func _normal(side: String) -> Vector3:
	match side:
		"north":
			return Vector3(0, 0, -1)
		"south":
			return Vector3(0, 0, 1)
		"east":
			return Vector3(1, 0, 0)
		"west":
			return Vector3(-1, 0, 0)
	return Vector3.ZERO


func _door_world(center: Vector3, half: Vector2, side: String, lane: float) -> Vector3:
	match side:
		"north":
			return center + Vector3(lane, 0, -half.y)
		"south":
			return center + Vector3(lane, 0, half.y)
		"east":
			return center + Vector3(half.x, 0, lane)
		"west":
			return center + Vector3(-half.x, 0, lane)
	return center
