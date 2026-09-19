extends Node
## 一次性探针：实测门节点成本，并复刻 verify_3d_performance_budget.gd 的四个计数器，
## 用于把门扇换成正式美术后重定「初始永久外壳」基线。
## 计数口径与门禁逐字一致（_count_nodes / _count_world_nodes / _count_canvas_nodes /
## _count_item_preview_nodes）。

var _doors := 0
var _proc := 0
var _imported := 0
var _door_nodes := 0


func _ready() -> void:
	var scene: PackedScene = load("res://scenes/levels3d/AbyssArchive3D.tscn")
	var dungeon: Dungeon3D = scene.instantiate() as Dungeon3D
	dungeon.test_mode = true
	dungeon.run_seed_override = 4242
	add_child(dungeon)
	await get_tree().process_frame
	await get_tree().physics_frame

	var initial_nodes := _count_nodes(dungeon)
	var initial_world := _count_world_nodes(dungeon)
	var hud_nodes := _count_canvas_nodes(dungeon)
	var hud_preview := _count_item_preview_nodes(dungeon)
	var hud_shell := hud_nodes - hud_preview
	print("PROBE_INITIAL world=%d hud_shell=%d hud_preview=%d hud_total=%d total=%d" % [
		initial_world, hud_shell, hud_preview, hud_nodes, initial_nodes,
	])
	_scan(dungeon)
	var avg := 0.0
	if _doors > 0:
		avg = float(_door_nodes) / float(_doors)
	print("PROBE_DOORS doors=%d procedural_panel=%d imported_leaf=%d door_subtree_nodes=%d avg_per_door=%.2f" % [
		_doors, _proc, _imported, _door_nodes, avg,
	])

	var generation: Dictionary = dungeon.get_generation_snapshot()
	for record in generation.get("records", []):
		var room_id := str(record.get("id", ""))
		var parent_id := str(record.get("parent", ""))
		if not parent_id.is_empty():
			dungeon.force_open_edge_for_test(parent_id, room_id)
		dungeon.force_enter_room_for_test(room_id)
		await get_tree().process_frame
	print("PROBE_EXPLORED world=%d total=%d" % [
		_count_world_nodes(dungeon), _count_nodes(dungeon),
	])
	get_tree().quit(0)


func _scan(root: Node) -> void:
	if root is RoomDoor3D:
		_doors += 1
		_door_nodes += _count_nodes(root)
		if root.get_node_or_null("DoorPanel/ProceduralDoorPanel") != null:
			_proc += 1
		if root.get_node_or_null("DoorPanel/ImportedDoorVisual") != null:
			_imported += 1
	for child in root.get_children():
		_scan(child)


func _count_nodes(root: Node) -> int:
	var count := 1
	for child in root.get_children():
		count += _count_nodes(child)
	return count


func _count_world_nodes(root: Node) -> int:
	var count := 1
	for child in root.get_children():
		if child is CanvasLayer:
			continue
		count += _count_world_nodes(child)
	return count


func _count_canvas_nodes(root: Node) -> int:
	var count := 0
	for child in root.get_children():
		if child is CanvasLayer:
			count += _count_nodes(child)
		else:
			count += _count_canvas_nodes(child)
	return count


func _count_item_preview_nodes(root: Node) -> int:
	var count := 0
	if root is ItemModelIcon3D:
		return _count_nodes(root)
	for child in root.get_children():
		count += _count_item_preview_nodes(child)
	return count
