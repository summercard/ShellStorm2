extends Node

# 实测远征 01 主路上每一对相邻房间的两扇门是否落在**同一世界点**。
# 判据：两房墙贴墙（净距 0）⇒ 本房门 world 位置与对端房门的 world 位置必须重合；
# 沿轴分量不一致就是「门和门没对齐」，也就是肉眼看到的屋子错位。
# 同时打印两房中心在垂轴上的偏移（0 或 2.5 m 是设计允许的共轴偏移，不是错位）。
#
# 两条装配路径都跑：STATIC（静态 TSCN，游戏内实际走的）与 DYNAMIC（程序化装配）。

const EXPEDITION_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const ROOM_SCRIPT := preload("res://src/world3d/DungeonRoom3D.gd")
## 远征01当前为固定版图；用项目既有固定种子同时验证静态/动态两条装配路径。
const RUN_SEEDS: Array[int] = [77001199]

var failures: Array[String] = []
var pair_count := 0

func _ready() -> void:
	for seed_value in RUN_SEEDS:
		await _probe_seed(seed_value, true, "STATIC")
	for seed_value in RUN_SEEDS:
		await _probe_seed(seed_value, false, "DYNAMIC")
	if failures.is_empty():
		print("EXPEDITION_DOOR_LANE_OK")
	else:
		for failure in failures:
			print("DOOR_GAP %s" % failure)
	print("EXPEDITION_DOOR_LANE_DONE pairs=%d misaligned=%d" % [pair_count, failures.size()])
	get_tree().quit(0)

func _probe_seed(seed_value: int, use_static: bool, label: String) -> void:
	ROOM_SCRIPT.use_expedition_static_layout_scenes = use_static
	var tower := EXPEDITION_SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = seed_value
	add_child(tower)
	for _index in range(6):
		await get_tree().process_frame
		await get_tree().physics_frame
	var rooms := _collect_rooms(tower)
	for room in rooms:
		room.ensure_shell_built()
	await get_tree().process_frame
	await get_tree().physics_frame
	print("=== seed=%d %s rooms=%d ===" % [seed_value, label, rooms.size()])
	var start_room := _room_by_id(rooms, "start")
	var room_01 := _room_by_id(rooms, "room_01")
	var room_02 := _room_by_id(rooms, "room_02")
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
		if seed_value == RUN_SEEDS[0]:
			await _check_start_room01_passage(tower, start_room, room_01, label)
	if room_02 != null:
		for target_value in room_02.door_targets.values():
			var target_room := _room_by_id(rooms, str(target_value))
			if target_room != null:
				await _check_shared_door_passage(tower, room_02, target_room, label)
	_check_pairs(rooms, "%s seed=%d" % [label, seed_value])
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
	var forward: Vector3 = (room_01.global_position - start_room.global_position).normalized()
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


## room02 的入口/出口曾出现“门扇在 +2.5、静态实墙仍在同槽”的空气墙。
## 开门后沿真实端口法线穿过三条射线；命中任何静态墙碰撞即失败。
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
	var normal := {
		"north": Vector3(0.0, 0.0, -1.0), "south": Vector3(0.0, 0.0, 1.0),
		"west": Vector3(-1.0, 0.0, 0.0), "east": Vector3(1.0, 0.0, 0.0),
	}.get(owner_side, Vector3.ZERO) as Vector3
	var tangent := Vector3(normal.z, 0.0, -normal.x)
	var center := _door_world(owner, owner_side)
	var space: PhysicsDirectSpaceState3D = tower.get_world_3d().direct_space_state
	for tangent_offset in [-0.8, 0.0, 0.8]:
		for height in [0.45, 1.20, 2.20]:
			var from: Vector3 = center - normal * 1.8 + tangent * tangent_offset + Vector3.UP * height
			var to: Vector3 = center + normal * 1.8 + tangent * tangent_offset + Vector3.UP * height
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
			print(
				"ROOM02_PASSAGE %s edge=%s-%s owner=%s.%s tangent=%+.2f y=%.2f hit=%s"
				% [label, first_room.room_id, second_room.room_id, owner.room_id, owner_side, tangent_offset, height, _hit_name(hit)]
			)
			if not hit.is_empty():
				failures.append(
					"%s %s-%s 开门后被 %s 阻挡（横偏 %.2f，高 %.2f）"
					% [label, first_room.room_id, second_room.room_id, _hit_name(hit), tangent_offset, height]
				)

func _hit_name(hit: Dictionary) -> String:
	if hit.is_empty():
		return "CLEAR"
	var collider := hit.get("collider") as Node
	if collider == null:
		return "UNKNOWN"
	return "%s:%s@%s" % [collider.name, collider.get_class(), collider.get_path()]

func _reciprocal_side(room: DungeonRoom3D, target_id: String) -> String:
	for side in room.doors:
		if str(room.door_targets.get(side, "")) == target_id:
			return side
	return ""

func _v(value: Vector3) -> String:
	return "(%.2f,%.2f,%.2f)" % [value.x, value.y, value.z]

func _v2(value: Vector2) -> String:
	return "(%.1fx%.1f)" % [value.x, value.y]
