extends Node
## 视觉取证探针：2026-09-21 天台装饰二次修正的 4 个验收点。
## ① 落地花草（花箱/盆栽/藤蔓基座）不再悬空 —— 平视掠过花箱底边看它是否贴地；
## ② 墙面藤蔓高低错落（基座 + 叠高件）；
## ③ 女儿墙挂藤（业主新增组件）贴在栏杆中心线上；
## ④ 基地东门净空（藤蔓/盆栽已北移，门前留出通行区）。
## 三次修正（2026-09-21）追加 5 机位：⑤ 立管接到地板（南/西两处侧视）+ 从上方基本看不到（俯视）；
## ⑥ 墙挂空调 90° 倾倒后风扇朝外（南/东两墙正视图）。
## 只读，不做任何修改。必须「不带 --headless」运行。

const OUT_DIR := "res://_scratch/rooftop/decor_fix_shots"

# 机位（Godot 世界平面：x=+东、z=+南、y=上）。
# 天台地面 y=0，房屋壳体 30×30 同心于 (0,5)，东墙门洞世界 gz≈-2.5。
const SHOTS := [
	# name, from, to
	# 南侧花圃 gz=+22.15（壳体南墙 gz=20，花圃在墙外 2.15m）⇒ 机位必须站在花圃更南侧。
	["01_ground_flowerbox_south", Vector3(-1.0, 1.6, 32.0), Vector3(-1.0, 0.6, 22.15)],
	# 东侧大盆栽 x=+17.0 / gz=−6.2（壳体东墙 x=15）⇒ 机位在盆栽更东侧。
	["02_ground_plant_east", Vector3(24.5, 1.8, -6.2), Vector3(17.0, 1.1, -6.2)],
	# 东墙藤蔓 x=15.22，g z∈{−11,−3,8.5} + 上层叠高（顶高 7.4m）⇒ 拉开距离看整段竖高。
	["03_ivy_east_wall_stagger", Vector3(31.0, 6.0, 8.5), Vector3(15.2, 3.4, 6.0)],
	# 南墙藤蔓 gz=20.22，基座 11 件 + 上层（顶高 5.8/7.0m）。
	["04_ivy_south_wall_stagger", Vector3(-3.0, 6.5, 32.0), Vector3(-3.0, 3.2, 20.2)],
	# 女儿墙挂藤：南线 gz=44.75。
	["05_parapet_ivy_south", Vector3(-5.0, 1.9, 38.0), Vector3(-5.0, 0.9, 44.75)],
	# 女儿墙挂藤：东线 x=39.75。
	["06_parapet_ivy_east", Vector3(33.5, 2.2, 10.0), Vector3(39.75, 0.9, 10.0)],
	# 基地东门净空：门洞世界 gz∈[−3.6,−1.4]，门前应无藤蔓/盆栽。（壳体外侧）
	["07_east_door_clearance", Vector3(28.0, 2.2, -2.5), Vector3(15.2, 1.3, -2.5)],
	["08_east_door_wide", Vector3(31.0, 5.5, 6.0), Vector3(15.4, 1.2, -4.0)],
	["09_decor_ring_overview", Vector3(-22.0, 12.0, 36.0), Vector3(2.0, 1.0, 4.0)],
	# —— 三次修正（2026-09-21）：立管落地 + 墙挂空调风扇朝外 ——
	# 南墙立管 x=-7.5 / x=2.5、gz=20.42（壳体南墙外皮 20.15 之外 0.27）：贴地侧视，看管底是否落承重面。
	["10_riser_south_grounded", Vector3(11.5, 5.6, 30.5), Vector3(2.5, 4.8, 20.42)],
	# 西墙立管 x=-15.42 / gz=+4.0：从西侧中位角看整根 0~9.89m 落地。
	["11_riser_west_grounded", Vector3(-23.5, 5.6, 11.5), Vector3(-15.42, 4.8, 4.0)],
	# 俯视南沿：业主「上面基本看不到」——从高处斜俯，立管应被 10.65 环管与支架遮住。
	["12_riser_topdown_south", Vector3(-2.5, 24.0, 27.0), Vector3(-2.5, 0.0, 20.42)],
	# 南墙墙挂空调 x=-5.0 / gz=20.10 / 高 6.38：与机位等高，从正南看风扇朝外（+Z）。
	["13_hvac_south_fan_out", Vector3(-5.0, 6.38, 25.5), Vector3(-5.0, 6.38, 20.1)],
	# 东墙墙挂空调 x=15.10 / gz=7.0：从正东看风扇朝外（+X）。
	["14_hvac_east_fan_out", Vector3(20.5, 6.08, 7.0), Vector3(15.1, 6.08, 7.0)],
]

# 夜景很暗，thin 的立管在实机光照下难以辨读 ⇒ 取证探针自加一盏跟随相机的
# 补光灯（只补光、不移动任何物体，故不影响几何判读）。
const SHOT_LIGHT_ENERGY := 3.2


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	if scene == null:
		print("DECOR_SHOT_FAIL: 场景加载失败")
		get_tree().quit(1)
		return
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 100990
	add_child(tower)
	for i in 10:
		await get_tree().process_frame
		await get_tree().physics_frame
	var player := tower.get("player") as Node3D
	if player != null:
		# 把玩家挪到天台（避开西侧楼梯口 x∈[-45,-30]、z∈[0,30]），否则流送会把天台隐藏。
		player.global_position = Vector3(-22.0, 1.0, 5.0)
		print("DECOR_SHOT player moved to %s" % str(player.global_position))
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

	var light := DirectionalLight3D.new()
	light.name = "ProbeKeyLight"
	light.light_energy = SHOT_LIGHT_ENERGY
	light.shadow_enabled = false
	add_child(light)

	for shot in SHOTS:
		await _shoot(camera, light, str(shot[0]), shot[1], shot[2])

	print("DECOR_SHOT_DONE")
	get_tree().quit(0)


func _shoot(camera: Camera3D, light: DirectionalLight3D, shot_name: String, from: Vector3, to: Vector3) -> void:
	camera.global_position = from
	camera.look_at(to, Vector3.UP)
	# 补光灯与相机同向（DirectionalLight3D 沿自身 −Z 照射），保证每个机位都被照亮。
	light.global_position = from + Vector3(0.0, 3.0, 0.0)
	light.look_at(to, Vector3.UP)
	for i in 12:
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, shot_name]
	var error := image.save_png(path)
	print("DECOR_SHOT %-28s from=%s err=%d" % [shot_name, str(from), error])
