extends Node
## 远征02门契约探针：普通连接门保持为开放门洞，安全房退出门保留。
##
## 远征02当前施工口径不是「每个 wall_door 都必须有 RoomDoor3D」：
## - 普通连接端口只保留 authored 开口、路线和触发，不生成门扇/门扇碰撞；
## - start 安全房唯一的空目标 east retreat 门必须保留，并绑定退出交互；
## - 静态 wall_door 实例只是门洞几何，不能再拿它要求动态门扇覆盖。
##
## 本探针同时保留门洞统计，防止误删静态布局；验收重点改为「普通门扇为 0、退出门为 1」。
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
var failures: Array[String] = []


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
	print("『门洞』= 静态布局里的 wall_door 实例；『门扇』= RoomDoor3D 节点")
	print("远征02预期：普通连接门扇=0；start 退出门扇=1；connection_ports 保留")
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
		# 远征02普通连接门是开放门洞，不再要求动态门扇覆盖。
		var door_holes: Array = []
		for h_v in holes:
			if str((h_v as Dictionary)["kind"]) == "door":
				door_holes.append(h_v)
		total_holes += door_holes.size()
		total_doors += doors.size()

		var unmatched: Array = []
		var stray: Array = []
		var is_start := target == "start"
		var expected_doors := 1 if is_start else 0
		if doors.size() != expected_doors:
			failures.append("%s 普通/退出门扇数量=%d，预期=%d" % [target, doors.size(), expected_doors])
		if room.connection_ports.is_empty():
			failures.append("%s connection_ports 被错误删除" % target)
		if is_start:
			var retreat_side := str(room.call("_safe_room_retreat_direction"))
			if retreat_side != "east":
				failures.append("start 退出侧=%s，预期 east" % retreat_side)
			var retreat_door := room.get_door_node(retreat_side)
			if retreat_door == null:
				failures.append("start 缺少 east 退出门")
			elif retreat_door.get_interaction_prompt_text() != "[E] 退出战局":
				failures.append("start 退出门提示错误：%s" % retreat_door.get_interaction_prompt_text())

		rows.append({
			"key": target, "holes": door_holes.size(), "doors": doors.size(),
			"unmatched": unmatched.size(), "detail": unmatched,
			"stray": stray,
			"room_doors": room.doors, "ports": (room.connection_ports as Array).size(),
		})

	for r in rows:
		var is_start := str(r["key"]) == "start"
		var expected_doors := 1 if is_start else 0
		var mark := "OK " if int(r["doors"]) == expected_doors else "失败"
		print("### %-9s %s  静态门洞=%2d  动态门扇=%2d  预期=%d  doors=%s  端口=%d" % [
			str(r["key"]), mark, int(r["holes"]), int(r["doors"]), expected_doors,
			str(r["room_doors"]), int(r["ports"])])

	print()
	print("=== 合计 ===")
	print("  静态门洞 %d  动态门扇 %d  普通连接门预期为0" % [total_holes, total_doors])

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
	print("  全房汇总：静态门洞 %d  动态门扇 %d" % [all_holes, all_doors])

	print()
	if failures.is_empty():
		print("EXP02_DOOR_COVERAGE_OK")
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("DOOR_COVERAGE_FAIL %s" % failure)
		print("EXP02_DOOR_COVERAGE_FAIL count=%d" % failures.size())
		get_tree().quit(1)


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
