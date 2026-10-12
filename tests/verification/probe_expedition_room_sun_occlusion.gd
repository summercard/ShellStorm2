extends Node
## 探针（只读、不断言）：远征01 逐房间的「太阳遮挡实测」。
##
## 复刻 EnemyIllumination3D._evaluate_sunlight 的判定：从身体采样点沿
## 主太阳方向光 basis.z 方向打长距离物理射线，mask=1（关卡静态世界层）。
## 射线命中 => 该采样点在投影里；未命中 => 判为太阳直射。
##
## 输出每房的「直接见太阳采样点比例」，以及射线被什么节点挡住。

const EXPEDITION_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const ROOM_SCRIPT := preload("res://src/world3d/DungeonRoom3D.gd")
const RUN_SEED := 77001199
const SUN_GROUP := &"gameplay_sun_3d"
const RAY_LENGTH := 1000.0
const SAMPLE_HEIGHTS := [0.22, 0.62, 1.03]
const GRID := 5
const INSET := 0.35


func _ready() -> void:
	ROOM_SCRIPT.use_expedition_static_layout_scenes = true
	var tower := EXPEDITION_SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	await _settle()

	var block := tower.get_node_or_null("Blocks/Expedition") as Node3D
	if block == null:
		print("SUNPROBE_FAIL 没有 Blocks/Expedition")
		get_tree().quit(1)
		return

	var sun := _find_sun(tower)
	if sun == null:
		print("SUNPROBE_FAIL 场景里找不到 DirectionalLight3D")
		get_tree().quit(1)
		return
	var toward_sun := sun.global_transform.basis.z.normalized()
	var elevation_deg := rad_to_deg(asin(clampf(toward_sun.y, -1.0, 1.0)))
	print("SUNPROBE_SUN node=%s toward_sun=%s elevation_deg=%.2f energy=%.3f color=%s" % [
		sun.name, var_to_str(toward_sun), elevation_deg, sun.light_energy,
		var_to_str(sun.light_color),
	])

	var room_ids: Array[String] = [
		"start", "room_01", "room_02", "room_03", "room_04", "room_05",
		"room_06", "room_07", "room_08", "room_09", "room_10", "boss", "extraction",
	]
	print("")
	print("SUNPROBE_HEADER room_id dims center(local_world) samples hit_sun ratio blocker_top")
	for room_id in room_ids:
		var room := block.get_node_or_null(room_id) as DungeonRoom3D
		if room == null:
			print("SUNPROBE_MISSING room=%s" % room_id)
			continue
		room.ensure_shell_built()
		room.ensure_detail_built()
		await _settle()
		_probe_room(room, toward_sun)

	print("")
	print("SUNPROBE_DONE")
	get_tree().quit(0)


func _probe_room(room: DungeonRoom3D, toward_sun: Vector3) -> void:
	var dimensions: Vector2 = room.call("get_dimensions")
	var space := room.get_world_3d().direct_space_state
	var exposed := 0
	var total := 0
	var blockers := {}
	var origin := room.global_position
	for height in SAMPLE_HEIGHTS:
		for ix in range(GRID):
			for iz in range(GRID):
				var fx := (float(ix) / float(GRID - 1) - 0.5) * (1.0 - INSET * 2.0)
				var fz := (float(iz) / float(GRID - 1) - 0.5) * (1.0 - INSET * 2.0)
				var from := origin + Vector3(fx * dimensions.x, 0.05 + float(height), fz * dimensions.y)
				var to := from + toward_sun * RAY_LENGTH
				var query := PhysicsRayQueryParameters3D.create(from, to, 1)
				query.collide_with_areas = false
				query.collide_with_bodies = true
				var hit := space.intersect_ray(query)
				total += 1
				if hit.is_empty():
					exposed += 1
					continue
				var collider := hit.get("collider") as Node
				var key := _blocker_key(collider)
				blockers[key] = int(blockers.get(key, 0)) + 1
	print("SUNPROBE room=%s dims=(%.0f,%.0f) world=(%.1f,%.1f,%.1f) samples=%d see_sun=%d ratio=%.2f blockers=%s" % [
		room.room_id, dimensions.x, dimensions.y,
		origin.x, origin.y, origin.z, total, exposed,
		float(exposed) / float(total) if total > 0 else 0.0,
		var_to_str(blockers),
	])


func _blocker_key(collider: Node) -> String:
	if collider == null:
		return "<null>"
	var parts: Array[String] = []
	var cursor: Node = collider
	var depth := 0
	while cursor != null and depth < 6:
		parts.append(cursor.name)
		cursor = cursor.get_parent()
		depth += 1
	return "/".join(parts)


func _find_sun(root: Node) -> DirectionalLight3D:
	for node in get_tree().get_nodes_in_group(SUN_GROUP):
		if node is DirectionalLight3D:
			return node as DirectionalLight3D
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is DirectionalLight3D:
			return current as DirectionalLight3D
		for child in current.get_children():
			stack.append(child as Node)
	return null


func _settle() -> void:
	for _index in range(4):
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.2).timeout
