extends Node
## 探针：办公室（room_03）门墙与门扇是否按关卡规范工作、开门是否真的会动。

const EXPEDITION_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const RUN_SEED := 77001199
const TARGET_ROOM := "room_03"


func _ready() -> void:
	var level := EXPEDITION_SCENE.instantiate() as TowerDescent3D
	level.test_mode = true
	level.run_seed_override = RUN_SEED
	add_child(level)
	await _frames(12)

	var room := _find_room(TARGET_ROOM)
	if room == null:
		print("!! 未找到 %s" % TARGET_ROOM)
		get_tree().quit(1)
		return
	print("---- %s doors=%s ----" % [TARGET_ROOM, str(room.doors)])
	_dump_door_walls(room)
	_dump_doors(room, "开门前")

	# 最低层 API：直接把门设成开启（绕开清房/钥匙/命运等玩法门禁）。
	for direction in room.doors:
		room.set_door_open(str(direction), true, false)
	await _frames(40)
	_dump_doors(room, "room.set_door_open(true) 之后")

	# 玩法层：把当前房间设成 room_03 再走正式开门通道。
	level.set("_current_room_id", TARGET_ROOM)
	level.set("_active_room_id", TARGET_ROOM)
	await _frames(2)
	for direction in room.doors:
		var target := str(room.door_targets.get(direction, ""))
		var opened: bool = level.call("_try_open_room_door", target)
		print("  玩法层开门 %s → %s = %s" % [str(direction), target, str(opened)])
	await _frames(40)
	_dump_doors(room, "玩法层开门之后")
	print("PROBE_OFFICE_DOOR_DONE")
	get_tree().quit(0)


func _find_room(room_id: String) -> DungeonRoom3D:
	for value in get_tree().get_nodes_in_group("dungeon_room_3d"):
		var room := value as DungeonRoom3D
		if room != null and room.authored_layout_room_id == room_id:
			return room
	return null


func _dump_door_walls(room: DungeonRoom3D) -> void:
	print("  -- 本房门墙/墙件（带 tower_wall_direction）--")
	var stack: Array[Node] = [room]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		var node3d := node as Node3D
		if node3d == null:
			continue
		var direction := str(node3d.get_meta("tower_wall_direction", ""))
		if direction.is_empty():
			continue
		print(
			"     %-28s dir=%-5s rot=%6.1f° pos=(%.2f, %.2f, %.2f) cid=%s 提升=%s 源=%s"
			% [
				node3d.name,
				direction,
				rad_to_deg(node3d.rotation.y),
				node3d.position.x,
				node3d.position.y,
				node3d.position.z,
				str(node3d.get_meta("authored_component_id", "")),
				str(node3d.get_meta("authored_door_wall_promoted", false)),
				str(node3d.get_meta("authored_source_component_id", "")),
			]
		)


func _dump_doors(room: DungeonRoom3D, label: String) -> void:
	print("  -- 门节点（%s）--" % label)
	var doors := room.get("_door_nodes") as Dictionary
	for key in doors:
		var door := doors[key] as RoomDoor3D
		if door == null:
			print("     %s = null" % str(key))
			continue
		var panel := door.get_node_or_null("DoorPanel") as Node3D
		var collision := door.get_node_or_null("DoorCollision") as CollisionShape3D
		var visual := door.get_node_or_null("DoorPanel/ImportedDoorVisual") as Node3D
		var snapshot := door.get_snapshot()
		print(
			"     %-6s is_open=%-5s 运动中=%-5s panel_y=%6.3f 碰撞禁用=%-5s panel可见=%s 视觉asset=%s"
			% [
				str(key),
				str(door.is_open),
				str(door.is_in_motion()),
				panel.position.y if panel != null else -1.0,
				str(collision.disabled) if collision != null else "无碰撞节点",
				str(panel.visible) if panel != null else "无面板",
				str(visual.get_meta("asset_id", "")) if visual != null else "无视觉",
			]
		)
		print(
			"            策略 key=%s clear=%s fate=%s 闭y=%.3f 碰撞y=%.3f 时长=%.3f"
			% [
				str(door.requires_key),
				str(door.requires_clear),
				str(door.triggers_fate),
				float(snapshot.get("panel_y", -1.0)),
				float(snapshot.get("collision_y", -1.0)),
				float(snapshot.get("motion_duration_s", -1.0)),
			]
		)


func _frames(count: int) -> void:
	for _index in range(count):
		await get_tree().process_frame
