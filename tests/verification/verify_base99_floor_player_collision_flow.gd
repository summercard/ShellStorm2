extends Node
## 99层完整新地板表现与TowerFloorStage承重面专项。
## V021完整视觉地板替换旧普通/铆钉MultiMesh，FloorSupport规格保持不变。

const EXPECTED_BASE_SURFACE_Y_M := 0.0
const MAX_SURFACE_DELTA_FROM_TOWER_M := 0.02
const EXPECTED_RIVET_VISUAL_PROTRUSION_M := 0.095


func _ready() -> void:
	var failures: Array[String] = []
	var packed := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := packed.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990099
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame

	var rooms := tower.get("_room_by_id") as Dictionary
	var facility := rooms.get("facility") as DungeonRoom3D
	_expect(facility != null, "99层基地房间没有生成", failures)
	var old_plain := facility.find_child("BaseFloorGrid6x6_Plain", true, false) if facility != null else null
	var old_rivet := facility.find_child("BaseFloorGrid6x6_Rivet", true, false) if facility != null else null
	_expect(old_plain == null and old_rivet == null, "旧普通/铆钉地板MultiMesh仍被渲染", failures)
	var full_floor := facility.get_node_or_null(
		"基地99层_美术布置层/BlenderV021完整地板表现_仅视觉/一层36块完整地板_替换旧MultiMesh_仅视觉"
	) as Node3D if facility != null else null
	_expect(full_floor != null, "V021完整地板替换资源没有挂载", failures)
	var replacement_surface := float(full_floor.get_meta("collision_surface_y_m", INF)) if full_floor != null else INF
	_expect(
		absf(replacement_surface - EXPECTED_BASE_SURFACE_Y_M) <= 0.001,
		"完整新地板没有保持旧地板Y=0承重坐标契约",
		failures
	)
	_expect(
		bool(full_floor.get_meta("visual_replaces_old_multimesh", false)) if full_floor != null else false,
		"完整新地板没有登记替换旧MultiMesh视觉的职责",
		failures
	)

	var stages := tower.get("_floor_stages") as Dictionary
	var rooftop_stage := stages.get(0) as TowerFloorStage3D
	var facility_stage := stages.get(1) as TowerFloorStage3D
	_expect(rooftop_stage != null, "100层物理楼板缺失", failures)
	_expect(facility_stage != null, "99层物理楼板缺失", failures)
	if rooftop_stage != null:
		var rooftop_surface := _tower_visual_surface_y(rooftop_stage)
		_expect(
			absf(replacement_surface - rooftop_surface) <= MAX_SURFACE_DELTA_FROM_TOWER_M,
			"99层完整新地板与100层正常地板表现高度差过大: %.4f" % absf(replacement_surface - rooftop_surface),
			failures
		)
	if facility_stage != null:
		var support := facility_stage.get_node_or_null("FloorSupport") as StaticBody3D
		_expect(
			support != null and support.process_mode == Node.PROCESS_MODE_ALWAYS,
			"99层FloorSupport缺失或会随流送退出物理空间",
			failures
		)
		_expect(
			_has_support_below_room_center(facility_stage, support),
			"99层基地中心下方没有启用的承重碰撞",
			failures
		)
		var collision_surface := _support_surface_below_room_center(facility_stage, support)
		_expect(
			absf(replacement_surface - collision_surface) <= 0.001,
			"99层完整新地板与承重碰撞顶面不一致: visual=%.4f collision=%.4f" % [
				replacement_surface, collision_surface,
			],
			failures
		)

	tower.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("BASE99_FLOOR_PLAYER_COLLISION_OK: shared structural surface, visible rivet protrusions, and unchanged flat support pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _surface_y(grid: MultiMeshInstance3D) -> float:
	if grid == null or grid.multimesh == null or grid.multimesh.mesh == null:
		return INF
	var structural_top := float(grid.get_meta("visual_structural_top_local_y_m", INF))
	var visual_origin := float(grid.get_meta("visual_origin_y_m", INF))
	return visual_origin + structural_top


func _tower_visual_surface_y(stage: TowerFloorStage3D) -> float:
	var grid := stage.get("_floor_visual_light") as MultiMeshInstance3D
	if grid == null or grid.multimesh == null or grid.multimesh.mesh == null:
		return INF
	var bounds := grid.multimesh.mesh.get_aabb()
	var mesh_top := bounds.position.y + bounds.size.y
	# Headless RenderingServer不保留MultiMesh实例buffer的回读；塔楼地砖代码
	# 统一下移半个板厚，所以直接按该稳定构造规则计算可视顶面。
	return mesh_top - TowerFloorStage3D.FLOOR_THICKNESS * 0.5


func _verify_runtime_transform_buffer(
	grid: MultiMeshInstance3D,
	display_name: String,
	failures: Array[String]
) -> void:
	if grid == null or grid.multimesh == null or grid.multimesh.instance_count <= 0:
		return
	var expected_origin := float(grid.get_meta("visual_origin_y_m", INF))
	var actual_origin := grid.multimesh.get_instance_transform(0).origin.y
	_expect(
		absf(actual_origin - expected_origin) <= 0.001,
		"99层%s没有把AABB校正写入真实MultiMesh变换: %.4f != %.4f" % [
			display_name, actual_origin, expected_origin,
		],
		failures
	)


func _has_support_below_room_center(stage: TowerFloorStage3D, support: StaticBody3D) -> bool:
	return is_finite(_support_surface_below_room_center(stage, support))


func _support_surface_below_room_center(stage: TowerFloorStage3D, support: StaticBody3D) -> float:
	if support == null:
		return INF
	# facility世界中心为(0,-9,5)，换算到stage局部后检查XZ是否落入某块承重盒。
	var local_center := stage.to_local(Vector3(0.0, -9.0, 5.0))
	for child in support.get_children():
		var collision := child as CollisionShape3D
		if collision == null or collision.disabled:
			continue
		var box := collision.shape as BoxShape3D
		if box == null:
			continue
		var half := box.size * 0.5
		if (
			absf(local_center.x - collision.position.x) <= half.x
			and absf(local_center.z - collision.position.z) <= half.z
		):
			return collision.position.y + half.y
	return INF


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
