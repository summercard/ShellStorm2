extends Node

## 一次性探针（业主 2026-10-21）：「08 号房间有一边墙的位置错位了。」
##
## 不猜是哪一边 —— 把四面墙**实际落在哪里**量成一条剖面：
## 沿每条边每 1 m 取一点，从房间内侧朝外打一条 14 m 的长射线，记录「首个命中离房间边界多远」
## （负数 = 墙在房间**里面**，正数 = 墙在房间**外面**，`---` = 14 m 内什么都没有）。
##
## 用法：
##   SS2_ROOM=room_08 godot --headless --path . res://tests/verification/probe_room_wall_profile.tscn
##   SS2_ROOM=room_01 godot --headless --path . res://tests/verification/probe_room_wall_profile.tscn

const EXPEDITION_SCENE := "res://scenes/ExpeditionLevel01_3D.tscn"
const WAIT_LIMIT_S := 60.0
const STEP_M := 1.0
## 从边界往房间**内**退这么多再起射，避免起点就贴在墙上。
const START_INSET_M := 6.0
## 射线总长（从起点朝外）。
const RAY_LENGTH_M := 20.0
const RAY_Y_M := 1.2

var _room: DungeonRoom3D = null


func _ready() -> void:
	var want := OS.get_environment("SS2_ROOM")
	if want.is_empty():
		want = "room_08"
	var scene := load(EXPEDITION_SCENE) as PackedScene
	var tower := scene.instantiate() as TowerDescent3D
	tower.test_mode = false
	add_child(tower)

	var waited := 0.0
	while waited < WAIT_LIMIT_S:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if not (tower.get("_records") as Array).is_empty():
			for _i in range(5):
				await get_tree().process_frame
			break

	for node in tower.find_children("*", "", true, false):
		if node is DungeonRoom3D and str((node as DungeonRoom3D).room_id) == want:
			_room = node as DungeonRoom3D
			break
	if _room == null:
		print("找不到房间 %s" % want)
		get_tree().quit(1)
		return

	var dims := _room.get_dimensions()
	print("")
	print("=== 墙剖面  room=%s  尺寸=%.1fx%.1f  rotY=%.1f°  doors=%s ===" % [
		want, dims.x, dims.y, rad_to_deg(_room.global_rotation.y), str(_room.doors),
	])
	print("口径：每格 = 该处墙离房间边界多少米（负=墙在房间里侧，正=墙在房间外，---=14m 内无墙）")
	print("")

	var half_x := dims.x * 0.5
	var half_z := dims.y * 0.5
	for side in ["north", "south", "east", "west"]:
		_print_side(side, dims, half_x, half_z)
	print("")
	print("ROOM_WALL_PROFILE_END")
	get_tree().quit(0)


func _print_side(side: String, dims: Vector2, half_x: float, half_z: float) -> void:
	var space := get_viewport().world_3d.direct_space_state
	var span := dims.x if (side == "north" or side == "south") else dims.y
	var count := maxi(1, int(span / STEP_M))
	var line := ""
	var hits: Array[float] = []
	for index in range(count):
		var t := -span * 0.5 + (float(index) + 0.5) * (span / float(count))
		var boundary := Vector3.ZERO
		var outward := Vector3.ZERO
		match side:
			"north":
				boundary = Vector3(t, 0.0, -half_z)
				outward = Vector3(0.0, 0.0, -1.0)
			"south":
				boundary = Vector3(t, 0.0, half_z)
				outward = Vector3(0.0, 0.0, 1.0)
			"east":
				boundary = Vector3(half_x, 0.0, t)
				outward = Vector3(1.0, 0.0, 0.0)
			"west":
				boundary = Vector3(-half_x, 0.0, t)
				outward = Vector3(-1.0, 0.0, 0.0)
		var origin := _room.global_transform * (boundary - outward * START_INSET_M)
		var dir := (_room.global_transform.basis * outward).normalized()
		origin.y = _room.global_position.y + RAY_Y_M
		var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * RAY_LENGTH_M)
		query.collide_with_areas = false
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			line += " ---"
			continue
		var hit_distance := origin.distance_to(hit.get("position", origin) as Vector3)
		# 相对边界的位置：命中点比边界更靠里 => 负数。
		var offset := START_INSET_M - hit_distance
		hits.append(offset)
		if absf(offset) <= 0.6:
			line += "   ." if false else "   0"
		elif offset < 0.0:
			line += "%4.0f" % offset
		else:
			line += "%+4.0f" % offset
	print("  %-5s %s" % [side, line])
	if not hits.is_empty():
		var worst := 0.0
		for value in hits:
			if absf(value) > absf(worst):
				worst = value
		print("        最远偏离边界 %+.1f m（%d/%d 点命中）" % [worst, hits.size(), count])
