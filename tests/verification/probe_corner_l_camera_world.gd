extends Node

# 实测 L 型转角两条臂在世界空间的延伸轴与 camera_lower_wall 标记，
# 判断「该触发镜头避障的南北向臂」是否被正确标记。
# 判据：臂的延伸轴接近世界 X（|x| >= |z|）= 南北向墙（玩家背后的墙）→ 应标记。

const EXPEDITION_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const ROOM_SCRIPT := preload("res://src/world3d/DungeonRoom3D.gd")
const RUN_SEED := 77001199
const TARGET_ROOM := "start"

var failures: Array[String] = []

func _ready() -> void:
	await _probe_mode(true, "STATIC")
	await _probe_mode(false, "DYNAMIC")
	if failures.is_empty():
		print("CORNER_L_CAMERA_WORLD_OK")
	else:
		for failure in failures:
			print("CORNER_GAP %s" % failure)
	print("CORNER_L_CAMERA_WORLD_DONE gaps=%d" % failures.size())
	get_tree().quit(0)

func _probe_mode(use_static: bool, label: String) -> void:
	ROOM_SCRIPT.use_expedition_static_layout_scenes = use_static
	var tower := EXPEDITION_SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	for _index in range(8):
		await get_tree().process_frame
		await get_tree().physics_frame
	var block := tower.get_node_or_null("Blocks/Expedition") as Node3D
	var room := block.get_node_or_null(TARGET_ROOM) as DungeonRoom3D
	room.ensure_shell_built()
	await get_tree().process_frame
	await get_tree().physics_frame
	var art_root := room.get_node_or_null("SafeRoomArtRoot") as Node3D
	print("=== %s room=%s art_root_rot_y=%.4f ===" % [label, TARGET_ROOM, art_root.rotation.y])
	_dump_corners(art_root)
	tower.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	ROOM_SCRIPT.use_expedition_static_layout_scenes = true

func _dump_corners(art_root: Node3D) -> void:
	for child in art_root.get_children():
		var module := child as Node3D
		if module == null:
			continue
		var corner_id := str(module.get_meta("tower_wall_corner", ""))
		if corner_id.is_empty():
			continue
		var world_yaw := rad_to_deg(module.global_transform.basis.get_euler().y)
		print(
			"--- corner=%s local_pos=%s local_rot_y=%.4f world_yaw=%.1f ---"
			% [corner_id, str(module.position), module.rotation.y, world_yaw]
		)
		for value in module.find_children("*", "StaticBody3D", true, false):
			var body := value as StaticBody3D
			var axis := Vector3.ZERO
			if body.name == "WallCollisionLong":
				axis = module.global_transform.basis.x
			elif body.name == "WallCollisionShort":
				axis = module.global_transform.basis.z
			else:
				continue
			var axis_world := axis.normalized()
			var should := absf(axis_world.x) >= absf(axis_world.z)
			var marked := bool(body.get_meta("camera_lower_wall", false))
			print(
				"    %s axis=(%.3f,%.3f,%.3f) should=%s marked=%s"
				% [body.name, axis_world.x, axis_world.y, axis_world.z, str(should), str(marked)]
			)
			if should != marked:
				failures.append(
					"%s 的 %s 应标记=%s 实际=%s（世界延伸轴 %.2f,%.2f）"
					% [corner_id, body.name, str(should), str(marked), axis_world.x, axis_world.z]
				)
