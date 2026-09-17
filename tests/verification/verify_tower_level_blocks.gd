extends Node
## WORLD-BLOCKS：验证四区块、短命名、楼层归属和首两段楼梯资产映射。


func _ready() -> void:
	var failures: Array[String] = []
	if not ResourceLoader.exists("res://assets/art/environments/tower_zones/rooftop/runtime/zone_rooftop.tscn", "PackedScene"):
		failures.append("zone_rooftop_v021.tscn cannot load")
	if not ResourceLoader.exists("res://assets/art/environments/tower_zones/base/runtime/zone_base.tscn", "PackedScene"):
		failures.append("zone_base_v002.tscn cannot load")

	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 1009998
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame

	var blocks := tower.get_node_or_null("Blocks") as Node3D
	if blocks == null:
		failures.append("Blocks root is missing")
	else:
		var expected := ["Rooftop", "Base", "Battle", "Stairs"]
		var actual: Array[String] = []
		for child in blocks.get_children():
			actual.append(str(child.name))
		if actual != expected:
			failures.append("block roots are %s, expected %s" % [actual, expected])
		for block_name in expected:
			var block := blocks.get_node_or_null(block_name) as Node3D
			if block == null or str(block.get_meta("block_id", "")) != block_name.to_lower():
				failures.append("%s block metadata is missing" % block_name)
			elif str(block.get_meta("runtime_owner", "")) != "TowerDescent3D":
				failures.append("%s runtime owner metadata is missing" % block_name)

	var rooms := tower.get("_room_by_id") as Dictionary
	_validate_room_parent(rooms, "start", "Rooftop", failures)
	_validate_room_parent(rooms, "facility", "Base", failures)
	_validate_room_parent(rooms, "floor_01_entry", "Battle", failures)
	var stages := tower.get("_floor_stages") as Dictionary
	_validate_floor_stage(stages, 0, "Floor_100", "Rooftop", failures)
	_validate_floor_stage(stages, 1, "Floor_99", "Base", failures)
	_validate_floor_stage(stages, 2, "Floor_98", "Battle", failures)

	var stair_names: Array[String] = []
	var stair_assets: Array[String] = []
	for value in (tower.get("_corridor_by_edge") as Dictionary).values():
		var connector := value as Node3D
		if connector == null or not bool(connector.get_meta("is_vertical_connector", false)):
			continue
		stair_names.append(str(connector.name))
		stair_assets.append(str(connector.get_meta("stair_asset_id", "")))
		if connector.get_parent() == null or connector.get_parent().name != "Stairs":
			failures.append("%s is outside Blocks/Stairs" % connector.name)
	stair_names.sort()
	stair_assets.sort()
	if stair_names != ["Stair_A", "Stair_B"]:
		failures.append("initial stairs are %s" % stair_names)
	if stair_assets != ["ENV-TOWER-STAIRWELL-GENERIC-12M", "ENV-TOWER-STAIRWELL-ROOFTOP-12M"]:
		failures.append("initial stair AssetIDs are %s" % stair_assets)

	tower.queue_free()
	await get_tree().process_frame
	_finish(failures)


func _validate_room_parent(
	rooms: Dictionary,
	room_id: String,
	expected_block: String,
	failures: Array[String]
) -> void:
	var room := rooms.get(room_id) as DungeonRoom3D
	if room == null:
		failures.append("%s room is missing" % room_id)
		return
	if room.name != room_id:
		failures.append("%s node name is %s" % [room_id, room.name])
	if room.get_parent() == null or room.get_parent().name != expected_block:
		failures.append("%s is outside Blocks/%s (actual: %s)" % [
			room_id,
			expected_block,
			str(room.get_path()),
		])


func _validate_floor_stage(
	stages: Dictionary,
	floor_index: int,
	expected_name: String,
	expected_block: String,
	failures: Array[String]
) -> void:
	var stage := stages.get(floor_index) as Node3D
	if stage == null:
		failures.append("%s stage is missing" % expected_name)
		return
	if stage.name != expected_name:
		failures.append("floor stage %d name is %s" % [floor_index, stage.name])
	if stage.get_parent() == null or stage.get_parent().name != expected_block:
		failures.append("%s is outside Blocks/%s" % [expected_name, expected_block])


func _finish(failures: Array[String]) -> void:
	if failures.is_empty():
		print("TOWER_LEVEL_BLOCKS_OK: Rooftop/Base/Battle/Stairs and source mappings pass")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error(failure)
	get_tree().quit(1)
