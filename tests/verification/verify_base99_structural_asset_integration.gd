extends Node

const MEZZANINE_ID := "ENV-BASE99-MEZZANINE-20X10-Z5"
const L_STAIR_ID := "ENV-BASE99-STAIR-L-Z5"
const UNDERDECK_ID := "ENV-BASE99-MEZZANINE-UNDERDECK-BLOCKER"


func _ready() -> void:
	var failures: Array[String] = []
	var tower := (load("res://scenes/TowerDescent3D.tscn") as PackedScene).instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990099
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	var facility := (tower.get("_room_by_id") as Dictionary).get("facility") as DungeonRoom3D
	_expect(facility != null, "99层基地房间没有生成", failures)
	if facility != null:
		var layout := facility.get_node_or_null("基地99层_美术布置层/基地结构组件_可移动旋转")
		_expect(layout != null, "基地可编辑美术布局不存在", failures)
		if layout != null:
			_expect(layout.get_node_or_null("二层楼中楼结构与护栏_复用V020地板") != null, "阁楼结构资产没有接入正式布局", failures)
			_expect(layout.get_node_or_null("L型楼梯_一楼至二楼_Z5") != null, "L型楼梯资产没有接入正式布局", failures)
			_expect(layout.get_node_or_null("楼中楼下方工业仓库挡板_随楼板移动") == null, "已删除的下方铁门不应随阁楼重新接入", failures)
		var mezzanine := _find_asset(facility, MEZZANINE_ID)
		_expect(mezzanine != null, "基地没有实例化阁楼结构资产", failures)
		if mezzanine != null:
			_expect(
				str(mezzanine.get_meta("asset_version", "")) == "v004"
				and str(mezzanine.get_meta("visual_deck_policy", "")).contains("LOFT-FLOOR-FINISH")
				and int(mezzanine.get_meta("removed_legacy_floor_mesh_count", 0)) == 9,
				"阁楼没有使用复用V020地板的v004低面数结构资产",
				failures
			)
		var stair := _find_asset(facility, L_STAIR_ID)
		_expect(stair != null and str(stair.get_meta("asset_version", "")) == "v004", "L型楼梯没有使用账本正式v004资产", failures)
		_expect(_find_asset(facility, UNDERDECK_ID) == null, "基地仍实例化已删除的阁楼下方铁门", failures)
		var floor_visuals := facility.get_node_or_null("基地99层_美术布置层/BlenderV021完整地板表现_仅视觉")
		_expect(floor_visuals != null and floor_visuals.get_node_or_null("二层楼中楼地板面层_仅视觉") != null, "阁楼结构接入时误删了V020二楼地板", failures)
		var underdeck_collision_count := 0
		for body_value in facility.find_children("*", "StaticBody3D", true, false):
			var body := body_value as StaticBody3D
			if body != null and bool(body.get_meta("base99_underdeck_permanent_blocker", false)):
				underdeck_collision_count += 1
		_expect(underdeck_collision_count == 0, "已删除铁门的永久碰撞仍残留", failures)
		var snapshot := facility.get_room_snapshot()
		_expect(
			int(snapshot.get("base99_mezzanine_count", 0)) == 1
			and int(snapshot.get("base99_stair_l_count", 0)) == 1
			and int(snapshot.get("base99_stair_exterior_count", 0)) == 1,
			"基地结构资产实例计数不正确: %s" % snapshot,
			failures
		)
	tower.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("BASE99_STRUCTURAL_ASSET_INTEGRATION_OK: v004 deck-free mezzanine, v004 L stair, existing optimized walls, and no underdeck gate")
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
		var result := _find_asset(child, asset_id)
		if result != null:
			return result
	return null
