extends Node3D
## 真实渲染采样：**远征01 入口安全房**（静态布局路径）的 EXIT 出口提示牌。
##
## 手跑（不要加 --headless）：
##   godot --path . --resolution 1280x720 \
##         --scene res://tests/verification/probe_expedition_start_exit_sign_visual.tscn
## 产物：ShellStorm2-work/scratch/exit_neon_sign/visual/*.png

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const RUN_SEED := 77001199
const SIGN_NODE_NAME := "SafeRoomExitSign"
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
	var scene := load(EXPEDITION_SCENE) as PackedScene
	if scene == null:
		push_error("PROBE_VISUAL_FAIL: 远征场景加载失败")
		return
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	await _settle(30)

	var start_room := tower._room_by_id.get("start") as DungeonRoom3D
	if start_room == null:
		push_error("PROBE_VISUAL_FAIL: 找不到入口房 start")
		return
	var sign_node := start_room.get_node_or_null(SIGN_NODE_NAME) as Node3D
	if sign_node == null:
		push_error("PROBE_VISUAL_FAIL: 入口房没有 SafeRoomExitSign")
		return

	var bounds := _world_bounds(sign_node)
	var focus := bounds.get_center()
	print("PROBE_VISUAL sign bounds=%s center=%s" % [str(bounds.size), str(focus)])
	print("PROBE_VISUAL sign direction=%s" % start_room.call("_safe_room_retreat_direction"))

	# 机位 1：从房内朝退出门斜俯视（模拟玩家走过去看到的画面）
	_set_camera_pose(focus + Vector3(-5.6, 4.2, 0.0), Vector3(focus.x, 0.0, focus.z))
	await _shot("expedition_start_exit_sign_approach.png")

	# 机位 2：贴到标牌上方，看清 EXIT 字样与它相对门洞的朝向
	_set_camera_pose(focus + Vector3(-1.45, 2.05, -0.35), Vector3(focus.x + 0.35, 0.0, focus.z))
	await _shot("expedition_start_exit_sign_closeup.png")

	tower.queue_free()


func _settle(frames: int) -> void:
	for _i in range(frames):
		await get_tree().process_frame


func _set_camera_pose(position: Vector3, look_target: Vector3) -> void:
	_camera.global_position = position
	_camera.look_at(look_target, Vector3.UP)
	# 🔴 必须**夺回** current：`TowerDescent3D` 会自建 gameplay 相机并在入树后把自己设为
	# current ⇒ 本探针的相机被顶掉，两张机位会拍成同一张（实测踩过：approach 与 topdown
	# 逐像素雷同）。这里在每次拍摄前把全场其它 Camera3D 取消 current 再认领自己。
	for node in get_tree().root.find_children("*", "Camera3D", true, false):
		var other := node as Camera3D
		if other != null and other != _camera:
			other.current = false
	_camera.current = true


func _shot(file_name: String) -> void:
	await _settle(8)
	var image := get_viewport().get_texture().get_image()
	var out_path := "%s/%s" % [OUTPUT_DIR, file_name]
	if image == null or image.is_empty() or image.save_png(out_path) != OK:
		push_error("PROBE_VISUAL_FAIL: cannot save %s" % out_path)
		return
	print("PROBE_VISUAL saved %s size=%s" % [out_path, str(image.get_size())])


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
