extends SceneTree
const CONTRACT := preload("res://src/world3d/RuntimeRoomArtSource.gd")
const ROOM := "res://src/world3d/DungeonRoom3D.gd"
const LEVEL := "res://scenes/ExpeditionLevel03_3D.tscn"
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, reason: String) -> void:
	checks += 1
	if not condition:
		failures.append(reason)
		printerr("RUNTIME_SOURCE_FAIL ", reason)

func _run() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://.godot/editor/scene_builder_runtime/latest.json"))
	if not data is Dictionary:
		check(false, "run runtime_capture.py first")
		_finish()
		return
	var level = load(LEVEL).instantiate()
	level.test_mode = true
	level.run_seed_override = int(data["seed"])
	root.add_child(level)
	for i in range(12):
		await process_frame
	var measured := 0
	var binding_cases: Array = []
	var landed := 0
	for row in data["rows"]:
		var room: Node3D = (level.get("_room_by_id") as Dictionary).get(str(row["room_id"]))
		check(room != null, "runtime room missing " + str(row["room_id"]))
		if room == null:
			continue
		room.call("ensure_shell_built")
		# ── 已落地美术的房间走另一条路 ────────────────────────────────────
		#
		# `path` 指向 `runtime_rooms/` 时，说明这间房已有正式美术（工坊保存过），
		# 采集器就不会再拍白盒快照 —— 它直接把这间房指向正式场景。
		# 那种情况下 `WhiteboxShell` 根本不存在（正式美术的容器是 `ArtComponents`），
		# 下面这整套「白盒快照往返」的断言**不适用**，硬跑只会得到假红
		# （2026-10-31 实测 17 项 "captured shell bounds differ"，全部是这个原因）。
		#
		# 已落地美术的正确验收在 `tools/_exp03_manor_shell_verify.tscn`：
		# 它按房间逐项查「美术层是否接管、地板是否满、四面是否覆盖、每个门位格
		# 放的是不是门墙模块」，比这里的 bounds 对照严格得多。
		# 本测试只保留对**尚未落地美术**的房间做白盒往返，并把跳过的数量打出来。
		if str(row.get("path", "")).contains("/runtime_rooms/"):
			landed += 1
			continue
		var snapshot := (load(str(row["path"])) as PackedScene).instantiate() as Node3D
		root.add_child(snapshot)
		var descriptor := CONTRACT.describe(room)
		check(str(descriptor["signature"]) == str(snapshot.get_meta("runtime_room_signature", "")), "room signature differs from actual level")
		check(is_equal_approx(float(row["wall_height_m"]), 2.8), "actual wall height differs from 2.8m")
		# 快照不再承载连接端口（2026-10-31）：端口是几何层，由运行时按本局算。
		# 同一份美术会被不同门位的房间复用，快照里的端口必然互相矛盾。
		var ports_container := snapshot.get_node_or_null("ConnectionPorts")
		check(ports_container == null or ports_container.get_child_count() == 0,
			"art snapshot must not carry connection ports")
		check(snapshot.get_node("WhiteboxShell").get_child_count() > 4, "runtime shell missing")
		check(snapshot.find_children("*", "Area3D", true, false).is_empty(), "gameplay trigger leaked into art")
		check(snapshot.find_children("*", "RoomDoor3D", true, false).is_empty(), "door FSM leaked into art")
		var clean := true
		for child in snapshot.find_children("*", "Node", true, false):
			if child.get_script() != null:
				clean = false
		check(clean, "runtime script leaked into art")
		# Every extracted structural part keeps the same local bounds and collision count.
		var source_bounds := _shell_bounds(room)
		var art_bounds := _shell_bounds(snapshot.get_node("WhiteboxShell"))
		check(source_bounds.is_equal_approx(art_bounds), "captured shell bounds differ " + str(row["room_id"]) + " " + str(source_bounds) + " vs " + str(art_bounds))
		measured += 1
		if str(row["room_id"]) in ["start", "boss_foyer", "room_01"]:
			binding_cases.append([room, snapshot])
		else:
			snapshot.free()
	# `measured` 只统计走了白盒快照往返的房间；已落地美术的跳过，
	# 所以总数要对上 `房间数 - landed`，否则说明有房间既没测也没跳过。
	check(measured == (level.get("_rooms") as Array).size() - landed,
		"some actual rooms omitted from capture")
	for pair in binding_cases:
		await _verify_binding(pair[0], pair[1])
		pair[1].free()
	level.queue_free()
	await process_frame
	print("RUNTIME_SOURCE_MEASURED rooms=", measured, " landed_skipped=", landed)
	_finish()

func _shell_bounds(node: Node3D) -> AABB:
	var result := AABB()
	var found := false
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		# 结构件判据统一走契约（2026-10-31）：原来这里自带一份
		# `contains("prp_room_wall")` 的名单，与运行时那份不是同一个 —— 换正式
		# 美术资产后两份会分叉，而分叉的表现是"包围盒对不上"这种看不出根因的红。
		var parent: Node = mesh
		var safe := true
		var structural := false
		while parent != node and parent != null:
			if parent.get_script() != null or parent is Area3D or parent is Light3D:
				safe = false
			if CONTRACT.is_structure_prefab(str(parent.scene_file_path)):
				structural = true
			parent = parent.get_parent()
		if not safe or not structural:
			continue
		var box: AABB = node.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
		result = result.merge(box) if found else box
		found = true
	return result

func _verify_binding(original: Node3D, snapshot: Node3D) -> void:
	var descriptor := CONTRACT.describe(original)
	var position := original.position
	original.position += Vector3(1000, 50, 1000)
	check(CONTRACT.describe(original)["signature"] == descriptor["signature"], "world position contaminated art identity")
	original.position = position
	var args := OS.get_cmdline_user_args()
	var directory := args[0] if not args.is_empty() else OS.get_user_data_dir()
	var base := directory.path_join("f00_binding_probe.tscn")
	var target := CONTRACT.art_path(base, descriptor)
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	var receipt := Marker3D.new()
	receipt.name = "ArtRoundtripReceipt"
	snapshot.get_node("ArtComponents").add_child(receipt)
	receipt.owner = snapshot
	var packed := PackedScene.new()
	check(packed.pack(snapshot) == OK and ResourceSaver.save(packed, target) == OK, "cannot save edited room")
	var test_room = load(ROOM).new()
	test_room.configure({"room_id": original.get("room_id"), "room_type": original.get("room_type"),
		"size_class": original.get("size_class"), "custom_dimensions": original.call("get_dimensions"),
		"tower_module_shell": false, "procedural_shell": true, "theme": original.get("theme"),
		"doors": original.get("doors"), "door_targets": original.get("door_targets"),
		"safe_room_corner_l": original.get("safe_room_corner_l"), "open_wall_directions": original.get("open_wall_directions"),
		"connection_ports": original.get("connection_ports"), "door_opening_style": "slide",
		"static_layout_scene_path": base})
	root.add_child(test_room)
	check(CONTRACT.matching_path(test_room, base) == target, "runtime failed to resolve saved art")
	test_room.ensure_shell_built()
	# 2026-10-31 语义变更：flow 房间里烘焙场景**只当美术层**，不再整房接管。
	# 判据从 `static_layout_scene_loaded` 换成 `art_layer_loaded` —— 前者表示
	# "墙体由该场景接管"，现在墙体归程序化分支，设它会误导
	# `_room_walls_owned_by_static_layout()` 等判据。
	check(bool(test_room.get_meta("art_layer_loaded", false)), "real room build did not load saved art")
	check(not bool(test_room.get_meta("static_layout_scene_loaded", false)),
		"flow room took over the shell instead of layering art")
	check(test_room.find_child("ArtRoundtripReceipt", true, false) != null, "edited art was not present in actual runtime room")
	var loaded_art := test_room.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
	if loaded_art == null:
		loaded_art = test_room.get_node_or_null("SafeRoomArtRoot") as Node3D
	check(loaded_art != null, "runtime art root missing after real build")
	# 几何层必须由运行时重建：墙在、且美术层里一份几何件都不剩。
	# 这两条是「跨局复用」的前提 —— 墙若跟着美术走，换一局门位就错位。
	check(test_room.get_node_or_null("Wall_north") != null, "procedural wall missing after art layer load")
	check(int(test_room.get_meta("art_layer_geometry_stripped", 0)) > 0, "art layer kept geometry parts")
	if loaded_art != null:
		var leftover := _shell_bounds(loaded_art)
		check(leftover.size.is_zero_approx() or leftover.size.y < 0.05,
			"art layer still carries structural geometry " + str(leftover))
		print("RUNTIME_ART_LAYER room=", original.get("room_id"),
			" stripped=", int(test_room.get_meta("art_layer_geometry_stripped", 0)),
			" art_bounds=", leftover)
	check(is_zero_approx(test_room._static_layout_alignment_delta_deg(snapshot)), "captured local geometry was rotated again")
	# 复用键的**第三次**语义演进（每次都是设计变更，不是修 bug）：
	#
	#   ① 2026-10-31 之前：门位进签名 → 每房一键 → 断言「不同端口拒绝复用」。
	#      那正是「美术做一次只有一局能用」的根因，业主明确要求同模板算可复用。
	#   ② 2026-10-31 中：门位不进签名 → 一局收敛到十几份 → 断言「不同门位必须复用」。
	#      复用成立了，但**墙和地板也被当装饰留在美术层**，套到门位不同的房间就错位堵门。
	#   ③ 2026-10-31 晚（当前）：门位不进**签名**（保持收敛），但进**文件名**
	#      （`<template>_<sig12>_<门位指纹>`）。结构件（护墙 / 门墙 / 地砖）进了美术层，
	#      门墙模块洞口固定 2.2m 居中，只能摆在本局门位那一格。
	#
	# 所以「不同门位必须复用同一份美术」在③已不成立 —— 复用粒度是
	# 「同模板 + 同门位」，装饰仍可跨种子共享（门位恰好相同时命中同一份）。
	var ports: Array = test_room.connection_ports.duplicate(true)
	if not ports.is_empty():
		ports[0]["lane_m"] = float(ports[0].get("lane_m", 0)) + 5.0
		test_room.connection_ports = ports
		check(CONTRACT.matching_path(test_room, base) != target,
			"different door lane must NOT reuse the same structural art (门墙会错位堵门)")
	test_room.free()
	DirAccess.remove_absolute(target)
	print("RUNTIME_SOURCE_BINDING actual_room_loaded=1 same_template_reuses_art=1 art_layer_only=1")

func _collision_layers(node: Node) -> Dictionary:
	var result := {}
	for shape in node.find_children("*", "CollisionShape3D", true, false):
		var parent := shape.get_parent() as CollisionObject3D
		var key := str(parent.collision_layer) if parent != null else "none"
		result[key] = int(result.get(key, 0)) + 1
	return result

func _finish() -> void:
	print("RUNTIME_SOURCE_%s checks=%d failures=%d" % ["OK" if failures.is_empty() else "FAILED", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
