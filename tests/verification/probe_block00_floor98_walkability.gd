extends Node
## 可通行性实测：从 99F 基底层出发，能否一路走到区块00 最里面的房间（办公室）。
##
## 这是「连通性」问题，节点存在 / 计数正确都证明不了它。本探针实测四件事：
##   1. 门目标图：从 99F 基地房出发，沿 room.door_targets 做 BFS，能否到达 floor_01_exit；
##   2. 每扇门状态：is_open / blocks_passage / requires_key / requires_clear / 门扇可见性；
##   3. 门洞物理净空：**先把全场门全部开到底**，再从门洞中心沿法向打射线，
##      看还有没有静态墙体挡在洞里（先全开可避免「对面那扇还没开」的顺序伪影）；
##   4. 清房可行性：进房后统计敌人数、以及敌人是否都落在房间内
##      —— `requires_clear` 靠「房内敌人全灭」满足，怪刷到房外就永远开不了门。
##
## 打印 PROBE_WALKABILITY_DONE 结束；只报事实，不判过/不过。

const FLOOR_INDEX := 2
const FLOOR_NUMBER := 98
const SEED := 990098
const PROBE_RAY_LENGTH := 1.6
const PROBE_RAY_HEIGHT := 0.9

var _lines: Array[String] = []


func _ready() -> void:
	var scene := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = SEED
	add_child(tower)
	await _settle()

	if not tower.generate_through_floor_for_test(FLOOR_NUMBER):
		_log("生成到 %dF 失败" % FLOOR_NUMBER)
		_finish()
		return
	await _settle()

	var room_by_id := tower.get("_room_by_id") as Dictionary
	var floor_rooms := tower.get("_floor_room_ids") as Dictionary
	if room_by_id == null or floor_rooms == null:
		_log("取不到塔楼内部状态")
		_finish()
		return

	_log("========== 楼层房间清单 ==========")
	for index_value in floor_rooms.keys():
		var index := int(index_value)
		var ids: Array[String] = []
		for id_value in floor_rooms[index_value]:
			ids.append(str(id_value))
		_log("  floor_index=%d -> %s" % [index, str(ids)])

	_log("")
	_log("========== 门目标图连通性（从 99F 起） ==========")
	_check_reachability(room_by_id, floor_rooms)

	_log("")
	_log("========== 全部门初始状态 ==========")
	_dump_all_doors(room_by_id, floor_rooms)

	_log("")
	_log("========== 98F 门洞物理净空（全部先开到底再测） ==========")
	await _ray_probe_98f_doorways(room_by_id, floor_rooms)

	_log("")
	_log("========== 98F 清房可行性（requires_clear 能否满足） ==========")
	await _probe_clear_feasibility(tower, room_by_id, floor_rooms)

	_finish()


func _finish() -> void:
	print("\n########## BLOCK00 98F 可通行性实测 ##########")
	for line in _lines:
		print(line)
	print("PROBE_WALKABILITY_DONE")
	get_tree().quit(0)


func _log(text: String) -> void:
	_lines.append(text)


func _settle() -> void:
	for i in 6:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.35).timeout


func _check_reachability(room_by_id: Dictionary, floor_rooms: Dictionary) -> void:
	var exit_id := "floor_01_exit"
	var starts: Array[String] = []
	for index in [1, 2]:
		for id_value in floor_rooms.get(index, []):
			var rid := str(id_value)
			if rid not in starts:
				starts.append(rid)
	if not room_by_id.has(exit_id):
		_log("  目标房 %s 不存在于 _room_by_id" % exit_id)
		return

	var adjacency: Dictionary = {}
	for rid in starts:
		var room := room_by_id.get(rid) as DungeonRoom3D
		if room == null:
			continue
		for side_value in room.doors:
			var target := str(room.door_targets.get(str(side_value), ""))
			if target.is_empty() or not room_by_id.has(target):
				continue
			if not adjacency.has(rid):
				adjacency[rid] = []
			(adjacency[rid] as Array).append(target)

	for start in starts:
		var visited: Dictionary = {start: true}
		var queue: Array[String] = [start]
		var predecessor: Dictionary = {}
		while not queue.is_empty():
			var current: String = queue.pop_front()
			for next_value in adjacency.get(current, []):
				var next := str(next_value)
				if visited.has(next):
					continue
				visited[next] = true
				predecessor[next] = current
				queue.append(next)
		if not visited.has(exit_id):
			_log("  从 %s 出发：到不了 %s（共探达 %d 房）" % [start, exit_id, visited.size()])
			continue
		var path: Array[String] = [exit_id]
		var cursor := exit_id
		while predecessor.has(cursor):
			cursor = str(predecessor[cursor])
			path.push_front(cursor)
		_log("  从 %s 出发：可到达 %s" % [start, exit_id])
		_log("      路径 = %s" % str(path))


func _dump_all_doors(room_by_id: Dictionary, floor_rooms: Dictionary) -> void:
	var interesting: Array[String] = []
	for index in [1, 2, 3]:
		for id_value in floor_rooms.get(index, []):
			var rid := str(id_value)
			if rid not in interesting:
				interesting.append(rid)
	for rid in interesting:
		var room := room_by_id.get(rid) as DungeonRoom3D
		if room == null:
			continue
		var sides := room.doors.duplicate()
		sides.sort()
		if sides.is_empty():
			_log("  [%s] 无门 pos=%s" % [rid, str(room.position)])
			continue
		_log(
			"  [%s] pos=%s dims=%s type=%s"
			% [rid, str(room.position), str(room.get_dimensions()), str(room.room_type)]
		)
		for side_value in sides:
			var side := str(side_value)
			var door := room.get_door_node(side)
			var target := str(room.door_targets.get(side, ""))
			if door == null:
				_log("      %-6s 门节点缺失   target=%s" % [side, target])
				continue
			var snap := door.get_snapshot()
			var panel := door.get_node_or_null("DoorPanel") as Node3D
			var panel_visible := panel.visible if panel != null else false
			_log(
				"      %-6s open=%-5s blocks=%-5s key=%-5s clear=%-5s panel_vis=%-5s target=%s"
				% [
					side,
					str(snap.get("is_open", false)),
					str(snap.get("blocks_passage", false)),
					str(snap.get("requires_key", false)),
					str(snap.get("requires_clear", false)),
					str(panel_visible),
					target,
				]
			)


## 先把 98F 全部房门开到底，再逐门打射线 —— 消除「对面门还没开」的顺序伪影。
func _ray_probe_98f_doorways(room_by_id: Dictionary, floor_rooms: Dictionary) -> void:
	var space := get_viewport().world_3d.direct_space_state
	if space == null:
		_log("  取不到物理空间（headless 下无 3D 视口）—— 跳过射线")
		return
	var ids: Array[String] = []
	for id_value in floor_rooms.get(FLOOR_INDEX, []):
		ids.append(str(id_value))
	for rid in ids:
		var room := room_by_id.get(rid) as DungeonRoom3D
		if room == null:
			continue
		for side_value in room.doors:
			room.set_door_open(str(side_value), true)
	await _settle()

	var probed := 0
	var blocked := 0
	for rid in ids:
		var room := room_by_id.get(rid) as DungeonRoom3D
		if room == null:
			continue
		for side_value in room.doors:
			var side := str(side_value)
			var door := room.get_door_node(side)
			if door == null:
				continue
			var origin := door.global_position
			var direction := Vector3.ZERO
			match side:
				"north":
					direction = Vector3(0, 0, -1)
				"south":
					direction = Vector3(0, 0, 1)
				"west":
					direction = Vector3(-1, 0, 0)
				"east":
					direction = Vector3(1, 0, 0)
			var from := origin + direction * -0.8 + Vector3(0, PROBE_RAY_HEIGHT, 0)
			var to := origin + direction * PROBE_RAY_LENGTH + Vector3(0, PROBE_RAY_HEIGHT, 0)
			var query := PhysicsRayQueryParameters3D.create(from, to)
			query.collide_with_areas = false
			query.collide_with_bodies = true
			var hit := space.intersect_ray(query)
			probed += 1
			if hit.is_empty():
				_log("  [%s] %-6s 门洞通路（射线无阻挡）" % [rid, side])
			else:
				blocked += 1
				var collider := hit.get("collider") as Node
				_log(
					"  [%s] %-6s 门洞仍被挡：%s @ %s（距起点 %.2fm）"
					% [
						rid,
						side,
						str(collider.name) if collider != null else "?",
						str(hit.get("position", Vector3.ZERO)),
						from.distance_to(hit.get("position", from)),
					]
				)
	if probed == 0:
		_log("  哨兵：98F 一扇门都没探到（射线全空跑）")
	else:
		_log("  小结：探测 %d 扇门洞，仍被挡 %d 处" % [probed, blocked])


## 把玩家挪进每间房，统计该房刷出的敌人数与位置是否都在房内。
## 注意：敌人挂在 Dungeon3D 的全局 `$ActiveEnemies`（按 enemy.room_id 归属），
## 不是房间自己的子节点。
func _probe_clear_feasibility(tower: Node, room_by_id: Dictionary, floor_rooms: Dictionary) -> void:
	var player := tower.get("player") as Node3D
	var holder := tower.get_node_or_null("ActiveEnemies")
	if player == null or holder == null:
		_log("  取不到 player 或 ActiveEnemies 容器")
		return
	var spawned := tower.get("_spawned_rooms") as Dictionary
	for id_value in floor_rooms.get(FLOOR_INDEX, []):
		var rid := str(id_value)
		var room := room_by_id.get(rid) as DungeonRoom3D
		if room == null:
			continue
		var center := room.global_position
		player.global_position = Vector3(center.x, center.y + 1.0, center.z)
		await _settle()
		var stream_state := ""
		if room.has_method("get_stream_state"):
			stream_state = str(room.call("get_stream_state"))
		# 瞬移不一定触发房间进入事件；未登记为「已访问」时显式补一次，
		# 否则刷怪根本没发生，会把「没刷怪」误报成「房里有怪」。
		var entered_naturally := spawned != null and spawned.has(rid)
		if not entered_naturally:
			tower.call("_on_room_entered", room)
			await _settle()
		var count := _count_room_enemies(holder, rid)
		# 仍然 0 只时，直接调刷怪入口，看它自己的返回值（区分「没触发」与「刷 0」）。
		var direct_ok := ""
		if count == 0 and str(room.room_type) in ["COMBAT", "ELITE", "BOSS", "TRAP", "BASEMENT"]:
			direct_ok = str(bool(tower.call("_spawn_room_enemies", room)))
			await _settle()
			count = _count_room_enemies(holder, rid)
		var dims := room.get_dimensions()
		var half_x := dims.x * 0.5
		var half_z := dims.y * 0.5
		var outside := 0
		var positions: Array[String] = []
		for child in holder.get_children():
			var enemy := child as Enemy3D
			if enemy == null or not is_instance_valid(enemy):
				continue
			if str(enemy.room_id) != rid:
				continue
			var local_x := enemy.global_position.x - center.x
			var local_z := enemy.global_position.z - center.z
			var inside := absf(local_x) <= half_x + 0.6 and absf(local_z) <= half_z + 0.6
			if not inside:
				outside += 1
				positions.append(str(enemy.global_position))
		_log(
			"  [%s] type=%s dims=%s stream=%s 自然触发=%s 直接刷怪=%s 敌人数=%d 出界=%d cleared=%s"
			% [
				rid,
				str(room.room_type),
				str(dims),
				stream_state,
				str(entered_naturally),
				direct_ok,
				count,
				outside,
				str(bool(room.get("cleared"))),
			]
		)
		if outside > 0:
			_log("      出界敌人坐标 = %s" % str(positions))
	_log("  全场 ActiveEnemies 子节点数 = %d" % holder.get_child_count())


func _count_room_enemies(holder: Node, room_id: String) -> int:
	var count := 0
	for child in holder.get_children():
		var enemy := child as Enemy3D
		if enemy == null or not is_instance_valid(enemy):
			continue
		if str(enemy.room_id) == room_id:
			count += 1
	return count
