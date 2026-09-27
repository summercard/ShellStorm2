extends Node
## 探针：门位车道坐标 vs 门墙/门扇实际落位，并实拍办公室门位现场。

const EXPEDITION_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const RUN_SEED := 77001199
const OUT_DIR := "I:/ss2_iso/office_door"

var _camera: Camera3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var level := EXPEDITION_SCENE.instantiate() as TowerDescent3D
	level.test_mode = true
	level.run_seed_override = RUN_SEED
	add_child(level)
	await _frames(12)
	var room := _find_room("room_03")
	if room == null:
		print("!! 未找到 room_03")
		get_tree().quit(1)
		return
	print("room_03 尺寸=%s doors=%s" % [str(room.get_dimensions()), str(room.doors)])
	for side in ["north", "south", "east", "west"]:
		print("  车道偏移 %-6s = %.3f" % [side, float(room.get_meta("tower_wall_door_offset_%s" % side, 0.0))])
	var door_nodes := room.get("_door_nodes") as Dictionary
	for key in door_nodes:
		var door := door_nodes[key] as RoomDoor3D
		if door == null:
			continue
		print(
			"  门 %-6s 局部=(%.2f, %.2f, %.2f) rot=%6.1f° 世界=(%.2f, %.2f, %.2f)"
			% [
				str(key),
				door.position.x,
				door.position.y,
				door.position.z,
				rad_to_deg(door.rotation.y),
				door.global_position.x,
				door.global_position.y,
				door.global_position.z,
			]
		)
	_setup_camera()
	for key in door_nodes:
		var door := door_nodes[key] as RoomDoor3D
		if door == null:
			continue
		await _shoot(str(key), door, false)
		room.set_door_open(str(key), true, false)
		await _frames(30)
		await _shoot(str(key), door, true)
		room.set_door_open(str(key), false, true)
		await _frames(4)
	print("PROBE_DOOR_LAYOUT_DONE")
	get_tree().quit(0)


func _setup_camera() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.04, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.22, 0.25, 0.3)
	env.ambient_light_energy = 0.35
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30.0, 20.0, 0.0)
	sun.light_energy = 1.4
	add_child(sun)
	_camera = Camera3D.new()
	_camera.fov = 65.0
	add_child(_camera)


func _shoot(tag: String, door: RoomDoor3D, opened: bool) -> void:
	# 站在房间内侧、与门同侧沿墙处，朝门看。
	var inward := -door.global_transform.basis.z
	if absf(door.rotation.y) > 0.1:
		inward = door.global_transform.basis.x
	var back := door.global_position + inward.normalized() * 7.0
	_camera.position = Vector3(back.x, 1.7, back.z)
	_camera.look_at(Vector3(door.global_position.x, 1.6, door.global_position.z), Vector3.UP)
	_camera.make_current()
	for _i in range(3):
		await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null:
		print("   !! 截图失败 %s" % tag)
		return
	var path := "%s/门位_%s_%s.png" % [OUT_DIR, tag, "开" if opened else "关"]
	image.save_png(path)
	print("   截图 %s" % path)


func _find_room(room_id: String) -> DungeonRoom3D:
	for value in get_tree().get_nodes_in_group("dungeon_room_3d"):
		var room := value as DungeonRoom3D
		if room != null and room.authored_layout_room_id == room_id:
			return room
	return null


func _frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame
