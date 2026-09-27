extends Node
## 只读探针：远征01 房间「刷怪避让」的基准到底是什么。
## 三问：① 安全距离是相对地砖并集边界还是相对碰撞体？② 墙件有没有碰撞代理？
## ③ 判据形状是圆还是方？输出 res://_scratch/expedition_spawn_map/spawn_avoidance.json

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const OUT_PATH := "res://_scratch/expedition_spawn_map/spawn_avoidance.json"
const SEED := 77001199


func _v3(value: Vector3) -> Array:
	return [
		snappedf(value.x, 0.001),
		snappedf(value.y, 0.001),
		snappedf(value.z, 0.001),
	]


func _instance_keys(level: Node) -> Array:
	var rooms: Array = level.find_children("*", "DungeonRoom3D", true, false)
	for value in rooms:
		var room := value as DungeonRoom3D
		if room == null or room.authored_layout_instances.is_empty():
			continue
		var first := room.authored_layout_instances[0] as Dictionary
		var keys: Array = []
		for key in first.keys():
			keys.append(str(key))
		return keys
	return []


func _ready() -> void:
	print("[probe] boot")
	var packed: PackedScene = load(EXPEDITION_SCENE) as PackedScene
	if packed == null:
		push_error("无法加载 %s" % EXPEDITION_SCENE)
		get_tree().quit(1)
		return
	var level: Node = packed.instantiate()
	if level == null:
		push_error("实例化失败")
		get_tree().quit(1)
		return
	if "test_mode" in level:
		level.set("test_mode", true)
	if "run_seed_override" in level:
		level.set("run_seed_override", SEED)
	add_child(level)
	for _i in 12:
		await get_tree().process_frame

	var rows: Array = []
	var rooms: Array = level.find_children("*", "DungeonRoom3D", true, false)
	for value in rooms:
		var room := value as DungeonRoom3D
		if room == null:
			continue
		room._collect_spawn_blockers()
		var blocker_rows: Array = []
		for b in room._spawn_blockers:
			var box := b as AABB
			blocker_rows.append({"pos": _v3(box.position), "size": _v3(box.size)})
		var roles: Dictionary = {}
		var wall_instances: Array = []
		for inst in room.authored_layout_instances:
			var entry := inst as Dictionary
			var role := str(entry.get("slot_role", ""))
			roles[role] = int(roles.get(role, 0)) + 1
			var tag := str(entry.get("component_id", entry.get("prefab_path", entry.get("path", ""))))
			var low := tag.to_lower()
			if low.contains("wall") and wall_instances.size() < 12:
				var pos := entry.get("position", Vector3.ZERO) as Vector3
				wall_instances.append({"tag": tag, "slot_role": role, "pos": _v3(pos)})
		rows.append({
			"room_id": room.room_id,
			"room_type": room.room_type,
			"clearance": room._spawn_clearance(),
			"authored_layout_shell": room.authored_layout_shell,
			"tile_cell_count": room._authored_tile_cells.size(),
			"candidate_count": room._spawn_candidates.size(),
			"slot_roles": roles,
			"blocker_count": blocker_rows.size(),
			"blockers": blocker_rows,
			"wall_instances_sample": wall_instances,
		})

	var wall_colliders: Array = []
	var owner_names: Dictionary = {}
	var total_colliders := 0
	for value in level.find_children("*", "CollisionShape3D", true, false):
		var shape_node := value as CollisionShape3D
		if shape_node == null or shape_node.shape == null:
			continue
		var body := shape_node.get_parent() as StaticBody3D
		if body == null or (body.collision_layer & 1) == 0:
			continue
		total_colliders += 1
		var owner_name := str(body.name)
		owner_names[owner_name] = int(owner_names.get(owner_name, 0)) + 1
		if owner_name.to_lower().contains("wall") and wall_colliders.size() < 80:
			var gbox: AABB = shape_node.global_transform * shape_node.shape.get_debug_mesh().get_aabb()
			wall_colliders.append({
				"owner": owner_name,
				"pos": _v3(gbox.position),
				"size": _v3(gbox.size),
			})

	var payload := {
		"seed": SEED,
		"instance_keys": _instance_keys(level),
		"constant_clearance_m": 1.15,
		"constant_boss_clearance_m": 2.2,
		"constant_body_height_m": 2.6,
		"room_count": rows.size(),
		"rooms": rows,
		"static_collider_total": total_colliders,
		"collider_owner_kinds": owner_names.size(),
		"collider_owners": owner_names,
		"wall_named_collider_count": wall_colliders.size(),
		"wall_named_colliders": wall_colliders,
	}
	var file := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("无法写入 %s" % OUT_PATH)
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify(payload, "  "))
	file.close()
	print("[probe] SPAWN_AVOIDANCE_DONE %s" % OUT_PATH)
	get_tree().quit(0)
