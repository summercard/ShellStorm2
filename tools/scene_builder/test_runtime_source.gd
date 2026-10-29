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
	for row in data["rows"]:
		var room: Node3D = (level.get("_room_by_id") as Dictionary).get(str(row["room_id"]))
		check(room != null, "runtime room missing " + str(row["room_id"]))
		if room == null:
			continue
		room.call("ensure_shell_built")
		var snapshot := (load(str(row["path"])) as PackedScene).instantiate() as Node3D
		root.add_child(snapshot)
		var descriptor := CONTRACT.describe(room)
		check(str(descriptor["signature"]) == str(snapshot.get_meta("runtime_room_signature", "")), "room signature differs from actual level")
		check(is_equal_approx(float(row["wall_height_m"]), 2.8), "actual wall height differs from 2.8m")
		check(snapshot.get_node("ConnectionPorts").get_child_count() == (room.get("connection_ports") as Array).size(), "runtime ports lost")
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
	check(measured == (level.get("_rooms") as Array).size(), "some actual rooms omitted from capture")
	for pair in binding_cases:
		await _verify_binding(pair[0], pair[1])
		pair[1].free()
	level.queue_free()
	await process_frame
	print("RUNTIME_SOURCE_MEASURED rooms=", measured)
	_finish()

func _shell_bounds(node: Node3D) -> AABB:
	var result := AABB()
	var found := false
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		# Exclude doors, UI signs, details and scripted gameplay trees, just like capture.
		var parent: Node = mesh
		var safe := true
		var wall_or_floor := false
		while parent != node and parent != null:
			if parent.get_script() != null or parent is Area3D or parent is Light3D:
				safe = false
			var path := str(parent.scene_file_path)
			if path.contains("prp_room_floor") or path.contains("prp_room_wall") or path.contains("prp_room_corner") or path.contains("prp_room_door_lintel"):
				wall_or_floor = true
			parent = parent.get_parent()
		if not safe or not wall_or_floor:
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
	check(bool(test_room.get_meta("static_layout_scene_loaded", false)), "real room build did not load saved art")
	check(test_room.find_child("ArtRoundtripReceipt", true, false) != null, "edited art was not present in actual runtime room")
	var loaded_art := test_room.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
	if loaded_art == null:
		loaded_art = test_room.get_node_or_null("SafeRoomArtRoot") as Node3D
	check(loaded_art != null, "runtime art root missing after real build")
	if loaded_art != null:
		check(_shell_bounds(loaded_art).is_equal_approx(_shell_bounds(snapshot.get_node("WhiteboxShell"))), "runtime reattachment changed original low-wall geometry")
		print("RUNTIME_COLLISION_COUNTS room=", original.get("room_id"), " loaded=", _collision_layers(loaded_art), " source=", _collision_layers(snapshot))
		check(loaded_art.find_children("*", "CollisionShape3D", true, false).size() == snapshot.find_children("*", "CollisionShape3D", true, false).size(), "runtime reattachment changed structural collision count")
	check(is_zero_approx(test_room._static_layout_alignment_delta_deg(snapshot)), "captured local geometry was rotated again")
	var ports: Array = test_room.connection_ports.duplicate(true)
	if not ports.is_empty():
		ports[0]["lane_m"] = float(ports[0].get("lane_m", 0)) + 5.0
		test_room.connection_ports = ports
		check(CONTRACT.matching_path(test_room, base).is_empty(), "different port geometry incorrectly reused art")
	test_room.free()
	DirAccess.remove_absolute(target)
	print("RUNTIME_SOURCE_BINDING actual_room_loaded=1 mismatched_ports_rejected=1")

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
