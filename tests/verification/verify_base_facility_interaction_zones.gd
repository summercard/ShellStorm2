extends Node

const TARGET_FACILITIES := ["mission_operations", "weapon_workshop", "base_vending"]


func _ready() -> void:
	var failures: Array[String] = []
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame

	var room_by_id := tower.get("_room_by_id") as Dictionary
	var facility_room := room_by_id.get("facility") as DungeonRoom3D
	if facility_room == null:
		failures.append("未生成基地设施房间")
	else:
		for facility_id in TARGET_FACILITIES:
			_verify_facility(tower, facility_room, facility_id, failures)

	tower.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("BASE_FACILITY_INTERACTION_ZONES_OK: authored facility transforms preserved and interaction zones remain usable")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _verify_facility(
	tower: TowerDescent3D,
	facility_room: DungeonRoom3D,
	facility_id: String,
	failures: Array[String]
) -> void:
	var facility: BaseFacility3D
	for candidate in tower.get_tree().get_nodes_in_group("base_facility"):
		if candidate is BaseFacility3D and tower.is_ancestor_of(candidate) and candidate.facility_id == facility_id:
			facility = candidate as BaseFacility3D
			break
	if facility == null:
		failures.append("缺少设施：%s" % facility_id)
		return
	var interaction := facility.get_node_or_null("InteractionShape") as CollisionShape3D
	var body_node := facility.get_node_or_null("StaticBody3D/CollisionShape3D") as CollisionShape3D
	if interaction == null or body_node == null:
		failures.append("设施缺少交互或实体碰撞：%s" % facility_id)
		return
	var interaction_box := interaction.shape as BoxShape3D
	var body_box := body_node.shape as BoxShape3D
	if interaction_box == null or body_box == null:
		failures.append("设施没有使用 BoxShape3D：%s" % facility_id)
		return
	if str(interaction.get_meta("front_interaction_profile", "")) != facility_id:
		failures.append("设施未应用正面交互配置：%s" % facility_id)
	var size_snapshot := facility.get_size_contract_snapshot()
	var expected_scale := Vector3.ONE * BaseFacility3D.DEFAULT_BASE_SIZE_MULTIPLIER
	if not (size_snapshot.get("interaction_scale", Vector3.ZERO) as Vector3).is_equal_approx(Vector3.ONE):
		failures.append("设施70%%缩放错误影响了交互范围：%s" % facility_id)
	if not (size_snapshot.get("body_scale", Vector3.ZERO) as Vector3).is_equal_approx(expected_scale):
		failures.append("设施实体碰撞未缩小到70%%：%s" % facility_id)
	if not (size_snapshot.get("visual_scale", Vector3.ZERO) as Vector3).is_equal_approx(expected_scale):
		failures.append("设施视觉未缩小到70%%：%s" % facility_id)

	var local_room_center := facility.to_local(facility_room.global_position)
	var toward_room := Vector2(local_room_center.x, local_room_center.z).normalized()
	var interaction_offset := Vector2(interaction.position.x, interaction.position.z)
	if interaction_offset.dot(toward_room) <= 0.0:
		failures.append("交互盒没有朝向房间内侧：%s" % facility_id)

	var axis_is_x := absf(toward_room.x) > absf(toward_room.y)
	var interaction_depth := interaction_box.size.x if axis_is_x else interaction_box.size.z
	var body_depth := body_box.size.x if axis_is_x else body_box.size.z
	var offset_depth := absf(interaction.position.x) if axis_is_x else absf(interaction.position.z)
	var exposed_depth := offset_depth + interaction_depth * 0.5 - body_depth * 0.5
	var required_depth := 4.0 if facility_id == "base_vending" else 3.4
	if exposed_depth < required_depth:
		failures.append("设施正面可站立交互距离不足：%s，实际 %.2f 米" % [facility_id, exposed_depth])
	var interaction_width := interaction_box.size.z if axis_is_x else interaction_box.size.x
	if facility_id != "base_vending" and interaction_width < 5.2:
		failures.append("工作设施正面交互宽度不足：%s" % facility_id)
