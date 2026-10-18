extends Node

## 一次性探针：量「子图位点门板」与「主路房间门」的世界坐标是否重合，
## 并把四个位点所在房间**实际占用**的门洞槽位（墙 + 沿墙 lane）逐个打出来。
##
## 为什么需要后半段：业主 2026-10-18 定「暗门入口/出口改成固定位置，角色自由配」。
## 要落地就得知道每间房到底哪几个槽被主路占了 —— 运行时房位由 `FloorPlanGenerator`
## 重排（expedition_01 还整体转了 180°），设计源的 `connection_ports` 不是最终答案。
##
## 用法：bash scripts/run_verification_suite.sh scene probe_secret_door_vs_main_doors
## 输出：SECRET_DOOR_OVERLAP_PROBE_OK / _MISS（脚本自身不判红绿，只出数）。

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
## 需要至少一个能让 pair 1（S3/S4）刷出来的种子 —— pair 1 是 50% 概率。
const SEEDS := [77001199, 77001200, 20261018, 1234, 42, 7, 99]
## 判定「重合」的距离上限：门板宽 2.2m，墙体厚约 0.4m；
## 两块门状物件中心距 < 1.5m 就算挤在同一处。
const OVERLAP_EPSILON_M := 1.5
## 位点房间（设计 §3.2），探针把它们的槽位占用全打一遍。
const SITE_ROOMS := ["room_03", "room_06", "room_07", "room_10"]

var _secret_doors: Array = []
var _main_doors: Array = []
var _rooms: Dictionary = {}


func _ready() -> void:
	var solved := false
	for seed_value in SEEDS:
		var ok := await _probe_seed(int(seed_value))
		if ok:
			solved = true
			break
	if not solved:
		print("SECRET_DOOR_OVERLAP_PROBE_MISS 所有种子都没刷出 S3 —— 无法测量")
	get_tree().quit(0)


func _probe_seed(seed_value: int) -> bool:
	var scene := load(EXPEDITION_SCENE) as PackedScene
	if scene == null:
		print("SECRET_DOOR_OVERLAP_PROBE_MISS 远征场景加载失败")
		return false
	var tower := scene.instantiate() as TowerDescent3D
	if tower == null:
		print("SECRET_DOOR_OVERLAP_PROBE_MISS 远征场景实例化失败")
		return false
	tower.test_mode = true
	tower.run_seed_override = seed_value
	add_child(tower)
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	_secret_doors = []
	_main_doors = []
	_rooms = {}
	_collect(tower)

	var has_s3 := false
	for value in _secret_doors:
		if str((value as Dictionary).get("name", "")) == "SecretDoor_S3":
			has_s3 = true
	if not has_s3:
		print(
			"[probe] seed=%d 未刷出 pair 1（S3/S4），换下一个种子。已有板体=%s"
			% [seed_value, str(_secret_names())]
		)
		tower.queue_free()
		await get_tree().process_frame
		return false

	print("")
	print("=== seed=%d 板体与主路门实测 ===" % seed_value)
	for value in _secret_doors:
		var door := value as Dictionary
		var pos := door.get("pos", Vector3.ZERO) as Vector3
		var nearest := _nearest_main_door(pos)
		if nearest.is_empty():
			print("  %-14s world=(%7.2f, %6.2f, %7.2f)  最近主路门：无" % [
				str(door.get("name", "")), pos.x, pos.y, pos.z,
			])
			continue
		var gap := float(nearest.get("dist", INF))
		var verdict := "★重合" if gap < OVERLAP_EPSILON_M else "不重合"
		print(
			"  %-14s world=(%7.2f, %6.2f, %7.2f)  最近=%s 距离=%.2fm   %s"
			% [
				str(door.get("name", "")), pos.x, pos.y, pos.z,
				str(nearest.get("label", "")), gap, verdict,
			]
		)

	print("")
	print("=== 四个位点房间的槽位占用（房间本地坐标）===")
	for room_id in SITE_ROOMS:
		_dump_room_slots(room_id)

	print("SECRET_DOOR_OVERLAP_PROBE_OK seed=%d 板体=%d 主路门=%d" % [
		seed_value, _secret_doors.size(), _main_doors.size(),
	])
	tower.queue_free()
	await get_tree().process_frame
	return true


func _collect(root: Node) -> void:
	for child in root.get_children():
		var node := child as Node
		if node == null:
			continue
		var name_text := str(node.name)
		if name_text.begins_with("SecretDoor_"):
			_secret_doors.append({
				"name": name_text,
				"pos": (node as Node3D).global_position if node is Node3D else Vector3.ZERO,
			})
		elif name_text.begins_with("Door_"):
			var direction := ""
			var target := ""
			if node.get("direction") != null:
				direction = str(node.get("direction"))
			if node.get("target_room_id") != null:
				target = str(node.get("target_room_id"))
			_main_doors.append({
				"name": name_text,
				"direction": direction,
				"target": target,
				"node": node,
				"label": "%s（父=%s，%s→%s）" % [
					name_text,
					str(node.get_parent().name if node.get_parent() else "?"),
					direction, target,
				],
				"pos": (node as Node3D).global_position if node is Node3D else Vector3.ZERO,
			})
		elif node.get("room_id") != null:
			_rooms[str(node.get("room_id"))] = node
		_collect(node)


func _nearest_main_door(pos: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_dist := INF
	for value in _main_doors:
		var row := value as Dictionary
		var other := row.get("pos", Vector3.ZERO) as Vector3
		# 只比水平距离：门板与门扇的 y 可能差一个门槛高度，那不算「撞在一起」。
		var d := Vector2(pos.x - other.x, pos.z - other.z).length()
		if d < best_dist:
			best_dist = d
			best = row.duplicate()
			best["dist"] = d
	return best


func _secret_names() -> Array:
	var out: Array = []
	for value in _secret_doors:
		out.append(str((value as Dictionary).get("name", "")))
	return out


## 把一间房的**所有**门扇按房间本地坐标归类成 (墙, lane)。
## 本地坐标系：原点房间中心，x 向东、z 向南（Godot），与设计源 `position_m` 同口径。
func _dump_room_slots(room_id: String) -> void:
	var room := _rooms.get(room_id) as Node3D
	if room == null:
		print("  [%s] 运行时找不到房间节点" % room_id)
		return
	# `DungeonRoom3D` 不暴露 `dimensions` 属性，只给 `get_dimensions()`。
	var dims: Vector2 = room.call("get_dimensions")
	var half := dims * 0.5
	print("  [%s] 中心=%s 旋转y=%.1f° 尺寸=%.1f×%.1f" % [
		room_id, str(room.global_position), rad_to_deg(room.global_rotation.y), dims.x, dims.y,
	])
	var occupied: Array = []
	for value in _main_doors:
		var row := value as Dictionary
		var node := row.get("node") as Node
		if node == null:
			continue
		# 门扇可能挂在自己房间名下，也可能挂在对面房间名下 —— 按**位置**归属，
		# 凡是落在这间房墙面上的门都算占槽，这才是「会不会堵路」的正确口径。
		var local := room.to_local((node as Node3D).global_position)
		if absf(local.y) > 6.0:
			continue
		var wall := ""
		var lane := 0.0
		if absf(local.x + half.x) <= 0.6:
			wall = "west"
			lane = local.z
		elif absf(local.x - half.x) <= 0.6:
			wall = "east"
			lane = local.z
		elif absf(local.z + half.y) <= 0.6:
			wall = "north"
			lane = local.x
		elif absf(local.z - half.y) <= 0.6:
			wall = "south"
			lane = local.x
		if wall.is_empty():
			continue
		var half_along := half.x if wall == "north" or wall == "south" else half.y
		if absf(lane) > half_along + 0.1:
			continue
		occupied.append({
			"wall": wall, "lane": snappedf(lane, 0.1), "label": str(row.get("label", "")),
		})
	if occupied.is_empty():
		print("    （这间房没有任何门）")
		return
	for value in occupied:
		var row := value as Dictionary
		print("    占槽：%s lane=%+.1f   ← %s" % [
			str(row.get("wall", "")), float(row.get("lane", 0.0)), str(row.get("label", "")),
		])
	print("    空槽候选（5m 网格，已剔除占用）：北 %s / 南 %s / 西 %s / 东 %s" % [
		str(_free_lanes(occupied, "north", half.x)),
		str(_free_lanes(occupied, "south", half.x)),
		str(_free_lanes(occupied, "west", half.y)),
		str(_free_lanes(occupied, "east", half.y)),
	])


## 以 5m 网格给出该墙上的候选 lane（与模板 `wall_lane_table` 同风格），
## 剔除已被占用（±1.6m 内）的。只为探针出候选，不作为产品逻辑。
func _free_lanes(occupied: Array, wall: String, half_along: float) -> Array:
	var out: Array = []
	var steps := int(floor(half_along / 5.0))
	for index in range(-steps, steps + 1):
		var lane := float(index) * 5.0
		var taken := false
		for value in occupied:
			var row := value as Dictionary
			if str(row.get("wall", "")) != wall:
				continue
			if absf(float(row.get("lane", 0.0)) - lane) < 1.6:
				taken = true
				break
		if not taken:
			out.append(lane)
	return out
