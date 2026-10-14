extends Node
## 逐种子实测：远征01 **全 13 房**的落位、房向、美术帧、门位是否自洽。
##
## 起因：业主实测「安全屋被墙面挡死、且后面房间也错位，且时好时坏（种子相关）」。
## 本探针不读代码推断，直接把每局真身装配结果打出来：
##   房心 / 房向(template_rotation_deg 与 global_rotation.y) / 美术根 local+global rot
##   / 门洞所在面 / 是否有几何清单 / 安全房转角步数
## 判据（每房独立算）：
##   ① 安全房：美术根朝向步数 × 90° 是否等于由门向推出的期望步数；
##   ② 非锚定房：美术根的**全局**朝向是否等于房的**全局**朝向（差 180° ⇒ 门开在实墙上）；
##   ③ 相邻两房门洞世界坐标是否重合（错位会在这里先露头）。

const EXP01_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")

## 业主截图里的种子排第一；其余三个用于对照「同关不同种子差异」。
const SEEDS: Array[int] = [286648852, 77001199, 20260919, 11111, 22222, 33333]


func _ready() -> void:
	call_deferred("probe")


func probe() -> void:
	for seed_value in SEEDS:
		await _one(seed_value)
	print("EXP01_SEED_LAYOUT_DONE")
	get_tree().quit(0)


func _one(seed_value: int) -> void:
	var tower := EXP01_SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = seed_value
	add_child(tower)
	for _i in range(8):
		await get_tree().process_frame
		await get_tree().physics_frame
	print("")
	print("========== SEED %d ==========" % seed_value)
	var order: Array[String] = [
		"entry", "room_01", "room_02", "room_03", "room_04", "room_05",
		"room_06", "room_07", "room_08", "room_09", "room_10", "boss", "extraction",
	]
	var door_world: Dictionary = {}
	for key in order:
		var room := tower._room_by_id.get(key) as DungeonRoom3D
		if room == null:
			print("  %-11s <缺>" % key)
			continue
		var art := room.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
		if art == null:
			art = room.get_node_or_null("SafeRoomArtRoot") as Node3D
		var entries := room.authored_layout_instances
		var dims := room.get_dimensions()
		print("  %-11s pos=(%8.2f,%7.2f,%8.2f) 房向meta=%5.1f 房全局yaw=%7.1f 清单=%4d dims=(%5.1f,%5.1f)" % [
			key,
			room.global_position.x, room.global_position.y, room.global_position.z,
			fposmod(float(room.get_meta("template_rotation_deg", 0.0)), 360.0),
			rad_to_deg(room.global_rotation.y),
			entries.size(), dims.x, dims.y,
		])
		if art == null:
			print("              art=<无>")
		else:
			var art_global := rad_to_deg(art.global_rotation.y)
			var room_global := rad_to_deg(room.global_rotation.y)
			var delta := fposmod(art_global - room_global + 180.0, 360.0) - 180.0
			print("              art=%s local=%5.1f global=%7.1f 与房间差=%7.1f° %s" % [
				str(art.name), rad_to_deg(art.rotation.y), art_global, delta,
				"✅" if absf(delta) < 1.0 else "🔴错位",
			])
		var port_desc: Array[String] = []
		for port_value in room.connection_ports:
			var port := port_value as Dictionary
			var target := str(port.get("target_room_id", port.get("target", "")))
			var side := str(port.get("side", "?"))
			var lane := float(port.get("lane_m", 0.0))
			port_desc.append("%s->%s@%s(%.1f)" % [str(port.get("port_id", "?")), target, side, lane])
			if target != "":
				door_world["%s|%s" % [key, target]] = _port_world(room, port)
		print("              口: %s" % " ".join(port_desc))
		if key == "entry":
			print("              安全房: orientation_steps=%s doors=%s 墙件=%s 期望=%s 角件=%s" % [
				str(room.get_meta("safe_room_orientation_steps", -1)),
				str(room.doors), str(room.get_meta("safe_room_wall_module_count", -1)),
				str(room.get_meta("safe_room_wall_expected_count", -1)),
				str(room.get_meta("safe_room_corner_module_count", -1)),
			])
	# 相邻门洞重合度
	print("  --- 相邻门洞世界坐标差（>0.5m 即错位） ---")
	for key in order:
		for other in order:
			var a: Variant = door_world.get("%s|%s" % [key, other], null)
			var b: Variant = door_world.get("%s|%s" % [other, key], null)
			if a == null or b == null:
				continue
			if key > other:
				continue
			var gap: float = (a as Vector3).distance_to(b as Vector3)
			print("    %-10s <-> %-10s gap=%.3f %s" % [
				key, other, gap, "OK" if gap < 0.5 else "🔴错位",
			])
	tower.free()
	await get_tree().process_frame
	await get_tree().process_frame


func _port_world(room: DungeonRoom3D, port: Dictionary) -> Vector3:
	var dims := room.get_dimensions()
	var lane := float(port.get("lane_m", 0.0))
	var side := str(port.get("side", ""))
	match side:
		"north":
			return room.to_global(Vector3(lane, 0.0, -dims.y * 0.5))
		"south":
			return room.to_global(Vector3(lane, 0.0, dims.y * 0.5))
		"west":
			return room.to_global(Vector3(-dims.x * 0.5, 0.0, lane))
		"east":
			return room.to_global(Vector3(dims.x * 0.5, 0.0, lane))
	return room.global_position
