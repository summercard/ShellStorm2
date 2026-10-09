extends Node
## 视觉取证探针：加载完整塔楼，确认两套鸟群在新摆位上的实际可见性。
## ① 100F 天台北侧（吊桥出口）往北看：应当看到吊桥离台 + 东面天台的落地鸟群。
## ② 落地鸟群近景。
## ③ 吊桥中段侧视：应当看到飞行鸟群。
## 只读，不做任何修改。必须「不带 --headless」运行。

const OUT_DIR := "res://_scratch/bird_flocks_import/shots"
const FLYBY := "res://assets/art/vfx/environment_3d/bird_flocks/runtime/flyby/vfx_env_birds_flyby_root_top3d.tscn"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	if scene == null:
		print("SHOT_FAIL scene load")
		get_tree().quit(1)
		return
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	for i in 10:
		await get_tree().process_frame
		await get_tree().physics_frame
	var player := tower.get("player") as Node3D
	if player != null:
		# 放到天台北侧、吊桥出口附近，避免流送隐藏天台层。
		player.global_position = Vector3(20.0, 1.0, -18.0)
		print("SHOT player at %s" % str(player.global_position))
	for i in 20:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.6).timeout

	# 现场重建一份飞行鸟群，确保取证时不处于 12 秒后的自毁窗口。
	var flyby := (load(FLYBY) as PackedScene).instantiate() as Node3D
	add_child(flyby)
	flyby.global_position = Vector3(18.0, 6.0, -93.0)
	flyby.rotation = Vector3(0.0, 0.26, 0.0)
	flyby.set_meta("shot_copy", true)

	var stage := _find_stage(tower)
	if stage != null:
		var ground := stage.get_node_or_null("RooftopGroundBirdFlock") as Node3D
		print("SHOT ground_flock=%s pos=%s" % [str(ground != null), str(ground.position) if ground != null else "n/a"])

	var camera := Camera3D.new()
	camera.name = "ProbeCamera"
	camera.fov = 70.0
	camera.far = 800.0
	add_child(camera)
	camera.make_current()

	await _shoot(camera, "01_rooftop_north_toward_bridge", Vector3(20.0, 4.0, -12.0), Vector3(20.0, 0.0, -70.0))
	await _shoot(camera, "02_ground_flock_closeup", Vector3(34.0, 2.4, -20.0), Vector3(27.0, 0.4, -27.0))
	await _shoot(camera, "03_ground_flock_wide", Vector3(38.0, 10.0, -6.0), Vector3(24.0, 0.0, -32.0))
	await _shoot(camera, "04_flyby_bridge_side", Vector3(46.0, 8.0, -74.0), Vector3(18.0, 5.0, -95.0))
	await _shoot(camera, "05_flyby_bridge_behind", Vector3(18.0, 7.0, -60.0), Vector3(18.0, 5.0, -100.0))
	await _shoot(camera, "06_flyby_closeup", Vector3(30.0, 8.5, -86.0), Vector3(18.0, 6.0, -93.0))

	print("SHOT_DONE")
	get_tree().quit(0)


func _find_stage(tower: Node) -> Node:
	for node in tower.find_children("*", "Node3D", true, false):
		var script: Script = node.get_script()
		if script != null and str(script.resource_path).ends_with("TowerFloorStage3D.gd"):
			if int(node.get("floor_index")) == 0:
				return node
	return null


func _shoot(camera: Camera3D, name: String, from: Vector3, to: Vector3) -> void:
	camera.global_position = from
	camera.look_at(to, Vector3.UP)
	for i in 12:
		await get_tree().process_frame
	await get_tree().create_timer(0.35).timeout
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	var error := image.save_png(path)
	print("SHOT %-34s from=%s err=%d" % [name, str(from), error])
