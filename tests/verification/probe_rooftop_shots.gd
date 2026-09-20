extends Node
## 视觉取证探针：加载完整塔楼，用自建相机拍三张照片，回答
## ① 天台西侧女儿墙缺口现在长什么样 ② 站在天台边缘往外看，下方是什么 ③ 塔楼外部体量。
## 只读，不做任何修改。必须「不带 --headless」运行。

const OUT_DIR := "res://_scratch/rooftop/shots"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	if scene == null:
		print("SHOT_FAIL: 场景加载失败")
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
		# 把玩家挪到天台，避免流送把天台层隐藏掉。
		player.global_position = Vector3(-30.0, 1.0, 15.0)
		print("SHOT player moved to %s" % str(player.global_position))
	for i in 20:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.8).timeout

	var camera := Camera3D.new()
	camera.name = "ProbeCamera"
	camera.fov = 70.0
	camera.far = 800.0
	add_child(camera)
	camera.make_current()

	await _shoot(camera, "01_west_gap_indoor", Vector3(-30.0, 6.0, 15.0), Vector3(-49.0, 2.0, 15.0))
	# 站在天台西侧边缘往下看：相机必须**高于女儿墙顶**，否则视线被女儿墙内壁挡住，
	# 拍出来只是「一堵墙」，看不到墙外下方的立面。女儿墙 2026-09-20 起改为含压顶
	# 总高 0.80m（见 TowerFloorStage3D.ROOFTOP_PARAPET_HEIGHT），本机位 y=8 时视线
	# 与 x=-49.75 相交处约 4.3m，仍明显越过墙顶；改矮后只会看得更多，无需回调机位。
	await _shoot(camera, "02_edge_look_down", Vector3(-45.0, 8.0, 15.0), Vector3(-68.0, -10.0, 15.0))
	await _shoot(camera, "03_tower_exterior", Vector3(-165.0, 45.0, 15.0), Vector3(0.0, 6.0, 5.0))
	await _shoot(camera, "04_rooftop_overview", Vector3(-30.0, 22.0, 45.0), Vector3(0.0, 0.0, 5.0))
	# 从塔楼外侧看西面：应当同时看到「顶上的女儿墙」+「其下 12m 的外立面墙」，
	# 这是「天台边缘往下不再是空的」最直接的一张图。
	await _shoot(camera, "05_facade_west_outside", Vector3(-64.0, 6.0, 15.0), Vector3(-50.0, -6.0, 15.0))
	# 西北角斜视：看女儿墙与立面环在角上是否接得上、有没有竖缝。
	await _shoot(camera, "06_nw_corner_oblique", Vector3(-74.0, 14.0, -46.0), Vector3(-46.0, -3.0, 6.0))
	# 整圈立面环俯瞰：确认四边都围起来了。
	await _shoot(camera, "07_facade_ring_oblique", Vector3(-108.0, 30.0, 92.0), Vector3(0.0, -6.0, 0.0))
	# 近距离看女儿墙「正面」：远景图在本场景重雾下几乎看不清墙板细节，判断
	# 「是否还是密集竖杠 / 有没有横杆压边」必须用近距机位（雾按距离累积）。
	# 站到离西墙内壁 ~4m、相机略高于墙顶，正对墙板立面拍。
	await _shoot(camera, "08_parapet_close_front", Vector3(-45.2, 0.95, 15.0), Vector3(-49.5, 0.45, 15.0))
	# 西北角近距斜视：竖直构件最容易在「直段与直段接缝」处露丑，专门盯这条缝。
	await _shoot(camera, "09_parapet_close_corner", Vector3(-40.0, 2.6, -31.0), Vector3(-49.6, 0.4, -37.5))

	print("SHOT_DONE")
	get_tree().quit(0)


func _shoot(camera: Camera3D, name: String, from: Vector3, to: Vector3) -> void:
	camera.global_position = from
	camera.look_at(to, Vector3.UP)
	for i in 12:
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	var error := image.save_png(path)
	print("SHOT %-22s from=%s err=%d" % [name, str(from), error])
