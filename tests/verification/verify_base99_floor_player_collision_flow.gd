extends Node
## 99层正式地板表现与TowerFloorStage承重面专项。
## 两种地板按共同0.30m结构面摆放；铆钉、压条可高出但不参与承重碰撞。

const EXPECTED_BASE_SURFACE_Y_M := 0.165
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
	var plain := facility.find_child("BaseFloorGrid6x6_Plain", true, false) as MultiMeshInstance3D if facility != null else null
	var rivet := facility.find_child("BaseFloorGrid6x6_Rivet", true, false) as MultiMeshInstance3D if facility != null else null
	_expect(plain != null, "99层普通地板MultiMesh缺失", failures)
	_expect(rivet != null, "99层铆钉地板MultiMesh缺失", failures)

	var plain_surface := _surface_y(plain)
	var rivet_surface := _surface_y(rivet)
	_expect(
		absf(plain_surface - EXPECTED_BASE_SURFACE_Y_M) <= 0.001,
		"99层普通地板顶面没有校正到统一高度: surface=%.4f origin=%.4f mesh_top=%.4f" % [
			plain_surface,
			float(plain.get_meta("visual_origin_y_m", INF)) if plain != null else INF,
			float(plain.get_meta("visual_mesh_top_y_m", INF)) if plain != null else INF,
		],
		failures
	)
	_expect(
		absf(rivet_surface - EXPECTED_BASE_SURFACE_Y_M) <= 0.001,
		"99层铆钉地板结构面没有校正到统一高度: surface=%.4f origin=%.4f structural_top=%.4f" % [
			rivet_surface,
			float(rivet.get_meta("visual_origin_y_m", INF)) if rivet != null else INF,
			float(rivet.get_meta("visual_structural_top_local_y_m", INF)) if rivet != null else INF,
		],
		failures
	)
	_expect(
		absf(plain_surface - rivet_surface) <= 0.001,
		"99层两种地板的角色接触视觉高度不一致",
		failures
	)
	var plain_origin := float(plain.get_meta("visual_origin_y_m", INF)) if plain != null else INF
	var rivet_origin := float(rivet.get_meta("visual_origin_y_m", INF)) if rivet != null else INF
	_expect(
		absf(plain_origin - rivet_origin) <= 0.001,
		"普通板与铆钉板没有按同一结构基准摆放",
		failures
	)
	var rivet_decoration_top := (
		float(rivet.get_meta("visual_decoration_top_y_m", -INF)) if rivet != null else -INF
	)
	_expect(
		absf(
			rivet_decoration_top
			- rivet_surface
			- EXPECTED_RIVET_VISUAL_PROTRUSION_M
		) <= 0.001,
		"铆钉地板的铁皮/铆钉突出表现被压入结构面: decoration_top=%.4f surface=%.4f" % [
			rivet_decoration_top, rivet_surface,
		],
		failures
	)
	_expect(
		str(rivet.get_meta("collision_policy", ""))
			== "shared_flat_support_visual_protrusions_ignored",
		"铆钉地板没有登记突出表现不参与阻挡的规则",
		failures
	)
	if RenderingServer.get_rendering_device() != null:
		_verify_runtime_transform_buffer(plain, "普通地板", failures)
		_verify_runtime_transform_buffer(rivet, "铆钉地板", failures)

	var stages := tower.get("_floor_stages") as Dictionary
	var rooftop_stage := stages.get(0) as TowerFloorStage3D
	var facility_stage := stages.get(1) as TowerFloorStage3D
	_expect(rooftop_stage != null, "100层物理楼板缺失", failures)
	_expect(facility_stage != null, "99层物理楼板缺失", failures)
	if rooftop_stage != null:
		var rooftop_surface := _tower_visual_surface_y(rooftop_stage)
		_expect(
			absf(plain_surface - rooftop_surface) <= MAX_SURFACE_DELTA_FROM_TOWER_M,
			"99层正式地板与100层正常地板表现高度差过大: %.4f" % absf(plain_surface - rooftop_surface),
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
	# Headless RenderingServer不保留MultiMesh实例buffer的回读；塔楼地砖代码的
	# 实例Y固定为0，因此这里直接使用Mesh顶面进行结构验收。
	return mesh_top


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
	if support == null:
		return false
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
			and absf(collision.position.y + half.y) <= 0.001
		):
			return true
	return false


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)
