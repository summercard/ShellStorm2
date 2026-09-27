extends Node3D
## 诊断 v3（只读）：把通道桥房的真实摆位槽位 dump 出来 —— 主层地砖 vs 坑底/坑壁，
## 用来判定「刷怪候选点是否落在坑区空洞上」。

const SCENE := preload("res://scenes/ExpeditionLevel01_3D.tscn")
const TARGET := "room_05"

var tower: TowerDescent3D


func _ready() -> void:
	tower = SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 700000
	add_child(tower)
	await _settle(10)
	var room := tower._room_by_id.get(TARGET) as DungeonRoom3D
	if room == null:
		print("BRIDGE_DUMP no room %s" % TARGET)
		get_tree().quit(1)
		return
	room.ensure_shell_built()
	room.ensure_detail_built()
	await _settle(3)
	print("BRIDGE_DUMP room=%s dims=%s size_class=%s authored_shell=%s" % [
		room.room_id, str(room.get_dimensions()), room.size_class, str(room.authored_layout_shell),
	])
	var main_cells: Array[Vector3] = []
	var other: Array[String] = []
	for value in room.authored_layout_instances:
		var instance := value as Dictionary
		var role := str(instance.get("slot_role", ""))
		var position := instance.get("position", Vector3.ZERO) as Vector3
		if role == "floor_tile":
			main_cells.append(position)
		else:
			other.append("%s part=%s pos=(%.2f,%.2f,%.2f)" % [
				role, str(instance.get("part", "")), position.x, position.y, position.z,
			])
	var ys: Dictionary = {}
	for cell in main_cells:
		ys[snappedf(cell.y, 0.01)] = int(ys.get(snappedf(cell.y, 0.01), 0)) + 1
	print("BRIDGE_DUMP floor_tile count=%d y_histogram=%s" % [main_cells.size(), str(ys)])
	print("BRIDGE_DUMP other_slots=%d" % other.size())
	for line in other:
		print("BRIDGE_SLOT %s" % line)
	print("BRIDGE_DUMP pit_plan=%s" % str(_plan(room)))
	for index in 12:
		var point := room.spawn_point_for_index(index)
		if point.is_finite():
			var local := room.to_local(point)
			print("BRIDGE_SPAWN index=%d local=(%.2f,%.2f,%.2f)" % [index, local.x, local.y, local.z])
	print("BRIDGE_DUMP_DONE")
	get_tree().quit(0)


func _plan(room: DungeonRoom3D) -> Dictionary:
	var record: Dictionary = room.plan_record if room != null else {}
	var templates := room.get("_templates") as Dictionary if room.get("_templates") != null else {}
	var plan := FloorPlanGenerator._bridge_multi_level_plan(record, templates)
	if plan.has("pit_rect"):
		var pit := plan["pit_rect"] as Rect2
		var bridge := plan["bridge_rect"] as Rect2
		return {
			"pit": [pit.position.x, pit.position.y, pit.size.x, pit.size.y],
			"bridge": [bridge.position.x, bridge.position.y, bridge.size.x, bridge.size.y],
			"depth": plan.get("depth_m", 0.0),
			"instances": (plan.get("instances", []) as Array).size(),
		}
	return {}


func _settle(frames: int) -> void:
	for _index in frames:
		await get_tree().process_frame
		await get_tree().physics_frame
