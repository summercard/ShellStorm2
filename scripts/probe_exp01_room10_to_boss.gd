extends Node
## 通行实测：从 room_10 房内走到 Boss 房内（含下楼梯到竞技场平台）。
##
## 判据：① 两房门洞世界坐标重合（**含 height_m**，深井房的高位入口 +12）；
##      ② 开门后能走进 Boss 房高位平台；③ 能沿楼梯下到竞技场平台。

const EXP01_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const RUN_SEED := 77001199
const MAX_SECONDS := 20.0
const SPEED_MPS := 4.5
const ARRIVE_M := 1.2
const STALL_MOVE_M := 0.01
const STALL_FRAMES := 45

var _root: Window
var _checks := 0
var _failures: Array[String] = []


func _ready() -> void:
	_root = get_tree().root
	call_deferred("probe")


func probe() -> void:
	var tower := EXP01_SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = RUN_SEED
	_root.add_child(tower)
	for _i in range(6):
		await get_tree().process_frame
		await get_tree().physics_frame
	var room_10 := tower._room_by_id.get("room_10") as DungeonRoom3D
	var boss := tower._room_by_id.get("boss") as DungeonRoom3D
	if room_10 == null or boss == null:
		_fail("缺 room_10 或 boss")
		_finish()
		return
	var dims10 := room_10.get_dimensions()
	var dims_b := boss.get_dimensions()
	print("POS room_10=%s dims=(%.1f,%.1f)" % [_v(room_10.global_position), dims10.x, dims10.y])
	print("POS boss   =%s dims=(%.1f,%.1f)" % [_v(boss.global_position), dims_b.x, dims_b.y])

	# 两端口世界坐标：必须**带上声明的高度**。Boss 房是深井房，南口 height_m=12
	# （房下沉 -12 ⇒ 世界 y=0）；漏了它就会得出「两门差 12 m」的假红。
	var port10 := _port_world(room_10, "north")
	var portb := _port_world(boss, "south")
	print("DOOR room_10北口=%s  boss南口=%s  重合=%.3f" % [
		_v(port10), _v(portb), port10.distance_to(portb),
	])
	_check(port10.distance_to(portb) < 0.05, "两房门洞世界坐标不重合")

	var space := _root.get_world_3d().direct_space_state
	var before := _ray(space, port10 + Vector3.UP * 0.6, port10 + Vector3.UP * 0.6 + Vector3(0.0, 0.0, -4.0))
	print("DOOR 开门前射线 → %s" % ("空" if before.is_empty() else "%s @%s" % [
		str((before.collider as Node).name), _v(before.position as Vector3),
	]))

	for side in ["north", "south", "east", "west"]:
		for probe_room in [room_10, boss]:
			var door: Node3D = probe_room.get_door_node(side) as Node3D
			if door != null:
				door.set_open(true, true)
	await get_tree().physics_frame
	var after := _ray(space, port10 + Vector3.UP * 0.6, port10 + Vector3.UP * 0.6 + Vector3(0.0, 0.0, -4.0))
	print("DOOR 开门后射线 → %s" % ("空" if after.is_empty() else "%s @%s" % [
		str((after.collider as Node).name), _v(after.position as Vector3),
	]))
	_check(after.is_empty(), "开门后门洞仍被挡")

	var player: Player3D = tower.player
	player.input_locked = true
	var lane10 := port10.x - room_10.global_position.x
	var from := room_10.to_global(Vector3(lane10, 0.0, -dims10.y * 0.5 + 4.0))
	var landing := _art_to_world(boss, Vector3(0.0, 12.0, 44.0))
	var ok_a := await _walk(player, from, landing, "room_10 → 高位平台")
	_check(ok_a, "从 room_10 走不进 Boss 房")

	var arena := _art_to_world(boss, Vector3(0.0, 0.0, -22.5))
	var ok_b := await _walk(player, player.global_position, arena, "高位平台 → 竞技场平台")
	_check(ok_b, "下不去楼梯")

	var inside := boss.contains_world_position(player.global_position)
	print("END inside_boss=%s 房间局部=%s" % [str(inside), _v(boss.to_local(player.global_position))])
	_finish()


func _port_world(room: DungeonRoom3D, side: String) -> Vector3:
	var dims := room.get_dimensions()
	for port_value in room.connection_ports:
		var port := port_value as Dictionary
		if str(port.get("side", "")) != side:
			continue
		var lane := float(port.get("lane_m", 0.0))
		var height := float(port.get("height_m", 0.0))
		match side:
			"north":
				return room.to_global(Vector3(lane, height, -dims.y * 0.5))
			"south":
				return room.to_global(Vector3(lane, height, dims.y * 0.5))
			"west":
				return room.to_global(Vector3(-dims.x * 0.5, height, lane))
			_:
				return room.to_global(Vector3(dims.x * 0.5, height, lane))
	return room.to_global(Vector3(0.0, 0.0, -dims.y * 0.5))


func _art_to_world(room: DungeonRoom3D, local: Vector3) -> Vector3:
	var art := room.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
	if art == null:
		return room.to_global(local)
	return art.global_transform * local


func _walk(player: Player3D, from: Vector3, to: Vector3, label: String) -> bool:
	player.global_position = from
	player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame
	var target := to
	target.y = player.global_position.y
	player.begin_narrative_walk(target, MAX_SECONDS, SPEED_MPS)
	var stall := 0
	var last := player.global_position
	var reached := false
	for _i in range(int(MAX_SECONDS * 60.0)):
		player.tick_narrative_walk(1.0 / 60.0)
		await get_tree().physics_frame
		var gp := player.global_position
		if Vector2(gp.x - last.x, gp.z - last.z).length() < STALL_MOVE_M:
			stall += 1
		else:
			stall = 0
		last = gp
		if Vector2(gp.x - target.x, gp.z - target.z).length() <= ARRIVE_M:
			reached = true
			break
		if stall >= STALL_FRAMES:
			break
	player.end_narrative_walk()
	print("  WALK %-24s reached=%s from=%s end=%s" % [label, str(reached), _v(from), _v(last)])
	return reached


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	return space.intersect_ray(query)


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	for failure in _failures:
		print("FAIL ", failure)
	print("ROOM10_TO_BOSS_", "OK" if _failures.is_empty() else "FAILED",
		" checks=", _checks, " failures=", _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)


func _v(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]
