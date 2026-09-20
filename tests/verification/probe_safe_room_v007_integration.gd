extends Node
## 一次性探针：核对入口安全房 v007 正式美术接入运行时之后的实际装配结果。
## 覆盖三件事：
##   1. 通用组件库 v004 的墙/地/门四件套契约（原点、包围盒、内嵌碰撞、地砖 snap 值）
##   2. 17 个 v007 房间包的 room_placement_position 元数据与实测本地包围盒
##   3. 四种门向组合下 STAIR_LOBBY 房间的整房旋转、墙模块落位、门扇落位与计数
## 只读，不改任何游戏状态。

const ROOM_RUNTIME_ROOT := "res://assets/art/environments/tower_zones/battle/runtime/"
const SAFE_ROOM_VERSION := "v007"
const SAFE_ROOM_PACKAGE_IDS: Array[String] = [
	"floor_base",
	"overhead_services",
	"debris_papers",
	"north_server_00",
	"north_server_01",
	"north_server_02",
	"north_server_03",
	"north_server_04",
	"north_server_05",
	"north_broken_core",
	"north_nexus_sign",
	"east_repair_bay",
	"east_robot_arm",
	"office_planter",
	"maintenance_chair",
]
const COMPONENT_IDS: Array[String] = [
	"wall_standard_5m", "wall_door_5m", "door_5m", "floor_tile_r01_c01", "floor_tile_r01_c02"
]
const DOOR_COMBINATIONS: Array = [
	["east", "south"],
	["west", "south"],
	["east", "north"],
	["west", "north"],
]

var failures: Array[String] = []


func _ready() -> void:
	print("=== 探针：安全房 v007 接入 —— 通用组件 v004 契约 ===")
	_probe_components()
	print("")
	print("=== 探针：安全房 v007 —— 17 个房间包元数据与包围盒 ===")
	_probe_packages()
	print("")
	print("=== 探针：安全房 v007 —— STAIR_LOBBY 实际装配 ===")
	await _probe_rooms()
	print("")
	if failures.is_empty():
		print("SAFE_ROOM_V007_INTEGRATION_OK")
	else:
		print("SAFE_ROOM_V007_INTEGRATION_FAIL: %d" % failures.size())
		for failure in failures:
			print("  - ", failure)
	get_tree().quit(0 if failures.is_empty() else 1)


func _probe_components() -> void:
	for component_id in COMPONENT_IDS:
		var scene_path := "%scommon_components/%s/%s_root_top3d.tscn" % [
			ROOM_RUNTIME_ROOT, _component_dir(component_id), component_id
		]
		var packed := load(scene_path) as PackedScene
		if packed == null:
			failures.append("组件无法加载 %s" % scene_path)
			continue
		var instance := packed.instantiate() as Node3D
		var bounds := instance.get_meta("bounds_size_m", Vector3.ZERO) as Vector3
		var collision_count := 0
		var enabled_shapes := 0
		for value in instance.find_children("*", "StaticBody3D", true, false):
			collision_count += 1
			for shape_value in (value as StaticBody3D).find_children(
				"*", "CollisionShape3D", true, false
			):
				if not (shape_value as CollisionShape3D).disabled:
					enabled_shapes += 1
		print(
			"  %-20s origin=%-13s forward=%-3s up=%-3s bounds=%s collision_owner=%s bodies=%d shapes=%d snap_y=%s"
			% [
				component_id,
				str(instance.get_meta("origin_contract", "")),
				str(instance.get_meta("forward_axis", "")),
				str(instance.get_meta("up_axis", "")),
				_vector3_text(bounds),
				str(instance.get_meta("collision_owner", "")),
				collision_count,
				enabled_shapes,
				str(instance.get_meta("snap_to_walk_plane_offset_m", "-")),
			]
		)
		instance.free()


func _component_dir(component_id: String) -> String:
	if component_id.begins_with("floor_tile"):
		return "floor_tile_5m"
	return component_id


func _probe_packages() -> void:
	var total_min_y := INF
	var total_max_y := -INF
	for package_id in SAFE_ROOM_PACKAGE_IDS:
		var scene_path := "%sentry_safe_room/%s/%s_root_top3d.tscn" % [
			ROOM_RUNTIME_ROOT, package_id, package_id
		]
		if not ResourceLoader.exists(scene_path):
			failures.append("房间包缺失 %s" % scene_path)
			continue
		var packed := load(scene_path) as PackedScene
		var package := packed.instantiate() as Node3D
		var placement := package.get_meta("room_placement_position", Vector3.ZERO) as Vector3
		var box := _local_aabb(package)
		total_min_y = minf(total_min_y, box.position.y)
		total_max_y = maxf(total_max_y, box.position.y + box.size.y)
		var has_meta := package.has_meta("room_placement_position")
		if not has_meta:
			failures.append("房间包缺少 room_placement_position：%s" % package_id)
		print(
			"  %-24s placement=%s aabb_min=%s aabb_size=%s  [落位后 y=%.3f..%.3f]"
			% [
				package_id,
				_vector3_text(placement),
				_vector3_text(box.position),
				_vector3_text(box.size),
				placement.y - DungeonRoom3D.SAFE_ROOM_WALK_LIFT_M + box.position.y,
				placement.y - DungeonRoom3D.SAFE_ROOM_WALK_LIFT_M + box.position.y + box.size.y,
			]
		)
		package.free()
	print("  全部房间包合并后本地 y 范围 %.3f .. %.3f（下沉 0.30 后 %.3f .. %.3f）" % [
		total_min_y, total_max_y, total_min_y - 0.30, total_max_y - 0.30
	])


func _probe_rooms() -> void:
	for combination in DOOR_COMBINATIONS:
		var doors: Array[String] = []
		for value in combination:
			doors.append(str(value))
		var room := DungeonRoom3D.new()
		room.configure({
			"room_id": "probe_safe_room_%s" % "_".join(doors),
			"room_type": "STAIR_LOBBY",
			"size_class": "tower_cell",
			"doors": doors,
			"door_targets": {doors[0]: "probe_a", doors[1]: "probe_b"},
			"seed": 4242,
			"custom_dimensions": Vector2(15.0, 15.0),
			"tower_module_shell": true,
		})
		add_child(room)
		room.ensure_shell_built()
		room.ensure_detail_built()
		var snapshot := room.get_room_snapshot()
		print("  --- doors=[%s] ---" % ", ".join(doors))
		print(
			"      steps=%d art=%s wall=%d doorwall=%d tile=%d package=%d" % [
				int(snapshot.get("safe_room_orientation_steps", -99)),
				str(snapshot.get("safe_room_art_version", "")),
				int(snapshot.get("safe_room_wall_module_count", -1)),
				int(snapshot.get("safe_room_door_wall_module_count", -1)),
				int(snapshot.get("safe_room_floor_tile_count", -1)),
				int(snapshot.get("safe_room_package_count", -1)),
			]
		)
		_expect(int(snapshot.get("safe_room_wall_module_count", -1)) == 10, "实墙模块应为 10", doors)
		_expect(int(snapshot.get("safe_room_door_wall_module_count", -1)) == 2, "门墙模块应为 2", doors)
		_expect(int(snapshot.get("safe_room_floor_tile_count", -1)) == 9, "地砖应为 9", doors)
		_expect(
			int(snapshot.get("safe_room_package_count", -1)) == SAFE_ROOM_PACKAGE_IDS.size(),
			"房间包数应与本清单一致（%d）" % SAFE_ROOM_PACKAGE_IDS.size(),
			doors
		)
		# 旧塔楼拼装不得残留，否则与 v004 墙体重影。
		_expect(
			_count_meta(room, "asset_id", "ENV-TOWER-WALL-SOLID-5M") == 0,
			"不应残留旧塔楼实墙视觉",
			doors
		)
		_expect(
			_count_meta(room, "asset_id", "ENV-TOWER-CORNER-L-5M") == 0,
			"不应残留旧塔楼拐角组件",
			doors
		)
		_expect(
			_count_meta(room, "asset_id", "ENV-TOWER-WALL-DOOR-5M") == 0,
			"不应残留旧塔楼门墙模块",
			doors
		)
		# 门洞必须落在真正有门的那两面墙上。
		var door_wall_sides: Array[String] = []
		for value in room.find_children("SafeRoomWall_*_Door", "Node3D", true, false):
			var module := value as Node3D
			door_wall_sides.append(
				_effective_direction(
					str(module.get_meta("stair_lobby_native_direction", "")),
					module.get_parent().rotation.y
				)
			)
		door_wall_sides.sort()
		var expected_sides: Array[String] = doors.duplicate()
		expected_sides.sort()
		print("      门墙实际朝向=%s  期望=%s" % [door_wall_sides, expected_sides])
		_expect(door_wall_sides == expected_sides, "门墙朝向与实际门向不一致", doors)
		# 门扇中心应落在 ±7.5 边界网格线上（= 塔楼房间边界口径）。
		for direction in doors:
			var door := room.get_node_or_null("Door_%s" % direction.capitalize()) as RoomDoor3D
			if door == null:
				failures.append("doors=%s 缺少 %s 门扇" % [doors, direction])
				continue
			# 北/南门沿 ±Z 面，东/西门沿 ±X 面；取对应轴才是"距房间中心的墙面距离"。
			var lateral := (
				absf(door.position.z) if direction in ["north", "south"] else absf(door.position.x)
			)
			var leaf := door.get_node_or_null("DoorPanel/ImportedDoorVisual")
			var leaf_bodies := 0
			var live_leaf_bodies := 0
			if leaf != null:
				for body_value in leaf.find_children("*", "StaticBody3D", true, false):
					leaf_bodies += 1
					if (body_value as StaticBody3D).collision_layer != 0:
						live_leaf_bodies += 1
			print(
				"      door %-5s pos=%s rot_y=%.1f 墙面距离=%.2f 门扇包=%s 门扇内碰撞体=%d(活%d)"
				% [
					direction,
					_vector3_text(door.position),
					rad_to_deg(door.rotation.y),
					lateral,
					"有" if leaf != null else "无",
					leaf_bodies,
					live_leaf_bodies,
				]
			)
			_expect(is_equal_approx(lateral, 7.5), "门扇未落在 7.5 边界网格线", doors)
			_expect(leaf != null, "门扇包未接入", doors)
			# 2026-09-19：安全房门扇换成塔楼 A 套正式美术（prp_tower_door_leaf_5m），
			# 它声明 visual_only 且**不自带碰撞**。旧断言要求「门扇包自带碰撞被去重」，
			# 那是 B 套 door_5m 包（自带 DoorCollision StaticBody3D）的历史形态 ——
			# 它正是最后一处冗余碰撞。契约已改为碰撞责任单一化：
			# 门扇不得携带任何活的碰撞，门洞阻挡唯一由 RoomDoor3D 的升降碰撞负责。
			_expect(leaf_bodies == 0, "门扇包不应自带碰撞（碰撞责任单一化）", doors)
			_expect(live_leaf_bodies == 0, "门扇包内不得有启用的碰撞体", doors)
			# 南北向门洞开门后不能留实体碰撞：必须有唯一 camera-only 门墙代理
			# 承接 TowerDescent3D 的镜头探针（与旧塔楼拼装路径同契约）。
			var proxies := room.find_children(
				"CameraOnlyDoorWall_%s_*" % direction.capitalize(),
				"StaticBody3D",
				true,
				false
			)
			if direction in ["north", "south"]:
				_expect(proxies.size() == 1, "南北向门缺少 camera-only 门墙代理", doors)
			else:
				_expect(proxies.is_empty(), "东西向门不应有 camera-only 门墙代理", doors)
			# 门墙模块的 tower_wall_direction 必须是整房旋转后的世界朝向。
			for value in room.find_children("SafeRoomWall_*_Door", "Node3D", true, false):
				var module := value as Node3D
				if _effective_direction(
					str(module.get_meta("stair_lobby_native_direction", "")),
					module.get_parent().rotation.y
				) == direction:
					_expect(
						str(module.get_meta("tower_wall_direction", "")) == direction,
						"门墙 tower_wall_direction 未按世界朝向记录",
						doors
					)
		room.queue_free()
		await get_tree().process_frame


func _effective_direction(native_direction: String, rotation_y: float) -> String:
	var vector := Vector3.ZERO
	match native_direction:
		"north":
			vector = Vector3(0.0, 0.0, -1.0)
		"south":
			vector = Vector3(0.0, 0.0, 1.0)
		"east":
			vector = Vector3(1.0, 0.0, 0.0)
		"west":
			vector = Vector3(-1.0, 0.0, 0.0)
	var rotated := vector.rotated(Vector3.UP, rotation_y)
	if absf(rotated.x) >= absf(rotated.z):
		return "east" if rotated.x > 0.0 else "west"
	return "south" if rotated.z > 0.0 else "north"


func _count_meta(root: Node, key: String, value: Variant) -> int:
	var total := 0
	if root.has_meta(key) and root.get_meta(key) == value:
		total += 1
	for child in root.get_children():
		total += _count_meta(child, key, value)
	return total


func _local_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var has_result := false
	for value in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := value as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var box := _relative_transform(root, mesh_instance) * mesh_instance.get_aabb()
		if not has_result:
			result = box
			has_result = true
		else:
			result = result.merge(box)
	return result


func _relative_transform(root: Node, node: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result


func _vector3_text(value: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [value.x, value.y, value.z]


func _expect(condition: bool, message: String, context: Variant) -> void:
	if not condition:
		failures.append("%s [%s]" % [message, context])
