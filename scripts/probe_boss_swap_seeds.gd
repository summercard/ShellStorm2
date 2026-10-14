extends Node
## 逐种子实测：远征01 的 Boss 房**美术帧是否恒等于端口帧**。
##
## 为什么要它：Boss 房是 `anchor_policy=static_port_layout`，落位旋转由
## `_explicit_port_candidates` 按「子口与父口反向」现算 —— 而它依赖上游链的朝向。
## 若不同种子算出不同旋转，而美术是**烘焙固定帧**，就会出现「有的种子门开在实墙上」。
## 本探针把每个种子的：端口帧（南/北）、美术帧（高位门扇 z 符号）、盒心一起打出来。

const EXP01_SCENE: PackedScene = preload("res://scenes/ExpeditionLevel01_3D.tscn")
const SEEDS: Array[int] = [77001199, 20260919, 11111, 22222, 33333]


func _ready() -> void:
	call_deferred("probe")


func probe() -> void:
	for seed_value in SEEDS:
		await _one(seed_value)
	print("SEEDS_DONE")
	get_tree().quit(0)


func _one(seed_value: int) -> void:
	var tower := EXP01_SCENE.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = seed_value
	add_child(tower)
	for _i in range(6):
		await get_tree().process_frame
		await get_tree().physics_frame
	var room := tower._room_by_id.get("boss") as DungeonRoom3D
	if room == null:
		print("SEED %-9d boss=<缺>" % seed_value)
		tower.free()
		await get_tree().process_frame
		return
	# 端口帧：通往 room_10 的那个口在哪面墙
	var port_side := "<无>"
	var port_world := Vector3.ZERO
	for port_value in room.connection_ports:
		var port := port_value as Dictionary
		if str(port.get("target_room_id", "")) != "room_10":
			continue
		port_side = str(port.get("side", ""))
		var dims := room.get_dimensions()
		var lane := float(port.get("lane_m", 0.0))
		match port_side:
			"north":
				port_world = room.to_global(Vector3(lane, 0.0, -dims.y * 0.5))
			"south":
				port_world = room.to_global(Vector3(lane, 0.0, dims.y * 0.5))
			"west":
				port_world = room.to_global(Vector3(-dims.x * 0.5, 0.0, lane))
			_:
				port_world = room.to_global(Vector3(dims.x * 0.5, 0.0, lane))
	# 美术帧：高位门扇相对房间局部的 z 符号
	var art := room.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
	var leaf_z := INF
	if art != null:
		var stack: Array[Node] = [art]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			if str(node.name).contains("外壳门扇_0_exit_leaf"):
				leaf_z = room.to_local((node as Node3D).global_position).z
			for child in node.get_children():
				stack.append(child)
	var placements := room.spawn_placements
	var box0 := (placements[0] as Dictionary) if not placements.is_empty() else {}
	var box_has_center := not (box0.get("box_center", Vector2.ZERO) as Vector2).is_zero_approx()
	var box_center := box0.get("box_center", Vector2.ZERO) as Vector2
	# 判据：端口在南(+z) ⇒ 美术门扇应在 +z；端口在北(-z) ⇒ 美术门扇应在 -z
	var expect_positive := port_side == "south"
	var art_ok := (leaf_z > 0.0) == expect_positive if is_finite(leaf_z) else false
	print("SEED %-9d 端口侧=%-5s 端口世界=%s | 美术门扇局部z=%7.2f | 一致=%s | 盒心=(%.1f,%.1f) 有盒=%s | 房心=%s" % [
		seed_value, port_side, _v(port_world), leaf_z, str(art_ok),
		box_center.x, box_center.y, str(box_has_center), _v(room.global_position),
	])
	tower.free()
	await get_tree().process_frame
	await get_tree().process_frame


func _v(v: Vector3) -> String:
	return "(%.1f,%.1f,%.1f)" % [v.x, v.y, v.z]
