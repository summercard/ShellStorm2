extends Node
## 视觉取证（跨塔吊桥 / 飞行鸟群）。直接实例化 open_world 外部场景，鸟群用它自己的
## 挂载节点，不另造副本。必须「不带 --headless」运行。

const OUT_DIR := "res://_scratch/bird_flocks_import/shots"
const ROUTE := "res://assets/art/environments/open_world/runtime/cross_tower_route/env_cross_tower_route_root_top3d.tscn"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_add_environment()
	var route := (load(ROUTE) as PackedScene).instantiate() as Node3D
	add_child(route)
	for i in 5:
		await get_tree().process_frame
	var birds := route.get_node_or_null("FlybyBirdFlock") as Node3D
	if birds == null:
		print("FLYBY_NODE_MISSING")
		get_tree().quit(1)
		return
	print("FLYBY local=%s global=%s visible=%s" % [str(birds.position), str(birds.global_position), str(birds.is_visible_in_tree())])
	# 推进到动画中段（队伍已散开、最容易被看见）。
	await get_tree().create_timer(5.0).timeout
	_dump_birds(birds)

	var camera := Camera3D.new()
	camera.name = "ProbeCamera"
	camera.fov = 70.0
	camera.far = 2000.0
	add_child(camera)
	camera.make_current()

	# ① 桥面中线、沿桥走向看：鸟群应正横越前方。
	await _shoot(camera, "C01_along_bridge_deck", Vector3(20.0, 3.0, -40.0), Vector3(20.0, 4.5, -70.0))
	# ② 略低机位贴近栏杆：验证鸟群高于栏杆顶。
	await _shoot(camera, "C02_above_rail_check", Vector3(20.0, 2.6, -44.0), Vector3(20.0, 4.4, -66.0))
	# ③ 塔2屋顶外侧斜视（「塔2上方」最直观的一张）。
	await _shoot(camera, "C03_tower2_roof_oblique", Vector3(52.0, 16.0, -46.0), Vector3(18.0, 4.0, -66.0))
	# ④ 高空俯瞰：塔2 + 吊桥 + 鸟群三者关系。
	await _shoot(camera, "C04_overview_high", Vector3(58.0, 46.0, -22.0), Vector3(20.0, 0.0, -70.0))
	# ⑤ 近距特写：确认 7 只鸟都在动（不是只有一只）。
	await _shoot(camera, "C05_flock_closeup", Vector3(20.0, 4.5, -52.0), Vector3(20.0, 4.3, -64.0))
	# ⑥ 侧后视角。
	await _shoot(camera, "C06_side_behind", Vector3(40.0, 8.0, -70.0), Vector3(18.0, 4.2, -64.0))

	print("SHOT_DONE")
	get_tree().quit(0)


func _dump_birds(host: Node3D) -> void:
	var skeleton := host.find_child("鸟群_整体移动缩放控制", true, false) as Node3D
	if skeleton == null:
		print("FLYBY_SKELETON_MISSING")
		return
	for child in skeleton.get_children():
		var bird := child as Node3D
		if bird != null:
			print("  FLYBY_BIRD %s world=%s" % [bird.name, str(bird.global_position)])


func _add_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.34, 0.42, 0.52)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.74, 0.80, 0.88)
	env.ambient_light_energy = 1.7
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	sun.light_energy = 1.6
	add_child(sun)


func _shoot(camera: Camera3D, name: String, from: Vector3, to: Vector3) -> void:
	camera.global_position = from
	camera.look_at(to, Vector3.UP)
	for i in 10:
		await get_tree().process_frame
	await get_tree().create_timer(0.25).timeout
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	var error := image.save_png(path)
	print("SHOT %-30s from=%s err=%d" % [name, str(from), error])
