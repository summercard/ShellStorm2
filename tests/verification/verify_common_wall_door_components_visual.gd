extends Node
## 战局区块通用组件库 v003 · 08 墙壁组件 / 10 门组件 资产墙验收图。
##
## 两张图：
##   1. common_wall_door_components.png      —— 标准墙 / 门墙+门扇装配 / 独立门扇 三方总览
##   2. common_wall_door_components_door.png —— 门洞近景：左右门垛 1.4 + 门楣 9.4 让出 2.2 × 2.5
##
## 读取 viewport 贴图，必须用真实渲染器运行（见 scripts/run_verification_suite.sh 的 renderer_scenes）。

const GALLERY_OUTPUT := "res://outputs/verification/common_wall_door_components.png"
const DOOR_OUTPUT := "res://outputs/verification/common_wall_door_components_door.png"

const RUNTIME_DIR := "res://assets/art/environments/tower_zones/battle/runtime/common_components"

## 总览排布（格心间距 5m 的模块化参照）
const WALL_STANDARD_CENTER := Vector3(-8.0, 0.0, 0.0)
const WALL_DOOR_CENTER := Vector3(0.0, 0.0, 0.0)
const DOOR_STANDALONE_CENTER := Vector3(7.4, 0.0, 0.0)

const WALL_HEIGHT := 11.9
const WALL_THICKNESS := 0.3
const DOOR_CLEAR_WIDTH := 2.2
const DOOR_CLEAR_HEIGHT := 2.5
const PIER_WIDTH := 1.4
const LINTEL_HEIGHT := 9.4


func _ready() -> void:
	VerificationOutput.prepare()
	var failures: Array[String] = []
	var stage := _create_stage()
	add_child(stage)
	var camera := stage.get_node("Camera3D") as Camera3D

	var assets := stage.get_node("Assets") as Node3D
	_build_overview(assets, failures)
	camera.look_at_from_position(Vector3(0.0, 7.4, -27.0), Vector3(0.0, 4.6, 0.0), Vector3.UP)
	camera.fov = 47.0
	await _settle()
	_save_view(GALLERY_OUTPUT, "墙/门组件总览验收图保存失败", failures)

	_clear_assets(stage)
	assets = stage.get_node("Assets") as Node3D
	_build_door_study(assets, failures)
	camera.look_at_from_position(Vector3(0.0, 1.9, -9.6), Vector3(0.0, 1.55, 0.0), Vector3.UP)
	camera.fov = 34.0
	await _settle()
	_save_view(DOOR_OUTPUT, "门洞净空近景验收图保存失败", failures)

	if failures.is_empty():
		print("COMMON_WALL_DOOR_COMPONENTS_VISUAL_OK: 墙/门组件总览与门洞净空近景验收图已生成")
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
	key.rotation_degrees = Vector3(-42.0, -30.0, 0.0)
	key.light_color = Color("ffffff")
	key.light_energy = 1.05
	stage.add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0.0, 6.5, -10.0)
	fill.light_color = Color("dbe6ff")
	fill.light_energy = 4.2
	fill.omni_range = 34.0
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
	_place(assets, "wall_standard_5m", WALL_STANDARD_CENTER, failures)
	_add_label(
		assets,
		"通用标准墙 wall_standard_5m\n5.0 × 0.3 × %.1fm ｜ 底面中心原点" % WALL_HEIGHT,
		WALL_STANDARD_CENTER + Vector3(-2.4, 12.9, 0.0),
		0.010
	)

	_place(assets, "wall_door_5m", WALL_DOOR_CENTER, failures)
	_place(assets, "door_5m", WALL_DOOR_CENTER, failures)
	_add_label(
		assets,
		"通用门墙 wall_door_5m + 通用门扇 door_5m（装配）\n门洞 %.1f × %.1fm ｜ 门扇底边中心原点、垂直升起" % [DOOR_CLEAR_WIDTH, DOOR_CLEAR_HEIGHT],
		WALL_DOOR_CENTER + Vector3(0.0, 12.9, 0.0),
		0.011
	)

	_place(assets, "door_5m", DOOR_STANDALONE_CENTER, failures)
	_add_label(
		assets,
		"通用门扇 door_5m（单体）\n%.1f × 0.18 × %.1fm" % [DOOR_CLEAR_WIDTH, DOOR_CLEAR_HEIGHT],
		DOOR_STANDALONE_CENTER + Vector3(0.0, 4.3, 0.0),
		0.010
	)

	_add_module_bars(assets, -8.0, 0.0)
	_add_module_bars(assets, 0.0, 0.0)
	_add_label(
		assets,
		"格心间距 5.00m ｜ 墙厚 0.30m ｜ 视觉墙高 %.1fm（逻辑层高 12.0m，墙顶留 0.1m）" % WALL_HEIGHT,
		Vector3(0.0, 0.22, -6.6),
		0.013
	)
	_add_height_reference(assets, Vector3(-13.4, 0.0, 2.6), 1.0, "1m 参照")
	_add_height_reference(assets, Vector3(13.4, 0.0, 2.6), 2.0, "2m 参照")


func _build_door_study(assets: Node3D, failures: Array[String]) -> void:
	_place(assets, "wall_door_5m", Vector3.ZERO, failures)
	_place(assets, "door_5m", Vector3.ZERO, failures)

	# 门洞净空高亮框：正好 2.2 宽 × 2.5 高，压在门扇前表面。
	var aperture := _wire_box(assets, Vector3(DOOR_CLEAR_WIDTH, DOOR_CLEAR_HEIGHT, 0.06), Color("5ee0a0"))
	aperture.position = Vector3(0.0, DOOR_CLEAR_HEIGHT * 0.5, -0.14)

	_add_label(assets, "门洞净空 %.1f × %.1fm（无碰撞）" % [DOOR_CLEAR_WIDTH, DOOR_CLEAR_HEIGHT], Vector3(0.0, 2.86, -0.5), 0.0075)
	# 正视（摄像机在 -Z 看 +Z）时世界 +X 落屏幕左侧；标签直接写世界坐标锚点，
	# 免得审图人把镜像当成左右门垛装反。
	_add_label(assets, "门垛宽 %.1fm ｜ x=+%.1f" % [PIER_WIDTH, PIER_WIDTH * 0.5 + DOOR_CLEAR_WIDTH * 0.5], Vector3(1.8, 4.2, -0.4), 0.0075)
	_add_label(assets, "门垛宽 %.1fm ｜ x=-%.1f" % [PIER_WIDTH, PIER_WIDTH * 0.5 + DOOR_CLEAR_WIDTH * 0.5], Vector3(-1.8, 4.2, -0.4), 0.0075)
	_add_label(assets, "门楣高 %.1fm" % LINTEL_HEIGHT, Vector3(0.0, 6.6, -0.4), 0.0075)
	_add_label(assets, "门扇厚 0.18m ｜ 贴门洞内缘", Vector3(0.0, 0.34, -0.62), 0.0065)

	# 门墙总宽 / 总高参照条
	_add_span_bar(assets, Vector3(-2.5, -0.05, 0.0), Vector3(2.5, -0.05, 0.0), "门墙总宽 5.0m")
	_add_height_reference(assets, Vector3(3.5, 0.0, 0.5), 1.0, "1m 参照")


func _place(assets: Node3D, slug: String, position: Vector3, failures: Array[String]) -> Node3D:
	var scene_path := "%s/%s/%s_root_top3d_v003.tscn" % [RUNTIME_DIR, slug, slug]
	var packed := load(scene_path) as PackedScene
	if packed == null:
		failures.append("组件包装场景加载失败：%s" % scene_path)
		return null
	var instance := packed.instantiate() as Node3D
	instance.position = position
	assets.add_child(instance)
	return instance


func _add_module_bars(assets: Node3D, center_x: float, z: float) -> void:
	# 5m 模块：在墙脚画一条跨整个格心的基准条，帮助判断墙是否满格。
	_add_span_bar(
		assets,
		Vector3(center_x - 2.5, 0.02, z - 0.9),
		Vector3(center_x + 2.5, 0.02, z - 0.9),
		"5.00m 模块"
	)


func _add_span_bar(assets: Node3D, from: Vector3, to: Vector3, text: String) -> void:
	var midpoint := (from + to) * 0.5
	var length := from.distance_to(to)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(length, 0.05, 0.09)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("ffd84a")
	material.emission_enabled = true
	material.emission = Color("8a5d08")
	material.emission_energy_multiplier = 0.4
	mesh.material = material
	mesh_instance.mesh = mesh
	mesh_instance.position = midpoint
	assets.add_child(mesh_instance)
	_add_label(assets, text, midpoint + Vector3(0.0, 0.34, 0.0), 0.0075)


func _wire_box(assets: Node3D, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.8
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color.a = 0.16
	mesh.material = material
	mesh_instance.mesh = mesh
	assets.add_child(mesh_instance)
	return mesh_instance


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
