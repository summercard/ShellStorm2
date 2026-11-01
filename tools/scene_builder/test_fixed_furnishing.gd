extends SceneTree
const INDEX := preload("res://tools/scene_builder/scene_index.gd")
const CONTRACT := preload("res://src/world3d/RoomArtLayoutContract.gd")
const ART := preload("res://src/world3d/RuntimeRoomArtSource.gd")
const SEEDS := [77003244, 100990, 42, 123456, 7, 99, 2026, 31415, 55555, 808080, 9173, 6060, 1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12, 13]
var checks := 0
var failures: Array[String] = []
var expected := {}
var used := {}
var door_shapes := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, reason: String) -> void:
	checks += 1
	if not value:
		failures.append(reason)
		printerr("FIXED_FURNISHING_FAIL ", reason)

func snapshot(node: Node3D) -> Dictionary:
	var out := {}
	for value in node.find_children("*", "Node3D", true, false):
		var child := value as Node3D
		# Safe-room assembly publishes this session's ports; it owns these markers.
		if str(node.get_path_to(child)).get_slice("/", 0) == "ConnectionPorts":
			continue
		if CONTRACT.is_structure(node, child):
			continue
		var item := {"transform": child.transform, "prefab": child.scene_file_path, "visible": child.visible}
		if child is CollisionObject3D:
			item["layers"] = [(child as CollisionObject3D).collision_layer, (child as CollisionObject3D).collision_mask]
		if child is CollisionShape3D:
			var collider := child as CollisionShape3D
			item["disabled"] = collider.disabled
			item["shape"] = (collider.shape as BoxShape3D).size if collider.shape is BoxShape3D else str(collider.shape)
		out[str(node.get_path_to(child))] = item
	return out

func art_root(room: Node) -> Node3D:
	var result := room.get_node_or_null("AuthoredLayoutArtRoot") as Node3D
	return result if result != null else room.get_node_or_null("SafeRoomArtRoot") as Node3D

func _run() -> void:
	var level_scene := load("res://scenes/ExpeditionLevel03_3D.tscn") as PackedScene
	_verify_door_theme_contract()
	var formal_rows := INDEX.game_rooms()
	var paths := {}
	for row in formal_rows:
		check(not paths.has(row["path"]), "duplicate formal file")
		paths[row["path"]] = true
		var packed := load(str(row["path"])) as PackedScene
		check(packed != null and packed.can_instantiate(), "formal file cannot load " + str(row["path"]))
		if packed == null:
			continue
		var source := packed.instantiate() as Node3D
		check(source != null and FileAccess.get_file_as_string(str(row["path"])).get_slice("\n", 0).contains("format=3"), "formal scene format/root mismatch")
		if row["level_id"] == "expedition_03":
			expected[row["path"]] = snapshot(source)
			check(CONTRACT.furnishing_conflicts(source).is_empty(), "legal door clearance " + str(row["path"]))
			# A real untagged author collider must fail even when its prefab metadata
			# would claim visual-only. Do not let an always-empty query pass this test.
			var box: Dictionary = CONTRACT.door_boxes(CONTRACT.dimensions(source))[0]
			var body := StaticBody3D.new()
			body.name = "AuthorCollisionProbe"
			body.position = Vector3(float(box["x"]), 0.5, float(box["z"]))
			body.rotation = Vector3(0.4, 0.2, 0.15)
			body.collision_layer = 1
			source.add_child(body)
			var shape_node := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(0.6, 0.7, 0.8)
			shape_node.shape = shape
			body.add_child(shape_node)
			check(not CONTRACT.furnishing_conflicts(source).is_empty(), "clearance query missed an author collider")
			body.free()
		source.free()
	var content_files := 0
	for path in expected:
		var source := (load(path) as PackedScene).instantiate() as Node3D
		var geometry: Dictionary = source.get_meta("runtime_room_geometry", {})
		if not str(geometry.get("type", "")).is_empty():
			content_files += 1
		source.free()
	check(content_files == 18, "expected original 18 content-room resources plus optional connector art")
	var seed_values: Array = SEEDS
	if "--quick" in OS.get_cmdline_user_args():
		seed_values = [77003244, 42]
	for seed_value in seed_values:
		var level = level_scene.instantiate()
		level.test_mode = true
		level.run_seed_override = seed_value
		root.add_child(level)
		for frame in 16:
			await process_frame
		_verify_indoor_envelope(level)
		for room in level.get("_rooms"):
			room.ensure_shell_built()
			for door in room.get_children():
				if door.get_script() != null and door.get_script().resource_path == "res://src/world3d/RoomDoor3D.gd":
					check(door.get_snapshot()["visual_asset_id"] == "ENV-EXP03-MANOR-DOOR-DOUBLE", "expedition03 still uses an armored door")
		var content := 0
		for value in level.get("_rooms"):
			var room := value as Node3D
			room.call("ensure_shell_built")
			var path := ART.matching_path(room, str(room.get("static_layout_scene_path")))
			if not expected.has(path):
				continue
			content += 1
			used[path] = true
			var loaded := art_root(room)
			check(loaded != null, "art root missing " + str(room.get("room_id")))
			if loaded != null:
				if snapshot(loaded) != expected[path]:
					var actual := snapshot(loaded)
					for key in actual:
						if not expected[path].has(key) or actual[key] != expected[path][key]:print("DIFF ", key, " got=", actual[key], " want=", expected[path].get(key))
				check(snapshot(loaded) == expected[path], "authored transform/node/collision changed " + str(room.get("room_id")))
				room.call("set_stream_state", 0)
				room.call("set_stream_state", 2)
				check(snapshot(loaded) == expected[path], "streaming changed authored furniture")
			check(int(room.get_meta("manor_furnishing_rebuilt", 0)) == 0, "runtime regenerated furniture")
		if seed_value == 77003244:
			await _fixture(level.get("_room_by_id")["n02"], true)
			await _fixture(level.get("_room_by_id")["start"], false)
		await physics_frame
		await physics_frame
		await _door_clearance(level)
		print("FIXED_SEED ", seed_value, " authored_rooms=", content)
		level.queue_free()
		await process_frame
	check(used.size() == expected.size() if seed_values.size() == SEEDS.size() else used.size() > 10, "canonical pool not exercised")
	print("FIXED_FURNISHING_%s checks=%d failures=%d files=%d used=%d door_samples=%d" % ["OK" if failures.is_empty() else "FAILED", checks, failures.size(), formal_rows.size(), used.size(), door_shapes])
	quit(0 if failures.is_empty() else 1)

func _verify_door_theme_contract() -> void:
	# MainLoop scripts compile before Autoload globals exist; load this gameplay
	# class only after _run starts, as with the other room fixtures in this test.
	var room = load("res://src/world3d/DungeonRoom3D.gd").new()
	room.room_type = "COMBAT"
	room.theme = load("res://assets/art/environments/dungeon_3d/env_expedition03_manor_kit_top3d.tres")
	for style in ["slide", "lift"]:
		room.door_opening_style = style
		check(room._door_panel_visual("").resource_path.contains("/manor_door_double/"), "explicit theme door ignored")
	room.theme = load("res://assets/art/environments/dungeon_3d/env_iron_frontier_kit_top3d_v001.tres")
	for style in ["slide", "lift"]:
		room.door_opening_style = style
		check(room._door_panel_visual("") == room.TOWER_DOOR_LEAF_PREFAB, "default door visual changed")
	room.room_type = "FACILITY"
	check(room._door_panel_visual("") == room.BASE99_DOOR_LIFT_PREFAB, "default facility lift changed")
	room.free()

func _verify_indoor_envelope(level: Node3D) -> void:
	var envelope := level.get_node_or_null("IndoorLightEnvelope")
	check(envelope != null, "indoor light envelope missing")
	if envelope == null:
		return
	var state: Dictionary = envelope.call("get_snapshot")
	check(state["built"] and state["blockers"] == 5, "indoor ceiling and four walls not ready")
	var rooms: Array = level.get("_rooms")
	check(state["room_count"] == rooms.size() and state["room_bounces"] == rooms.size(), "indoor coverage / bounce count mismatch")
	var bounds: AABB = state["bounds"]
	for room in rooms:
		var dimensions: Vector2 = room.call("get_dimensions")
		var footprint: AABB = envelope.global_transform.affine_inverse() * room.global_transform * AABB(Vector3(-dimensions.x / 2, 0, -dimensions.y / 2), Vector3(dimensions.x, 0.01, dimensions.y))
		check(bounds.encloses(footprint), "indoor envelope misses room " + str(room.get("room_id")))
		check(room.get_node_or_null("IndoorEnvelopeBounce") != null, "room has no indoor bounce")
	for blocker in envelope.get_children():
		check(blocker is MeshInstance3D and blocker.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "indoor blocker hides gameplay camera")
		check(blocker.layers & GameDesignConfig.SHADOW_MASK_WORLD_AND_PLAYER != 0, "indoor blocker cannot cast sun shadow")
	check(envelope.find_children("*", "CollisionObject3D", true, false).is_empty(), "visual envelope added gameplay collision")

func _fixture(original: Node3D, procedural: bool) -> void:
	var directory := OS.get_cmdline_user_args()[0].path_join("expedition_03")
	DirAccess.make_dir_recursive_absolute(directory)
	var base := directory.path_join("f00_fixture.tscn")
	var desc := ART.describe(original)
	var path := ART.art_path(base, desc)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var fixture_scene := load(ART.matching_path(original, str(original.get("static_layout_scene_path")))) as PackedScene
	var source := fixture_scene.instantiate() as Node3D
	var group := source.get_node("ArtComponents")
	var changed := false
	for child in group.get_children():
		if child is Node3D and str(child.name).begins_with("Furn_") and not changed:
			child.position += Vector3(0.25, 0, 0.5)
			child.rotation.y += 0.1
			child.scale *= Vector3(1.05, 1, 0.95)
			changed = true
	var marker := Marker3D.new()
	marker.name = "Furn_AuthorCustom"
	group.add_child(marker)
	marker.owner = source
	var light := OmniLight3D.new()
	light.name = "AuthorLight"
	light.position = Vector3(2, 2, 1)
	source.add_child(light)
	light.owner = source
	for empty in [false, true]:
		if empty:
			for child in group.get_children():
				if str(child.name).begins_with("Furn_"):
					child.free()
		var wanted := snapshot(source)
		var packed := PackedScene.new()
		check(packed.pack(source) == OK and ResourceSaver.save(packed, path) == OK, "fixture save failed")
		for retry in 2:
			var room = load("res://src/world3d/DungeonRoom3D.gd").new()
			room.configure({"room_id":original.get("room_id"), "room_type":original.get("room_type"), "size_class":original.get("size_class"), "custom_dimensions":original.call("get_dimensions"), "tower_module_shell":false, "procedural_shell":procedural, "art_layer_keep_structure":true, "static_layout_scene_path":base, "connection_ports":original.get("connection_ports"), "theme":original.get("theme"), "safe_room_corner_l":original.get("safe_room_corner_l"), "doors":original.get("doors"), "door_targets":original.get("door_targets")})
			root.add_child(room)
			room.ensure_shell_built()
			var loaded := art_root(room)
			check(loaded != null and snapshot(loaded) == wanted, "saved edits/empty layout lost procedural=%s empty=%s retry=%d" % [procedural, empty, retry])
			room.free()
			await process_frame
	source.free()
	DirAccess.remove_absolute(path)

func _door_clearance(level: Node3D) -> void:
	var excluded: Array[RID] = []
	for value in level.find_children("*", "CollisionObject3D", true, false):
		var body := value as CollisionObject3D
		var parent: Node = body
		while parent != null and parent != level:
			var script := parent.get_script() as Script
			if script != null and script.resource_path == "res://src/world3d/RoomDoor3D.gd":
				excluded.append(body.get_rid())
				break
			parent = parent.get_parent()
	var space := level.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.33
	capsule.height = 1.2
	for room in level.get("_rooms"):
		for port in room.get("connection_ports"):
			if str(port.get("target_room_id", "")).is_empty():
				continue
			var p: Array = port.get("position_m", [])
			var n: Array = port.get("outward", [])
			if p.size() != 2 or n.size() != 2:
				continue
			var normal := Vector3(float(n[0]), 0, float(n[1]))
			var tangent := Vector3(-normal.z, 0, normal.x)
			var approach := PhysicsShapeQueryParameters3D.new()
			approach.shape = capsule
			approach.transform = Transform3D(Basis.IDENTITY, room.global_position + Vector3(float(p[0]), 0.75, float(p[1])) - normal * 2.2)
			approach.motion = normal * 2.5
			approach.collision_mask = 1
			approach.exclude = excluded
			var motion := space.cast_motion(approach)
			check(motion[0] >= 0.999, "capsule cannot pass door approach %s %s" % [room.get("room_id"), port.get("side")])
			for offset in [-0.65, 0.0, 0.65]:
				var gate: Vector3 = room.global_position + Vector3(float(p[0]), 0.8, float(p[1])) + tangent * offset
				var query := PhysicsRayQueryParameters3D.create(gate - normal * 2.6, gate + normal * 0.1, 1, excluded)
				var hit := space.intersect_ray(query)
				door_shapes += 1
				check(hit.is_empty(), "door approach blocked %s %s: %s" % [room.get("room_id"), port.get("side"), hit.get("collider", "")])
