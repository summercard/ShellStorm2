extends Node
## 战局区块通用组件库 v003 · 09 地板组件（floor_tile_5m）资产墙验收图。
##
## 两张图：
##   1. common_floor_tile_components.png       —— c01 / c02 / L 型转角参照 三方总览
##   2. common_floor_tile_components_edge.png  —— 低角近景：厚度 0.056 vs 0.081 与 0.06m 留缝
##
## 读取 viewport 贴图，必须用真实渲染器运行（见 scripts/run_verification_suite.sh 的 renderer_scenes）。

const GALLERY_OUTPUT := "res://outputs/verification/common_floor_tile_components.png"
const EDGE_OUTPUT := "res://outputs/verification/common_floor_tile_components_edge.png"

const BATTLE_FLOOR_TILE_DIR := "res://assets/art/environments/tower_zones/battle/runtime/common_components/floor_tile_5m/"
const CORNER_L_SCENE := "res://assets/art/environments/base_facility_3d/runtime/env_base99_corner_l_5m/env_base99_corner_l_5m_root_top3d_v005.tscn"

## key → [slug, 厚度]
const TILES := {
	"c01": ["floor_tile_r01_c01", 0.056],
	"c02": ["floor_tile_r01_c02", 0.081],
}

## 运行时口径：格心间距 5m，地砖自身 4.94m，留缝 0.06m；塔楼承重楼板厚 0.30m。
const GRID_PITCH := 5.0
const RUNTIME_SUPPORT_THICKNESS := 0.30

## 总览排布：两块 2×2 地砖并排（各 10m 宽），L 型转角范式参照置于其后。
const C01_CENTER := Vector3(-6.5, 0.0, -3.0)
const C02_CENTER := Vector3(6.5, 0.0, -3.0)
const CORNER_CENTER := Vector3(0.0, 0.0, 10.5)


func _ready() -> void:
	VerificationOutput.prepare()
	var failures: Array[String] = []
	var stage := _create_stage()
	add_child(stage)
	var camera := stage.get_node("Camera3D") as Camera3D

	var assets := stage.get_node("Assets") as Node3D
	_build_overview(assets, failures)
	camera.look_at_from_position(Vector3(0.0, 12.4, -27.5), Vector3(0.0, 3.2, 0.0), Vector3.UP)
	camera.fov = 46.0
	await _settle()
	_save_view(GALLERY_OUTPUT, "地砖组件总览验收图保存失败", failures)

	_clear_assets(stage)
	assets = stage.get_node("Assets") as Node3D
	_build_edge_study(assets, failures)
	camera.look_at_from_position(Vector3(0.0, 1.46, -12.8), Vector3(0.0, 0.18, 1.4), Vector3.UP)
	camera.fov = 30.0
	await _settle()
	_save_view(EDGE_OUTPUT, "地砖厚度/留缝近景验收图保存失败", failures)

	if failures.is_empty():
		print("COMMON_FLOOR_TILE_COMPONENTS_VISUAL_OK: 地砖组件总览与厚度/留缝近景验收图已生成")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _create_stage() -> Node3D:
	var stage := Node3D.new()
	stage.name = "Stage"
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("141824")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("aebfe4")
	environment.ambient_light_energy = 0.8
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment
	stage.add_child(world_environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-46.0, -32.0, 0.0)
	key.light_color = Color("ffffff")
	key.light_energy = 1.05
	stage.add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0.0, 9.0, -12.0)
	fill.light_color = Color("dbe6ff")
	fill.light_energy = 4.0
	fill.omni_range = 44.0
	stage.add_child(fill)
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.current = true
	stage.add_child(camera)
	var assets := Node3D.new()
	assets.name = "Assets"
	stage.add_child(assets)
	return stage


func _build_overview(assets: Node3D, failures: Array[String]) -> void:
	for key in ["c01", "c02"]:
		var center: Vector3 = C01_CENTER if key == "c01" else C02_CENTER
		_place_block(assets, key, center, failures)
		_add_label(
			assets,
			"%s\n4.94m ｜ 厚 %.3fm ｜ 落位 y=-%.3f" % [_slug(key), _thickness(key), _thickness(key)],
			center + Vector3(0.0, 2.1, 0.0),
			0.010
		)

	var corner := load(CORNER_L_SCENE) as PackedScene
	if corner == null:
		failures.append("L 型转角 v005 包装无法加载，总览图缺少范式参照")
	else:
		var corner_instance := corner.instantiate() as Node3D
		corner_instance.position = CORNER_CENTER
		assets.add_child(corner_instance)
		_add_label(
			assets,
			"L 型转角 v005（包装范式同源）\n5 × 12 × 5m ｜ 碰撞外置 DungeonRoom3D",
			CORNER_CENTER + Vector3(0.0, 14.2, 0.0),
			0.011
		)

	_add_label(
		assets,
		"格心间距 5.00m ｜ 地砖 4.94m ｜ 留缝 0.06m ｜ 顶面回到步行面 Y=0",
		Vector3(0.0, 0.22, -9.6),
		0.014
	)
	_add_height_reference(assets, Vector3(-12.6, 0.0, 3.6), 1.0, "1m 参照")
	_add_height_reference(assets, Vector3(12.6, 0.0, 3.6), 2.0, "2m 参照")


func _build_edge_study(assets: Node3D, failures: Array[String]) -> void:
	# 两块相邻地砖：格心间距 5.00m，各自 4.94m → 边缘之间正好留 0.06m。
	_place_single(assets, "c01", Vector3(-GRID_PITCH * 0.5, -_thickness("c01"), 0.0), failures)
	_place_single(assets, "c02", Vector3(GRID_PITCH * 0.5, -_thickness("c02"), 0.0), failures)

	# 运行时塔楼承重楼板参照：0.30m 厚，落在两砖后方。
	var support := MeshInstance3D.new()
	var support_mesh := BoxMesh.new()
	support_mesh.size = Vector3(4.2, RUNTIME_SUPPORT_THICKNESS, 1.6)
	var support_material := StandardMaterial3D.new()
	support_material.albedo_color = Color("64709b")
	support_material.metallic = 0.2
	support_material.roughness = 0.62
	support_mesh.material = support_material
	support.mesh = support_mesh
	support.position = Vector3(0.0, -RUNTIME_SUPPORT_THICKNESS * 0.5, 3.5)
	assets.add_child(support)
	_add_label(
		assets,
		"运行时承重楼板 0.30m",
		Vector3(-1.4, 1.62, 3.5),
		0.010
	)

	# 两块地砖标签分别落在各自外侧（世界 +X → 屏幕右侧），与居中说明错开。
	_add_label(assets, "c01 · 厚 0.056m", Vector3(-4.6, 0.72, 1.2), 0.009)
	_add_label(assets, "c02 · 厚 0.081m", Vector3(4.6, 0.72, 1.2), 0.009)
	_add_label(assets, "相邻边缘留缝 0.06m", Vector3(0.0, 0.30, -0.4), 0.008)
	_add_height_reference(assets, Vector3(-7.6, 0.0, 0.4), 1.0, "1m 参照")


func _slug(key: String) -> String:
	return str((TILES[key] as Array)[0])


func _thickness(key: String) -> float:
	return float((TILES[key] as Array)[1])


func _place_block(assets: Node3D, key: String, center: Vector3, failures: Array[String]) -> void:
	var packed := _tile_scene(key, failures)
	if packed == null:
		return
	var thickness := _thickness(key)
	for row in 2:
		for column in 2:
			var tile := packed.instantiate() as Node3D
			tile.position = center + Vector3(
				(float(column) - 0.5) * GRID_PITCH,
				-thickness,
				(float(row) - 0.5) * GRID_PITCH
			)
			assets.add_child(tile)


func _place_single(assets: Node3D, key: String, position: Vector3, failures: Array[String]) -> void:
	var packed := _tile_scene(key, failures)
	if packed == null:
		return
	var tile := packed.instantiate() as Node3D
	tile.position = position
	assets.add_child(tile)


func _tile_scene(key: String, failures: Array[String]) -> PackedScene:
	var scene_path := "%s%s_root_top3d_v003.tscn" % [BATTLE_FLOOR_TILE_DIR, _slug(key)]
	var packed := load(scene_path) as PackedScene
	if packed == null:
		failures.append("地砖包装场景加载失败：%s" % scene_path)
	return packed


func _add_height_reference(parent: Node3D, position: Vector3, height: float, text: String) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.12, height, 0.12)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("ffd84a")
	material.emission_enabled = true
	material.emission = Color("8a5d08")
	material.emission_energy_multiplier = 0.45
	mesh.material = material
	mesh_instance.mesh = mesh
	mesh_instance.position = position + Vector3(0.0, height * 0.5, 0.0)
	parent.add_child(mesh_instance)
	_add_label(parent, text, position + Vector3(0.0, height + 0.28, 0.0), 0.010)


func _add_label(parent: Node3D, text: String, position: Vector3, pixel_size: float) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = position
	label.font_size = 36
	label.pixel_size = pixel_size
	label.outline_size = 10
	label.modulate = Color("e6f4ff")
	label.outline_modulate = Color(0.04, 0.05, 0.11, 1.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(label)


func _clear_assets(stage: Node3D) -> void:
	var old_assets := stage.get_node("Assets")
	old_assets.free()
	var assets := Node3D.new()
	assets.name = "Assets"
	stage.add_child(assets)


func _settle() -> void:
	for _frame in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _save_view(path: String, message: String, failures: Array[String]) -> void:
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(path) != OK:
		failures.append(message)
