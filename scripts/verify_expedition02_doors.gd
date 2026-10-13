extends Node
## 远征关卡02 门扇覆盖验收（运行时，纯只读）。
##
## 契约：设计源声明了门位的**每一个标准门洞都必须有一扇实体门扇**，且门扇不许
## 落在没有洞的地方。
##
## 为什么需要这条：`RoomDoor3D` 一个方向只能挂一个节点（`_door_nodes[direction]`），
## 按「方向」建门会让同一面墙上的 N 扇门只建出 1 扇、其余门洞永远是洞。
## 远征02 实测过：长廊 `room_02` 一间房 10 个客房门洞只建出 2 扇，
## 另有 3 扇门扇悬在 5m 通洞里（开门交互指向空气）。
##
## 跑法（**以场景方式跑**，autoload 才可用）：
##   godot --headless --path "<项目根>" res://tests/verification/verify_expedition02_doors.tscn

const LEVEL_SCENE := "res://scenes/ExpeditionLevel02_3D.tscn"
## 门扇中心到门洞中心的匹配半径（米）。门宽最大 5m，门扇落在洞中心。
const MATCH_R := 2.5
## 允许「有门扇、没门洞」的门数：入口安全房的**封闭气闸门**是设计要求的
## （`_build_expedition_records` 特意加的"传送抵达侧封闭气闸门"：不挂地图边、
## 不参与拓扑、只补安全房造型与退出交互位），它本来就没有洞。
const ALLOWED_HOLELESS_DOORS := 1

var failures: Array[String] = []


func _ready() -> void:
	var packed := load(LEVEL_SCENE) as PackedScene
	if packed == null:
		_fail("关卡场景加载失败: %s" % LEVEL_SCENE)
		_finish()
		return
	var tower := packed.instantiate() as TowerDescent3D
	tower.test_mode = true
	add_child(tower)
	for i in 10:
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.4).timeout

	var room_by_id: Dictionary = tower.get("_room_by_id")
	if room_by_id.size() != 26:
		_fail("房间数 %d，期望 26" % room_by_id.size())

	var total_holes := 0
	var total_doors := 0
	var holeless := 0
	var keys: Array = room_by_id.keys()
	keys.sort()
	for key_value in keys:
		var room := room_by_id.get(key_value) as DungeonRoom3D
		if room == null:
			continue
		room.ensure_shell_built()
		for i in 3:
			await get_tree().process_frame
			await get_tree().physics_frame
		var holes := _door_holes(room)
		var doors := _door_leafs(room)
		total_holes += holes.size()
		total_doors += doors.size()
		for h_v in holes:
			var hole: Vector3 = h_v
			var nearest := _nearest(doors, hole)
			if nearest > MATCH_R:
				_fail("%s 门洞 @%s 没有门扇（最近 %.2fm）" % [room.room_id, str(hole), nearest])
		for d_v in doors:
			var leaf: Vector3 = d_v
			var nearest := _nearest(holes, leaf)
			if nearest > MATCH_R:
				holeless += 1
				print("  提示：%s 有门扇 @%s 但附近无门洞（最近 %.2fm）" % [
					room.room_id, str(leaf), nearest])

	if total_holes == 0:
		_fail("一个标准门洞都没采到 —— 静态布局或门墙族可能变了，本判据已失效")
	if holeless > ALLOWED_HOLELESS_DOORS:
		_fail("有 %d 扇门扇落在没有门洞的地方，上限 %d（多出来的是悬空门）" % [
			holeless, ALLOWED_HOLELESS_DOORS])

	print("门洞 %d / 门扇 %d / 无洞门扇 %d（上限 %d）" % [
		total_holes, total_doors, holeless, ALLOWED_HOLELESS_DOORS])
	_finish()


func _nearest(points: Array, from: Vector3) -> float:
	var best := 1.0e9
	for p_v in points:
		var p: Vector3 = p_v
		best = minf(best, from.distance_to(p))
	return best


## 静态布局里的标准门洞（`wall_door_5m*` 实例）的世界坐标。
## 坍塌门洞（`wall_collapse_5m*`）是纯开口，不计入。
func _door_holes(room: DungeonRoom3D) -> Array:
	var out: Array = []
	for nv in room.find_children("*", "Node3D", true, false):
		var node := nv as Node3D
		if node == null or not String(node.name).to_lower().begins_with("wall_door_5m"):
			continue
		# 门墙是嵌套 PackedScene，实例根与内部包装节点同名同前缀 ⇒ 只认最外层。
		var has_match_ancestor := false
		var cur := node.get_parent()
		while cur != null:
			if cur is Node3D and String(cur.name).to_lower().begins_with("wall_door_5m"):
				has_match_ancestor = true
				break
			cur = cur.get_parent()
		if has_match_ancestor:
			continue
		out.append(node.global_position)
	return out


func _door_leafs(room: DungeonRoom3D) -> Array:
	var out: Array = []
	for nv in room.find_children("*", "", true, false):
		if nv is RoomDoor3D:
			out.append((nv as RoomDoor3D).global_position)
	return out


func _fail(message: String) -> void:
	failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("EXPEDITION02_DOORS_VERIFY_OK")
		get_tree().quit(0)
		return
	print("EXPEDITION02_DOORS_VERIFY_FAILED count=%d" % failures.size())
	for failure in failures:
		print("FAIL %s" % failure)
	get_tree().quit(1)
