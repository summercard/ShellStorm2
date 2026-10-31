extends Node
## 地砖接缝实测：把三种地砖各按 5m 网格铺 2×2，出图 + 量实际接缝。
##
## ## 为什么要有这个探针
##
## 目录登记里 `manor_floor_stone` 的尺寸是 **5.0655 × 5.2845**，不是 5×5
## （木地板与黑白瓷砖精确 5.0000）。按 5m 网格铺装时，石地板每排**重叠 0.2845m**，
## 且两者顶面同高（0.1046 与 0.1000 相差 4.6mm），重叠区会 z-fighting 或
## 挤出可见棱线。这一条**任何现有验收都发现不了** —— 它们只核对元数据与节点名。
##
## 探测两件事：
##   1. 相邻地砖的世界包围盒是否真的重叠（数值）；
##   2. 重叠区在上方视角是否出现可见亮/暗带（出图人工确认）。
##
## 必须**不用 --headless** 运行：
##   godot --path . --scene res://tools/_exp03_floor_seam_probe.tscn

const MANOR := "res://assets/art/environments/tower_zones/expedition/runtime/common_components"
const OUT_DIR := "res://outputs/expedition03_floor_seam_20261031"
const GRID := 5.0

const FLOORS := [
	{"slug": "manor_floor_wood", "label": "wood"},
	{"slug": "manor_floor_stone", "label": "stone"},
	{"slug": "manor_floor_bath", "label": "bath"},
]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for spec in FLOORS:
		await _probe(str(spec["slug"]), str(spec["label"]))
	print("SEAM_ALL_DONE")
	get_tree().quit(0)


func _probe(slug: String, label: String) -> void:
	var stage := Node3D.new()
	add_child(stage)
	_setup_environment(stage)

	var prefab := "%s/%s/env_%s_root_top3d.tscn" % [MANOR, slug, slug]
	var packed := load(prefab) as PackedScene
	var boxes: Array[AABB] = []
	for row in range(2):
		for col in range(2):
			var node := packed.instantiate() as Node3D
			node.position = Vector3(float(col) * GRID, 0.0, float(row) * GRID)
			stage.add_child(node)
			boxes.append(_world_aabb(node))

	# 数值：相邻两块在 x 与 z 方向的重叠量
	var dx := (boxes[0].position.x + boxes[0].size.x) - boxes[1].position.x
	var dz := (boxes[0].position.z + boxes[0].size.z) - boxes[2].position.z
	print("SEAM %-8s footprint=(%.4f, %.4f) overlap_x=%.4f overlap_z=%.4f top_y=%.4f"
		% [label, boxes[0].size.x, boxes[0].size.z, dx, dz, boxes[0].position.y + boxes[0].size.y])

	var camera := Camera3D.new()
	camera.current = true
	stage.add_child(camera)
	# 顶视：接缝在正中间，最容易被看见
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = GRID * 2.4
	camera.position = Vector3(GRID * 0.5, 20.0, GRID * 0.5)
	camera.look_at(Vector3(GRID * 0.5, 0.0, GRID * 0.5), Vector3.FORWARD)
	await _capture("%s_2x2_top.png" % label)

	# 低角度掠视：重叠挤出棱线在掠射光下最明显
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 46.0
	camera.near = 0.02
	camera.far = 200.0
	camera.position = Vector3(GRID * 0.5, 0.30, GRID * 0.5 - 7.0)
	camera.look_at(Vector3(GRID * 0.5, 0.10, GRID * 0.5 + 2.0), Vector3.UP)
	await _capture("%s_2x2_grazing.png" % label)

	stage.queue_free()
	for _frame in 2:
		await get_tree().process_frame


func _world_aabb(root: Node3D) -> AABB:
	var box := AABB()
	var has := false
	for value in root.find_children("*", "MeshInstance3D", true, false):
		var mi := value as MeshInstance3D
		if mi.mesh == null:
			continue
		var a: AABB = mi.global_transform * mi.get_aabb()
		box = box.merge(a) if has else a
		has = true
	return box


func _setup_environment(stage: Node3D) -> void:
	var env := WorldEnvironment.new()
	var res := Environment.new()
	res.background_mode = Environment.BG_COLOR
	res.background_color = Color(0.10, 0.10, 0.112)
	res.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	res.ambient_light_color = Color(0.78, 0.76, 0.72)
	res.ambient_light_energy = 1.7
	res.tonemap_mode = Environment.TONE_MAPPER_ACES
	res.tonemap_exposure = 1.0
	env.environment = res
	stage.add_child(env)
	# 近乎贴地的掠射光：只在有棱线/台阶的地方拉出亮暗带
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-9, -34, 0)
	sun.light_energy = 2.2
	sun.light_color = Color(1.0, 0.97, 0.92)
	sun.shadow_enabled = true
	stage.add_child(sun)


func _capture(file_name: String) -> void:
	for _frame in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := OUT_DIR.path_join(file_name)
	if image.save_png(path) != OK:
		printerr("SEAM_FAIL ", path)
	else:
		print("SEAM_FILE %s" % file_name)
