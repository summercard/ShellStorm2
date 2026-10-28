extends Node3D
## 探针：真实加载 `ExpeditionLevel03_3D.tscn`，确认 flow 模式真的建出了房间。
##
## 用 tscn 场景而不是 `--script`：后者不加载 autoload（`AudioManager` /
## `GameplaySpatialRegistry3D` 等），整个场景链会编译失败，验不出任何东西。
##
## godot --headless --path . res://tests/verification/probe_expedition03_runtime.tscn

const LEVEL_SCENE := "res://scenes/ExpeditionLevel03_3D.tscn"

func _ready() -> void:
	await get_tree().process_frame
	var packed: PackedScene = load(LEVEL_SCENE)
	if packed == null:
		print("RUNTIME_PROBE_FAIL: 场景加载失败")
		get_tree().quit(1)
		return
	var scene := packed.instantiate()
	add_child(scene)
	for i in range(300):
		await get_tree().process_frame
		var rv: Variant = scene.get("_rooms")
		if rv is Array and (rv as Array).size() >= 10:
			break
	# 启动前置条件：规划有效、没有 bootstrap 失败、没有冲突。
	var conflicts: Array = scene.get("_floor_layout_plan_conflicts") as Array
	var failed := bool(scene.get("_expedition_bootstrap_failed"))
	var snaps: Dictionary = scene.get("_floor_plan_snapshots") as Dictionary
	var plan: Dictionary = snaps.get(0, {}) as Dictionary
	print("RUNTIME_PROBE plan_valid=%s plan_rooms=%d mode=%s" % [
		str(plan.get("valid")), (plan.get("rooms", []) as Array).size(), str(plan.get("mode"))])
	if failed or not conflicts.is_empty() or not bool(plan.get("valid", false)):
		print("RUNTIME_PROBE FAIL: bootstrap_failed=%s conflicts=%s" % [
			str(failed), str(conflicts.slice(0, 3))])
		get_tree().quit(1)
		return
	# 房间挂在 `_room_block_for_floor(floor_index)` 返回的 Blocks 子节点下，
	# 不是 `GeneratedRooms`（那个只给旧的程序化路径用）。权威清单是 `_rooms`。
	var rooms_value: Variant = scene.get("_rooms")
	var rooms: Array = rooms_value as Array if rooms_value is Array else []
	print("RUNTIME_PROBE rooms=%d" % rooms.size())
	var names: Array[String] = []
	var with_mesh := 0
	var with_collision := 0
	var total_mesh := 0
	var total_collision := 0
	for room in rooms:
		names.append(str(room.name))
		var m := _count_type(room, "MeshInstance3D")
		var c := _count_type(room, ["CollisionShape3D", "StaticBody3D"])
		total_mesh += m
		total_collision += c
		if m > 0:
			with_mesh += 1
		if c > 0:
			with_collision += 1
	names.sort()
	print("RUNTIME_PROBE names=%s" % str(names))
	print("RUNTIME_PROBE with_mesh=%d with_collision=%d mesh_total=%d collision_total=%d" % [
		with_mesh, with_collision, total_mesh, total_collision])
	var ok := rooms.size() >= 10 and with_mesh >= 10 and with_collision >= 10
	print("RUNTIME_PROBE %s" % ("OK" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


func _count_type(node: Node, types) -> int:
	var want: Array = types if types is Array else [types]
	var count := 0
	for child in node.get_children():
		if str(child.get_class()) in want or child.is_class(str(want[0])):
			count += 1
		count += _count_type(child, types)
	return count
