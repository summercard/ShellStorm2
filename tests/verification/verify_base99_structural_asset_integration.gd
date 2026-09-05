extends Node

const MEZZANINE_ID := "ENV-BASE99-MEZZANINE-20X10-Z5"
const L_STAIR_ID := "ENV-BASE99-STAIR-L-Z5"
const UNDERDECK_ID := "ENV-BASE99-MEZZANINE-UNDERDECK-BLOCKER"
const V021_IDS := [
	"ENV-BASE99-STRUCTURAL-V021::east_mezzanine_structure",
	"ENV-BASE99-STRUCTURAL-V021::east_upper_transition_stair",
	"ENV-BASE99-STRUCTURAL-V021::northwest_l_stair",
	"ENV-BASE99-STRUCTURAL-V021::underdeck_sheet_blocker",
]


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
			_expect(layout.get_child_count() == 5 and layout.get_node_or_null("100层上层围护与18米封顶") != null, "基地结构层没有完整接入四项V021结构资产", failures)
		_expect(_find_asset(facility, MEZZANINE_ID) == null, "基地仍实例化旧阁楼资产", failures)
		_expect(_find_asset(facility, L_STAIR_ID) == null, "基地仍实例化旧L型楼梯资产", failures)
		_expect(_find_asset(facility, UNDERDECK_ID) == null, "基地仍实例化旧13号阁楼下铁皮包裹区", failures)
		for asset_id in V021_IDS:
			var replacement := _find_asset(facility, asset_id)
			_expect(replacement != null and replacement.has_node("StaticCollision"), "V021结构资产未接入或缺少阻挡: %s" % asset_id, failures)
		var floor_visuals := facility.get_node_or_null("基地99层_美术布置层/BlenderV021完整地板表现_仅视觉")
		_expect(floor_visuals != null and floor_visuals.get_node_or_null("二层楼中楼地板面层_仅视觉") != null, "阁楼结构接入时误删了V020二楼地板", failures)
		var underdeck_collision_count := 0
		for body_value in facility.find_children("*", "StaticBody3D", true, false):
			var body := body_value as StaticBody3D
			if body != null and bool(body.get_meta("base99_underdeck_permanent_blocker", false)):
				underdeck_collision_count += 1
		_expect(underdeck_collision_count == 0, "基地仍保留旧13号阁楼下铁皮包裹区的阻挡", failures)
		var snapshot := facility.get_room_snapshot()
		_expect(
			int(snapshot.get("base99_mezzanine_count", 0)) == 0
			and int(snapshot.get("base99_stair_l_count", 0)) == 0
			and int(snapshot.get("base99_stair_exterior_count", 0)) == 0,
			"基地仍保留旧阁楼或楼梯实例: %s" % snapshot,
			failures
		)
	tower.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("BASE99_STRUCTURAL_ASSET_INTEGRATION_OK: four V017-derived V021 structural packages replace old base assets")
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
