extends Node
## 正式Boss房TSCN与生产Room函数；只测选点，不生成怪物，不改场景/资产/锚点。
const LAYOUT := "res://assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_01/f00_boss_room_02_static_layout.tscn"

class ProbeRoom extends DungeonRoom3D:
	func _ready() -> void:
		pass

var failures := 0
var checked := 0

func check(ok: bool, message: String) -> void:
	checked += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var parent := Node3D.new()
	add_child(parent)
	parent.position = Vector3(71, -12, 99)
	parent.rotation.y = 0.31
	var room := ProbeRoom.new()
	room.room_id = "boss"
	room.room_type = "BOSS"
	room.room_seed = 77001199
	room.custom_dimensions = Vector2(80, 100)
	parent.add_child(room)
	room.rotation.y = -0.8
	var layout := (load(LAYOUT) as PackedScene).instantiate() as Node3D
	room.add_child(layout)
	room._collect_spawn_blockers()
	room._build_spawn_points()
	await get_tree().physics_frame
	await get_tree().physics_frame
	check(room._spawn_support_triangles.size() == 102, "正式承重三角面必须全部收集")
	for point in [Vector3(0,0,-22.5), Vector3(-22,0,-22.5), Vector3(22,0,-22.5), Vector3(0,11.965,45)]:
		check(room._spawn_surface_contains(point, room._spawn_clearance()), "平台/双桥/高台真支撑：" + str(point))
		print("BOSS_BOX_SUPPORT point=%s support=true obstacle_free=%s" % [str(point), str(room.is_safe_spawn_position_valid(room.to_global(point)))])
	for point in [Vector3(20,0,-30), Vector3(-20,0,0), Vector3(0,0,45), Vector3(0,12.3,45)]:
		check(not room.is_safe_spawn_position_valid(room.to_global(point)), "虚空/错层/错误高度必须拒绝：" + str(point))
	var floor_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/level_plans/expedition_01/floors/floor_00.json"))
	var boss: Dictionary = {}
	for value in floor_data.get("rooms", []):
		if str(value.get("key", "")) == "boss":
			boss = value
	check(not boss.is_empty(), "读取生产Boss房配置")
	var occupied: Array[Vector3] = []
	var player_world := room.to_global(Vector3(0,0,-12))
	var placements: Array = boss.get("spawn_placements", [])
	check(placements.size() == 4, "生产Boss仍为四盒")
	for index in placements.size():
		var placement: Dictionary = placements[index]
		var box_id := str(placement["box"])
		var box: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/spawn_boxes/%s.json" % box_id))
		var center := Vector2(placement["center_m"][0], placement["center_m"][1])
		var size := Vector2(box["size_m"][0], box["size_m"][2])
		var rotation_deg := float(placement.get("rotation_deg", 0.0))
		var angle := deg_to_rad(rotation_deg)
		var policy: Dictionary = box.get("placement_policy", {})
		var spacing := float(policy.get("min_spacing_m", 0.0))
		var needs := [4,3,2,2]
		var need: int = needs[index]
		room._collect_spawn_blockers()
		var center_point := Vector3(center.x, 0, center.y)
		var nearby_blockers: Array = []
		for bounds in room._spawn_blockers:
			if bounds.end.y > .15 and bounds.position.y < room.SPAWN_BODY_HEIGHT_M and Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z)).grow(room._spawn_clearance()).has_point(center):
				nearby_blockers.append(bounds)
		print("BOSS_BOX_CENTER id=%s support=%s blockers=%s" % [box_id, str(room._spawn_surface_contains(center_point, room._spawn_clearance())), str(nearby_blockers)])
		var local_pool := room._box_sample_points(center, size * 0.5, cos(angle), sin(angle), room._spawn_clearance())
		var world_pool: Array[Vector3] = []
		for point in local_pool:
			var world_point := room.to_global(point)
			check(room.is_safe_spawn_position_valid(world_point), "每个盒候选必须合法")
			check(physics_supported(room, point), "每个候选完整占地采样须命中实际物理承重面")
			check(not room.is_safe_spawn_position_valid(room.to_global(point + Vector3.UP * .3)), "每个候选抬高30厘米无支撑必须拒绝")
			world_pool.append(world_point)
		var old_points := room._scatter_box_pick(local_pool, maxf(1.7, spacing), need, room._box_pick_seed(center, size * 0.5))
		var safe: Array[Vector3] = []
		for _slot in need:
			var result := room.choose_safe_spawn_position(player_world, 6.0, safe, world_pool)
			if not bool(result.get("ok", false)):
				break
			safe.append(result["position"])
		var cross: Array[Vector3] = []
		for _slot in need:
			var result := room.choose_safe_spawn_position(player_world, 6.0, occupied, world_pool)
			if not bool(result.get("ok", false)):
				break
			var point: Vector3 = result["position"]
			check(room.is_safe_spawn_position_valid(point, player_world, 6.0, occupied), "跨盒玩家距离/净距一致")
			check(room._box_local_point(room.to_local(point), center, cos(angle), sin(angle)).abs().x <= size.x * .5 + .001 and room._box_local_point(room.to_local(point), center, cos(angle), sin(angle)).abs().y <= size.y * .5 + .001, "不越原授权盒")
			occupied.append(point)
			cross.append(point)
		var resolved := room.resolve_spawn_box_center_local(center, size, need, rotation_deg, spacing, int(policy.get("wall_recess_tiles", 1)))
		var actual := room.spawn_points_in_box(center, size, need, rotation_deg, spacing, int(policy.get("wall_recess_tiles", 1)))
		var actual_count := 0
		for point in actual:
			if point.is_finite():
				actual_count += 1
				check(room.is_safe_spawn_position_valid(point), "生产盒输出不能失去支持/碰撞安全")
		print("BOSS_BOX id=%s demand=%s candidates=%d original_box_capacity=%d safe_6m_4.5spacing=%d cross_box=%d production_capacity=%d declared=%s resolved=%s drift=%.3f" % [box_id, "1-2" if index == 3 else str(need), local_pool.size(), old_points.size(), safe.size(), cross.size(), actual_count, str(center), str(resolved), center.distance_to(resolved)])
	print("BOSS_BOX_PROBE_DONE checks=%d failures=%d" % [checked, failures])
	parent.free()
	get_tree().quit(0 if failures == 0 else 1)

func physics_supported(room: DungeonRoom3D, local_point: Vector3) -> bool:
	var radius := room._spawn_clearance()
	for x in [-radius, 0.0, radius]:
		for z in [-radius, 0.0, radius]:
			var point := room.to_global(local_point + Vector3(x, 0, z))
			var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * .16, point - Vector3.UP * .16, 1)
			query.hit_back_faces = true
			var hit := room.get_world_3d().direct_space_state.intersect_ray(query)
			if hit.is_empty() or absf((hit["position"] as Vector3).y - point.y) > .15 or (hit["normal"] as Vector3).y < cos(deg_to_rad(44.0)):
				return false
	return true
