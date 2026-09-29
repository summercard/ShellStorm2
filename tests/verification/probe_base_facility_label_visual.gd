extends Node3D

## 99F 基地设施头顶文字的**视觉**采样（真渲染器，非 headless）。
##
## 回答「去掉常驻名字牌之后，设施头顶到底还剩什么」：给每件设施拍一张近景，
## 相机贴到模型前方、画面里必须装得下设施顶上的黄色提示牌。
##
## 不走验证套件（`probe_` 前缀），手动跑：
##   godot --path <隔离项目> --scene res://tests/verification/probe_base_facility_label_visual.tscn
## 产物：res://outputs/verification/base99_facility_label_<slug>.png

const OUTPUT_DIR := "res://outputs/verification"

const FACILITY_SLUGS := [
	[
		"east_supply_24h_station",
		"res://assets/art/environments/base_facility_3d/runtime/env_base99_remaining_facilities/"
		+ "east_supply_24h_station/east_supply_24h_station_facility_top3d.tscn",
	],
	[
		"medical_cabinet",
		"res://assets/art/environments/base_facility_3d/runtime/env_base99_remaining_facilities/"
		+ "medical_cabinet/medical_cabinet_facility_top3d.tscn",
	],
	[
		"hologram_terminal_platform",
		"res://assets/art/environments/base_facility_3d/runtime/env_base99_remaining_facilities/"
		+ "hologram_terminal_platform/hologram_terminal_platform_root_top3d.tscn",
	],
]

var _camera: Camera3D
var _key_light: DirectionalLight3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	_build_stage()
	for entry in FACILITY_SLUGS:
		await _shoot(str(entry[0]), str(entry[1]))
	get_tree().quit(0)


func _build_stage() -> void:
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.045, 0.055, 0.07)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.92, 0.96, 1.0)
	environment.ambient_light_energy = 1.35
	world_environment.environment = environment
	add_child(world_environment)

	_key_light = DirectionalLight3D.new()
	_key_light.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(36.0), 0.0)
	_key_light.light_energy = 1.6
	add_child(_key_light)

	_camera = Camera3D.new()
	_camera.fov = 55.0
	add_child(_camera)
	_camera.current = true


func _shoot(slug: String, scene_path: String) -> void:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("PROBE_VISUAL_FAIL: cannot load %s" % scene_path)
		get_tree().quit(1)
		return
	var facility := packed.instantiate() as BaseFacility3D
	add_child(facility)
	# 让黄色提示处于「玩家在范围内 + 已聚焦」的真实可见态。
	facility.set("_player_in_range", true)
	facility.set_interaction_focus({}, true)
	await _settle(3)

	var visual_bounds := _world_bounds(facility)
	var focus := visual_bounds.get_center()
	var label_y := _label_ceiling(facility)
	# 取景框要同时装下模型和头顶提示牌：抬高视线中心到两者之间。
	focus.y = lerpf(focus.y, label_y, 0.55)
	var radius := maxf(visual_bounds.size.length() * 0.5, 1.0)
	# 取景：相机落在设施正前方偏上，画面同时装下模型与头顶提示牌。
	# （高度不能压太低也不能抬太高 —— 抬到 radius*1.15 时实测拍成空视口。）
	_camera.global_position = focus + Vector3(0.0, radius * 0.45, radius * 2.35 + 1.6)
	_camera.look_at(focus, Vector3.UP)
	await _settle(4)

	var image := get_viewport().get_texture().get_image()
	var out_path := "%s/base99_facility_label_%s.png" % [OUTPUT_DIR, slug]
	if image == null or image.is_empty() or image.save_png(out_path) != OK:
		push_error("PROBE_VISUAL_FAIL: cannot save %s" % out_path)
		get_tree().quit(1)
		return
	print(
		"PROBE_VISUAL\t%s\tfacility=%s\tlabel_y=%.3f\tprompt_visible=%s\tname_visible=%s\t%s"
		% [
			slug,
			facility.facility_id,
			label_y,
			facility.prompt_label.visible,
			facility.name_label.visible,
			out_path,
		]
	)
	facility.queue_free()
	await _settle(2)


## 设施可见几何的世界包围盒（只统计有 mesh 的节点）。
func _world_bounds(root: Node3D) -> AABB:
	var bounds := AABB()
	var started := false
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var local := mesh_instance.get_aabb()
		var world := mesh_instance.global_transform * local
		if not started:
			bounds = world
			started = true
		else:
			bounds = bounds.merge(world)
	if not started:
		bounds = AABB(root.global_position, Vector3.ONE)
	return bounds


## 头顶文字的最高落点（世界 y）：提示牌与名字牌取高者。
func _label_ceiling(facility: BaseFacility3D) -> float:
	var highest := facility.global_position.y
	for node_name in ["PromptLabel", "NameLabel"]:
		var label := facility.get_node_or_null(node_name) as Label3D
		if label != null:
			highest = maxf(highest, label.global_position.y)
	return highest


func _settle(frames: int) -> void:
	for _index in range(frames):
		await get_tree().process_frame
