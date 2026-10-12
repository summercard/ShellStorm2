extends Node3D
## 入口安全房退出门 EXIT 标牌的**视觉**采样（真渲染器，非 headless）。
##
## 回答「平铺 0.09m 的标牌在真实光照下到底能不能看清、位置对不对」：
## 现场建一间 15×15 双门安全房，把相机架在房间内看向东侧（退出门）地面。
##
## 手跑（不要加 --headless）：
##   godot --path . --scene res://tests/verification/probe_safe_room_exit_sign_visual.tscn
## 产物：I:/工作项目/shellstrom2/ShellStorm2-work/scratch/exit_neon_sign/visual/*.png

const OUTPUT_DIR := "I:/工作项目/shellstrom2/ShellStorm2-work/scratch/exit_neon_sign/visual"

var _camera: Camera3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	_build_stage()
	await _run()
	get_tree().quit(0)


func _build_stage() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.03, 0.035, 0.045)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.9, 0.94, 1.0)
	environment.ambient_light_energy = 0.55
	world_environment.environment = environment
	add_child(world_environment)

	_camera = Camera3D.new()
	_camera.fov = 65.0
	add_child(_camera)
	_camera.current = true


func _run() -> void:
	var room := DungeonRoom3D.new()
	room.configure({
		"room_id": "probe_exit_sign_visual",
		"room_type": "STAIR_LOBBY",
		"size_class": "tower_cell",
		"doors": ["north", "east"],
		"door_targets": {"north": "probe_a", "east": ""},
		"seed": 4242,
		"custom_dimensions": Vector2(15.0, 15.0),
		"tower_module_shell": true,
	})
	add_child(room)
	room.ensure_shell_built()
	room.ensure_detail_built()
	await _settle(20)

	var sign_node := room.get_node_or_null("SafeRoomExitSign") as Node3D
	if sign_node == null:
		push_error("PROBE_VISUAL_FAIL: 找不到 SafeRoomExitSign")
		return
	var bounds := _world_bounds(sign_node)
	var focus := bounds.get_center()
	print("PROBE_VISUAL exit_sign bounds=%s center=%s" % [str(bounds.size), str(focus)])

	# 机位 1：房间内侧看向东门的斜俯视（模拟玩家在房内朝出口走）
	_camera.global_position = Vector3(focus.x - 6.2, 4.6, focus.z)
	_camera.look_at(Vector3(focus.x, 0.0, focus.z), Vector3.UP)
	await _shot("safe_room_exit_sign_approach.png")

	# 机位 2：正上方偏后俯视（看清 EXIT 字样与罗盘朝向）
	_camera.global_position = Vector3(focus.x - 2.2, 6.4, focus.z)
	_camera.look_at(Vector3(focus.x, 0.0, focus.z), Vector3.UP)
	await _shot("safe_room_exit_sign_topdown.png")

	room.queue_free()


func _settle(frames: int) -> void:
	for _i in range(frames):
		await get_tree().process_frame


func _shot(file_name: String) -> void:
	await _settle(6)
	var image := get_viewport().get_texture().get_image()
	var out_path := "%s/%s" % [OUTPUT_DIR, file_name]
	if image == null or image.is_empty() or image.save_png(out_path) != OK:
		push_error("PROBE_VISUAL_FAIL: cannot save %s" % out_path)
		return
	print("PROBE_VISUAL saved %s  size=%s" % [out_path, str(image.get_size())])


func _world_bounds(root: Node3D) -> AABB:
	var bounds := AABB()
	var started := false
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var world: AABB = mesh_instance.global_transform * mesh_instance.get_aabb()
		if not started:
			bounds = world
			started = true
		else:
			bounds = bounds.merge(world)
	if not started:
		bounds = AABB(root.global_position, Vector3.ONE)
	return bounds
