extends Node

# 实测远征 01 主路上每一对相邻房间的两扇门是否落在**同一世界点**。
# 判据：两房墙贴墙（净距 0）⇒ 本房门 world 位置与对端房门的 world 位置必须重合；
# 沿轴分量不一致就是「门和门没对齐」，也就是肉眼看到的屋子错位。
# 同时打印两房中心在垂轴上的偏移（0 或 2.5 m 是设计允许的共轴偏移，不是错位）。
#
# 两条装配路径都跑：STATIC（静态 TSCN，游戏内实际走的）与 DYNAMIC（程序化装配）。

const EXPEDITION_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const ROOM_SCRIPT := preload("res://src/world3d/DungeonRoom3D.gd")
## 用三个固定种子同时验证静态/动态两条装配路径与所有有向门端点。
const RUN_SEEDS: Array[int] = [77001199, 77001200, 77001201]
const MISSING_WALL_SLOT := "WALL_south_ym210_m127.5"
const ROOM07_SAVED_SCENE: PackedScene = preload("res://assets/art/environments/tower_zones/expedition/runtime/room_instances/expedition_01/f00_room_07_static_layout.tscn")
# 正式根为单位变换；北向差异日志(-5,0,-12.5)及旧向ArtRoot逆变换一致。
# 缺件未保存为节点，不能从其历史世界坐标名称推导跨seed位置。
const MISSING_WALL_SAVED_FRAME_CENTER := Vector3(-5.0, 0.0, -12.5)
# 5m 槽内取 -2..2m，间隔0.5m，两端各留0.5m（大于0.3m）。
const WALL_TANGENT_OFFSETS: Array[float] = [-2.0, -1.5, -1.0, -0.5, 0.0, 0.5, 1.0, 1.5, 2.0]
const WALL_HEIGHTS: Array[float] = [0.45, 1.20, 2.20]
# 仅核读过的单盒5m直墙；门墙/L角/柜体不能走此承接判据。
const WALL_COVER_PREFABS: Array[PackedScene] = [
	preload("res://assets/art/environments/tower_zones/battle/runtime/common_components/wall_standard_5m/wall_standard_5m_root_top3d.tscn"),
	preload("res://assets/art/environments/tower_zones/expedition/runtime/room_type_components/l_corridor/wall_5m_a/wall_5m_a_root_top3d.tscn"),
	preload("res://assets/art/environments/tower_zones/expedition/runtime/room_type_components/l_corridor/wall_5m_c/wall_5m_c_root_top3d.tscn"),
	preload("res://assets/art/environments/tower_zones/expedition/runtime/room_type_components/l_corridor/wall_5m_d/wall_5m_d_root_top3d.tscn"),
]

var failures: Array[String] = []
var pair_count := 0
var passage_count := 0
var ray_count := 0
var wall_failures: Array[String] = []
var wall_slot_count := 0
var wall_point_count := 0
var wall_ray_count := 0
var wall_blocked_count := 0
var wall_clear_count := 0
var wall_door_ray_count := 0
var wall_owner_point_count := 0
var wall_planned_owner_ray_count := 0
var wall_actual_owner_ray_count := 0

func _ready() -> void:
	var previous_static := bool(ROOM_SCRIPT.use_expedition_static_layout_scenes)
	for seed_value in RUN_SEEDS:
		await _probe_seed(seed_value, true, "STATIC")
	for seed_value in RUN_SEEDS:
		await _probe_seed(seed_value, false, "DYNAMIC")
	ROOM_SCRIPT.use_expedition_static_layout_scenes = previous_static
	if pair_count != RUN_SEEDS.size() * 2 * 12 or passage_count != RUN_SEEDS.size() * 2 * 24 or ray_count != passage_count * 9:
		failures.append("全房全边覆盖不足 pairs=%d passages=%d rays=%d" % [pair_count, passage_count, ray_count])
	if failures.is_empty():
		print("EXPEDITION_DOOR_LANE_OK")
	else:
		for failure in failures:
			print("DOOR_GAP %s" % failure)
	print("EXPEDITION_DOOR_LANE_DONE pairs=%d passages=%d rays=%d misaligned=%d" % [pair_count, passage_count, ray_count, failures.size()])
	if wall_slot_count != RUN_SEEDS.size() * 2 or wall_point_count != RUN_SEEDS.size() * 2 * 27 or wall_ray_count != RUN_SEEDS.size() * 2 * 54:
		wall_failures.append("缺墙槽覆盖不足 expected_slots=6 expected_points=162 expected_rays=324 slots=%d points=%d rays=%d" % [wall_slot_count, wall_point_count, wall_ray_count])
	if wall_owner_point_count != RUN_SEEDS.size() * 2 * 27 or wall_planned_owner_ray_count + wall_actual_owner_ray_count != RUN_SEEDS.size() * 2 * 54:
		wall_failures.append("真实墙owner覆盖不足 expected_points=162 expected_rays=324 owner_points=%d planned_rays=%d actual_prefab_only_rays=%d" % [wall_owner_point_count, wall_planned_owner_ray_count, wall_actual_owner_ray_count])
	print("WALL_SLOT_OWNER_DONE points=%d planned_rays=%d actual_prefab_only_rays=%d（后者仅证明实际墙覆盖，不证明plan一致）" % [wall_owner_point_count, wall_planned_owner_ray_count, wall_actual_owner_ray_count])
	for failure in wall_failures:
		print("WALL_SLOT_FAIL %s" % failure)
	if wall_failures.is_empty():
		print("EXPEDITION_WALL_SLOT_OK")
	print("EXPEDITION_WALL_SLOT_DONE slots=%d points=%d rays=%d blocked=%d clear=%d door_rays=%d failures=%d" % [wall_slot_count, wall_point_count, wall_ray_count, wall_blocked_count, wall_clear_count, wall_door_ray_count, wall_failures.size()])
	get_tree().quit(0 if failures.is_empty() and wall_failures.is_empty() else 1)

func _probe_seed(seed_value: int, use_static: bool, label: String) -> void:
	ROOM_SCRIPT.use_expedition_static_layout_scenes = use_static
	var tower := EXPEDITION_SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = seed_value
	if "--legacy" in OS.get_cmdline_user_args():
		tower.set("_runtime_restore_snapshot", {"world_state": {}})
	# 入树前阻断刷怪/补刷/延迟批次入口，不清房、不改门墙或碰撞状态。
	for room_id in ["start", "boss", "extraction"]:
		tower._room_spawn_blocked[room_id] = true
	for index in range(1, 11):
		tower._room_spawn_blocked["room_%02d" % index] = true
	add_child(tower)
	if tower.player != null:
		tower.player.velocity = Vector3.ZERO
		tower.player.set_process(false)
		tower.player.set_physics_process(false)
	for _index in range(6):
		await get_tree().process_frame
		await get_tree().physics_frame
	var rooms := _collect_rooms(tower)
	# 共墙远征仍必须实际构建连接器；不能因没有非零走廊而跳过被测函数。
	var connectors := tower.get("_corridor_by_edge") as Dictionary
	var corridor_failure_start := failures.size()
	if connectors.size() != 12:
		failures.append("%s seed=%d 必须实际构建12条共墙连接器，实际%d" % [label, seed_value, connectors.size()])
	for value in connectors.values():
		var connector := value as Node3D
		if connector == null or bool(connector.get_meta("is_vertical_connector", true)):
			failures.append("%s seed=%d 共墙连接器缺失或类型错误" % [label, seed_value])
			continue
		var start := connector.get_meta("start_door_position", Vector3.INF) as Vector3
		var end := connector.get_meta("end_door_position", Vector3.INF) as Vector3
		var tangent := float(connector.get_meta("door_tangent_error_m", INF))
		if not start.is_finite() or not end.is_finite() or start.distance_to(end) > 0.01:
			failures.append("%s seed=%d %s 共墙端点未重合" % [label, seed_value, connector.name])
		if not is_finite(tangent) or not is_zero_approx(tangent):
			failures.append("%s seed=%d %s 共墙门槽误差不为零" % [label, seed_value, connector.name])
		for key in ["module_count", "floor_module_count", "wall_module_count", "module_coverage_length_m"]:
			if float(connector.get_meta(key, -1.0)) != 0.0:
				failures.append("%s seed=%d %s 零长度连接器生成了%s" % [label, seed_value, connector.name, key])
	print("EXPEDITION_CORRIDOR_REGRESSION seed=%d mode=%s connectors=%d failures=%d" % [seed_value, label, connectors.size(), failures.size() - corridor_failure_start])
	for room in rooms:
		room.ensure_shell_built()
	await get_tree().process_frame
	await get_tree().physics_frame
	print("=== seed=%d %s rooms=%d ===" % [seed_value, label, rooms.size()])
	var start_room := _room_by_id(rooms, "start")
	var room_01 := _room_by_id(rooms, "room_01")
	if rooms.size() != 13:
		failures.append("%s seed=%d 必须生成13房，实际%d" % [label, seed_value, rooms.size()])
	if start_room != null and room_01 != null:
		print(
			"  START=%s dim=%s  ROOM01=%s dim=%s  lateral_delta=%.2f/%s"
			% [
				_v(start_room.global_position),
				_v2(start_room.get_dimensions()),
				_v(room_01.global_position),
				_v2(room_01.get_dimensions()),
				absf(start_room.global_position.x - room_01.global_position.x),
				"coaxial_x" if is_equal_approx(start_room.global_position.x, room_01.global_position.x) else "offset_x",
			]
		)
		await _check_start_room01_passage(tower, start_room, room_01, "%s seed=%d" % [label, seed_value])
	else:
		failures.append("%s seed=%d 缺少start或room01，禁止跳过通行判据" % [label, seed_value])
	for room in rooms:
		for side in room.doors:
			var target_id := str(room.door_targets.get(side, ""))
			if target_id.is_empty():
				continue
			var target_room := _room_by_id(rooms, target_id)
			if target_room == null:
				failures.append("%s seed=%d %s.%s 找不到对端%s" % [label, seed_value, room.room_id, side, target_id])
				continue
			# 双向都测，确保每房每个连接端点都被实际射线覆盖。
			await _check_shared_door_passage(tower, room, target_room, "%s seed=%d" % [label, seed_value])
	_check_pairs(rooms, "%s seed=%d" % [label, seed_value])
	_check_missing_wall_slot(tower, rooms, "%s seed=%d" % [label, seed_value])
	tower.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	ROOM_SCRIPT.use_expedition_static_layout_scenes = true

func _collect_rooms(tower: TowerDescent3D) -> Array[DungeonRoom3D]:
	var rooms: Array[DungeonRoom3D] = []
	var block := tower.get_node_or_null("Blocks/Expedition") as Node3D
	if block == null:
		return rooms
	for child in block.get_children():
		var room := child as DungeonRoom3D
		if room != null:
			rooms.append(room)
	return rooms

func _room_by_id(rooms: Array[DungeonRoom3D], id: String) -> DungeonRoom3D:
	for room in rooms:
		if room.room_id == id:
			return room
	return null

func _door_world(room: DungeonRoom3D, side: String) -> Vector3:
	var key := "room_door_world_%s" % side
	if room.has_meta(key):
		return room.get_meta(key) as Vector3
	return Vector3.ZERO

func _check_pairs(rooms: Array[DungeonRoom3D], label: String) -> void:
	for room in rooms:
		for side in room.doors:
			var target_id := str(room.door_targets.get(side, ""))
			if target_id.is_empty():
				continue
			var target := _room_by_id(rooms, target_id)
			if target == null:
				failures.append("%s %s -> %s 对端房不存在" % [label, room.room_id, target_id])
				continue
			# 每对只报一次：以 room_id 字典序较小的一侧为准。
			if room.room_id > target_id:
				continue
			var target_side := _reciprocal_side(target, room.room_id)
			if target_side.is_empty():
				failures.append(
					"%s %s <-> %s 对端没有回指门（非成对衔接）" % [label, room.room_id, target_id]
				)
				continue
			pair_count += 1
			var a_world := _door_world(room, side)
			var b_world := _door_world(target, target_side)
			var gap := a_world.distance_to(b_world)
			var along_x := side in ["north", "south"]
			var along_gap := absf(a_world.x - b_world.x) if along_x else absf(a_world.z - b_world.z)
			var lateral_gap := absf(a_world.z - b_world.z) if along_x else absf(a_world.x - b_world.x)
			print(
				(
					"PAIR %-12s -%s-> %-12s | %s%s | along_gap=%.3f lateral_gap=%.3f d=%.3f"
					% [
						room.room_id, side, target_id,
						_v(a_world), _v(b_world),
						along_gap, lateral_gap, gap
					]
				)
			)
			if along_gap > 0.01:
				failures.append(
					(
						"%s %s -%s-> %s 门槽未对齐：沿轴相差 %.3f m（本房槽 %s，对端槽 %s）"
						% [label, room.room_id, side, target_id, along_gap, _v(a_world), _v(b_world)]
					)
				)
			if lateral_gap > 5.01:
				failures.append(
					"%s %s <-> %s 两房不共轴：垂轴相差 %.3f m" % [label, room.room_id, target_id, lateral_gap]
				)

func _check_start_room01_passage(
	tower: TowerDescent3D,
	start_room: DungeonRoom3D,
	room_01: DungeonRoom3D,
	label: String
) -> void:
	var start_side := _reciprocal_side(start_room, room_01.room_id)
	var room_01_side := _reciprocal_side(room_01, start_room.room_id)
	var start_door := start_room.get_door_node(start_side)
	var room_01_door := room_01.get_door_node(room_01_side)
	if start_door == null or room_01_door == null:
		failures.append("%s start-room_01 缺门节点" % label)
		return
	start_door.set_open(true, true)
	room_01_door.set_open(true, true)
	await get_tree().process_frame
	await get_tree().physics_frame
	var door_center: Vector3 = _door_world(start_room, start_side)
	var start_port := start_room.get_connection_port_towards(room_01.room_id)
	var raw_outward := start_port.get("outward", []) as Array
	if raw_outward.size() != 2:
		failures.append("%s start-room_01 缺少真实端口法线" % label)
		return
	var forward := Vector3(float(raw_outward[0]), 0.0, float(raw_outward[1])).normalized()
	if forward.is_zero_approx():
		failures.append("%s start-room_01 端口法线为零" % label)
		return
	var tangent := Vector3(forward.z, 0.0, -forward.x)
	var room_01_tiles: Array = room_01.get("_authored_tile_cells") as Array
	var nearest_tiles: Array[Vector3] = []
	for tile_value in room_01_tiles:
		var tile := tile_value as Vector3
		if nearest_tiles.size() < 8:
			nearest_tiles.append(tile)
			nearest_tiles.sort_custom(func(a: Vector3, b: Vector3) -> bool:
				return a.distance_squared_to(room_01.to_local(door_center)) < b.distance_squared_to(room_01.to_local(door_center))
			)
		elif tile.distance_squared_to(room_01.to_local(door_center)) < nearest_tiles[-1].distance_squared_to(room_01.to_local(door_center)):
			nearest_tiles[-1] = tile
			nearest_tiles.sort_custom(func(a: Vector3, b: Vector3) -> bool:
				return a.distance_squared_to(room_01.to_local(door_center)) < b.distance_squared_to(room_01.to_local(door_center))
			)
	print(
		"PASSAGE_FOOTPRINT %s start_side=%s room01_side=%s door_local=%s tiles=%d nearest=%s"
		% [label, start_side, room_01_side, _v(room_01.to_local(door_center)), room_01_tiles.size(), str(nearest_tiles)]
	)
	var space: PhysicsDirectSpaceState3D = tower.get_world_3d().direct_space_state
	for tangent_offset in [-0.8, 0.0, 0.8]:
		for height in [0.45, 1.20, 2.20]:
			var from: Vector3 = door_center - forward * 1.8 + tangent * tangent_offset + Vector3.UP * height
			var to: Vector3 = door_center + forward * 1.8 + tangent * tangent_offset + Vector3.UP * height
			var query := PhysicsRayQueryParameters3D.create(from, to, 1)
			var hit: Dictionary = space.intersect_ray(query)
			print(
				"PASSAGE_RAY %s tangent=%+.2f y=%.2f from=%s to=%s hit=%s"
				% [label, tangent_offset, height, _v(from), _v(to), _hit_name(hit)]
			)
			if not hit.is_empty():
				failures.append(
					"%s start->room_01 开门后通道被 %s 阻挡（横偏 %.2f, 高 %.2f）"
					% [label, _hit_name(hit), tangent_offset, height]
				)
	var player := tower.player
	if player == null:
		failures.append("%s 没有玩家节点，无法验房间归属切换" % label)
		return
	for distance in [-1.5, -0.4, 0.4, 1.5, 3.0]:
		player.global_position = door_center + forward * distance + Vector3.UP * 0.05
		await get_tree().process_frame
		await get_tree().physics_frame
		tower.call("_refresh_physical_location_authority", true)
		var start_contains := start_room.contains_world_position(player.global_position)
		var room_01_contains := room_01.contains_world_position(player.global_position)
		var current_room_id := str(tower.get("_current_room_id"))
		print(
			"PASSAGE_OWNER %s d=%+.2f pos=%s current=%s start_contains=%s room01_contains=%s"
			% [
				label,
				distance,
				_v(player.global_position),
				current_room_id,
				str(start_contains),
				str(room_01_contains),
			]
		)
		if distance > 0.1 and (not room_01_contains or current_room_id != "room_01"):
			failures.append(
				"%s 玩家过门 %.2f m 后未归属 room_01（current=%s room01_contains=%s）"
				% [label, distance, current_room_id, str(room_01_contains)]
			)


## 所有房间所有连接边开门后，按本端真实端口法线穿过九条射线。
## room02 曾出现同槽空气墙；同一判据覆盖全关，命中任何静态墙碰撞即失败。
func _check_shared_door_passage(
	tower: TowerDescent3D, first_room: DungeonRoom3D, second_room: DungeonRoom3D, label: String
) -> void:
	var first_side := _reciprocal_side(first_room, second_room.room_id)
	var second_side := _reciprocal_side(second_room, first_room.room_id)
	if first_side.is_empty() or second_side.is_empty():
		failures.append("%s %s-%s 缺少成对门向" % [label, first_room.room_id, second_room.room_id])
		return
	var owner := first_room if first_room.owns_door_endpoint(first_side) else second_room
	var owner_side := first_side if owner == first_room else second_side
	var door := owner.get_door_node(owner_side)
	if door == null:
		failures.append("%s %s-%s 缺少唯一门实体" % [label, first_room.room_id, second_room.room_id])
		return
	door.set_open(true, true)
	await get_tree().process_frame
	await get_tree().physics_frame
	var port := first_room.get_connection_port_towards(second_room.room_id)
	var raw_position := port.get("position_m", []) as Array
	var raw_outward := port.get("outward", []) as Array
	if raw_position.size() != 2 or raw_outward.size() != 2:
		failures.append("%s %s.%s 缺少真实端口位置或法线" % [label, first_room.room_id, first_side])
		return
	var normal := Vector3(float(raw_outward[0]), 0.0, float(raw_outward[1])).normalized()
	if normal.is_zero_approx():
		failures.append("%s %s.%s 端口法线为零" % [label, first_room.room_id, first_side])
		return
	var tangent := Vector3(normal.z, 0.0, -normal.x)
	var center := first_room.to_global(Vector3(float(raw_position[0]), 0.0, float(raw_position[1])))
	if center.distance_to(_door_world(first_room, first_side)) > 0.01 or center.distance_to(_door_world(second_room, second_side)) > 0.01:
		failures.append("%s %s.%s 门中心与真实端口不重合" % [label, first_room.room_id, first_side])
	passage_count += 1
	var space: PhysicsDirectSpaceState3D = tower.get_world_3d().direct_space_state
	for tangent_offset in [-0.8, 0.0, 0.8]:
		for height in [0.45, 1.20, 2.20]:
			var from: Vector3 = center - normal * 1.8 + tangent * tangent_offset + Vector3.UP * height
			var to: Vector3 = center + normal * 1.8 + tangent * tangent_offset + Vector3.UP * height
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
			ray_count += 1
			print(
				"ROOM_PASSAGE %s edge=%s-%s owner=%s.%s tangent=%+.2f y=%.2f hit=%s"
				% [label, first_room.room_id, second_room.room_id, owner.room_id, owner_side, tangent_offset, height, _hit_name(hit)]
			)
			if not hit.is_empty():
				failures.append(
					"%s %s-%s 开门后被 %s 阻挡（横偏 %.2f，高 %.2f）"
					% [label, first_room.room_id, second_room.room_id, _hit_name(hit), tangent_offset, height]
				)

## 缺槽属于正式TSCN保存帧；仅使用实际静态根对齐，不叠加plan/template旋转。
func _check_missing_wall_slot(tower: TowerDescent3D, rooms: Array[DungeonRoom3D], label: String) -> void:
	var failure_start := wall_failures.size()
	var room := _room_by_id(rooms, "room_07")
	var plan := tower._floor_plan_snapshots.get(TowerDescent3D.EXPEDITION_LAYER_INDEX, {}) as Dictionary
	var rotation_value: Variant = plan.get("expedition_global_rotation_deg")
	if room == null or tower.player == null or not (rotation_value is int or rotation_value is float):
		wall_failures.append("%s 缺room07/玩家/plan合法朝向，禁止跳过缺墙槽" % label)
		return
	var rotation_deg := float(rotation_value)
	if rotation_deg not in [0.0, 180.0] or not room.global_basis.is_equal_approx(Basis.IDENTITY):
		wall_failures.append("%s plan朝向非法或房根额外旋转/缩放 rotation=%s room_basis=%s" % [label, str(rotation_value), str(room.global_basis)])
		return
	if WALL_TANGENT_OFFSETS.size() != 9 or WALL_HEIGHTS != [0.45, 1.20, 2.20]:
		wall_failures.append("%s 缺墙槽采样数量/高度不足" % label)
		return
	for index in WALL_TANGENT_OFFSETS.size():
		var offset := WALL_TANGENT_OFFSETS[index]
		if absf(offset) > 2.2 or not is_equal_approx(offset, -2.0 + float(index) * 0.5):
			wall_failures.append("%s 缺墙槽未满足0.5m间距/端点至少0.3m退让" % label)
			return
	var enemies := tower.get_node_or_null("ActiveEnemies")
	if enemies == null or enemies.get_child_count() != 0:
		wall_failures.append("%s 动态敌人隔离未成立，禁止其遮挡缺槽制造假绿" % label)
		return
	var art_root := room.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
	var use_static := label.begins_with("STATIC")
	if use_static and (art_root == null or not bool(room.get_meta("static_layout_scene_loaded", false))):
		wall_failures.append("%s room07未加载正式静态布局，禁止动态兜底制造假绿" % label)
		return
	# 副本始终离树：只读对齐函数，不执行门墙转换，不增加任何碰撞遮挡。
	var saved_root := ROOM07_SAVED_SCENE.instantiate() as Node3D
	var source_transform := saved_root.transform
	var alignment_deg := float(room.call("_static_layout_alignment_delta_deg", saved_root))
	var aligned_transform := Transform3D(Basis(Vector3.UP, deg_to_rad(alignment_deg)), Vector3.ZERO) * source_transform
	var slot_to_room := art_root.transform if use_static else aligned_transform
	var source_metadata := {}
	var art_metadata := {}
	for key in saved_root.get_meta_list():
		source_metadata[str(key)] = saved_root.get_meta(key)
	if art_root != null:
		for key in art_root.get_meta_list():
			art_metadata[str(key)] = art_root.get_meta(key)
	print("WALL_SLOT_FRAME %s source_scene=%s source_metadata=%s art_metadata=%s plan_rotation=%.0f template_rotation=%s alignment=%.0f source_root=%s aligned_root=%s actual_art_root=%s selected_root=%s" % [label, ROOM07_SAVED_SCENE.resource_path, str(source_metadata), str(art_metadata), rotation_deg, str(room.get_meta("template_rotation_deg", "MISSING")), alignment_deg, str(source_transform), str(aligned_transform), str(art_root.transform) if art_root != null else "NONE", str(slot_to_room)])
	saved_root.free()
	if alignment_deg not in [0.0, 90.0, 180.0, 270.0]:
		wall_failures.append("%s 正式根对齐角度非法 alignment=%s" % [label, str(alignment_deg)])
		return
	if use_static and not slot_to_room.is_equal_approx(aligned_transform):
		wall_failures.append("%s 实际ArtRoot与正式源根对齐推导不一致，仍按实际根测射线" % label)
	var local_center := slot_to_room * MISSING_WALL_SAVED_FRAME_CENTER
	var slot_to_world := room.global_transform * slot_to_room
	var center := slot_to_world * MISSING_WALL_SAVED_FRAME_CENTER
	var tangent := (slot_to_world.basis * Vector3.RIGHT).normalized()
	var normal := (slot_to_world.basis * Vector3.BACK).normalized()
	var rigid_basis := slot_to_world.basis.orthonormalized()
	if not slot_to_world.basis.is_equal_approx(rigid_basis) or not rigid_basis.y.is_equal_approx(Vector3.UP) or not is_equal_approx(rigid_basis.determinant(), 1.0):
		wall_failures.append("%s 缺槽根不是水平刚体变换，禁止缩放改变5m采样" % label)
		return
	var matching_slots: Array[Dictionary] = []
	var nearest_wall: Dictionary = {}
	var nearest_distance := INF
	for value in room.authored_layout_instances:
		var instance := value as Dictionary
		var position := instance.get("position", Vector3.INF) as Vector3
		var distance := position.distance_to(local_center)
		if distance < 0.01:
			matching_slots.append(instance)
		if str(instance.get("slot_role", "")) in ["solid_wall", "door_wall", "corner_l"] and distance < nearest_distance:
			nearest_wall = instance
			nearest_distance = distance
	var planned_solid := matching_slots.size() == 1 and str(matching_slots[0].get("slot_role", "")) == "solid_wall"
	print("WALL_SLOT_SPACE %s slot=%s saved_frame=%s saved_tangent=%s saved_normal=%s local=%s world=%s tangent=%s normal=%s room_world=%s mapped_plan_slots=%s solid_wall=%s nearest_wall=%s nearest_distance=%.3f" % [label, MISSING_WALL_SLOT, _v(MISSING_WALL_SAVED_FRAME_CENTER), _v(Vector3.RIGHT), _v(Vector3.BACK), _v(local_center), _v(center), _v(tangent), _v(normal), str(room.global_transform), str(matching_slots), str(planned_solid), str(nearest_wall), nearest_distance])
	var connection_side := str(room.call("_authored_wall_connection_side", local_center, room.get_dimensions() * 0.5))
	if not planned_solid:
		print("WALL_SLOT_PLAN_DIAGNOSTIC %s room07非自持实墙 local=%s slots=%s；逐点要求全房真实墙owner承接" % [label, _v(local_center), str(matching_slots)])
	if not connection_side.is_empty():
		print("WALL_SLOT_PLAN_DIAGNOSTIC %s room07连接槽=%s owns_endpoint=%s（自持转门墙/共享端不生成）；仍要求逐点真实实墙承接" % [label, connection_side, str(room.owns_door_endpoint(connection_side))])
	if not planned_solid or not connection_side.is_empty():
		for value in room.connection_ports:
			var port := value as Dictionary
			var raw_position := port.get("position_m", []) as Array
			if raw_position.size() != 2:
				print("WALL_SLOT_PORT %s 非法端口=%s" % [label, str(port)])
				continue
			var port_position := Vector3(float(raw_position[0]), 0.0, float(raw_position[1]))
			var offset_world := room.to_global(port_position) - center
			var side := str(port.get("side", ""))
			print("WALL_SLOT_PORT %s port=%s local=%s world=%s slot_distance=%.3f tangent_offset=%.3f normal_offset=%.3f owns_endpoint=%s shared_endpoint=%s" % [label, str(port), _v(port_position), _v(room.to_global(port_position)), offset_world.length(), offset_world.dot(tangent), offset_world.dot(normal), str(room.owns_door_endpoint(side)), str(not room.owns_door_endpoint(side))])
	var wall_geometry := _wall_cover_geometry()
	var planned_walls := _planned_cover_walls(rooms, wall_geometry)
	wall_slot_count += 1
	var owner_points_start := wall_owner_point_count
	var space: PhysicsDirectSpaceState3D = tower.get_world_3d().direct_space_state
	var blocked := 0
	var clear := 0
	var door_rays := 0
	for offset in WALL_TANGENT_OFFSETS:
		for height in WALL_HEIGHTS:
			var point := center + tangent * offset + Vector3.UP * height
			wall_point_count += 1
			var point_owner_rays := 0
			for direction: float in [-1.0, 1.0]:
				var from := point - normal * 0.8 * direction
				var to := point + normal * 0.8 * direction
				var query := PhysicsRayQueryParameters3D.create(from, to, 1)
				query.exclude = [tower.player.get_rid()]
				var hit := space.intersect_ray(query)
				wall_ray_count += 1
				var collider := hit.get("collider") as Node
				var hit_room: DungeonRoom3D = null
				var ancestor := collider
				while ancestor != null:
					if ancestor is DungeonRoom3D:
						hit_room = ancestor as DungeonRoom3D
						break
					ancestor = ancestor.get_parent()
				var neighbor := hit_room != null and hit_room != room
				var door_crossing := _wall_ray_door_crossing(rooms, from, to)
				print("WALL_SLOT_RAY %s offset=%+.2f height=%.2f direction=%+.0f world_point=%s from=%s to=%s hit=%s collider_room=%s neighbor_cover=%s door_crossing=%s" % [label, offset, height, direction, _v(point), _v(from), _v(to), _hit_name(hit), hit_room.room_id if hit_room != null else "NONE", str(neighbor), door_crossing])
				if not door_crossing.is_empty():
					# 真实门实体的净洞范围，不按房名/缺件名豁免；正常门洞不记缺墙。
					door_rays += 1
					wall_door_ray_count += 1
					continue
				if hit.is_empty():
					clear += 1
					wall_clear_count += 1
					wall_failures.append("%s %s 实墙缺槽无遮挡 world=%s offset=%.2f height=%.2f direction=%.0f" % [label, MISSING_WALL_SLOT, _v(point), offset, height, direction])
				else:
					blocked += 1
					wall_blocked_count += 1
					var coverage := _wall_hit_owner_coverage(hit, hit_room, point, from, to, normal, planned_walls, wall_geometry)
					print("WALL_SLOT_OWNER %s offset=%+.2f height=%.2f direction=%+.0f source_slot_room07_solid=%s coverage=%s" % [label, offset, height, direction, str(planned_solid), str(coverage)])
					if coverage.is_empty():
						wall_failures.append("%s 非空命中但无已验证直墙owner承接 point=%s direction=%.0f hit=%s" % [label, _v(point), direction, _hit_name(hit)])
					else:
						point_owner_rays += 1
						if str(coverage["source"]) == "PLANNED_SOLID":
							wall_planned_owner_ray_count += 1
						else:
							wall_actual_owner_ray_count += 1
			if point_owner_rays == 2:
				wall_owner_point_count += 1
			else:
				wall_failures.append("%s 采样点双向真实墙owner覆盖不足 point=%s owner_rays=%d" % [label, _v(point), point_owner_rays])
	if wall_owner_point_count - owner_points_start != 27:
		wall_failures.append("%s 真实墙承接点不足 expected=27 actual=%d" % [label, wall_owner_point_count - owner_points_start])
	if door_rays > 0:
		wall_failures.append("%s 真实门洞射线%d条（不判缺墙），但预期实墙槽覆盖不足，需分析WALL_SLOT_RAY与当前plan端口" % [label, door_rays])
	if blocked + clear + door_rays != 54:
		wall_failures.append("%s 缺墙槽双向射线覆盖不足" % label)
	print("WALL_SLOT_SUMMARY %s points=27 rays=%d blocked=%d clear=%d door_rays=%d failures=%d" % [label, blocked + clear + door_rays, blocked, clear, door_rays, wall_failures.size() - failure_start])

## 尺寸与局部碰撞变换来自已核读直墙Prefab，不从名称或外包AABB推断。
func _wall_cover_geometry() -> Dictionary:
	var result := {}
	for packed in WALL_COVER_PREFABS:
		var root := packed.instantiate() as Node3D
		var shapes := root.find_children("*", "CollisionShape3D", true, false)
		if shapes.size() == 1:
			var collision := shapes[0] as CollisionShape3D
			var box := collision.shape as BoxShape3D
			var body := collision.get_parent() as StaticBody3D
			if box != null and body != null and body.get_parent() == root and not collision.disabled:
				result[packed.resource_path] = {"size": box.size, "shape_transform": body.transform * collision.transform}
		root.free()
	return result

func _planned_cover_walls(rooms: Array[DungeonRoom3D], geometry: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for room in rooms:
		for value in room.authored_layout_instances:
			var slot := value as Dictionary
			if str(slot.get("slot_role", "")) != "solid_wall":
				continue
			var position := slot.get("position", Vector3.INF) as Vector3
			# 清单的solid_wall若已提升门槽或是共享端，不能声称当前有计划实墙。
			if not str(room.call("_authored_wall_connection_side", position, room.get_dimensions() * 0.5)).is_empty():
				continue
			var packed := ROOM_SCRIPT._authored_component_prefab(str(slot.get("component_id", ""))) as PackedScene
			if packed == null or not geometry.has(packed.resource_path):
				continue
			var source := geometry[packed.resource_path] as Dictionary
			var basis := Basis(Vector3.UP, deg_to_rad(float(slot.get("rotation_y_deg", 0.0)))).scaled(slot.get("scale", Vector3.ONE) as Vector3)
			var slot_transform := room.global_transform * Transform3D(basis, position)
			result.append({"room": room, "slot": slot, "path": packed.resource_path, "transform": slot_transform * (source["shape_transform"] as Transform3D), "size": source["size"]})
	return result

## 在Box自身局部坐标验证：5m长轴、直立、同结构平面，射线完整垂直穿越两厚度面。
## 允许作者墙中心的微偏移，但采样边界必须仍在真实墙厚内，不接受远处碰撞。
func _wall_box_crosses(transform: Transform3D, size: Vector3, point: Vector3, from: Vector3, to: Vector3, normal: Vector3) -> bool:
	var along_axis := 0 if is_equal_approx(size.x, 5.0) else 2
	var thickness_axis := 2 if along_axis == 0 else 0
	if not is_equal_approx(size[along_axis], 5.0) or size[thickness_axis] <= 0.0 or size[thickness_axis] >= 0.8:
		return false
	var along := transform.basis.x if along_axis == 0 else transform.basis.z
	var outward := transform.basis.z if thickness_axis == 2 else transform.basis.x
	if not is_equal_approx(along.length(), 1.0) or not is_equal_approx(outward.length(), 1.0) or not transform.basis.y.is_equal_approx(Vector3.UP):
		return false
	if absf(outward.dot(normal)) < 0.999 or absf(along.dot(normal)) > 0.001 or absf(along.dot(outward)) > 0.001:
		return false
	var inverse := transform.affine_inverse()
	var local_point := inverse * point
	var local_from := inverse * from
	var local_to := inverse * to
	var half := size * 0.5
	if absf(local_point[thickness_axis]) > half[thickness_axis] + 0.001:
		return false
	if not ((local_from[thickness_axis] < -half[thickness_axis] and local_to[thickness_axis] > half[thickness_axis]) or (local_to[thickness_axis] < -half[thickness_axis] and local_from[thickness_axis] > half[thickness_axis])):
		return false
	var delta := local_to - local_from
	for face: float in [-1.0, 1.0]:
		var fraction := (face * half[thickness_axis] - local_from[thickness_axis]) / delta[thickness_axis]
		var crossing := local_from + delta * fraction
		if absf(crossing[along_axis]) >= half[along_axis] - 0.001 or absf(crossing.y) >= half.y - 0.001:
			return false
	return true

func _wall_hit_owner_coverage(hit: Dictionary, owner: DungeonRoom3D, point: Vector3, from: Vector3, to: Vector3, normal: Vector3, planned: Array[Dictionary], geometry: Dictionary) -> Dictionary:
	var body := hit.get("collider") as StaticBody3D
	var shape_index := int(hit.get("shape", -1))
	if owner == null or body == null or shape_index < 0 or (body.collision_layer & 1) == 0:
		return {}
	var module := body.get_parent() as Node3D
	# 已核读Prefab的自身碰撞；不允许沿祖先追到整屋场景来替柜子背书。
	if module == null or not geometry.has(module.scene_file_path) or module.get_parent() != owner.get_node_or_null("AuthoredLayoutArtRoot"):
		return {}
	var shape_owner := body.shape_find_owner(shape_index)
	var collision := body.shape_owner_get_owner(shape_owner) as CollisionShape3D
	if collision == null or collision.get_parent() != body or collision.disabled or body.is_shape_owner_disabled(shape_owner):
		return {}
	var box := collision.shape as BoxShape3D
	var source := geometry[module.scene_file_path] as Dictionary
	if box == null or not box.size.is_equal_approx(source["size"] as Vector3) or not (body.transform * collision.transform).is_equal_approx(source["shape_transform"] as Transform3D):
		return {}
	if not _wall_box_crosses(collision.global_transform, box.size, point, from, to, normal):
		return {}
	var result := {"source": "ACTUAL_PREFAB_ONLY", "plan_consistent": false, "owner_room": owner.room_id, "owner_slot": str(module.name), "slot_center": module.global_position, "shape_center": collision.global_position, "orientation": collision.global_basis, "prefab_source": module.scene_file_path, "shape": str(collision.get_path()), "size": box.size}
	for candidate in planned:
		if candidate["room"] != owner or str(candidate["path"]) != module.scene_file_path:
			continue
		var transform := candidate["transform"] as Transform3D
		if not _wall_box_crosses(transform, candidate["size"] as Vector3, point, from, to, normal):
			continue
		# 同房归属还不够：实际墙与计划墙须几何一致，不能拿同房另一个槽背书。
		if not transform.origin.is_equal_approx(collision.global_position) or not transform.basis.is_equal_approx(collision.global_basis):
			continue
		result["source"] = "PLANNED_SOLID"
		result["plan_consistent"] = true
		result["planned_slot"] = candidate["slot"]
		break
	return result

## 只认当前真实连接门实体净洞与射线交点，不把同侧但远离门洞的缺槽豁免。
func _wall_ray_door_crossing(rooms: Array[DungeonRoom3D], from: Vector3, to: Vector3) -> String:
	for room in rooms:
		for side in room.doors:
			if str(room.door_targets.get(side, "")).is_empty():
				continue
			var door := room.get_door_node(side)
			if door == null:
				continue
			var local_from := door.to_local(from)
			var local_to := door.to_local(to)
			var delta := local_to - local_from
			if absf(delta.z) < 0.0001:
				continue
			var fraction := -local_from.z / delta.z
			if fraction < 0.0 or fraction > 1.0:
				continue
			var crossing := local_from + delta * fraction
			var snapshot := door.get_snapshot()
			var half_width := float(snapshot["clear_width_m"]) * 0.5
			var clear_height := float(snapshot["clear_height_m"])
			if absf(crossing.x) < half_width - 0.01 and crossing.y > 0.0 and crossing.y < clear_height - 0.01:
				return "REAL_DOOR path=%s owner_room=%s local_crossing=%s width=%.2f height=%.2f open=%s" % [str(door.get_path()), room.room_id, _v(crossing), half_width * 2.0, clear_height, str(snapshot["is_open"])]
	return ""

func _hit_name(hit: Dictionary) -> String:
	if hit.is_empty():
		return "CLEAR"
	var collider := hit.get("collider") as Node
	if collider == null:
		return "UNKNOWN"
	var result := "%s:%s@%s" % [collider.name, collider.get_class(), collider.get_path()]
	var body := collider as CollisionObject3D
	if body == null:
		return result
	var shape_index := int(hit.get("shape", -1))
	result += " hit_world=%s shape_index=%d layer=%d mask=%d" % [str(hit.get("position", Vector3.ZERO)), shape_index, body.collision_layer, body.collision_mask]
	var room: DungeonRoom3D = null
	var module: Node3D = null
	var ancestor: Node = body.get_parent()
	while ancestor != null:
		if module == null and ancestor.has_meta("door_wall_collision_diagnostic"):
			module = ancestor as Node3D
		if ancestor is DungeonRoom3D:
			room = ancestor as DungeonRoom3D
			break
		ancestor = ancestor.get_parent()
	if shape_index < 0:
		return result
	var owner_id := body.shape_find_owner(shape_index)
	var collision := body.shape_owner_get_owner(owner_id) as CollisionShape3D
	result += " owner_disabled=%s" % str(body.is_shape_owner_disabled(owner_id))
	if collision == null:
		return result + " shape_owner_not_CollisionShape3D"
	result += " shape=%s disabled_now=%s shape_local=%s shape_world=%s" % [str(collision.get_path()), str(collision.disabled), str(collision.transform), str(collision.global_transform)]
	var box := collision.shape as BoxShape3D
	if box != null:
		result += " box_size=%s" % str(box.size)
	if room != null:
		var body_to_room := room.global_transform.affine_inverse() * body.global_transform
		var shape_to_room := room.global_transform.affine_inverse() * collision.global_transform
		result += " body_to_room=%s shape_to_room=%s" % [str(body_to_room), str(shape_to_room)]
		if box != null:
			var local_bounds := AABB(-box.size * 0.5, box.size)
			result += " shape_room_aabb=%s shape_world_aabb=%s" % [str(shape_to_room * local_bounds), str(collision.global_transform * local_bounds)]
	# 每个命中 body 只展开一次调用记录；射线日志仍逐条给出实际命中 shape。
	if not body.has_meta("door_lane_hit_diagnostic_printed"):
		body.set_meta("door_lane_hit_diagnostic_printed", true)
		print("HIT_BODY_SPACE path=%s local=%s world=%s" % [str(body.get_path()), str(body.transform), str(body.global_transform)])
		if room != null:
			var current_offsets := {}
			for side in room.doors:
				var key := "tower_wall_door_offset_%s" % side
				current_offsets[side] = {"present": room.has_meta(key), "offset": room.get_meta(key, 0.0), "door_world": room.get_meta("room_door_world_%s" % side, Vector3.ZERO)}
			print("HIT_ROOM_SPACE room=%s world=%s doors=%s offsets_now=%s ports_now=%s" % [room.room_id, str(room.global_transform), str(room.doors), str(current_offsets), str(room.connection_ports)])
		if module != null:
			print("HIT_WALL_CUT_CALL module=%s module_to_room_now=%s diagnostic=%s" % [str(module.get_path()), str(room.global_transform.affine_inverse() * module.global_transform) if room != null else "NO_ROOM", str(module.get_meta("door_wall_collision_diagnostic"))])
		else:
			print("HIT_WALL_CUT_CALL path=%s diagnostic=MISSING" % str(body.get_path()))
	return result

func _reciprocal_side(room: DungeonRoom3D, target_id: String) -> String:
	for side in room.doors:
		if str(room.door_targets.get(side, "")) == target_id:
			return side
	return ""

func _v(value: Vector3) -> String:
	return "(%.2f,%.2f,%.2f)" % [value.x, value.y, value.z]

func _v2(value: Vector2) -> String:
	return "(%.1fx%.1f)" % [value.x, value.y]
