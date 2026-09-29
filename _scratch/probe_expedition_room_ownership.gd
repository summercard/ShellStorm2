extends Node
## 探针：远征01 房间**归属矩阵**实测。
## 对每个房间的中心点，列出所有 `contains_world_position` 为真的房间，
## 并打印 `_room_floor_index` 与当前物理楼层，定位「房间中心竟不属于自己」的原因。
##
## 运行：
##   export APPDATA='C:\tmp\ss2_appdata_probe'
##   "<godot-console>" --headless --path "<project>" --scene res://_scratch/probe_expedition_room_ownership.tscn

const SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const ROOM_SCRIPT := preload("res://src/world3d/DungeonRoom3D.gd")
const RUN_SEED := 77001199


func _ready() -> void:
	ROOM_SCRIPT.use_expedition_static_layout_scenes = true
	var tower := SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	add_child(tower)
	await _settle()
	var rooms := _collect_rooms(tower)
	print("EXPEDITION_ROOM_OWNERSHIP rooms=%d" % rooms.size())
	print("physical_floor_index=%s" % str(tower.call("_physical_floor_index")))
	print("_room_floor_index=%s" % str(tower.get("_room_floor_index")))
	print("_floor_room_ids=%s" % str(tower.get("_floor_room_ids")))
	for room in rooms:
		var pos := room.global_position
		var owners: Array[String] = []
		for other in rooms:
			if other.contains_world_position(pos):
				owners.append(other.room_id)
		print("%-12s pos=%s dims=%s floor_idx=%s self_contains=%s owners=%s" % [
			room.room_id, _v(pos), _v2(room.get_dimensions()),
			str(tower.get("_room_floor_index").get(room.room_id, "<未登记>")),
			str(room.contains_world_position(pos)),
			str(owners) if not owners.is_empty() else "<无房包含该点>",
		])
	print("EXPEDITION_ROOM_OWNERSHIP_DONE")
	get_tree().quit(0)


func _collect_rooms(tower: TowerDescent3D) -> Array[DungeonRoom3D]:
	var rooms: Array[DungeonRoom3D] = []
	var block := tower.get_node_or_null("Blocks/Expedition") as Node3D
	if block == null:
		return rooms
	for child in block.get_children():
		var room := child as DungeonRoom3D
		if room != null:
			rooms.append(room)
	return rooms


func _settle() -> void:
	for _index in range(6):
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.3).timeout


func _v(value: Vector3) -> String:
	return "(%.2f,%.2f,%.2f)" % [value.x, value.y, value.z]


func _v2(value: Vector2) -> String:
	return "(%.1fx%.1f)" % [value.x, value.y]
