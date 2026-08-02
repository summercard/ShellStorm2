extends Node
## 用 ImmediateMesh 在缺口中心画一个 wireframe 立方体 + 在地砖上画 5m 网格，
## 用来肉眼确认墙体、地砖、缺口是否严格对齐。

const OUTPUT_DIR := "res://outputs/verification"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990095
	add_child(tower)
	await _settle_long()
	tower.force_enter_room_for_test("start")
	await _settle_long()

	# 关闭所有 UI
	for child in tower.find_children("*", "CanvasLayer", true, false):
		(child as CanvasLayer).visible = false
	for child in tower.find_children("*", "Control", true, false):
		(child as Control).visible = false

	# 完全冻结
	tower.set_physics_process(false)
	tower.set_process(false)
	tower.player.set_physics_process(false)
	tower.player.set_process(false)
	tower.player.visible = false

	# 加一个独立 Marker3D root 给我们的 overlay
	var overlay_root := Node3D.new()
	overlay_root.name = "WallAlignmentOverlay"
	add_child(overlay_root)

	# 战斗层
	const COMBAT_Y := -18.0
	const FLOOR_TOP := COMBAT_Y + 0.3

	# 1. 画 5m 网格覆盖整个战斗层
	_draw_grid(overlay_root, FLOOR_TOP, 50, 5.0)

	# 2. 在每个缺口中心画一个 wireframe 立方体（标记缺口范围）
	var holes := [
		# name, center xz, wall_axis (xz vec)
		{"name": "north", "center": Vector2(-2.5, -37.5)},
		{"name": "south", "center": Vector2(17.5, 42.5)},
		{"name": "west", "center": Vector2(-37.5, 12.5)},
		{"name": "east", "center": Vector2(42.5, -2.5)},
	]
	for hole in holes:
		_draw_hole_marker(overlay_root, hole["center"], FLOOR_TOP)

	# 3. 在每面墙的位置画细线标识墙体所在（z=±125, x=±125）
	_draw_wall_lines(overlay_root, FLOOR_TOP)

	# 等渲染稳定
	await _wait_render()

	# 用 player.camera 拍斜俯视图
	var cam := tower.player.camera
	cam.fov = 45.0
	cam.global_position = Vector3(0.0, COMBAT_Y + 200.0, 0.0)
	cam.rotation_degrees = Vector3(-65.0, 0.0, 45.0)
	await _wait_render()
	_save("overlay_oblique")

	# 正俯视
	cam.fov = 40.0
	cam.global_position = Vector3(0.0, COMBAT_Y + 280.0, 0.0)
	cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	await _wait_render()
	_save("overlay_topdown")

	print("截图完成 → %s" % OUTPUT_DIR)
	get_tree().quit()


func _draw_grid(root: Node3D, y: float, count: int, unit: float) -> void:
	var mesh_inst := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	mesh_inst.mesh = im
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.0, 1.0, 0.4, 0.7)
	mat.flags_transparent = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_inst.material_override = mat
	mesh_inst.position.y = y + 0.05
	# 画横竖各 50 条线
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	var half := unit * count * 0.5
	for i in range(count + 1):
		var p := -half + unit * i
		# x 方向线
		im.surface_add_vertex(Vector3(p, 0.0, -half))
		im.surface_add_vertex(Vector3(p, 0.0, half))
		# z 方向线
		im.surface_add_vertex(Vector3(-half, 0.0, p))
		im.surface_add_vertex(Vector3(half, 0.0, p))
	im.surface_end()
	root.add_child(mesh_inst)


func _draw_hole_marker(root: Node3D, center: Vector2, y: float) -> void:
	# 缺口是 10m × 9m 的矩形（沿墙面 10m, 垂直墙面由楼板决定）
	# 这里画一个 10m × 9m 的 wireframe 方框，中心在 hole center, 顶部 y+9, 底部 y
	var im := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.4, 0.0, 0.9)
	mat.flags_transparent = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.position = Vector3(center.x, y, center.y)
	# 假设是 west/east 墙（沿 z 方向），南北墙翻转即可
	# 为简化，我们画一个通用 10m × 9m 的盒子，绕 y 旋转
	# 实际上要先判断缺口在哪个方向：
	# north/south 墙：墙在 ±Z, 缺口宽沿 x（10m）, 沿 z 是墙厚（10m 用作 span 标记也可）
	# west/east 墙：墙在 ±X, 缺口宽沿 z（10m）
	# 我们用最简标记：画一个 10m × 9m × 0.5m 的盒子，中心对齐墙外侧
	# 让盒子略在墙外（+0.5m 朝外方向）
	var wall_thickness := 0.5
	var half_x := 5.0  # 沿缺口宽度方向（默认 x）
	var half_z := wall_thickness * 0.5  # 沿墙面方向（厚度）
	var half_y := 9.0 * 0.5
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	# 8 个顶点
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


func _draw_wall_lines(root: Node3D, y: float) -> void:
	# 画 4 面墙的边缘线（z = ±125, x = ±125）
	var im := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.0, 0.0, 0.8)
	mat.flags_transparent = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.position = Vector3.ZERO
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	var boundary := 125.0
	var top := 9.0
	# 4 条边
	var corners_2d: Array[Vector2] = [
		Vector2(-boundary, -boundary),
		Vector2( boundary, -boundary),
		Vector2( boundary,  boundary),
		Vector2(-boundary,  boundary),
	]
	for i in 4:
		var a: Vector2 = corners_2d[i]
		var b: Vector2 = corners_2d[(i + 1) % 4]
		im.surface_add_vertex(Vector3(a.x, y, a.y))
		im.surface_add_vertex(Vector3(b.x, y, b.y))
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


func _settle_long() -> void:
	for i in 10:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.5).timeout