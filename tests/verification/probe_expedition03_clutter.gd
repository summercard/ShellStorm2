extends Node
## 远征03 房间里的「场景可交互易碎小物件」随机布置探针。
##
## 验的是五条会真出事的性质，不是「节点数对得上」：
##   1. 每间应布置的房间都拿到了物件（能力段生效）
##   2. 全部落在房间走行面内（不穿墙、不出房）
##   3. 离门/端口有净空（不堵门）
##   4. 彼此不重叠（不叠成一堆）
##   5. 流送卸载重建后位置逐格不变（离开再回来不会「换地方」）
##
## 第 5 条最容易漏：随机布置若直接用 randf()，房间重建就会重新抽一次，
## 玩家进进出出看到罐子自己跑位 —— 而那不会让任何「数量断言」变红。

const LEVEL_SCENE := "res://scenes/ExpeditionLevel03_3D.tscn"
const LEVEL_ID := "expedition_03"

var failures: Array[String] = []
var tower: TowerDescent3D
var placements: Dictionary = {}


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error("E3_CLUTTER: " + message)


func _ready() -> void:
	if not GameDesignConfig.select_expedition_level(LEVEL_ID):
		check(false, "select_expedition_level 被拒绝")
		_finish()
		return
	tower = (load(LEVEL_SCENE) as PackedScene).instantiate() as TowerDescent3D
	tower.set("test_mode", true)
	tower.set("run_seed_override", 100990)
	add_child(tower)
	for step in range(90):
		await get_tree().process_frame
		if not (tower.get("_room_by_id") as Dictionary).is_empty():
			break
	await _settle()
	var rooms: Dictionary = tower.get("_room_by_id")
	check(not rooms.is_empty(), "远征03 没有建出房间")
	if rooms.is_empty():
		_finish()
		return
	var total := 0
	var placed_rooms := 0
	var excluded_rooms := 0
	var skipped_small := 0
	for room_id in rooms:
		var room := rooms[room_id] as DungeonRoom3D
		room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
		room.ensure_detail_built()
	await _settle()
	# 第一遍：逐房核对并记录位置
	for room_id in rooms:
		var room := rooms[room_id] as DungeonRoom3D
		var clutter := _room_clutter(room)
		var excluded := room.room_type in ["STAIR_LOBBY", "BOSS"]
		if excluded:
			excluded_rooms += 1
			continue
		if clutter.is_empty():
			var dimensions := room.get_dimensions()
			var min_size := float(room.interactive_clutter_plan.get("min_room_size_m", 0.0))
			# 显式的小房跳过（5×5 十字路口）不算错；尺寸够却没物件才是缺陷。
			if min_size > 0.0 and minf(dimensions.x, dimensions.y) < min_size:
				skipped_small += 1
				continue
			check(
				false,
				"%s 尺寸够却没布置 type=%s dims=%s" % [room.room_id, room.room_type, dimensions]
			)
			continue
		placed_rooms += 1
		total += clutter.size()
		check(clutter.size() >= 3 and clutter.size() <= 6, "%s 数量越界 %d" % [room.room_id, clutter.size()])
		_check_room(room, clutter)
		var snapshot: Array = []
		for item in clutter:
			snapshot.append({
				"id": str(item.get_meta("clutter_id", "")),
				"pos": item.position,
				"yaw": item.rotation.y,
			})
		placements[room.room_id] = snapshot
	print("E3_CLUTTER_ROOMS placed=%d excluded=%d skipped_small=%d total_items=%d" % [
		placed_rooms, excluded_rooms, skipped_small, total
	])
	check(placed_rooms >= 8, "随机布置覆盖房间过少：%d" % placed_rooms)
	check(total >= 30, "随机布置总量过少：%d" % total)
	# 第二遍：流送重建，位置必须逐格不变
	for room_id in placements:
		var room := rooms[room_id] as DungeonRoom3D
		room.set_stream_state(DungeonRoom3D.STREAM_DATA_ONLY)
		await get_tree().process_frame
		room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
		room.ensure_detail_built()
	await _settle()
	var drift := 0
	for room_id in placements:
		var room := rooms[room_id] as DungeonRoom3D
		var before: Array = placements[room_id]
		var after := _room_clutter(room)
		if after.size() != before.size():
			check(false, "%s 重建后数量变了 %d -> %d" % [room_id, before.size(), after.size()])
			continue
		for index in range(after.size()):
			var record: Dictionary = before[index]
			var item: BreakableClutter3D = after[index]
			if str(item.get_meta("clutter_id", "")) != str(record["id"]):
				drift += 1
				continue
			if item.position.distance_to(record["pos"] as Vector3) > 0.001:
				drift += 1
			elif absf(item.rotation.y - float(record["yaw"])) > 0.001:
				drift += 1
	check(drift == 0, "重建后物件位置/朝向漂移 %d 处" % drift)
	print("E3_CLUTTER_DRIFT ", drift)
	await _verify_real_shot(rooms)
	_finish()


## 在远征03 的真房间里打一枪：证明这些物件不是「只摆着好看」，
## 而是真能被 Projectile3D 打碎，且碎完不挡路。
func _verify_real_shot(rooms: Dictionary) -> void:
	for room_id in placements:
		var room := rooms[room_id] as DungeonRoom3D
		var clutter := _room_clutter(room)
		if clutter.is_empty():
			continue
		var target: BreakableClutter3D = clutter[0]
		var direction := Vector3(0.0, 0.0, -1.0)
		var projectile := Projectile3D.new()
		add_child(projectile)
		projectile.collision_mask = 5
		projectile.position = target.global_position - direction * 1.2 + Vector3(0, 0.22, 0)
		projectile.activate(
			{"direction": direction, "speed": 22.0, "damage": 1, "hostile": false},
			projectile.position
		)
		await get_tree().process_frame
		for step in range(30):
			await get_tree().physics_frame
			await get_tree().process_frame
			if target.is_broken():
				break
		check(target.is_broken(), "%s 真子弹没打碎物件" % room_id)
		if target.is_broken():
			check(target.fragment_total() <= 5, "%s 碎片超过 5 块" % room_id)
			check(
				target.break_direction().dot(direction) > 0.99,
				"%s 破碎方向与子弹方向不一致" % room_id
			)
		if is_instance_valid(projectile):
			projectile.queue_free()
		await get_tree().physics_frame
		print("E3_CLUTTER_SHOT ", room_id, " broken=", target.is_broken(), " frags=", target.fragment_total())
		return
	check(false, "没有任何房间可做真实射击验证")


func _room_clutter(room: DungeonRoom3D) -> Array[BreakableClutter3D]:
	var result: Array[BreakableClutter3D] = []
	for value in get_tree().get_nodes_in_group("breakable_clutter_3d"):
		var clutter := value as BreakableClutter3D
		if clutter != null and room.is_ancestor_of(clutter):
			result.append(clutter)
	return result


func _check_room(room: DungeonRoom3D, clutter: Array[BreakableClutter3D]) -> void:
	var dimensions := room.get_dimensions()
	var half_x := dimensions.x * 0.5
	var half_z := dimensions.y * 0.5
	for item in clutter:
		var local := item.position
		var bounds := item.bounds_size
		# 视觉包络也算进去：中心在房内但半个身子穿墙，同样是错。
		check(
			absf(local.x) + bounds.x * 0.5 <= half_x + 0.02
			and absf(local.z) + bounds.z * 0.5 <= half_z + 0.02,
			"%s/%s 出房或穿墙 %s" % [room.room_id, item.name, local]
		)
		check(absf(local.y) <= 0.35, "%s/%s 离地异常 y=%0.3f" % [room.room_id, item.name, local.y])
		# 门净空：门在墙中点，走廊房一墙多门也不该把物件顶在门口。
		for side in room.doors:
			var door_center := Vector3.ZERO
			match str(side):
				"north":
					door_center = Vector3(0.0, 0.0, -half_z)
				"south":
					door_center = Vector3(0.0, 0.0, half_z)
				"west":
					door_center = Vector3(-half_x, 0.0, 0.0)
				"east":
					door_center = Vector3(half_x, 0.0, 0.0)
			var planar := Vector2(local.x - door_center.x, local.z - door_center.z).length()
			check(planar >= 2.0, "%s/%s 离 %s 门太近 %0.2fm" % [room.room_id, item.name, side, planar])
	for first in range(clutter.size()):
		for second in range(first + 1, clutter.size()):
			var gap := Vector2(
				clutter[first].position.x - clutter[second].position.x,
				clutter[first].position.z - clutter[second].position.z
			).length()
			check(gap >= 1.0, "%s 物件重叠 %s/%s %0.2fm" % [
				room.room_id, clutter[first].name, clutter[second].name, gap
			])


func _settle() -> void:
	for step in range(4):
		await get_tree().process_frame
		await get_tree().physics_frame


func _finish() -> void:
	if failures.is_empty():
		print("E3_CLUTTER_OK")
	else:
		print("E3_CLUTTER_FAIL count=%d" % failures.size())
		for failure in failures.slice(0, 20):
			print("  - ", failure)
	get_tree().quit(0 if failures.is_empty() else 1)
