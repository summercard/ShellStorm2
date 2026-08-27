extends Node

const ASSET_ID := "ENV-BASE99-MEZZANINE-UNDERDECK-BLOCKER"
const EXPECTED_ASSET_VERSION := "v002"
const EXPECTED_BLOCKER_COUNT := 3
const MAX_BLOCKER_TOP_M := 4.96


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
		_expect(str(blocker.get_meta("asset_id", "")) == ASSET_ID, "挡板资产ID不正确", failures)
		_expect(str(blocker.get_meta("asset_version", "")) == EXPECTED_ASSET_VERSION, "挡板没有使用灰色横向分板v002资产", failures)
		_expect(absf(float(blocker.get_meta("frame_inset_m", -1.0)) - 0.55) <= 0.001, "挡板没有保留0.55米内收契约", failures)
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
	tower.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("BASE99_MEZZANINE_UNDERDECK_BLOCKER_OK: inset warehouse visual and permanent underdeck blockers pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)


func _expect(condition: bool, message: String, failures: Array[String]) -> void:
	if not condition:
		failures.append(message)


func _find_asset(root: Node, asset_id: String) -> Node:
	if str(root.get_meta("asset_id", "")) == asset_id:
		return root
	for child in root.get_children():
		var found := _find_asset(child, asset_id)
		if found != null:
			return found
	return null
