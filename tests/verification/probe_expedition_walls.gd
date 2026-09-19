extends Node
## 临时探针：实测远征关卡01 的「房间包围 + 走廊地面/侧墙」物理真值。
## 只读物理空间，不修改任何运行内容。

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const SIDE_DIRS := {
	"north": Vector3(0, 0, -1),
	"south": Vector3(0, 0, 1),
	"west": Vector3(-1, 0, 0),
	"east": Vector3(1, 0, 0),
}
const SIDES: Array[String] = ["north", "south", "west", "east"]


func _ready() -> void:
	var scene := load(EXPEDITION_SCENE) as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 77001199
	add_child(tower)
	for _index in range(4):
		await get_tree().process_frame
		await get_tree().physics_frame

	print("=== 上下文 ===")
	print("玩家位置 = %s" % (str(tower.player.global_position) if tower.player != null else "无"))
	print("当前房(内部) = %s" % str(tower.get("_current_room_id")))
	var stages: Dictionary = tower.get("_floor_stages")
	for key in stages.keys():
		var stage := stages[key] as Node3D
		if stage == null:
			continue
		print("  舞台 %s  pos=%s  path=%s" % [
			str(key), str(stage.global_position), str(stage.get_path()).replace("/root/", ""),
		])
		var snapshot: Dictionary = stage.get_snapshot()
		print("      grid_dimensions=%s  floor_world_rect=%s  support_rect_count=%s" % [
			str(snapshot["grid_dimensions"]),
			str(snapshot["floor_world_rect"]),
			str(snapshot["support_rect_count"]),
		])
		print("      outer_grid_dimensions=%s  outer_world_rect=%s  outer_wall_height=%.2f" % [
			str(snapshot["outer_grid_dimensions"]),
			str(snapshot["outer_world_rect"]),
			float(snapshot["outer_wall_height"]),
		])
		print("      force_standard_map=%s  block_id=%s" % [
			str(snapshot["force_standard_map"]), str(stage.get_meta("block_id")),
		])

	var block := tower.get_node_or_null("Blocks/Expedition") as Node3D
	print("")
	print("=== 逐房：脚下楼面 + 四向 20m 是否撞墙 ===")
	for child in block.get_children():
		var room := child as DungeonRoom3D
		if room == null:
			continue
		var center := room.global_position
		var down := _cast(center + Vector3(0, 3.0, 0), center + Vector3(0, -3.0, 0))
		var line := "  %-11s 楼面->%-42s" % [room.room_id, _short(down)]
		for side in SIDES:
			var direction := SIDE_DIRS[side] as Vector3
			var hit := _cast(center + Vector3(0, 1.5, 0), center + Vector3(0, 1.5, 0) + direction * 20.0)
			var distance := -1.0
			if not hit.is_empty():
				distance = (hit["position"] as Vector3).distance_to(center + Vector3(0, 1.5, 0))
			line += "  %s=%s" % [side.substr(0, 1).to_upper(), ("%.1fm" % distance) if distance >= 0.0 else "×"]
		print(line)

	print("")
	print("=== 逐走廊：地面 + 两侧墙 + 碰撞体诊断 ===")
	var corridors := _collect_corridors(tower)
	for corridor in corridors:
		var start := corridor.get_meta("start_door_position", Vector3.ZERO) as Vector3
		var end := corridor.get_meta("end_door_position", Vector3.ZERO) as Vector3
		var mid := (start + end) * 0.5
		var dir := (end - start).normalized()
		var perp := Vector3(-dir.z, 0, dir.x)
		var down := _cast(mid + Vector3(0, 2.0, 0), mid + Vector3(0, -2.0, 0))
		var left := _cast(mid + Vector3(0, 1.5, 0), mid + Vector3(0, 1.5, 0) + perp * 3.5)
		var right := _cast(mid + Vector3(0, 1.5, 0), mid + Vector3(0, 1.5, 0) - perp * 3.5)
		print("  %s ←→ %s  (len=%.1f)" % [
			str(corridor.get_meta("from_room_id", "?")),
			str(corridor.get_meta("to_room_id", "?")),
			start.distance_to(end),
		])
		print("      mid=%s  visible=%s  parent=%s" % [
			str(mid), str(corridor.visible), str(corridor.get_parent().name),
		])
		print("      地面->%s   左墙->%s   右墙->%s" % [
			_short(down), _short(left), _short(right),
		])
		for body_name in ["CorridorWallCollision_LBody", "CorridorWallCollision_RBody"]:
			var body := corridor.get_node_or_null(body_name) as StaticBody3D
			if body == null:
				print("      %s  缺失" % body_name)
				continue
			var shape_node := body.get_child(0) as CollisionShape3D
			var box := shape_node.shape as BoxShape3D if shape_node != null else null
			print("      %s  world=%s  size=%s  enabled=%s  layer=%d" % [
				body_name,
				str(body.global_position),
				str(box.size) if box != null else "?",
				str(not shape_node.disabled) if shape_node != null else "?",
				body.collision_layer,
			])
	await _probe_corridor_streaming(tower)
	get_tree().quit(0)


func _probe_corridor_streaming(tower: TowerDescent3D) -> void:
	print("")
	print("=== 走廊流送契约：开门后通道是否真的可见可撞 ===")
	var open_edges := tower.get("_open_edges") as Dictionary
	var corridor_by_edge := tower.get("_corridor_by_edge") as Dictionary
	var current_id := str(tower.get("_current_room_id"))
	print("  当前房 = %s   open_edges 初始 = %s" % [current_id, str(open_edges)])
	for edge_value in corridor_by_edge.keys():
		var edge := str(edge_value)
		var corridor := corridor_by_edge[edge_value] as Node3D
		if corridor == null:
			continue
		var start := corridor.get_meta("start_door_position", Vector3.ZERO) as Vector3
		var end := corridor.get_meta("end_door_position", Vector3.ZERO) as Vector3
		var mid := (start + end) * 0.5
		var dir := (end - start).normalized()
		var perp := Vector3(-dir.z, 0, dir.x)
		open_edges[edge] = true
		tower.call("_update_corridor_streaming", current_id)
		await get_tree().physics_frame
		var left := _cast(mid + Vector3(0, 1.5, 0), mid + Vector3(0, 1.5, 0) + perp * 3.5)
		var right := _cast(mid + Vector3(0, 1.5, 0), mid + Vector3(0, 1.5, 0) - perp * 3.5)
		print("  %-28s 置为开启后 visible=%s  左墙->%s  右墙->%s" % [
			edge, str(corridor.visible), _short(left), _short(right),
		])
	open_edges.clear()


func _collect_corridors(tower: Node) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for node in tower.find_children("Corridor_*", "", true, false):
		var corridor := node as Node3D
		if corridor != null:
			out.append(corridor)
	return out


func _short(hit: Dictionary) -> String:
	if hit.is_empty():
		return "!! 未命中"
	var collider := hit.get("collider") as Node
	var path := str(collider.get_path()).replace("/root/", "") if collider != null else "?"
	return "%s @y=%.2f" % [path.get_file(), (hit["position"] as Vector3).y]


func _cast(from: Vector3, to: Vector3) -> Dictionary:
	var space := get_viewport().world_3d.direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return space.intersect_ray(query)
