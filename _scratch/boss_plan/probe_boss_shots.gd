extends Node
## Boss 房（v008）实拍：门位、墙壁封闭、地板与机柜受光。

const OUT_DIR := "I:/ss2_iso/boss_room"
const RUN_SEED := 77001199

var _camera: Camera3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var scene := load("res://scenes/ExpeditionLevel01_3D.tscn") as PackedScene
	var level := scene.instantiate()
	level.set("test_mode", true)
	level.set("run_seed_override", RUN_SEED)
	add_child(level)
	for _i in range(12):
		await get_tree().process_frame
		await get_tree().physics_frame
	var hud := level.get_node_or_null("HUD")
	if hud != null:
		(hud as CanvasLayer).visible = false
	_setup()
	var room := _find_room("boss")
	if room == null:
		print("!! 未找到 boss")
		get_tree().quit(1)
		return
	print("boss 尺寸=%s doors=%s 形心=%s" % [str(room.get_dimensions()), str(room.doors), str(room.global_position)])
	# ① 站在房间中央偏西，朝东门看
	await _shot(room.global_position + Vector3(-14.0, 1.9, -2.5), Vector3(20.0, 1.6, -2.5), "01_朝东门")
	# ② 站在房间中央，朝北看主屏与机柜
	await _shot(room.global_position + Vector3(0.0, 2.2, 12.0), Vector3(0.0, 2.6, -8.0), "02_朝主屏")
	# ③ 俯视全景
	await _shot(room.global_position + Vector3(-18.0, 26.0, 24.0), Vector3(2.0, 0.0, -2.0), "03_俯视")
	print("PROBE_BOSS_SHOTS_DONE")
	get_tree().quit(0)


func _setup() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.04, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.46, 0.55)
	env.ambient_light_energy = 0.55
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	_camera = Camera3D.new()
	_camera.fov = 78.0
	_camera.near = 0.05
	_camera.far = 400.0
	_camera.current = true
	add_child(_camera)
	for offset in [
		Vector3(-16.0, 9.0, 14.0),
		Vector3(16.0, 9.0, 14.0),
		Vector3(-16.0, 9.0, -14.0),
		Vector3(16.0, 9.0, -14.0),
	]:
		var lamp := OmniLight3D.new()
		lamp.omni_range = 46.0
		lamp.light_energy = 5.0
		lamp.shadow_enabled = false
		lamp.position = offset
		add_child(lamp)


func _find_room(room_id: String) -> DungeonRoom3D:
	for value in get_tree().get_nodes_in_group("dungeon_room_3d"):
		var room := value as DungeonRoom3D
		if room != null and room.authored_layout_room_id == room_id:
			return room
	return null


func _shot(from: Vector3, to: Vector3, tag: String) -> void:
	_camera.position = from
	_camera.look_at(to, Vector3.UP)
	for _i in range(3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("%s/%s.png" % [OUT_DIR, tag])
	print("   截图 %s" % tag)
