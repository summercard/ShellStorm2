extends Node
## 只读探查：远征02「每个门洞是否都有可开的物理门扇」。
##
## 背景：静态布局把门墙**逐扇烘进各房 tscn**（长廊 room_02 一间就有 10 面
## `wall_door_5m_h3`），但 `DungeonRoom3D` 的门扇是**按 `room.doors` 的方向**建的，
## 而 `RoomDoor3D` 一个方向只能有一个节点（`_door_nodes[direction]`）。
## ⇒ 同一面墙上有 N 扇门时，只有 1 扇有门扇、其余 N-1 扇只是门洞。
##
## 本探针把缺口量化：逐房列出**门洞数 / 门扇数 / 没配到门扇的洞**。
##
## 跑法：
##   "<godot_console>" --headless --path "<project>" --scene res://tests/verification/probe_expedition02_door_coverage.tscn

const LEVEL_SCENE := "res://scenes/ExpeditionLevel02_3D.tscn"
const TARGETS: Array[String] = ["start", "room_01", "room_02", "room_13", "room_14"]
## 门扇中心到门洞中心的匹配半径（米）。门宽 5m/2.2m，门扇落在洞中心，
## 取 2.5m 足以吸收 ±2.5m 的门槽偏移又不会跨扇误配。
const MATCH_R := 2.5

var _scene_path := LEVEL_SCENE
var _targets: Array[String] = TARGETS.duplicate()


## 支持 `-- <scene_path> [room_id...]`，便于对远征01 跑同一套判据做回归对照。
## ⚠️ 本探针 `extends Node`，只能在 `_ready()` 里读参数 —— 写 `_initialize()` 是
##    `SceneTree`/`MainLoop` 才有的入口，放在这里会静默不执行（参数被忽略）。
func _read_args() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		var s := str(a)
		if s.begins_with("res://"):
			_scene_path = s
		elif not s.is_empty() and not s.begins_with("--"):
			_targets.append(s)
	if _scene_path != LEVEL_SCENE:
		_targets = []


func _ready() -> void:
	_read_args()
	var packed := load(_scene_path) as PackedScene
	if packed == null:
		printerr("[doorcov] 关卡场景加载失败: %s" % _scene_path)
		get_tree().quit(1)
		return
	var tower := packed.instantiate() as TowerDescent3D
	tower.test_mode = true
	add_child(tower)
	for i in 10:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.5).timeout

	var room_by_id: Dictionary = tower.get("_room_by_id")
	print("=== %s 门洞 / 门扇 覆盖对账 ===" % _scene_path)
	print("匹配半径 %.1fm；『门洞』= 静态布局里的 wall_door 实例；『门扇』= RoomDoor3D 节点" % MATCH_R)
	print("房间字典共 %d 房" % room_by_id.size())
	print()

	# 未显式指定时，全房都查（远征01 只有 13 房，全查更省事）
	if _targets.is_empty():
		var keys: Array = room_by_id.keys()
		keys.sort()
		for k in keys:
			_targets.append(str(k))

	var total_holes := 0
	var total_doors := 0
	var total_unmatched := 0
	var rows: Array = []

	for target in _targets:
		var room := room_by_id.get(target) as DungeonRoom3D
		if room == null:
			print("### %s —— 不在房间字典里" % target)
			continue
		room.ensure_shell_built()
		for i in 5:
			await get_tree().process_frame
			await get_tree().physics_frame

		var holes := _door_holes(room)
		var doors := _door_leafs(room)
		# 只有 2.2m 标准门洞才需要门扇；坍塌门洞天然是通洞。
		var door_holes: Array = []
		for h_v in holes:
			if str((h_v as Dictionary)["kind"]) == "door":
				door_holes.append(h_v)
		total_holes += door_holes.size()
		total_doors += doors.size()

		# 逐洞找最近门扇
		var unmatched: Array = []
		for h in door_holes:
			var hp := h["pos"] as Vector3
			var best := 999.0
			var best_name := ""
			for d in doors:
				var dist := hp.distance_to(d["pos"] as Vector3)
				if dist < best:
					best = dist
					best_name = str(d["name"])
			if best > MATCH_R:
				unmatched.append({ "hole": h, "nearest": best, "nearest_name": best_name })
		total_unmatched += unmatched.size()

		# 反向：有没有门扇落在没有门洞的地方（通洞里插门扇）
		var stray: Array = []
		for d in doors:
			var dp := d["pos"] as Vector3
			var best2 := 999.0
			for h in holes:
				best2 = minf(best2, dp.distance_to(h["pos"] as Vector3))
			if best2 > MATCH_R:
				stray.append({ "door": d, "nearest": best2 })

		rows.append({
			"key": target, "holes": door_holes.size(), "doors": doors.size(),
			"unmatched": unmatched.size(), "detail": unmatched,
			"stray": stray,
			"room_doors": room.doors, "ports": (room.connection_ports as Array).size(),
		})

	for r in rows:
		var mark := "OK " if int(r["unmatched"]) == 0 else "缺口"
		print("### %-9s %s  门洞=%2d  门扇=%2d  缺门扇=%2d  doors=%s  端口=%d" % [
			str(r["key"]), mark, int(r["holes"]), int(r["doors"]), int(r["unmatched"]),
			str(r["room_doors"]), int(r["ports"])])
		for d_v in r["detail"] as Array:
			var d: Dictionary = d_v
			var h: Dictionary = d["hole"]
			print("      ✗ 缺门扇 洞@(%7.2f,%6.2f,%7.2f) 最近门扇 %s 在 %.2fm 外" % [
				(h["pos"] as Vector3).x, (h["pos"] as Vector3).y, (h["pos"] as Vector3).z,
				str(d["nearest_name"]), float(d["nearest"])])
		for s_v in r["stray"] as Array:
			var s: Dictionary = s_v
			var dd: Dictionary = s["door"]
			print("      ✗ 多余门扇 %s dir=%s @(%7.2f,%6.2f,%7.2f) 附近 %.2fm 内无门洞" % [
				str(dd["name"]), str(dd["direction"]),
				(dd["pos"] as Vector3).x, (dd["pos"] as Vector3).y, (dd["pos"] as Vector3).z,
				float(s["nearest"])])

	print()
	print("=== 合计 ===")
	print("  门洞 %d  门扇 %d  缺门扇的洞 %d" % [total_holes, total_doors, total_unmatched])

	# 全房总账
	var all_holes := 0
	var all_doors := 0
	for v in room_by_id.values():
		var room := v as DungeonRoom3D
		if room == null:
			continue
		room.ensure_shell_built()
		for i in 3:
			await get_tree().process_frame
			await get_tree().physics_frame
		for h_v in _door_holes(room):
			if str((h_v as Dictionary)["kind"]) == "door":
				all_holes += 1
		all_doors += _door_leafs(room).size()
	print("  全房汇总：标准门洞 %d  门扇 %d  缺口 %d" % [all_holes, all_doors, all_holes - all_doors])

	print()
	print("EXP02_DOOR_COVERAGE_DONE")
	get_tree().quit(0)


## 静态布局里的门墙实例（= 门洞）。返回 [{pos, size, name, kind}]
##
## ⚠️ 去重必须按**最外层**：`wall_door_5m_h3` 是嵌套 PackedScene，
## 实例根与它内部的包装节点会**同名同前缀**（第一版就是这么把 22 个数成 44 的）。
## 判据：沿祖先链上溯，若任一祖先名字也匹配，则本节点是内层，跳过。
func _door_holes(room: DungeonRoom3D) -> Array:
	var out: Array = []
	for nv in room.find_children("*", "Node3D", true, false):
		var node := nv as Node3D
		if node == null or not _is_door_wall_name(String(node.name)):
			continue
		var has_match_ancestor := false
		var cur := node.get_parent()
		while cur != null:
			if cur is Node3D and _is_door_wall_name(String(cur.name)):
				has_match_ancestor = true
				break
			cur = cur.get_parent()
		if has_match_ancestor:
			continue
		var low := String(node.name).to_lower()
		out.append({
			"pos": node.global_position,
			"size": _subtree_size(node),
			"name": String(node.name),
			# collapse = 坍塌门洞（5m 通洞，白盒里本来就没有墙件），不该配门扇
			"kind": "collapse" if low.begins_with("wall_collapse") else "door",
		})
	return out


func _is_door_wall_name(raw: String) -> bool:
	var low := raw.to_lower()
	return low.begins_with("wall_door_5m") or low.begins_with("wall_collapse_5m")


## 房间里的门扇（RoomDoor3D）
func _door_leafs(room: DungeonRoom3D) -> Array:
	var out: Array = []
	for nv in room.find_children("*", "", true, false):
		if nv is RoomDoor3D:
			var d := nv as RoomDoor3D
			out.append({
				"pos": d.global_position,
				"name": String(d.name),
				"direction": d.direction,
				"target": d.target_room_id,
			})
	return out


func _subtree_size(root: Node3D) -> Vector3:
	var acc := AABB()
	var found := false
	for mv in root.find_children("*", "MeshInstance3D", true, false):
		var mi := mv as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var a := mi.get_aabb()
		var xf := mi.global_transform
		var p := a.position
		var s := a.size
		var mn := xf * p
		var mx := mn
		for i in range(8):
			var c := p + Vector3(
				s.x if (i & 1) else 0.0,
				s.y if (i & 2) else 0.0,
				s.z if (i & 4) else 0.0)
			var wp := xf * c
			mn = Vector3(minf(mn.x, wp.x), minf(mn.y, wp.y), minf(mn.z, wp.z))
			mx = Vector3(maxf(mx.x, wp.x), maxf(mx.y, wp.y), maxf(mx.z, wp.z))
		var b := AABB(mn, mx - mn)
		acc = b if not found else acc.merge(b)
		found = true
	return acc.size if found else Vector3.ZERO
