extends Node
## 视觉 A/B 对照：同一机位拍两张 —— ①外立面环开着 ②外立面环隐藏。
## 目的：用**像素差**回答「外立面环到底渲染出来没有」。因为本场景光照偏暗、立面
## 与背景都是低对比灰，单看一张图容易误判成「什么都没画」。
##
## 若两张图**有**明显差异 ⇒ 立面确实在渲染（差异区域 = 立面覆盖的像素）。
## 若两张图**几乎一样** ⇒ 立面没渲染出来（真 bug，不是观感问题）。
##
## 只读；必须「不带 --headless」运行。

const OUT_DIR := "res://_scratch/rooftop/ab"
const FACADE_NODE_NAMES: Array[String] = [
	"ImportedRooftopFacadeSolidGrid5M",
	"ImportedRooftopFacadeWindowGrid5M",
]
## 机位：塔楼外侧看西面。立面外皮 x≈-49.95，相机在 x=-64，正对墙面。
const CAM_FROM := Vector3(-64.0, 6.0, 15.0)
const CAM_TO := Vector3(-50.0, -6.0, 15.0)
const CAM_FAR := Vector3(120.0, 14.0, 40.0)


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	if scene == null:
		print("FACADE_AB_FAIL: 场景加载失败")
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
		player.global_position = Vector3(-30.0, 1.0, 15.0)
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
	camera.global_position = CAM_FROM
	camera.look_at(CAM_TO, Vector3.UP)
	camera.far = CAM_FAR.length()

	var facade_nodes := _find_facade_nodes(tower)
	if facade_nodes.is_empty():
		print("FACADE_AB_FAIL: 没找到外立面 MultiMesh 节点（名字改了？）")
		get_tree().quit(1)
		return
	for node in facade_nodes:
		var mm := node as MultiMeshInstance3D
		var instances := -1
		var mesh_ok := false
		if mm != null and mm.multimesh != null:
			instances = mm.multimesh.instance_count
			mesh_ok = mm.multimesh.mesh != null
		print(
			"FACADE_AB node=%s instances=%d mesh=%s visible=%s"
			% [node.name, instances, str(mesh_ok), str((node as Node3D).visible)]
		)

	var path_on := "%s/on_facade_visible.png" % OUT_DIR
	var path_off := "%s/off_facade_hidden.png" % OUT_DIR
	var image_on := await _shoot(camera, path_on)
	# 只改可见性，不动任何装配 —— 「隐藏后变样」才说明它真的在画。
	for node in facade_nodes:
		(node as Node3D).visible = false
	var image_off := await _shoot(camera, path_off)

	if image_on == null or image_off == null:
		print("FACADE_AB_FAIL: 截图失败")
		get_tree().quit(1)
		return
	var stats := _diff(image_on, image_off)
	print(
		"FACADE_AB diff size=%s changed=%d/%d ratio=%.4f mean_delta=%.2f max_delta=%d"
		% [
			str(image_on.get_size()),
			int(stats["changed"]),
			int(stats["total"]),
			float(stats["ratio"]),
			float(stats["mean_delta"]),
			int(stats["max_delta"]),
		]
	)
	# 判据：立面若真在渲染，隐藏它必然改变画面（本机位立面占画面很大一块）。
	var rendered := float(stats["ratio"]) >= 0.005
	print("FACADE_AB_DONE facade_rendered=%s" % ("true" if rendered else "false"))
	get_tree().quit(0 if rendered else 1)


func _find_facade_nodes(root: Node) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for wanted in FACADE_NODE_NAMES:
		var node := root.find_child(wanted, true, false) as Node3D
		if node != null:
			found.append(node)
	return found


func _shoot(camera: Camera3D, path: String) -> Image:
	for i in 12:
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(path)
	print("FACADE_AB shot %s err=%d" % [path, error])
	return image if error == OK else null


## 逐像素比较（同尺寸）。changed = 任一分量差 > 8 的像素数。
func _diff(a: Image, b: Image) -> Dictionary:
	if a.get_size() != b.get_size():
		return {"changed": -1, "total": 0, "ratio": 0.0, "mean_delta": 0.0, "max_delta": 0}
	var width := a.get_width()
	var height := a.get_height()
	var changed := 0
	var total := width * height
	var sum_delta := 0.0
	var max_delta := 0
	for y in range(height):
		for x in range(width):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var delta := absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			delta /= 3.0
			sum_delta += delta
			max_delta = maxi(max_delta, int(round(delta * 255.0)))
			if delta * 255.0 > 8.0:
				changed += 1
	return {
		"changed": changed,
		"total": total,
		"ratio": float(changed) / float(total),
		"mean_delta": sum_delta * 255.0 / float(total),
		"max_delta": max_delta,
	}
