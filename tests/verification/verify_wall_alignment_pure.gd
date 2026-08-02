extends Node
## 纯独立场景：手动构造塔楼外墙（5m 模块）+ 地砖（5m）+ 缺口（hole_center 5m 网格对齐），
## 不依赖 TowerDescent3D，避免 HUD 干扰。
## 输出俯视图，让主人直接肉眼验证墙体和地砖是否工整对齐。

const OUTPUT_DIR := "res://outputs/verification"
const GRID_UNIT := 5.0
const GRID_COUNT := 50
const MAP_SIZE := GRID_UNIT * GRID_COUNT  # 250
const MAP_HALF := MAP_SIZE * 0.5  # 125
const WALL_DOOR_GAP_HALF_WIDTH := 5.0
const WALL_THICKNESS := 0.30
const WALL_HEIGHT := 9.0

# 4 个缺口中心（必须落在 5m 网格上 = 5*(n+0.5)）
const HOLE_CENTERS := {
	"west":  Vector3(-37.5, 0.0, 12.5),
	"east":  Vector3(42.5, 0.0, -2.5),
	"north": Vector3(-2.5, 0.0, -37.5),
	"south": Vector3(17.5, 0.0, 42.5),
}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))

	# 1. 建场景根 + 5m 网格地砖（按模块摆放）
	var root := Node3D.new()
	add_child(root)

	# 1.1 地砖（50×50 块，每块 5m × 5m）
	_build_floor(root)

	# 1.2 外墙（5m 模块，缺口跳过）
	_build_outer_shell(root)

	# 1.3 在每个缺口位置画红色 wireframe 标记
	for side in HOLE_CENTERS.keys():
		_draw_hole_marker(root, HOLE_CENTERS[side])

	# 1.4 在地砖上画绿色 5m 网格线
	_draw_grid_overlay(root)

	# 2. 相机：从上方斜俯视整个 250m 楼顶
	var camera := Camera3D.new()
	camera.fov = 45.0
	camera.near = 1.0
	camera.far = 1500.0
	add_child(camera)
	camera.current = true

	# 等渲染稳定
	await _wait_render()

	# 拍图 1：正俯视（直上往下）
	camera.global_position = Vector3(0.0, 300.0, 0.0)
	camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	camera.fov = 35.0
	await _wait_render()
	_save("pure_topdown")

	# 拍图 2：斜俯视（南面看）
	camera.global_position = Vector3(0.0, 200.0, 200.0)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	camera.fov = 50.0
	await _wait_render()
	_save("pure_oblique_south")

	# 拍图 3：斜俯视（北面看）
	camera.global_position = Vector3(0.0, 200.0, -200.0)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	camera.fov = 50.0
	await _wait_render()
	_save("pure_oblique_north")

	# 拍图 4：斜俯视（西面看）
	camera.global_position = Vector3(-200.0, 200.0, 0.0)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	camera.fov = 50.0
	await _wait_render()
	_save("pure_oblique_west")

	print("截图完成 → %s" % OUTPUT_DIR)
	get_tree().quit()


func _build_floor(root: Node3D) -> void:
	# 用 Multimesh 摆 50×50 块地砖
	var mesh := BoxMesh.new()
	mesh.size = Vector3(GRID_UNIT, 0.30, GRID_UNIT)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.18, 0.22, 0.32)
	material.metallic = 0.10
	material.roughness = 0.85
	mesh.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	var count := GRID_COUNT * GRID_COUNT
	multimesh.instance_count = count
	var idx := 0
	for i in GRID_COUNT:
		for j in GRID_COUNT:
			var x := -MAP_HALF + GRID_UNIT * (float(i) + 0.5)
			var z := -MAP_HALF + GRID_UNIT * (float(j) + 0.5)
			multimesh.set_instance_transform(idx, Transform3D(Basis.IDENTITY, Vector3(x, 0.0, z)))
			idx += 1
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = multimesh
	root.add_child(mi)


func _build_outer_shell(root: Node3D) -> void:
	# 墙用 BoxMesh，5m 宽 × 9m 高 × 0.3m 厚
	var mesh := BoxMesh.new()
	mesh.size = Vector3(GRID_UNIT, WALL_HEIGHT, WALL_THICKNESS)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.42, 0.45, 0.55)
	material.metallic = 0.55
	material.roughness = 0.55
	mesh.material = material

	var boundary := MAP_HALF - WALL_THICKNESS * 0.5
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh

	# 收集 4 面墙的所有模块（跳过缺口）
	var transforms: Array[Transform3D] = []
	for side in ["north", "south", "west", "east"]:
		var hole: Vector3 = HOLE_CENTERS[side]
		var along_axis: String = "x" if side in ["north", "south"] else "z"
		var hole_along: float = hole.x if along_axis == "x" else hole.z
		for index in GRID_COUNT:
			var offset := -MAP_HALF + GRID_UNIT * (float(index) + 0.5)
			if absf((offset if along_axis == "x" else offset) - hole_along) <= WALL_DOOR_GAP_HALF_WIDTH:
				continue
			match side:
				"north":
					transforms.append(Transform3D(Basis.IDENTITY, Vector3(offset, WALL_HEIGHT * 0.5, -boundary)))
				"south":
					transforms.append(Transform3D(Basis(Vector3.UP, PI), Vector3(-offset, WALL_HEIGHT * 0.5, boundary)))
				"west":
					transforms.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-boundary, WALL_HEIGHT * 0.5, -offset)))
				"east":
					transforms.append(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(boundary, WALL_HEIGHT * 0.5, offset)))

	multimesh.instance_count = transforms.size()
	for index in range(transforms.size()):
		multimesh.set_instance_transform(index, transforms[index])

	var mi := MultiMeshInstance3D.new()
	mi.multimesh = multimesh
	root.add_child(mi)


func _draw_hole_marker(root: Node3D, center: Vector3) -> void:
	# 在缺口位置画一个绿色 wireframe 立方体（10m × 9m × 0.5m）
	var im := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 1.0, 0.4, 0.9)
	mat.flags_transparent = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.position = Vector3(center.x, WALL_HEIGHT * 0.5, center.z)
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	var half_x := 5.0  # 缺口沿墙面方向 10m
	var half_y := WALL_HEIGHT * 0.5
	var half_z := 0.5
	var corners: Array[Vector3] = [
		Vector3(-half_x, -half_y, -half_z),
		Vector3( half_x, -half_y, -half_z),
		Vector3( half_x, -half_y,  half_z),
		Vector3(-half_x, -half_y,  half_z),
		Vector3(-half_x,  half_y, -half_z),
		Vector3( half_x,  half_y, -half_z),
		Vector3( half_x,  half_y,  half_z),
		Vector3(-half_x,  half_y,  half_z),
	]
	var edges: Array = [
		[0, 1], [1, 2], [2, 3], [3, 0],
		[4, 5], [5, 6], [6, 7], [7, 4],
		[0, 4], [1, 5], [2, 6], [3, 7],
	]
	for edge in edges:
		var i0: int = edge[0]
		var i1: int = edge[1]
		im.surface_add_vertex(corners[i0])
		im.surface_add_vertex(corners[i1])
	im.surface_end()
	root.add_child(mi)


func _draw_grid_overlay(root: Node3D) -> void:
	# 在地砖上画红色细线，覆盖所有 5m 网格接缝
	var im := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.3, 0.3, 0.8)
	mat.flags_transparent = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.position.y = 0.18
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	for i in range(GRID_COUNT + 1):
		var p := -MAP_HALF + GRID_UNIT * float(i)
		im.surface_add_vertex(Vector3(p, 0.0, -MAP_HALF))
		im.surface_add_vertex(Vector3(p, 0.0, MAP_HALF))
		im.surface_add_vertex(Vector3(-MAP_HALF, 0.0, p))
		im.surface_add_vertex(Vector3(MAP_HALF, 0.0, p))
	im.surface_end()
	root.add_child(mi)


func _save(label: String) -> void:
	var path := "%s/wall_alignment_%s.png" % [OUTPUT_DIR, label]
	var image := get_viewport().get_texture().get_image()
	if image != null and not image.is_empty():
		image.save_png(path)
		print("已存 %s  size=%s" % [path, image.get_size()])
	else:
		print("截图失败 %s" % path)


func _wait_render() -> void:
	for i in 4:
		RenderingServer.force_draw()
		await RenderingServer.frame_post_draw