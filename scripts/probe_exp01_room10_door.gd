extends Node
## 专查 room_09 → room_10 那一扇门为什么被实体挡住。
##
## 做法：关掉全部门扇碰撞后，把 room_10 / room_09 在**门位附近**的所有美术子件
## 逐件列出（名字 / 组件来源 / 烘焙局部位置 / 对齐后房间局部位置 / 落面 / 是否压住门位），
## 并把该边的 `door_endpoint_owners`（谁持有门）一并打出来。
##
## 这样能直接回答三件事：
##   ① 压门的是什么件（实墙 wall_standard 还是门墙 wall_door）；
##   ② 它在本局哪一侧、哪个 lane；
##   ③ 该不该由本房持有（对照 door_endpoint_owners）。

const EXP01_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const SEEDS: Array[int] = [3198984856, 286648852, 20260919]
const HIT_RADIUS := 3.0  # 距门位多近算「附近」


func _ready() -> void:
	call_deferred("probe")


func probe() -> void:
	for seed_value in SEEDS:
		await _one(seed_value)
	print("EXP01_ROOM10_DOOR_DONE")
	get_tree().quit(0)


func _one(seed_value: int) -> void:
	var tower := EXP01_SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = seed_value
	add_child(tower)
	for _i in range(8):
		await get_tree().process_frame
		await get_tree().physics_frame
	print("")
	print("========== SEED %d ==========" % seed_value)
	# ① 本轮修复清掉了哪些墙（每房）—— 安全检查：只应清「本局门槽上的实墙」
	print("  --- authored_layout_port_walls_cleared（本房被清掉的实墙） ---")
	for key in [
		"start", "room_01", "room_02", "room_03", "room_04", "room_05",
		"room_06", "room_07", "room_08", "room_09", "room_10", "boss", "extraction",
	]:
		var room := tower._room_by_id.get(key) as DungeonRoom3D
		if room == null:
			continue
		var cleared: Array = room.get_meta("authored_layout_port_walls_cleared", []) as Array
		print("    %-11s %s" % [key, "<无>" if cleared.is_empty() else str(cleared)])
	_dump_room(tower, "room_10")
	_dump_room(tower, "room_09")
	tower.free()
	await get_tree().process_frame
	await get_tree().process_frame


func _dump_room(tower: TowerDescent3D, key: String) -> void:
	var room := tower._room_by_id.get(key) as DungeonRoom3D
	if room == null:
		print("  %s <缺>" % key)
		return
	var dims := room.get_dimensions()
	var half := dims * 0.5
	print("")
	print("  —— %s 房心=(%.2f,%.2f) dims=(%.1f,%.1f) doors=%s ——" % [
		key, room.global_position.x, room.global_position.z, dims.x, dims.y, str(room.doors),
	])
	print("     door_endpoint_owners=%s" % str(room.door_endpoint_owners))
	print("     door_targets=%s" % str(room.door_targets))
	for port_value in room.connection_ports:
		var port := port_value as Dictionary
		print("     口 %s side=%s lane=%.1f → %s (door_width=%s)" % [
			str(port.get("port_id", "?")), str(port.get("side", "")),
			float(port.get("lane_m", 0.0)), str(port.get("target_room_id", "")),
			str(port.get("door_width_m", "-")),
		])
	# 本房各门的房间局部坐标
	var doors_local: Array[Dictionary] = []
	for port_value in room.connection_ports:
		var port := port_value as Dictionary
		var side := str(port.get("side", ""))
		if side.is_empty():
			continue
		var lane := float(port.get("lane_m", 0.0))
		var local := Vector3.ZERO
		match side:
			"north":
				local = Vector3(lane, 0.0, -half.y)
			"south":
				local = Vector3(lane, 0.0, half.y)
			"east":
				local = Vector3(half.x, 0.0, lane)
			"west":
				local = Vector3(-half.x, 0.0, lane)
		doors_local.append({"side": side, "lane": lane, "local": local,
			"target": str(port.get("target_room_id", ""))})
	var art := room.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
	if art == null:
		art = room.get_node_or_null("SafeRoomArtRoot") as Node3D
	if art == null:
		print("     art=<无>")
		return
	print("     art.local_rot_y=%.1f° art.global_rot_y=%.1f°" % [
		rad_to_deg(art.rotation.y), rad_to_deg(art.global_rotation.y),
	])
	print("     %-52s %-22s %-24s %s" % ["子件（直接子）", "组件来源", "房间局部(x,z)", "落面/命中门"])
	for child in art.get_children():
		var node := child as Node3D
		if node == null:
			continue
		var room_local := room.to_local(node.global_position)
		var src := node.scene_file_path.get_file()
		if src.is_empty():
			src = "<脚本节点>"
		var side := _side_of(room_local, half)
		var hits: Array[String] = []
		for d in doors_local:
			var gap := Vector2(room_local.x - (d["local"] as Vector3).x,
				room_local.z - (d["local"] as Vector3).z).length()
			if gap <= HIT_RADIUS:
				hits.append("%s→%s(%.1f)" % [d["side"], d["target"], gap])
		# 只关注有几何的件（脚本代理节点没有 mesh）
		var has_mesh := _has_mesh(node)
		var is_door_wall := src.contains("wall_door") or src.contains("door_wall")
		var kind := "门墙" if is_door_wall else ("实墙" if src.begins_with("wall") else "")
		if hits.is_empty() and not is_door_wall and not src.begins_with("wall"):
			continue
		print("     %-52s %-22s (%7.2f,%7.2f) %-6s %s%s" % [
			str(node.name).substr(0, 52), src.substr(0, 22), room_local.x, room_local.z,
			side, ("%s " % kind) if kind != "" else "",
			("🔴压门 " + " ".join(hits)) if not hits.is_empty() else "",
		])
		if not has_mesh:
			print("          ↑ 无网格（纯脚本代理）")


func _side_of(local: Vector3, half: Vector2) -> String:
	const TOL := 0.75
	if absf(absf(local.z) - half.y) < TOL and absf(local.x) <= half.x + TOL:
		return "north" if local.z < 0.0 else "south"
	if absf(absf(local.x) - half.x) < TOL and absf(local.z) <= half.y + TOL:
		return "west" if local.x < 0.0 else "east"
	return "内部"


func _has_mesh(node: Node) -> bool:
	if node is MeshInstance3D:
		return true
	for child in node.get_children():
		if _has_mesh(child):
			return true
	return false
