extends Node

const EXPEDITION_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const RUN_SEED := 77001199
const CAMERA_MASK := 17
const CAMERA_LAYER := 16
const EPSILON_M := 0.001
var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	var tower := EXPEDITION_SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	var legacy := "--legacy" in OS.get_cmdline_user_args()
	if legacy:
		tower.set("_runtime_restore_snapshot", {"world_state": {}})
	add_child(tower)
	for _index in range(8):
		await get_tree().process_frame
		await get_tree().physics_frame
	var plan := (tower.get("_floor_plan_snapshots") as Dictionary).get(0, {}) as Dictionary
	_check(int(plan.get("expedition_global_rotation_deg", -1)) == (0 if legacy else 180), "实际关卡必须使用旧快照0/新局180朝向")
	var block := tower.get_node("Blocks/Expedition") as Node3D
	var rooms: Array[DungeonRoom3D] = []
	var proxies: Dictionary = {}
	var transforms: Dictionary = {}
	var panels: Dictionary = {}
	var edge_counts: Dictionary = {}
	var doors: Dictionary = {}
	for child in block.get_children():
		var room := child as DungeonRoom3D
		if room == null:
			continue
		rooms.append(room)
		room.ensure_shell_built()
		var art := _art_root(room)
		_check(art != null, "%s 必须加载正式静态布局" % room.room_id)
		if art == null:
			continue
		var owned := 0
		for direction in room.doors:
			var door := room.get_door_node(direction)
			_check(door != null, "%s/%s 必须有真实门" % [room.room_id, direction])
			if door == null:
				continue
			var matches := _proxies_for_side(art, direction)
			if not room.owns_door_endpoint(direction):
				_check(matches.is_empty(), "%s/%s 非owner不得创建代理" % [room.room_id, direction])
				continue
			owned += 1
			_check(matches.size() == 1, "%s/%s 必须恰好一个代理" % [room.room_id, direction])
			if matches.size() != 1:
				continue
			var proxy := matches[0]
			_check_contract(room, door, proxy)
			proxies[door.get_instance_id()] = proxy
			doors[door.get_instance_id()] = door
			transforms[door.get_instance_id()] = proxy.global_transform
			door.set_open(false, true)
			var panel := door.get_node("DoorPanel") as Node3D
			panels[door.get_instance_id()] = panel.position.y
			var edge := str(door.get_meta("shared_edge_key", ""))
			if not edge.is_empty():
				edge_counts[edge] = int(edge_counts.get(edge, 0)) + 1
		_check(_all_proxies(art).size() == owned, "%s 旧烘焙空代理必须清理" % room.room_id)
		_check_idempotence_and_rotation(room, art)
	_check(rooms.size() == 13, "真实远征01必须包含13房")
	_check(proxies.size() == 13, "12条共享边及入口弃局门必须合计13个代理")
	_check(edge_counts.size() == 12, "必须覆盖12条shared edge")
	for edge in edge_counts:
		_check(int(edge_counts[edge]) == 1, "%s 必须仅一个owner代理" % edge)
	for room in rooms:
		for direction in room.doors:
			var door := room.get_door_node(direction)
			if door != null:
				_check(proxies.has(door.get_instance_id()), "%s/%s 共享引用必须指向owner代理对应门" % [room.room_id, direction])
	await get_tree().physics_frame
	for door_value in doors.values():
		(door_value as RoomDoor3D).set_open(true, false)
	await get_tree().create_timer(0.1).timeout
	for id in proxies:
		_check((proxies[id] as StaticBody3D).global_transform.is_equal_approx(transforms[id] as Transform3D), "门板动画进行中代理必须原位保持")
	await get_tree().create_timer(1.0).timeout
	await get_tree().physics_frame
	await get_tree().physics_frame
	var excluded: Array[RID] = []
	for value in tower.find_children("*", "CollisionObject3D", true, false):
		var body := value as CollisionObject3D
		if not bool(body.get_meta("camera_only_door_wall", false)):
			excluded.append(body.get_rid())
	var space := tower.get_world_3d().direct_space_state
	for id in proxies:
		var proxy := proxies[id] as StaticBody3D
		var door := doors[id] as RoomDoor3D
		var label := "%s/%s" % [str(door.get_meta("shared_door_owner_room_id", "start")), door.direction]
		_check(proxy.global_transform.is_equal_approx(transforms[id] as Transform3D), "%s 代理不得随门板升降" % label)
		var snapshot := door.get_snapshot()
		_check(bool(snapshot["is_open"]) and not bool(snapshot["blocks_passage"]) and not bool(snapshot["transitioning"]), "%s 开门完成且门碰撞关闭" % label)
		_check(float(snapshot["panel_y"]) > float(panels[id]) + 1.0, "%s 真实DoorPanel必须升起" % label)
		for height in [1.5, 6.0, 11.8]:
			var center := proxy.to_global(Vector3(0.0, height, 0.0))
			var normal := proxy.global_basis.z.normalized()
			for mask in [CAMERA_MASK, CAMERA_LAYER, 1, 5, 8]:
				var query := PhysicsRayQueryParameters3D.create(center - normal * 0.25, center + normal * 0.25, mask, excluded)
				var hit := space.intersect_ray(query)
				if mask in [CAMERA_MASK, CAMERA_LAYER]:
					_check(hit.get("collider") == proxy, "%s 高%.1f mask%d必须命中原门位置代理" % [label, height, mask])
				else:
					_check(hit.is_empty(), "%s 高%.1f 角色/子弹mask%d不得命中代理" % [label, height, mask])
		# 不排除真实世界碰撞，门洞中心的相机查询也必须直接命中代理。
		var center := proxy.to_global(Vector3(0.0, 1.5, 0.0))
		var normal := proxy.global_basis.z.normalized()
		var camera_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(center - normal * 0.25, center + normal * 0.25, CAMERA_MASK))
		_check(camera_hit.get("collider") == proxy, "%s 真实世界相机mask17必须命中代理" % label)
		_check_contract(door.get_parent() as DungeonRoom3D, door, proxy)
	print("CAMERA_DOOR_MODE legacy=%s rooms=%d proxies=%d edges=%d" % [str(legacy), rooms.size(), proxies.size(), edge_counts.size()])
	tower.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	for failure in failures:
		print("FAIL %s" % failure)
	if failures.is_empty():
		print("EXPEDITION_CAMERA_DOOR_PROXIES_OK checks=%d" % checks)
	call_deferred("_finish", 0 if failures.is_empty() else 1)


func _finish(code: int) -> void:
	get_tree().quit(code)


func _art_root(room: DungeonRoom3D) -> Node3D:
	return room.get_node_or_null("SafeRoomArtRoot" if room.room_id == "start" else "AuthoredLayoutArtRoot") as Node3D


func _all_proxies(art: Node3D) -> Array[StaticBody3D]:
	var result: Array[StaticBody3D] = []
	for value in art.find_children("*", "StaticBody3D", true, false):
		var body := value as StaticBody3D
		if bool(body.get_meta("camera_only_door_wall", false)) or str(body.name).begins_with("CameraOnlyDoorWall_"):
			result.append(body)
	return result


func _proxies_for_side(art: Node3D, side: String) -> Array[StaticBody3D]:
	var result: Array[StaticBody3D] = []
	for body in _all_proxies(art):
		if str(body.get_meta("tower_wall_direction", "")) == side:
			result.append(body)
	return result


func _check_contract(room: DungeonRoom3D, door: RoomDoor3D, proxy: StaticBody3D) -> void:
	var label := "%s/%s" % [room.room_id, door.direction]
	_check(proxy.collision_layer == CAMERA_LAYER and proxy.collision_mask == 0, "%s 层必须16/mask0" % label)
	_check(bool(proxy.get_meta("camera_only_door_wall", false)), "%s 必须有camera-only元数据" % label)
	_check(str(proxy.get_meta("tower_wall_direction", "")) == door.direction, "%s 方向元数据必须按真实门" % label)
	_check(proxy.get_parent() == _art_root(room), "%s 代理必须独立于DoorPanel" % label)
	_check(proxy.global_position.distance_to(door.global_position) <= EPSILON_M and proxy.global_basis.is_equal_approx(door.global_basis), "%s 位置/朝向必须与最终门对齐" % label)
	var collisions := proxy.find_children("*", "CollisionShape3D", true, false)
	_check(collisions.size() == 1, "%s 必须恰好一个碰撞形状" % label)
	if collisions.size() == 1:
		var collision := collisions[0] as CollisionShape3D
		var box := collision.shape as BoxShape3D
		_check(box != null and not collision.disabled, "%s 必须启用BoxShape3D" % label)
		if box != null:
			_check(box.size.is_equal_approx(Vector3(5.0, 12.0, 0.08)) and collision.position.is_equal_approx(Vector3(0.0, 6.0, 0.0)), "%s 盒必须覆盖完整5×12m门墙" % label)
	var along_x := absf(proxy.global_basis.x.x) >= absf(proxy.global_basis.x.z)
	_check(bool(proxy.get_meta("camera_lower_wall", false)) == along_x, "%s 后墙标记必须按真实世界几何" % label)


func _check_idempotence_and_rotation(room: DungeonRoom3D, art: Node3D) -> void:
	var original := art.transform
	var ids: Array[int] = []
	for proxy in _all_proxies(art):
		ids.append(proxy.get_instance_id())
	# 模拟遗留空节点、重复管理节点及不再拥有的旧方向。
	var stale := StaticBody3D.new()
	stale.name = "CameraOnlyDoorWall_Obsolete"
	stale.collision_layer = CAMERA_LAYER
	stale.set_meta("camera_only_door_wall", true)
	art.add_child(stale)
	if not ids.is_empty():
		var duplicate := _all_proxies(art)[0].duplicate() as StaticBody3D
		art.add_child(duplicate)
	for _index in range(2):
		room.call("_sync_expedition_static_camera_door_proxies", art)
	var actual_ids: Array[int] = []
	for proxy in _all_proxies(art):
		actual_ids.append(proxy.get_instance_id())
	_check(actual_ids == ids, "%s 重复同步必须保留原代理且清掉空/重复代理" % room.room_id)
	for steps in [1, 2, 3, 0]:
		art.transform = Transform3D(Basis(Vector3.UP, float(steps) * PI * 0.5), Vector3.ZERO) * original
		room.call("_sync_expedition_static_camera_door_proxies", art)
		room.call("_restore_static_layout_camera_wall_contract", art)
		for proxy in _all_proxies(art):
			var side := str(proxy.get_meta("tower_wall_direction", ""))
			_check_contract(room, room.get_door_node(side), proxy)
	_check(art.transform.is_equal_approx(original), "%s 旋转恢复不得改变艺术根" % room.room_id)
	var room_transform := room.transform
	for steps in [1, 2, 3, 0]:
		room.transform = Transform3D(Basis(Vector3.UP, float(steps) * PI * 0.5), Vector3.ZERO) * room_transform
		room.call("_restore_static_layout_camera_wall_contract", art)
		for proxy in _all_proxies(art):
			var side := str(proxy.get_meta("tower_wall_direction", ""))
			_check_contract(room, room.get_door_node(side), proxy)
	_check(room.transform.is_equal_approx(room_transform), "%s 整房旋转恢复必须不漂移" % room.room_id)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
