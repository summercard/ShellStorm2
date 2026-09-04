extends Node

const REMOVED_ASSET_IDS := [
	"ENV-BASE99-MEZZANINE-20X10-Z5",
	"ENV-BASE99-STAIR-L-Z5",
	"ENV-BASE99-MEZZANINE-UNDERDECK-BLOCKER",
]
const FLOOR_VISUAL_LAYOUT_ID := "ENV-BASE99-FLOOR-VISUAL-LAYOUT-V017"


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
	if facility != null:
		var layout := facility.get_node_or_null("基地99层_美术布置层/基地结构组件_可移动旋转")
		_expect(layout != null, "基地可编辑美术布局不存在", failures)
		if layout != null:
			for removed_name in ["二层楼中楼楼板_20x10米_Z5", "L型楼梯_一楼至二楼_Z5"]:
				_expect(
					layout.get_node_or_null(removed_name) == null,
					"基地布局仍包含应删除的旧摆设: %s" % removed_name,
					failures
				)
		for asset_id in REMOVED_ASSET_IDS:
			_expect(
				_find_asset(facility, asset_id) == null,
				"基地运行时仍实例化已移除资产: %s" % asset_id,
				failures
			)
		var underdeck_blocker_count := 0
		for body_value in facility.find_children("*", "StaticBody3D", true, false):
			var body := body_value as StaticBody3D
			if body != null and bool(body.get_meta("base99_underdeck_permanent_blocker", false)):
				underdeck_blocker_count += 1
		_expect(underdeck_blocker_count == 0, "基地仍残留阁楼下方铁门的永久碰撞", failures)
		var floor_visuals := facility.get_node_or_null("基地99层_美术布置层/BlenderV021完整地板表现_仅视觉")
		_expect(floor_visuals != null, "完整地板表现根节点缺失", failures)
		if floor_visuals != null:
			_expect(
				str(floor_visuals.get_meta("asset_id", "")) == FLOOR_VISUAL_LAYOUT_ID
				and str(floor_visuals.get_meta("source_blender_version", "")) == "v020"
				and floor_visuals.get_node_or_null("二层楼中楼地板面层_仅视觉") != null,
				"清理旧阁楼架时误删或替换了Blender V020新增二楼地板",
				failures
			)
		var snapshot := facility.get_room_snapshot()
		_expect(
			int(snapshot.get("base99_mezzanine_count", -1)) == 0
			and int(snapshot.get("base99_stair_l_count", -1)) == 0
			and int(snapshot.get("base99_stair_exterior_count", -1)) == 1,
			"基地楼梯/阁楼布局快照不符合清理后的保留范围: %s" % snapshot,
			failures
		)
	tower.queue_free()
	await get_tree().process_frame
	if failures.is_empty():
		print("BASE99_MEZZANINE_PLACEMENT_REMOVAL_OK: old L stair, mezzanine rack and underdeck iron gate are absent; V020 loft floor finish remains")
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
