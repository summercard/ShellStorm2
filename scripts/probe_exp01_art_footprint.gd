extends Node
## 决定性检查（含安全屋）：每房的**美术壳占地** vs **房间应有占地**，
## 并把**门位处的实体墙件**点出来 —— 那正是「被墙挡住」的物证。
##
## 判据：房间在场景里 yaw 恒 0；美术壳若转错 90°，其 AABB 的 (x,z) 相对房间尺寸会**转置**。
## 安全屋额外看：美术壳里的门墙件（含门洞）落在哪面墙，与本局门位是否同一面。

const EXP01_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const SEEDS: Array[int] = [286648852, 77001199, 20260919]
const TOL := 0.75
const KEYS: Array[String] = [
	"start", "room_01", "room_02", "room_03", "room_04", "room_05",
	"room_06", "room_07", "room_08", "room_09", "room_10", "boss", "extraction",
]


func _ready() -> void:
	call_deferred("probe")


func probe() -> void:
	for seed_value in SEEDS:
		await _one(seed_value)
	print("EXP01_ART_FOOTPRINT_DONE")
	get_tree().quit(0)


func _one(seed_value: int) -> void:
	var tower := EXP01_SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = seed_value
	add_child(tower)
	for _i in range(8):
		await get_tree().process_frame
		await get_tree().physics_frame
	print("")
	print("========== SEED %d ==========" % seed_value)
	for key in KEYS:
		var room := tower._room_by_id.get(key) as DungeonRoom3D
		if room == null:
			print("  %-11s <缺>" % key)
			continue
		var art := room.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
		if art == null:
			art = room.get_node_or_null("SafeRoomArtRoot") as Node3D
		var dims := room.get_dimensions()
		var box := _art_aabb(art)
		var art_yaw := rad_to_deg(art.global_rotation.y) if art != null else 0.0
		var size := box.size
		var center := box.get_center()
		var rc := room.global_position
		var direct := absf(size.x - dims.x) <= TOL and absf(size.z - dims.y) <= TOL
		var swapped := absf(size.x - dims.y) <= TOL and absf(size.z - dims.x) <= TOL
		print("  %-11s 房=%5.1fx%5.1f 壳=%5.1fx%5.1f 心差=(%6.2f,%6.2f) artYaw=%7.1f 向meta=%6.1f %s" % [
			key, dims.x, dims.y, size.x, size.z,
			center.x - rc.x, center.z - rc.z,
			art_yaw, fposmod(float(room.get_meta("template_rotation_deg", 0.0)), 360.0),
			"尺寸转置🔴" if (swapped and not direct) else ("吻合✅" if direct else "对不上⚠"),
		])
		# 门位处的实体墙件：把美术里的墙件换算到房间局部，找落在「门位」附近的那些。
		if key == "start":
			_report_safe_room(room, art, dims)
	tower.free()
	await get_tree().process_frame
	await get_tree().process_frame


## 安全屋专查：门洞（DoorWall/RoomDoor）在美术里的世界位置，与房间声明的门位比对。
func _report_safe_room(room: DungeonRoom3D, art: Node3D, dims: Vector2) -> void:
	var half := dims * 0.5
	var ports: Array[String] = []
	for port_value in room.connection_ports:
		var port := port_value as Dictionary
		var side := str(port.get("side", "?"))
		var lane := float(port.get("lane_m", 0.0))
		var target := str(port.get("target_room_id", port.get("target", "")))
		ports.append("%s%.1f%s" % [side, lane, ("→" + target) if target != "" else "(空)"])
	print("              安全屋门位: %s  doors=%s rotSteps=%s" % [
		" ".join(ports), str(room.doors), str(room.get_meta("safe_room_orientation_steps", -1)),
	])
	if art == null:
		print("              安全屋 art=<无>")
		return
	var found := 0
	for value in art.find_children("*", "Node3D", true, false):
		var node := value as Node3D
		if node == null:
			continue
		var low := str(node.name).to_lower()
		var is_door := low.contains("door") or low.contains("门")
		if not is_door:
			continue
		var local := room.to_local(node.global_position)
		var on_side := ""
		if absf(absf(local.z) - half.y) < TOL and absf(local.x) < half.x + TOL:
			on_side = "north" if local.z < 0.0 else "south"
		elif absf(absf(local.x) - half.x) < TOL and absf(local.z) < half.y + TOL:
			on_side = "west" if local.x < 0.0 else "east"
		print("                 门件 %-40s 房局部=(%7.2f,%7.2f) 落在=%-6s" % [
			str(node.name), local.x, local.z, on_side if on_side != "" else "非墙位",
		])
		found += 1
		if found >= 14:
			break
	if found == 0:
		print("                 门件 <未找到匹配名>")


func _art_aabb(root: Node3D) -> AABB:
	if root == null:
		return AABB()
	var box := AABB()
	var first := true
	for value in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := value as MeshInstance3D
		if mesh_node == null or mesh_node.mesh == null:
			continue
		if not mesh_node.is_visible_in_tree():
			continue
		var local_box := mesh_node.get_aabb()
		var corners: Array[Vector3] = [
			local_box.position,
			local_box.position + Vector3(local_box.size.x, 0, 0),
			local_box.position + Vector3(0, 0, local_box.size.z),
			local_box.position + Vector3(local_box.size.x, 0, local_box.size.z),
		]
		for corner in corners:
			var world_point := mesh_node.global_transform * corner
			if first:
				box = AABB(world_point, Vector3.ZERO)
				first = false
			else:
				box = box.expand(world_point)
	return box
