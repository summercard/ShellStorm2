extends Node
## 探针：房间墙面灯开关 RoomLightSwitch3D 的**落位可达性**实测。
##
## 背景：`DungeonRoom3D._place_light_switch` 只按 `absi(room_seed) % 4` 挑一面墙、
## 内缩 0.34m 放置，**不看 doors / open_wall_directions / 该侧到底有没有墙**。
## 本探针把「四个候选面各自的落位」全部算一遍，用**物理射线**判定：
##   A) 开关背后 1.5m 内有没有墙（没有 = 悬空）；
##   B) 从房内 3m 外能不能看见开关（被挡 = 埋进墙或被墙隔开）。
##
## 运行：
##   godot --headless --path . res://tests/verification/probe_room_light_switch.tscn

const SCENE_PATH := "res://scenes/ExpeditionLevel99_3D.tscn"
const TOWER_GEOMETRY := preload("res://src/world3d/TowerGeometry3D.gd")
const RUN_SEED := 77199999
const SIDE_DIRECTIONS: Array[String] = ["north", "south", "west", "east"]
const SWITCH_INSET_M := 0.34
const SWITCH_PROBE_Y := 1.0


func _ready() -> void:
	var scene := load(SCENE_PATH) as PackedScene
	if scene == null:
		printerr("PROBE_FAIL 场景加载失败: %s" % SCENE_PATH)
		get_tree().quit(1)
		return
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	await _settle()
	var room_by_id: Dictionary = tower.get("_room_by_id")
	var ids := room_by_id.keys()
	ids.sort()
	printerr("")
	printerr("############ 灯开关落位实测 %s  seed=%d  房间=%d" % [
		SCENE_PATH, RUN_SEED, ids.size(),
	])
	for key in ids:
		var room := room_by_id[key] as DungeonRoom3D
		if room == null:
			continue
		room.ensure_shell_built()
		room.ensure_detail_built()
		await _settle()
		_report_room(room)
	printerr("")
	printerr("PROBE_LIGHT_SWITCH_DONE")
	get_tree().quit(0)


func _report_room(room: DungeonRoom3D) -> void:
	var dims := room.get_dimensions()
	var seed_value := int(room.room_seed)
	var actual_side := absi(seed_value) % 4
	printerr("")
	printerr("--- %s type=%s dims=%s seed=%d 实际 side=%d(%s)" % [
		room.room_id, room.room_type, str(dims), seed_value,
		actual_side, SIDE_DIRECTIONS[actual_side],
	])
	printerr("    doors=%s open_wall=%s" % [
		str(room.doors), str(room.open_wall_directions),
	])
	for direction in room.doors:
		var door := room.get_door_node(str(direction))
		if door != null:
			var offset_key := "tower_wall_door_offset_%s" % str(direction)
			printerr("      门 %-5s local=%s  沿墙偏移 meta=%s" % [
				str(direction), str(door.position),
				str(room.get_meta(offset_key, "<无此 meta>")),
			])
	var sw := room.find_child("RoomLightSwitch3D", true, false) as RoomLightSwitch3D
	if sw != null:
		printerr("    实际开关 local=%s rot_y=%.3f global=%s" % [
			str(sw.position), sw.rotation.y, str(sw.global_position),
		])
		var inward := _inward(SIDE_DIRECTIONS[actual_side])
		if room.room_type == "FACILITY":
			inward = Vector3(1.0, 0.0, 0.0)
		var center := sw.global_position
		for child_name in ["SwitchPlate", "Indicator", "Lever"]:
			var part := sw.get_node_or_null(child_name) as Node3D
			if part == null:
				continue
			var offset := part.global_position - center
			var facing := offset.dot(inward)
			printerr("      %-12s world=%s  朝房间内分量=%+.3f  %s" % [
				child_name, str(part.global_position), facing,
				"朝房内 OK" if facing > 0.0 or absf(facing) < 1e-6 else "★朝墙内(反了)",
			])
		var wall_mesh: Mesh = room.get("_tower_solid_wall_mesh") as Mesh
		if wall_mesh != null:
			printerr("    塔楼实墙网格 AABB=%s（厚度看 z 分量）" % str(wall_mesh.get_aabb()))
	else:
		printerr("    !! 未找到 RoomLightSwitch3D")
	for side in range(4):
		printerr("      %s" % _evaluate_side(room, dims, side))


## 复刻 `_place_light_switch` 的位置公式（非 FACILITY 分支），用射线判定该候选面是否可用。
func _evaluate_side(room: DungeonRoom3D, dims: Vector2, side: int) -> String:
	if room.room_type == "FACILITY":
		return "side %d: FACILITY 走专属固定位，不参与四选一" % side
	var direction := SIDE_DIRECTIONS[side]
	var x_margin := minf(4.2, dims.x * 0.22)
	var z_margin := minf(4.2, dims.y * 0.22)
	var local := Vector3.ZERO
	var half_length := 0.0
	var along := 0.0
	match side:
		0:
			local = Vector3(x_margin, 0.0, -dims.y * 0.5 + SWITCH_INSET_M)
			half_length = dims.x * 0.5
			along = x_margin
		1:
			local = Vector3(-x_margin, 0.0, dims.y * 0.5 - SWITCH_INSET_M)
			half_length = dims.x * 0.5
			along = -x_margin
		2:
			local = Vector3(-dims.x * 0.5 + SWITCH_INSET_M, 0.0, z_margin)
			half_length = dims.y * 0.5
			along = z_margin
		_:
			local = Vector3(dims.x * 0.5 - SWITCH_INSET_M, 0.0, -z_margin)
			half_length = dims.y * 0.5
			along = -z_margin
	var notes: Array[String] = []
	if room.open_wall_directions.has(direction):
		notes.append("开放墙方向")
	if room.doors.has(direction):
		var meta_key := "tower_wall_door_offset_%s" % direction
		if room.has_meta(meta_key):
			var door_along := float(room.get_meta(meta_key))
			var half_door: float = TOWER_GEOMETRY.DOOR_CLEAR_WIDTH_M * 0.5
			if absf(along - door_along) < half_door:
				notes.append("落在门洞净空内")
			elif absf(along - door_along) < 2.5:
				notes.append("落在门墙模块")

	var inward := _inward(direction)
	var target := room.global_position + local + Vector3(0.0, SWITCH_PROBE_Y, 0.0)
	var eye := target + inward * 3.0
	var occluder: Variant = _ray(room, eye, target)
	if occluder is Dictionary:
		return "side %d %-5s along=%7.2f 距边端=%6.2f  ★看不见：%s 挡在 3m 视线内  %s" % [
			side, direction, along, half_length - absf(along),
			str((occluder as Dictionary)["node"]), " ".join(notes),
		]
	var back: Variant = _ray(room, target, target - inward * 1.5)
	var behind_face := -1.0
	var behind_who := ""
	if back is Dictionary:
		behind_face = float((back as Dictionary)["distance"])
		behind_who = str((back as Dictionary)["node"])
	if behind_face < 0.0:
		return "side %d %-5s along=%7.2f 距边端=%6.2f  ★背后 1.5m 内没有墙 -> 悬空  %s" % [
			side, direction, along, half_length - absf(along), " ".join(notes),
		]
	if behind_face > 0.75:
		return "side %d %-5s along=%7.2f 距边端=%6.2f  ★背后墙皮 %.2fm 太远 -> 悬空  %s" % [
			side, direction, along, half_length - absf(along), behind_face, " ".join(notes),
		]
	var front: Variant = _ray(room, target + inward * 0.4, target + inward * 1.5)
	if front is Dictionary:
		return "side %d %-5s along=%7.2f 距边端=%6.2f  ★正面 %.2fm 处被 %s 挡住  %s" % [
			side, direction, along, half_length - absf(along),
			float((front as Dictionary)["distance"]), str((front as Dictionary)["node"]),
			" ".join(notes),
		]
	return "side %d %-5s along=%7.2f 距边端=%6.2f  贴墙 OK(背后 %.2fm 命中 %s)  %s" % [
		side, direction, along, half_length - absf(along), behind_face, behind_who,
		" ".join(notes),
	]


## 从墙指向房间中心的水平单位向量。
func _inward(direction: String) -> Vector3:
	match direction:
		"north":
			return Vector3(0.0, 0.0, 1.0)
		"south":
			return Vector3(0.0, 0.0, -1.0)
		"west":
			return Vector3(1.0, 0.0, 0.0)
		_:
			return Vector3(-1.0, 0.0, 0.0)


## 射线：命中返回 {"node": 名称, "distance": 米}；未命中返回 ""。
## collide_with_areas=false 排除房间触发器等 Area3D。
func _ray(room: DungeonRoom3D, from: Vector3, to: Vector3) -> Variant:
	var space := room.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return ""
	var collider := hit.get("collider") as Node
	var node_name := "<null>"
	if collider != null:
		node_name = str(collider.get_path()).replace(str(room.get_path()) + "/", "")
	return {
		"node": node_name,
		"distance": from.distance_to(hit.get("position") as Vector3),
	}


func _settle() -> void:
	for i in 6:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.30).timeout
