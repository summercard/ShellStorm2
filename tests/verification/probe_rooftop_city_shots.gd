extends Node
## 视觉取证探针：远景城市「旧的两圈极坐标」vs「新的贴轮廓环带」同一机位并排拍。
## 只读生产代码：旧摆法在本文件里按原样复刻一份（不改 `TowerAtmosphere3D.gd`），
## 这样一次运行就能拿到真 A/B；新摆法直接读生产节点。
## **必须「不带 --headless」运行**（headless 没有渲染目标，截图恒失败）。

const OUT_DIR := "res://_scratch/rooftop_city/shots"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	if scene == null:
		print("CITY_SHOT_FAIL: 场景加载失败")
		get_tree().quit(1)
		return
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	for _i in 10:
		await get_tree().process_frame
		await get_tree().physics_frame
	var player := tower.get("player") as Node3D
	if player != null:
		player.global_position = Vector3(-30.0, 1.0, 15.0)
		print("CITY_SHOT player -> %s" % str(player.global_position))
	for _i in 20:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.8).timeout

	var atmosphere := tower.get_node_or_null("TowerAtmosphere3D")
	if atmosphere == null:
		print("CITY_SHOT_FAIL: 没有 TowerAtmosphere3D")
		get_tree().quit(1)
		return
	# ⚠️ 必须显式把大气层抬到 100F：`_city_root.visible = floor_number >= 100`，
	# 而塔楼开场停在 99F（`_install_atmosphere` 时 _current_floor_number() == 99）
	# ⇒ 只挪玩家不报楼层号的话，城市整圈是隐藏的，怎么拍都是空的。
	atmosphere.call("set_floor_number", 100)
	await get_tree().process_frame
	var city_root := atmosphere.get_node_or_null("RooftopCityBelow") as Node3D
	var production := city_root.get_node_or_null("CityBuildingSilhouettes") as MultiMeshInstance3D
	if city_root == null or production == null:
		print("CITY_SHOT_FAIL: 没有 RooftopCityBelow/CityBuildingSilhouettes")
		get_tree().quit(1)
		return
	_report_aabb("new_band", production)
	var material: Material = (production.multimesh.mesh as PrimitiveMesh).material
	var snapshot: Dictionary = atmosphere.call("get_snapshot")
	print(
		"CITY_SHOT diag city_root.visible=%s city.is_visible_in_tree=%s snapshot.city_visible=%s floor=%s"
		% [
			city_root.visible,
			production.is_visible_in_tree(),
			snapshot.get("city_visible"),
			snapshot.get("floor_number"),
		]
	)
	print("CITY_SHOT diag aabb=%s visibility_range_end=%.1f" % [str(production.get_aabb()), production.visibility_range_end])

	# 本文件里复刻的旧摆法（两圈极坐标，半径 145 / 203，顶面一律 -20）
	var legacy := _build_legacy_city(city_root, material)
	legacy.visible = false
	_report_aabb("legacy_rings", legacy)

	var camera := Camera3D.new()
	camera.name = "CityProbeCamera"
	camera.fov = 70.0
	camera.far = 900.0
	add_child(camera)
	camera.make_current()
	await get_tree().process_frame

	# 机位说明（都踩过坑）：
	#  · 视线必须**从女儿墙正上方掠过**，且**俯角要够陡**。站在墙内侧 5m、俯角只有
	#    ~10° 时，15m 外、20m 下方的楼顶被女儿墙整块挡住；即便贴到墙边，若只瞄 44°
	#    俯角，最近那圈楼（在 66~84° 下方）仍会从视野下方漏掉。
	#  · 距离雾密度 0.030 ⇒ 20m 处已有 45% 雾、100m 处 95% ⇒ 只有最近一环能读出剪影，
	#    外两环基本融进雾里（这是全局观感口径，不是摆位问题）。
	var fog_shots := [
		["01_edge_steep_down", Vector3(-49.8, 1.6, 5.0), Vector3(-70.0, -46.0, 5.0), Vector3.UP],
		["02_edge_mid_down", Vector3(-49.8, 1.6, 5.0), Vector3(-95.0, -55.0, 5.0), Vector3.UP],
		["05_outside_se", Vector3(215.0, 95.0, 205.0), Vector3(-10.0, -30.0, 5.0), Vector3.UP],
	]
	var layout_shots := [
		["03_above_roof_down", Vector3(-15.0, 48.0, 58.0), Vector3(-28.0, -42.0, -6.0), Vector3.UP],
		["04_high_oblique_nw", Vector3(-150.0, 120.0, -140.0), Vector3(0.0, -45.0, 5.0), Vector3.UP],
		["06_topdown_layout", Vector3(0.0, 120.0, 5.0), Vector3(0.0, 0.0, 5.0), Vector3(0.0, 0.0, -1.0)],
		# 决定性机位：贴到最近一环西侧楼体的正上方 20m，正对楼体俯视。
		# 若这一张还是空的，说明 MultiMesh 根本没渲染，问题不在机位。
		["07_close_near_west", Vector3(-78.0, 22.0, 5.0), Vector3(-78.0, -45.0, 5.0), Vector3(0.0, 0.0, -1.0)],
		["08_close_side_west", Vector3(-120.0, -10.0, 5.0), Vector3(-74.0, -45.0, 5.0), Vector3.UP],
	]
	var environment := _find_environment(tower)
	for kind in ["legacy", "new"]:
		production.visible = kind == "new"
		legacy.visible = kind == "legacy"
		if environment != null:
			environment.fog_enabled = true
		await get_tree().process_frame
		for shot in fog_shots:
			await _shoot(camera, "%s_%s" % [kind, shot[0]], shot[1], shot[2], shot[3])
		if environment != null:
			environment.fog_enabled = false
		for shot in layout_shots:
			await _shoot(camera, "%s_%s" % [kind, shot[0]], shot[1], shot[2], shot[3])

	print("CITY_SHOT_DONE")
	get_tree().quit(0)


func _find_environment(root: Node) -> Environment:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var world := node as WorldEnvironment
		if world != null and world.environment != null:
			return world.environment
		for child in node.get_children():
			stack.append(child)
	return null


## 旧摆法（2026-09-22 之前的 `_build_city_silhouette` 逐值复刻）。
func _build_legacy_city(parent: Node3D, material: Material) -> MultiMeshInstance3D:
	var building_mesh := BoxMesh.new()
	building_mesh.size = Vector3(1.0, 1.0, 1.0)
	building_mesh.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = building_mesh
	var transforms: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 990095
	for ring in range(2):
		var radius := 145.0 + float(ring) * 58.0
		var count := 40 + ring * 16
		for index in range(count):
			var angle := TAU * float(index) / float(count) + rng.randf_range(-0.035, 0.035)
			var width := rng.randf_range(12.0, 28.0)
			var depth := rng.randf_range(12.0, 28.0)
			var height := rng.randf_range(45.0, 150.0)
			var position := Vector3(cos(angle) * radius, -20.0 - height * 0.5, sin(angle) * radius)
			var basis := Basis.IDENTITY.scaled(Vector3(width, height, depth))
			transforms.append(Transform3D(basis, position))
	multimesh.instance_count = transforms.size()
	for index in range(transforms.size()):
		multimesh.set_instance_transform(index, transforms[index])
	var city := MultiMeshInstance3D.new()
	city.name = "LegacyCityBuildingSilhouettes"
	city.multimesh = multimesh
	city.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	city.visibility_range_end = 520.0
	parent.add_child(city)
	return city


## 摆位实测口径：到塔楼外墙矩形的最近距离（不看角部让位）。
func _report_aabb(tag: String, node: MultiMeshInstance3D) -> void:
	var multimesh := node.multimesh
	var rect := TowerFloorStage3D.TOWER_SHELL_WORLD_RECT
	var nearest := INF
	var farthest := -INF
	var highest := -INF
	var lowest := INF
	for index in range(multimesh.instance_count):
		var transform := multimesh.get_instance_transform(index)
		var nearest_point := Vector2(
			clampf(transform.origin.x, rect.position.x, rect.end.x),
			clampf(transform.origin.z, rect.position.y, rect.end.y)
		)
		var distance := Vector2(transform.origin.x, transform.origin.z).distance_to(nearest_point)
		nearest = minf(nearest, distance)
		farthest = maxf(farthest, distance)
		# 单件顶面：中心 Y + 半个高度（高度 = basis.y 的长度）
		var top := transform.origin.y + transform.basis.y.length() * 0.5
		highest = maxf(highest, top)
		lowest = minf(lowest, top)
	print(
		"CITY_SHOT %-14s count=%d 中心点到外墙最近=%.1f 最远=%.1f 顶面 Y=[%.1f, %.1f]"
		% [tag, multimesh.instance_count, nearest, farthest, lowest, highest]
	)


func _shoot(camera: Camera3D, shot_name: String, from: Vector3, to: Vector3, up: Vector3) -> void:
	camera.global_position = from
	camera.look_at(to, up)
	for _i in 10:
		await get_tree().process_frame
	await get_tree().create_timer(0.35).timeout
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, shot_name]
	var error := image.save_png(path)
	print("CITY_SHOT %-34s err=%d" % [shot_name, error])
