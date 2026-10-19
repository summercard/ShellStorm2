extends Node

## 一次性探针：按**真实游戏流程**（`test_mode = false`）进远征 01，回答
## 「按 E 传送进暗门之后，到底落在哪儿、落点周围有没有子图房间」。
##
## 为什么要这个探针（业主 2026-10-19 反馈）：
##   「我可以看到了，也可以打破墙，但是我点击 E 后，传送会传送到空房间，
##     好像没有装配支线的房间。」
##   验收套件里 A9/A15/A16 都是绿的，说明「能传送 / 有返程门 / 内部有门」这几件事
##   在**验收种子**下成立 —— 但那是断言，不是玩家的眼睛。玩家看到的是「一片空」。
##   所以这里不打断言，只把事实逐条打出来：
##     · 传送落点（世界坐标）与玩家实际坐标；
##     · 每个子图房间节点在不在树里、壳体建没建、加载的是哪份美术、有几件可视件；
##     · 落点周围 40m 内的可视件数量（= 玩家眼里有没有东西）；
##     · 子图房间的可视包围盒相对落点在哪。
##
## 用法：
##   godot --headless --path . res://tests/verification/probe_secret_branch_landing.tscn
##   SS2_SEED=1122239949 ...   # 指定种子

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const WAIT_LIMIT_S := 45.0
## 落点周围这个半径内数可视件 —— 视野量级，不是精确几何。
const AROUND_RADIUS_M := 40.0

var _tower: TowerDescent3D = null
var _branch: Node3D = null


func _ready() -> void:
	var seed_env := OS.get_environment("SS2_SEED")
	var scene := load(EXPEDITION_SCENE) as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = false
	if not seed_env.is_empty():
		tower.run_seed_override = int(seed_env)
	_tower = tower
	add_child(tower)

	var waited := 0.0
	while waited < WAIT_LIMIT_S:
		await get_tree().process_frame
		waited += get_process_delta_time()
		var branch := tower.get_node_or_null("SecretBranches")
		if branch != null and not (tower.get("_records") as Array).is_empty():
			await get_tree().process_frame
			await get_tree().process_frame
			_branch = branch as Node3D
			break

	print("")
	print("=== 真实流程：破板 → 按 E → 落点核对  seed=%s 等待=%.1fs ===" % [
		seed_env if not seed_env.is_empty() else "<随机器>", waited,
	])
	if _branch == null:
		print("**SecretBranches 不存在，后面全部无法核对**")
		print("BRANCH_LANDING_PROBE_END")
		get_tree().quit(0)
		return

	_dump_branch_config()
	_dump_rooms()
	await _break_and_teleport()
	_dump_around_player()
	print("")
	print("BRANCH_LANDING_PROBE_END")
	get_tree().quit(0)


func _dump_branch_config() -> void:
	print("[配置] level_id=%s  origin=%s  pairs=%s" % [
		str(_branch.get("_level_id")),
		str(_branch.get("_origin")),
		str((_branch.get("_pairs") as Dictionary).keys()),
	])
	print("[配置] _room_templates=%d 项  keys=%s" % [
		(_branch.get("_room_templates") as Dictionary).size(),
		str((_branch.get("_room_templates") as Dictionary).keys()),
	])


## 子图房间事实：节点在不在、壳体建没建、加载的是哪份美术、有几件可视件。
func _dump_rooms() -> void:
	var rows: Dictionary = _branch.get("_branch_rooms") as Dictionary
	print("[子图] 登记房间=%d 项" % rows.size())
	for room_id in rows:
		var row := rows[room_id] as Dictionary
		var room := row.get("room") as DungeonRoom3D
		if room == null:
			print("  %-24s **节点为空**" % str(room_id))
			continue
		var dims: Vector2 = room.call("get_dimensions")
		var meshes := room.find_children("*", "VisualInstance3D", true, false)
		var lights := room.find_children("*", "Light3D", true, false)
		var aabb := _subtree_visible_box(room)
		print("  %-24s pos=(%8.1f,%6.1f,%8.1f) dims=%sx%s 在树=%s 可见=%s 可视件=%d 灯=%d" % [
			str(room_id), room.global_position.x, room.global_position.y, room.global_position.z,
			str(dims.x), str(dims.y), str(room.is_inside_tree()), str(room.is_visible_in_tree()),
			meshes.size(), lights.size(),
		])
		print("      壳体路径=%s  已加载=%s  壳体根=%s" % [
			str(room.get_meta("static_layout_scene_path", "<无>")),
			str(room.get_meta("static_layout_scene_loaded", false)),
			"有" if room.get_node_or_null("AuthoredLayoutArtRoot") != null else "**没有**",
		])
		if aabb.size == Vector3.ZERO:
			print("      可视包围盒=**空**（这间房在玩家眼里什么都没有）")
		else:
			print("      可视包围盒 pos=(%.1f,%.1f,%.1f) size=(%.1f,%.1f,%.1f)" % [
				aabb.position.x, aabb.position.y, aabb.position.z,
				aabb.size.x, aabb.size.y, aabb.size.z,
			])


func _break_and_teleport() -> void:
	var door := _find_entry_door()
	if door == null:
		print("[传送] **找不到入口门**")
		return
	var target: Variant = door.call("get_teleport_target")
	print("[传送] 入口门 %s  site=%s role=%s  落点=%s" % [
		str(door.name), str(door.get("site_id")), str(door.get("role")), str(target),
	])
	_dump_nearest_room_door(door)
	var player := _find_player()
	if player == null:
		print("[传送] **场景里没有玩家节点**")
		return
	# 破板：入口门在入口房清完前是锁着的，探针先解锁再打，绕开战斗流程。
	door.call("set_locked", false)
	var guard := 0
	while not bool(door.call("is_broken")) and guard < 20:
		door.call("take_damage", 999)
		await get_tree().process_frame
		guard += 1
	print("[传送] 破板=%s  交互候选=%s" % [
		str(door.call("is_broken")),
		str(door.call("get_interaction_candidate", player)),
	])
	# 站到门前（房间侧 = 门局部 -Z），再按 E。
	var room_side := -door.global_transform.basis.z
	player.set("global_position", door.global_position + room_side * 1.5)
	await get_tree().process_frame
	await get_tree().process_frame
	print("[传送] 站位后 玩家=(%.1f,%.1f,%.1f) 候选=%s" % [
		player.global_position.x, player.global_position.y, player.global_position.z,
		str(door.call("get_interaction_candidate", player)),
	])
	var ok: Variant = door.call("perform_interaction", player, {})
	print("[传送] perform_interaction → %s" % str(ok))
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	print("[传送] 落点后 玩家=(%.1f,%.1f,%.1f) 目标=(%s)" % [
		player.global_position.x, player.global_position.y, player.global_position.z,
		str(target),
	])
	if player is CharacterBody3D:
		print("[传送] velocity=%s  on_floor=%s" % [
			str((player as CharacterBody3D).velocity),
			str((player as CharacterBody3D).is_on_floor()),
		])
	# 落点与各子图房间中心的水平距离
	var rows: Dictionary = _branch.get("_branch_rooms") as Dictionary
	for room_id in rows:
		var room := (rows[room_id] as Dictionary).get("room") as Node3D
		if room == null:
			continue
		var d := Vector2(
			player.global_position.x - room.global_position.x,
			player.global_position.z - room.global_position.z
		).length()
		print("      落点 ↔ %-22s 水平距=%.1fm" % [str(room_id), d])


func _dump_around_player() -> void:
	var player := _find_player()
	if player == null:
		return
	var pos := player.global_position
	var all_total := 0
	var near_total := 0
	var nearest_name := ""
	var nearest_d := INF
	for node in _tower.find_children("*", "VisualInstance3D", true, false):
		var vi := node as VisualInstance3D
		if vi == null or not vi.is_visible_in_tree():
			continue
		all_total += 1
		var box := _world_box(vi)
		var center := box.get_center()
		var d := Vector2(center.x - pos.x, center.z - pos.z).length()
		if d > AROUND_RADIUS_M:
			continue
		near_total += 1
		if d < nearest_d:
			nearest_d = d
			nearest_name = _label(vi)
	print("[四周] 落点 %.0fm 内可视件=%d  最近一件=%s（%.2fm）" % [
		AROUND_RADIUS_M, near_total,
		nearest_name if not nearest_name.is_empty() else "<没有>", nearest_d,
	])
	print("[四周] 全场景可视件=%d" % all_total)


## 这扇手摆门离最近的主路房间门有多远。两块 2.2m 门中心距 < 2.3m 就等于压住了。
func _dump_nearest_room_door(door: Node3D) -> void:
	var best := INF
	var best_name := ""
	for node in _tower.find_children("*", "Node3D", true, false):
		var n := str(node.name)
		if not n.begins_with("Door_"):
			continue
		var p := (node as Node3D).global_position
		var d := Vector2(p.x - door.global_position.x, p.z - door.global_position.z).length()
		if d < best:
			best = d
			best_name = n
	print("[位点] 最近的主路门 %s 距 %.2fm（< 2.3m 即压住主路门洞）" % [
		best_name if not best_name.is_empty() else "<没有找到 Door_*>", best,
	])


func _find_entry_door() -> Node3D:
	for child in _branch.get_children():
		var door := child as Node3D
		if door == null or not str(door.name).begins_with("SecretDoor_"):
			continue
		if str(door.get("role")) == "entry":
			return door
	for child in _branch.get_children():
		if str(child.name).begins_with("SecretDoor_"):
			return child as Node3D
	return null


func _find_player() -> Node3D:
	var direct := _tower.get_node_or_null("Player") as Node3D
	if direct != null:
		return direct
	for node in get_tree().get_nodes_in_group("player_3d"):
		return node as Node3D
	return null


func _subtree_visible_box(root: Node3D) -> AABB:
	var result := AABB()
	var seeded := false
	for node in root.find_children("*", "VisualInstance3D", true, false):
		var vi := node as VisualInstance3D
		if vi == null or not vi.is_visible_in_tree():
			continue
		var box := _world_box(vi)
		if box.size == Vector3.ZERO:
			continue
		result = box if not seeded else result.merge(box)
		seeded = true
	return result


func _world_box(vi: VisualInstance3D) -> AABB:
	var mesh_node := vi as MeshInstance3D
	if mesh_node != null:
		return mesh_node.global_transform * mesh_node.get_aabb()
	var mm := vi as MultiMeshInstance3D
	if mm != null and mm.multimesh != null:
		return mm.global_transform * mm.get_aabb()
	return AABB(vi.global_position, Vector3.ZERO)


func _label(node: Node) -> String:
	var cursor := node
	for _i in range(6):
		if cursor == null:
			return "<null>"
		var n := str(cursor.name)
		if n.begins_with("ENV-") or n.begins_with("DB-") or n.begins_with("ENV_"):
			return n
		cursor = cursor.get_parent()
	return str(node.name)
