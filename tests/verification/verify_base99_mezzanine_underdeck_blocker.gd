extends Node

const ASSET_ID := "ENV-BASE99-MEZZANINE-UNDERDECK-BLOCKER"
const EXPECTED_ASSET_VERSION := "v003"
const EXPECTED_BLOCKER_COUNT := 3
const MAX_BLOCKER_TOP_M := 4.96
const PANEL_RAY_SAMPLES := [
	[Vector3(0.0, 1.10, -3.70), Vector3(0.0, 1.10, -5.20), "south_lower"],
	[Vector3(0.0, 4.35, -3.70), Vector3(0.0, 4.35, -5.20), "south_upper"],
	[Vector3(-8.70, 1.10, 0.0), Vector3(-10.20, 1.10, 0.0), "west_lower"],
	[Vector3(-8.70, 4.35, 0.0), Vector3(-10.20, 4.35, 0.0), "west_upper"],
	[Vector3(8.70, 1.10, 0.0), Vector3(10.20, 1.10, 0.0), "east_lower"],
	[Vector3(8.70, 4.35, 0.0), Vector3(10.20, 4.35, 0.0), "east_upper"],
]


func _ready() -> void:
	var failures: Array[String] = []
	var packed := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := packed.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990099
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	var facility := (tower.get("_room_by_id") as Dictionary).get("facility") as DungeonRoom3D
	_expect(facility != null, "99层基地房间没有生成", failures)
	var blocker := _find_asset(facility, ASSET_ID) as Base99MezzanineUnderdeckBlocker3D if facility != null else null
	_expect(blocker != null, "楼中楼下方工业仓库挡板没有实例化", failures)
	if blocker != null:
		var platform := blocker.get_parent()
		_expect(
			platform != null
			and str(platform.get_meta("asset_id", "")) == "ENV-BASE99-MEZZANINE-20X10-Z5"
			and str(platform.get_meta("asset_version", "")) == "v003"
			and int(platform.get_meta("coplanar_edge_face_count", -1)) == 0,
			"阁楼平台没有使用已消除边缘共面的Blender v003资产",
			failures
		)
		_expect(str(blocker.get_meta("asset_id", "")) == ASSET_ID, "挡板资产ID不正确", failures)
		_expect(str(blocker.get_meta("asset_version", "")) == EXPECTED_ASSET_VERSION, "挡板没有使用灰色横向分板v003资产", failures)
		_expect(absf(float(blocker.get_meta("frame_inset_m", -1.0)) - 0.55) <= 0.001, "挡板没有保留0.55米内收契约", failures)
		_expect(
			str(blocker.get_meta("collision_contract", ""))
			== "three_authored_panel_aligned_permanent_blockers",
			"横向挡板没有使用v003源资产对齐的碰撞契约",
			failures
		)
		var collision_root := blocker.get_node_or_null("UnderdeckBlockerCollision")
		_expect(
			collision_root != null
			and str(collision_root.get_meta("collision_source", ""))
			== "authored_v003_packed_scene",
			"横向挡板碰撞仍依赖运行时临时生成",
			failures
		)
		var colliders := blocker.find_children("*", "StaticBody3D", true, false)
		var permanent_count := 0
		for collider_value in colliders:
			var collider := collider_value as StaticBody3D
			if not bool(collider.get_meta("base99_underdeck_permanent_blocker", false)):
				continue
			permanent_count += 1
			_expect(collider.process_mode == Node.PROCESS_MODE_ALWAYS, "挡板碰撞会随楼层停用: %s" % collider.name, failures)
			var shape := collider.get_child(0) as CollisionShape3D if collider.get_child_count() > 0 else null
			var box := shape.shape as BoxShape3D if shape != null else null
			_expect(box != null, "挡板没有盒形永久阻挡: %s" % collider.name, failures)
			if shape != null and box != null:
				_expect(shape.position.y + box.size.y * 0.5 <= MAX_BLOCKER_TOP_M, "挡板碰撞穿入5米楼板: %s" % collider.name, failures)
		_expect(permanent_count == EXPECTED_BLOCKER_COUNT, "挡板永久阻挡数量错误: %d" % permanent_count, failures)
		_validate_authored_panel_rays(blocker, failures)
	tower.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("BASE99_MEZZANINE_UNDERDECK_BLOCKER_OK: v003 authored source, packed collision and physical panel rays pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _validate_authored_panel_rays(
	blocker: Base99MezzanineUnderdeckBlocker3D,
	failures: Array[String]
) -> void:
	var space := blocker.get_world_3d().direct_space_state
	for sample in PANEL_RAY_SAMPLES:
		var start := blocker.to_global(sample[0] as Vector3)
		var finish := blocker.to_global(sample[1] as Vector3)
		var query := PhysicsRayQueryParameters3D.create(start, finish, 1)
		query.collide_with_areas = false
		query.collide_with_bodies = true
		var hit := space.intersect_ray(query)
		var collider := hit.get("collider") as CollisionObject3D
		var hit_summary := "none"
		if collider != null:
			hit_summary = "%s at %s" % [
				collider.name,
				blocker.to_local(hit.get("position", Vector3.ZERO) as Vector3),
			]
		_expect(
			collider != null
			and bool(collider.get_meta("base99_underdeck_permanent_blocker", false)),
			"横向挡板物理射线没有命中专属实体阻挡: %s (%s)" % [
				str(sample[2]), hit_summary
			],
			failures
		)


func _find_asset(root: Node, asset_id: String) -> Node:
	if str(root.get_meta("asset_id", "")) == asset_id:
		return root
	for child in root.get_children():
		var found := _find_asset(child, asset_id)
		if found != null:
			return found
	return null
