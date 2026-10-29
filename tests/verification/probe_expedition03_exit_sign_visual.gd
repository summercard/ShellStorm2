extends Node3D
## 真实渲染采样：**远征03 入口安全屋**（程序化壳体路径）退出门内侧的 EXIT 灯牌。
##
## 为什么单独一条：远征03 走 EGT flow，入口房没有静态美术 TSCN，
## 墙体程序化生成 —— 与远征01/02 的静态布局是两条不同的建壳路径，
## 标牌漏摆过一次（2026-10-29 业主报单），证据要能复现。
##
## 手跑（不要加 --headless）：
##   godot --path . --resolution 1280x720 \
##         --scene res://tests/verification/probe_expedition03_exit_sign_visual.tscn
## 产物：outputs/expedition03_exit_sign/*.png
##
## 机位 1 = 业主同种子（1590629068）的俯视构图，用于和业主截图对照；
## 机位 2 / 3 = 走近与贴近，看牌面是否平行门洞、是否贴地。

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel03_3D.tscn"
const OWNER_RUN_SEED := 1590629068
const SIGN_NODE_NAME := "SafeRoomExitSign"
const OUTPUT_DIR := "res://outputs/expedition03_exit_sign"

var _camera: Camera3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
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
		push_error("PROBE_VISUAL_FAIL: 远征03 场景加载失败")
		return
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = OWNER_RUN_SEED
	add_child(tower)
	await _settle(60)

	var start_room := tower._room_by_id.get("start") as DungeonRoom3D
	if start_room == null:
		push_error("PROBE_VISUAL_FAIL: 找不到入口房 start")
		return
	var retreat_side := str(start_room.call("_safe_room_retreat_direction"))
	var sign_node := start_room.get_node_or_null(SIGN_NODE_NAME) as Node3D
	var door := start_room.get_door_node(retreat_side) as Node3D
	print("PROBE_VISUAL retreat=%s sign=%s door=%s" % [
		retreat_side, str(sign_node != null), str(door != null)])
	if sign_node == null:
		push_error("PROBE_VISUAL_FAIL: 入口房没有 SafeRoomExitSign")
		return

	var bounds := _world_bounds(sign_node)
	var focus := bounds.get_center()
	print("PROBE_VISUAL sign bounds=%s center=%s" % [str(bounds.size), str(focus)])

	# 机位 1：业主截图同构图 —— 房间中心上方 10m、俯角约 −60°，朝退出门方向。
	var normal := start_room.call("_direction_normal", retreat_side) as Vector3
	var room_center := start_room.global_position
	_set_camera_pose(
		room_center - normal * 6.0 + Vector3(0.0, 10.0, 0.0),
		room_center + normal * 3.0
	)
	await _shot("expedition03_exit_sign_owner_view.png")

	# 机位 2：从房内斜俯视退出门（模拟玩家走过去看到的画面）
	_set_camera_pose(focus - normal * 4.2 + Vector3(0.0, 3.4, 0.0), Vector3(focus.x, 0.0, focus.z))
	await _shot("expedition03_exit_sign_approach.png")

	# 机位 3：贴近标牌，看清 EXIT 字样与它相对门洞的朝向
	_set_camera_pose(focus - normal * 1.3 + Vector3(0.0, 1.9, -0.3), Vector3(focus.x, 0.0, focus.z))
	await _shot("expedition03_exit_sign_closeup.png")

	tower.queue_free()


func _settle(frames: int) -> void:
	for _i in range(frames):
		await get_tree().process_frame


func _set_camera_pose(position: Vector3, look_target: Vector3) -> void:
	_camera.global_position = position
	_camera.look_at(look_target, Vector3.UP)
	# 必须夺回 current：`TowerDescent3D` 会自建 gameplay 相机并在入树后设为 current，
	# 不夺权的话两张机位会拍成同一张（2026-10-12 远征01 那条探针踩过）。
	for node in get_tree().root.find_children("*", "Camera3D", true, false):
		var other := node as Camera3D
		if other != null and other != _camera:
			other.current = false
	_camera.current = true


func _shot(file_name: String) -> void:
	await _settle(10)
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
