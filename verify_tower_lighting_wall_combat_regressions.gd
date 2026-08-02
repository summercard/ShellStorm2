extends Node
## 灯光分层、9m墙、南墙摄像机标记、隐藏连接器碰撞和刷怪软锁综合回归。

const TOWER_SCENE: PackedScene = preload("res://scenes/TowerDescent3D.tscn")
const HOSTILE_TYPES: Array[String] = [
	"COMBAT", "ELITE", "BOSS", "TRAP", "BASEMENT", "STORAGE", "SCAVENGE",
]


func _ready() -> void:
	var failures: Array[String] = []
	var tower := TOWER_SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	_validate_light_layers(tower, failures)
	_validate_floor_materials(failures)
	_validate_wall_components(tower, failures)
	_validate_hidden_connector_collisions(tower, failures)
	_validate_hostile_room_spawning(tower, failures)
	tower.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("TOWER_LIGHTING_WALL_COMBAT_REGRESSIONS_OK: external avatar shadows, matte floors, 9m walls, south-only camera walls, visible collision parity and hostile spawning pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _validate_light_layers(tower: TowerDescent3D, failures: Array[String]) -> void:
	var sun := tower.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if sun == null or not sun.shadow_enabled or sun.light_cull_mask != 3:
		failures.append("Sun does not cast shadows onto both environment and avatar layers")
	elif sun.light_energy > 0.60:
		failures.append("Sun energy is still overexposed: %.2f" % sun.light_energy)
	var avatar_casters := 0
	for value in tower.player.avatar.find_children("*", "MeshInstance3D", true, false):
		var mesh := value as MeshInstance3D
		if mesh.layers == 2 and mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
			avatar_casters += 1
	if avatar_casters <= 0:
		failures.append("Avatar has no external-light shadow casters on render layer 2")
	var flashlight := tower.player.get_node_or_null("PlayerFlashlight3D") as PlayerFlashlight3D
	if flashlight == null:
		failures.append("Player three-light rig is missing")
		return
	flashlight.set_light_enabled(true)
	var beam := flashlight.get_node_or_null("FlashlightKit/ForwardBeam") as SpotLight3D
	var spill := flashlight.get_node_or_null("FlashlightKit/EnvironmentSpill") as OmniLight3D
	var fill := flashlight.get_node_or_null("FlashlightKit/AvatarFrontFill") as SpotLight3D
	if beam == null or beam.light_cull_mask != 1 or not beam.shadow_enabled:
		failures.append("Player forward beam is not an environment-only shadow light")
	if spill == null or spill.light_cull_mask != 1 or spill.shadow_enabled:
		failures.append("Player spill light can affect/self-shadow the avatar")
	if fill == null or fill.light_cull_mask != 2 or fill.shadow_enabled:
		failures.append("Player avatar fill is not an avatar-only no-shadow light")
	var facility := (tower.get("_room_by_id") as Dictionary).get("facility") as DungeonRoom3D
	if facility == null or not is_instance_valid(facility):
		failures.append("Facility room is unavailable for room-light validation")
		return
	facility.set_stream_state(2)
	var room_lights := facility.get("_room_lights") as Array[WastelandLight3D]
	var shadow_room_light_found := false
	for light in room_lights:
		if light != null and light.light_cull_mask == 3 and light.cast_shadow:
			shadow_room_light_found = true
			break
	if not shadow_room_light_found:
		failures.append("Indoor lights cannot cast avatar shadows on render layer 2")


func _validate_floor_materials(failures: Array[String]) -> void:
	for path in [
		"res://assets/art/environments/tower_descent_3d/components/mat_tower_floor_tile_override_top3d_v001.tres",
		"res://assets/art/environments/tower_descent_3d/components/mat_tower_floor_tile_dark_top3d_v001.tres",
		"res://assets/art/environments/tower_descent_3d/components/mat_tower_floor_tile_warm_a_v001.tres",
		"res://assets/art/environments/tower_descent_3d/components/mat_tower_floor_tile_warm_b_v001.tres",
	]:
		var material := load(path) as StandardMaterial3D
		if material == null or material.metallic > 0.10 or material.roughness < 0.88:
			failures.append("Floor material remains too reflective: %s" % path)


func _validate_wall_components(tower: TowerDescent3D, failures: Array[String]) -> void:
	var rooms := tower.get("_rooms") as Array[DungeonRoom3D]
	for room in rooms:
		if room == null or not is_instance_valid(room) or not room.tower_module_shell or room.size_class == "rooftop":
			continue
		room.set_stream_state(1)
		for value in room.find_children("*", "MeshInstance3D", true, false):
			var mesh := value as MeshInstance3D
			if not (
				mesh.name.begins_with("Imported_SolidWall5M_")
				or mesh.name in ["Wall_Long", "Wall_Short", "WallDoor_Left", "WallDoor_Right", "WallDoor_Lintel"]
			):
				continue
			var world_aabb := mesh.global_transform * mesh.get_aabb()
			var room_floor_y := room.global_position.y
			if world_aabb.position.y < room_floor_y - 0.02 or world_aabb.end.y > room_floor_y + 9.02:
				failures.append("Wall component exceeds the 0-9m floor envelope: %s" % mesh.get_path())
			elif world_aabb.size.y < 6.45 and "Lintel" not in mesh.name:
				failures.append("Wall component is not full-height: %s height=%.2f" % [mesh.get_path(), world_aabb.size.y])
		for value in room.find_children("*", "StaticBody3D", true, false):
			var body := value as StaticBody3D
			if not bool(body.get_meta("camera_lower_wall", false)):
				continue
			var is_south_component := (
				"South" in str(body.name)
				or _ancestor_has_meta(body, "tower_wall_direction", "south")
				or _ancestor_corner_is_south(body)
			)
			if not is_south_component:
				failures.append("Non-south wall has camera interaction enabled: %s" % body.get_path())
		break


func _validate_hidden_connector_collisions(tower: TowerDescent3D, failures: Array[String]) -> void:
	for value in (tower.get("_corridor_by_edge") as Dictionary).values():
		var connector := value as Node3D
		if connector == null or connector.visible:
			continue
		for shape_value in connector.find_children("*", "CollisionShape3D", true, false):
			var shape := shape_value as CollisionShape3D
			if not shape.disabled:
				failures.append("Hidden connector retains a blocking collision: %s" % shape.get_path())
				return


func _validate_hostile_room_spawning(tower: TowerDescent3D, failures: Array[String]) -> void:
	var representatives: Dictionary = {}
	for room in (tower.get("_rooms") as Array[DungeonRoom3D]):
		if room != null and is_instance_valid(room) and room.room_type in HOSTILE_TYPES and not representatives.has(room.room_type):
			representatives[room.room_type] = room
	for room_type in representatives:
		var room := representatives[room_type] as DungeonRoom3D
		if room == null or not is_instance_valid(room):
			failures.append("Hostile room representative was freed: %s" % room_type)
			continue
		room.set_stream_state(2)
		var spawned := bool(tower.call("_spawn_room_enemies", room))
		var alive := int((tower.get("_alive_by_room") as Dictionary).get(room.room_id, 0))
		if not spawned or alive <= 0:
			failures.append("Hostile room type %s cannot spawn a first wave" % room_type)
	# 模拟旧版本残留：房间被记为访问过，但既没有活怪也没有待刷波次。
	var repair_room := representatives.get("COMBAT") as DungeonRoom3D
	if repair_room != null and is_instance_valid(repair_room):
		var repair_room_id := repair_room.room_id
		for value in (tower.get("_enemy_nodes_by_room") as Dictionary).get(repair_room_id, []):
			var enemy := value as Enemy3D
			if enemy != null:
				enemy.free()
		(tower.get("_enemy_nodes_by_room") as Dictionary)[repair_room_id] = []
		(tower.get("_room_wave_queues") as Dictionary)[repair_room_id] = []
		(tower.get("_alive_by_room") as Dictionary)[repair_room_id] = 7
		(tower.get("_spawned_rooms") as Dictionary)[repair_room_id] = true
		repair_room.cleared = false
		tower.call("_on_room_entered", repair_room)
		if int((tower.get("_alive_by_room") as Dictionary).get(repair_room_id, 0)) <= 0:
			failures.append("Visited hostile room with stale enemy state was not repaired")


func _ancestor_has_meta(node: Node, key: String, value: String) -> bool:
	var current := node
	while current != null:
		if str(current.get_meta(key, "")) == value:
			return true
		current = current.get_parent()
	return false


func _ancestor_corner_is_south(node: Node) -> bool:
	var current := node
	while current != null:
		if str(current.get_meta("tower_wall_corner", "")) in ["SW", "SE"]:
			return true
		current = current.get_parent()
	return false
