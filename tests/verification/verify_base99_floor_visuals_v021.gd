extends Node
## Blender V021 完整地板替换验收：移除旧MultiMesh视觉砖，保持原有承重碰撞。

const OUTPUT := "res://outputs/verification/base99_floor_visuals_v021.png"
const GROUND_SCENE := preload(
	"res://assets/art/environments/base_facility_3d/runtime/env_base99_floor_full_replacement_v021/env_base99_floor_full_replacement_v021_root_top3d_v003.tscn"
)
const LOFT_SCENE := preload(
	"res://assets/art/environments/base_facility_3d/runtime/env_base99_loft_floor_finish_v020/env_base99_loft_floor_finish_v020_root_top3d_v002.tscn"
)
const PALETTE_PATH := "res://assets/art/shared/palette/设施低亮多巴胺色盘_10x10_512.png"


func _ready() -> void:
	VerificationOutput.prepare()
	var failures: Array[String] = []
	_validate_standalone_visual_packages(failures)
	await _validate_runtime_placement(failures)
	if failures.is_empty():
		print("BASE99_FLOOR_VISUALS_V021_PASS: Blender V020 full-floor replacement, old MultiMesh removal, collision and placement verified")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("BASE99_FLOOR_VISUALS_V021_FAIL: %s" % " | ".join(failures))
	get_tree().quit(1)


func _validate_standalone_visual_packages(failures: Array[String]) -> void:
	var ground := GROUND_SCENE.instantiate() as Node3D
	add_child(ground)
	_validate_visual_package(ground, 2, 4, "一层完整地板替换", failures)
	if not bool(ground.get_meta("visual_replaces_old_multimesh", false)):
		failures.append("完整地板资源没有登记替换旧MultiMesh的职责")
	if float(ground.get_meta("collision_surface_y_m", INF)) != 0.0:
		failures.append("完整地板没有登记与旧地板一致的Y=0碰撞基准")
	ground.queue_free()
	var loft := LOFT_SCENE.instantiate() as Node3D
	add_child(loft)
	_validate_visual_package(loft, 1, 2, "二层地板面层", failures)
	loft.queue_free()


func _validate_visual_package(
	root: Node3D, expected_mesh_count: int, expected_surface_count: int, label: String, failures: Array[String]
) -> void:
	if not bool(root.get_meta("visual_only", false)):
		failures.append("%s没有标记为仅视觉资源" % label)
	if not root.find_children("*", "CollisionObject3D", true, false).is_empty():
		failures.append("%s意外携带玩法碰撞" % label)
	var meshes := _mesh_instances(root)
	if meshes.size() != expected_mesh_count:
		failures.append("%s网格数应为%d，实际为%d" % [label, expected_mesh_count, meshes.size()])
	var surface_count := 0
	for mesh_instance in meshes:
		if mesh_instance.mesh == null:
			failures.append("%s存在空网格" % label)
			continue
		surface_count += mesh_instance.mesh.get_surface_count()
		if mesh_instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			failures.append("%s关闭了投影: %s" % [label, mesh_instance.name])
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			var material := mesh_instance.get_active_material(surface_index) as BaseMaterial3D
			if material == null:
				failures.append("%s缺少BaseMaterial3D材质: %s/%d" % [label, mesh_instance.name, surface_index])
				continue
			if material.albedo_texture == null or material.albedo_texture.resource_path != PALETTE_PATH:
				failures.append("%s没有绑定共享Palette贴图: %s/%d" % [label, mesh_instance.name, surface_index])
	if surface_count != expected_surface_count:
		failures.append("%s材质表面数应为%d，实际为%d" % [label, expected_surface_count, surface_count])


func _validate_runtime_placement(failures: Array[String]) -> void:
	var packed := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := packed.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990117
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	var facility := (tower.get("_room_by_id") as Dictionary).get("facility") as DungeonRoom3D
	if facility == null:
		failures.append("未生成99层基地房间")
		tower.queue_free()
		return
	facility.ensure_detail_built()
	var snapshot := facility.get_room_snapshot()
	if int(snapshot.get("base99_floor_plain_instance_count", 0)) != 0:
		failures.append("旧普通地板MultiMesh仍在运行时生成")
	if int(snapshot.get("base99_floor_rivet_instance_count", 0)) != 0:
		failures.append("旧铆钉地板MultiMesh仍在运行时生成")
	var visual_root := facility.get_node_or_null("基地99层_美术布置层/BlenderV021完整地板表现_仅视觉") as Node3D
	if visual_root == null:
		failures.append("运行时基地没有挂载Blender V021完整地板表现层")
		tower.queue_free()
		return
	if str(visual_root.get_meta("source_blender_version", "")) != "v020":
		failures.append("运行时地板表现层没有指向Blender v020源文件")
	if not bool(visual_root.get_meta("visual_replaces_old_multimesh", false)):
		failures.append("运行时地板装配没有声明替换旧MultiMesh")
	var ground := visual_root.get_node_or_null("一层36块完整地板_替换旧MultiMesh_仅视觉") as Node3D
	var loft := visual_root.get_node_or_null("二层楼中楼地板面层_仅视觉") as Node3D
	if ground == null or loft == null:
		failures.append("一层深化或二层面层节点缺失")
	else:
		_validate_visual_package(ground, 2, 4, "运行时一层完整地板替换", failures)
		_validate_visual_package(loft, 1, 2, "运行时二层地板面层", failures)
		if not is_equal_approx(loft.position.y, -1.0):
			failures.append("二层面层没有进行Blender Z6到运行时Y5的-1m对齐")
		_validate_layout_bounds(ground, loft, facility, failures)
		await _capture_preview(tower, facility, failures)
	tower.queue_free()
	await get_tree().process_frame


func _validate_layout_bounds(ground: Node3D, loft: Node3D, facility: Node3D, failures: Array[String]) -> void:
	var ground_bounds := _relative_mesh_bounds(ground, facility)
	if ground_bounds.size == Vector3.ZERO:
		failures.append("一层地板深化没有可计算的包围盒")
		return
	if (
		ground_bounds.position.x < -15.05
		or ground_bounds.end.x > 15.05
		or ground_bounds.position.z < -15.05
		or ground_bounds.end.z > 15.05
	):
		failures.append("一层深化越出30×30米基地地板边界: %s" % ground_bounds)
	var loft_bounds := _relative_mesh_bounds(loft, facility)
	if loft_bounds.size == Vector3.ZERO:
		failures.append("二层地板面层没有可计算的包围盒")
		return
	if (
		loft_bounds.position.x < -5.05
		or loft_bounds.end.x > 15.05
		or loft_bounds.position.z < -15.05
		or loft_bounds.end.z > -4.95
	):
		failures.append("二层面层没有落在20×10米楼中楼范围: %s" % loft_bounds)
	if loft_bounds.position.y < 4.85 or loft_bounds.position.y > 5.12:
		failures.append("二层面层底面没有对齐运行时Y=5楼板: %s" % loft_bounds.position.y)


func _capture_preview(tower: TowerDescent3D, facility: DungeonRoom3D, failures: Array[String]) -> void:
	for canvas_value in tower.find_children("*", "CanvasLayer", true, false):
		(canvas_value as CanvasLayer).visible = false
	var fill := DirectionalLight3D.new()
	fill.light_energy = 2.0
	fill.light_color = Color("d9efff")
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-58.0, -35.0, 0.0)
	add_child(fill)
	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 68.0
	add_child(camera)
	camera.global_position = facility.global_position + Vector3(-10.5, 6.8, 13.5)
	camera.look_at(facility.global_position + Vector3(0.0, 0.5, -2.5), Vector3.UP)
	for _frame in range(12):
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(OUTPUT) != OK:
		failures.append("无法保存地板表现验收图")
	camera.queue_free()
	fill.queue_free()


func _mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for mesh_value in root.find_children("*", "MeshInstance3D", true, false):
		result.append(mesh_value as MeshInstance3D)
	return result


func _relative_mesh_bounds(root: Node3D, facility: Node3D) -> AABB:
	var has_point := false
	var bounds := AABB()
	for mesh_instance in _mesh_instances(root):
		if mesh_instance.mesh == null:
			continue
		var mesh_bounds := mesh_instance.mesh.get_aabb()
		for x_factor in [0.0, 1.0]:
			for y_factor in [0.0, 1.0]:
				for z_factor in [0.0, 1.0]:
					var corner := mesh_bounds.position + Vector3(
						mesh_bounds.size.x * x_factor,
						mesh_bounds.size.y * y_factor,
						mesh_bounds.size.z * z_factor
					)
					var local_corner := facility.to_local(mesh_instance.global_transform * corner)
					if not has_point:
						bounds = AABB(local_corner, Vector3.ZERO)
						has_point = true
					else:
						bounds = bounds.expand(local_corner)
	return bounds
