extends Node

## 一次性探针：按**玩家真实流程**进远征 01，回答「3 号房里到底有没有这道暗门」。
##
## 与 `verify_secret_branch_flow` / `probe_secret_door_player_view` 的关键区别：
##   · 那两个都跑 `test_mode = true`（开发者测试接缝）；
##   · 这里默认 `test_mode = false`，走真机的 bootstrap / 存档恢复 / 流送路径。
##
## 用法：
##   godot --headless --path . res://tests/verification/probe_secret_door_real_run.tscn
##   SS2_SEED=1122239949 ...   # 指定种子（默认不指定 = 真实随机种子）
##   SS2_PROBE_TESTMODE=1 ...  # 回到 test_mode 做对照
##
## 输出：
##   · 本局 run_seed / layout_id；
##   · 全部房间的 id、世界坐标、尺寸；
##   · SecretBranches 是否存在，每个位点的门是否真的建出来了；
##   · 逐门：外推量、可视遮挡、门前遮挡、门心与房间外壁的几何关系；
##   · 每个房间「门内 3m 朝门看」的首个可视命中件（不依赖碰撞层）。

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
## 主路第 3 间（业主说的「3 号房间」）。
const TARGET_ROOM := "room_03"
## 等 bootstrap 装配完的上限（秒）。
const WAIT_LIMIT_S := 40.0

var _tower: TowerDescent3D = null


func _ready() -> void:
	var use_test_mode := OS.get_environment("SS2_PROBE_TESTMODE") == "1"
	var seed_env := OS.get_environment("SS2_SEED")

	var scene := load(EXPEDITION_SCENE) as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = use_test_mode
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
			# 再等两帧让 settle_sites 的 deferred 跑完
			await get_tree().process_frame
			await get_tree().process_frame
			break

	print("")
	print("=== 真实流程核对：test_mode=%s  seed_override=%s 等待=%.1fs ===" % [
		str(use_test_mode), seed_env if not seed_env.is_empty() else "<随机器>", waited,
	])
	_dump_run()
	_dump_rooms()
	_dump_branch()
	_dump_doors()
	_dump_target_room_visibility()
	print("")
	print("REAL_RUN_PROBE_END")
	get_tree().quit(0)


func _dump_run() -> void:
	print("[运行] run_seed=%d  is_expedition=%s  level=%s  layout_id=%s" % [
		int(_tower.get("run_seed")), str(_tower.call("is_expedition")),
		str(_tower.call("get_expedition_level_id")), str(_tower.get("run_seed")),
	])
	var plan := {}
	var snaps: Dictionary = _tower.get("_floor_plan_snapshots") as Dictionary
	for key in snaps.keys():
		plan = snaps[key] as Dictionary
		break
	print("[运行] 规划房间数=%d  main_path=%s" % [
		(plan.get("rooms", []) as Array).size(),
		str(plan.get("main_path", [])),
	])


func _dump_rooms() -> void:
	var records: Array = _tower.get("_records") as Array
	print("[房间] 记录数=%d" % records.size())
	for value in records:
		var record := value as Dictionary
		var pos := record.get("position", Vector3.ZERO) as Vector3
		var dims := record.get("dimensions", Vector2.ZERO) as Vector2
		var site := record.get("secret_site", {}) as Dictionary
		print("  %-12s pos=(%8.1f,%8.1f,%8.1f) dims=%sx%s kind=%-10s secret=%s" % [
			str(record.get("id", "")), pos.x, pos.y, pos.z,
			str(dims.x), str(dims.y), str(record.get("type", "")),
			str(site.get("site_id", "-")),
		])
	# 真实节点是否都在树里，以及真实尺寸（记录里没有尺寸，必须问节点）
	var by_id: Dictionary = _tower.get("_room_by_id") as Dictionary
	print("[房间] _room_by_id=%d 项" % by_id.size())
	for key in by_id.keys():
		var room := by_id[key] as Node3D
		if room == null:
			continue
		var dims: Vector2 = room.call("get_dimensions")
		print("  [节点] %-12s pos=(%8.1f,%8.1f,%8.1f) dims=%sx%s" % [
			str(key), room.global_position.x, room.global_position.y, room.global_position.z,
			str(dims.x), str(dims.y),
		])


func _dump_branch() -> void:
	var branch := _tower.get_node_or_null("SecretBranches")
	print("[支线] SecretBranches=%s" % ("有" if branch != null else "**没有**"))
	if branch == null:
		return
	var snapshot := branch.call("debug_snapshot") as Dictionary
	print("[支线] pairs=%s doors=%s" % [
		str(snapshot.get("pairs", [])), str(snapshot.get("doors", [])),
	])
	for value in snapshot.get("sites", []) as Array:
		var site := value as Dictionary
		var pos := site.get("position", Vector3.ZERO) as Vector3
		print("  位点 %-3s room=%-9s wall=%-5s lane=%6.2f pos=(%8.2f,%6.2f,%8.2f) 外推=%.3f 遮挡=%s 门前=%s" % [
			str(site.get("site_id", "")), str(site.get("room_id", "")),
			str(site.get("wall", "")), float(site.get("lane", 0.0)),
			pos.x, pos.y, pos.z,
			float(site.get("wall_push_m", 0.0)),
			str(site.get("covered_by", "-")), str(site.get("blocker", "-")),
		])


func _dump_doors() -> void:
	var branch := _tower.get_node_or_null("SecretBranches")
	if branch == null:
		return
	for child in branch.get_children():
		if not str(child.name).begins_with("SecretDoor_"):
			continue
		var door := child as Node3D
		var pos := door.global_position
		var boards := door.get_node_or_null("Boards") as Node3D
		var root_visible := door.is_visible_in_tree()
		var boards_visible := boards != null and boards.is_visible_in_tree()
		print("[门] %-14s pos=(%8.2f,%6.2f,%8.2f) 可见=%s 木板=%s 木板可见=%s 子节点=%d" % [
			str(door.name), pos.x, pos.y, pos.z,
			str(root_visible), "有" if boards != null else "**无**", str(boards_visible),
			door.get_child_count(),
		])


## 用「可视几何」判断目标房间的门有没有埋在墙/家具里 —— 不依赖碰撞代理盒。
func _dump_target_room_visibility() -> void:
	var branch := _tower.get_node_or_null("SecretBranches")
	var records: Array = _tower.get("_records") as Array
	var record: Dictionary = {}
	for value in records:
		var candidate := value as Dictionary
		if str(candidate.get("id", "")) == TARGET_ROOM:
			record = candidate
			break
	if record.is_empty():
		print("[%s] **房表里没有这间**" % TARGET_ROOM)
		return
	var pos := record.get("position", Vector3.ZERO) as Vector3
	var dims := record.get("dimensions", Vector2.ZERO) as Vector2
	var site := record.get("secret_site", {}) as Dictionary
	var by_id: Dictionary = _tower.get("_room_by_id") as Dictionary
	var room_node := by_id.get(TARGET_ROOM) as Node3D
	if room_node != null:
		pos = room_node.global_position
		dims = room_node.call("get_dimensions")
	print("[%s] pos=(%.1f,%.1f,%.1f) dims=%sx%s secret_site=%s" % [
		TARGET_ROOM, pos.x, pos.y, pos.z, str(dims.x), str(dims.y), str(site),
	])
	if branch == null or site.is_empty():
		print("[%s] 无支线节点或无位点声明" % TARGET_ROOM)
		return
	var site_id := str(site.get("site_id", ""))
	var door := branch.get_node_or_null("SecretDoor_%s" % site_id) as Node3D
	print("[%s] 对应门节点 SecretDoor_%s=%s" % [
		TARGET_ROOM, site_id, "存在" if door != null else "**不存在**",
	])
	if door == null:
		return
	var wall := str(site.get("wall", ""))
	var normal := _wall_normal(wall)
	var half_w := dims.x * 0.5
	var half_d := dims.y * 0.5
	var wall_coord := 0.0
	match wall:
		"south": wall_coord = pos.z + half_d
		"north": wall_coord = pos.z - half_d
		"east": wall_coord = pos.x + half_w
		"west": wall_coord = pos.x - half_w
	var door_coord := door.global_position.dot(normal)
	var wall_half_coord := Vector3(pos.x, 0.0, pos.z).dot(normal) + _half_along(dims, normal)
	print("[%s] 沿外法线：门心=%.3f  标称墙面=%.3f  门心朝房间里凸出 %.3fm" % [
		TARGET_ROOM, door_coord, wall_half_coord, wall_half_coord - door_coord,
	])
	# 最近的墙/家具可视面（沿法线）。**必须排除门自己那棵子树**，
	# 否则第一个找到的永远是门自己的木板，等于自己证明自己。
	var faces: Array = []
	for node in _tower.find_children("*", "VisualInstance3D", true, false):
		var vi := node as VisualInstance3D
		if vi == null or not vi.is_visible_in_tree():
			continue
		if branch.is_ancestor_of(vi):
			continue
		var box := _world_box(vi)
		if not _box_covers_door(box, door.global_position, normal):
			continue
		var lo := INF
		for i in range(8):
			lo = minf(lo, box.get_endpoint(i).dot(normal))
		if absf(lo - door_coord) > 8.0:
			continue
		faces.append({"name": _label(vi), "lo": lo})
	if faces.is_empty():
		print("[%s] 门宽×门高范围内没有其它可视件（只剩墙本身也不在？）" % TARGET_ROOM)
		return
	faces.sort_custom(func(a, b): return float(a["lo"]) < float(b["lo"]))
	print("[%s] 门宽×门高范围内、最靠房间内侧的可视件（沿外法线，值越小越靠房间内）：" % TARGET_ROOM)
	for i in range(mini(faces.size(), 5)):
		var row := faces[i] as Dictionary
		var protrusion := float(row["lo"]) - door_coord
		print("    %-56s 面=%.3f  门心在它前面 %.3fm" % [str(row["name"]), float(row["lo"]), protrusion])
	var first := faces[0] as Dictionary
	var protrusion := float(first["lo"]) - door_coord
	print("[%s] 结论：门心比最靠里的可视面（%s）前凸 %.3fm → %s" % [
		TARGET_ROOM, str(first["name"]), protrusion,
		"玩家看得见门" if protrusion > 0.05 else "**玩家只看到墙**",
	])


func _half_along(dims: Vector2, normal: Vector3) -> float:
	if absf(normal.x) > 0.5:
		return dims.x * 0.5
	return dims.y * 0.5


func _wall_normal(wall: String) -> Vector3:
	match wall:
		"south": return Vector3(0, 0, 1)
		"north": return Vector3(0, 0, -1)
		"east": return Vector3(1, 0, 0)
		"west": return Vector3(-1, 0, 0)
	return Vector3.ZERO


func _world_box(vi: VisualInstance3D) -> AABB:
	var mesh_node := vi as MeshInstance3D
	if mesh_node != null:
		return mesh_node.global_transform * mesh_node.get_aabb()
	var mm := vi as MultiMeshInstance3D
	if mm != null and mm.multimesh != null:
		return mm.global_transform * mm.get_aabb()
	return vi.global_transform * AABB(Vector3.ZERO, Vector3.ZERO)


## 这个可视件是否挡在「门宽 × 门高」这一片范围里（不区分在门前还是门后，
## 判断凸出量必须同时看到墙面本身）。
func _box_covers_door(box: AABB, door_pos: Vector3, normal: Vector3) -> bool:
	var tangent := normal.cross(Vector3.UP).normalized()
	var lo_t := INF
	var hi_t := -INF
	var lo_y := INF
	var hi_y := -INF
	for i in range(8):
		var p := box.get_endpoint(i)
		var t := p.dot(tangent)
		lo_t = minf(lo_t, t)
		hi_t = maxf(hi_t, t)
		lo_y = minf(lo_y, p.y)
		hi_y = maxf(hi_y, p.y)
	var door_t := door_pos.dot(tangent)
	var overlap := minf(hi_t - door_t, door_t - lo_t)
	var covers_width := overlap >= 0.6
	var covers_height := hi_y >= 1.4 and lo_y <= 2.0
	return covers_width and covers_height


func _label(node: Node) -> String:
	var cursor := node
	for _i in range(5):
		if cursor == null:
			return "<null>"
		var n := str(cursor.name)
		if n.begins_with("ENV-") or n.begins_with("DB-") or n.begins_with("ENV_"):
			return n
		cursor = cursor.get_parent()
	return str(node.name)


func _find_room_node(root: Node, room_id: String) -> Node:
	for node in root.find_children("*", "Node3D", true, false):
		if str(node.name) == room_id:
			return node
	return null
