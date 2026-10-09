extends Node
## 视觉取证（100F 天台 / 停留鸟群）。只装配 TowerFloorStage3D，不起整座塔。
## 必须「不带 --headless」运行。

const OUT_DIR := "res://_scratch/bird_flocks_import/shots"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_add_environment()
	var stage := TowerFloorStage3D.new()
	stage.configure(0, "rooftop", ["west"], [], false, Rect2())
	add_child(stage)
	for i in 10:
		await get_tree().process_frame
	var birds := stage.get_node_or_null("RooftopGroundBirdFlock") as Node3D
	if birds == null:
		print("GROUND_FLOCK_MISSING")
		get_tree().quit(1)
		return
	print("GROUND_FLOCK local=%s global=%s visible=%s" % [str(birds.position), str(birds.global_position), str(birds.is_visible_in_tree())])
	# 推进到「已落地停留」窗口（源动画 t≈6s，动作控制 x≈-1.65 / z≈+0.48）。
	await get_tree().create_timer(6.0).timeout

	var camera := Camera3D.new()
	camera.name = "ProbeCamera"
	camera.fov = 70.0
	camera.far = 2000.0
	add_child(camera)
	camera.make_current()

	# ① 站在桥口(x=20)东侧朝西看：应看到鸟群停在东面天台上。
	await _shoot(camera, "D01_from_bridge_gap_looking_east", Vector3(14.0, 1.8, -30.0), Vector3(26.0, 0.4, -31.0))
	# ② 站在鸟群南侧俯视：确认贴地、不悬空。
	await _shoot(camera, "D02_from_south_above", Vector3(25.0, 3.4, -20.0), Vector3(25.0, 0.2, -31.0))
	# ③ 斜上方全景：东面天台 + 北沿 + 鸟群 + 吊桥头。
	await _shoot(camera, "D03_oblique_wide", Vector3(46.0, 9.0, -8.0), Vector3(24.0, 0.0, -31.0))
	# ④ 贴地近景：鸟的脚与地砖的关系。
	await _shoot(camera, "D04_ground_level_closeup", Vector3(28.0, 0.6, -25.0), Vector3(23.6, 0.2, -30.4))
	# ⑤ 从天台北沿回望（模拟从吊桥走回来的第一眼）。
	await _shoot(camera, "D05_from_north_walkback", Vector3(25.0, 1.8, -38.0), Vector3(25.0, 0.4, -30.0))
	# ⑥ 鸟群起飞瞬间（t≈20s，应越北女儿墙飞向城市）。
	await get_tree().create_timer(14.0).timeout
	await _shoot(camera, "D06_takeoff_over_parapet", Vector3(28.0, 2.4, -24.0), Vector3(31.0, 4.5, -33.0))

	print("SHOT_DONE")
	get_tree().quit(0)


func _add_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.30, 0.36, 0.44)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.78, 0.86)
	env.ambient_light_energy = 1.6
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	sun.light_energy = 1.5
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
	print("SHOT %-34s from=%s err=%d" % [name, str(from), error])
