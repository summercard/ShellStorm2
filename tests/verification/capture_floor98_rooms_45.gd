extends Node
## Screenshot-only harness. Does not save or modify production scenes.
## Runtime geometry, orthographic camera pitched down exactly 45 degrees.
## Foreground south/east walls are hidden in this process only for a cutaway view.
const OUTPUT_DIR := "res://outputs/floor98_rooms_45_20261008"
const SHOTS: Array = [
	["floor_01_entry", "01_lobby_45.png"],
	["floor_01_hub", "02_corridor_45.png"],
	["floor_01_main_02", "03_meeting_room_45.png"],
	["floor_01_exit", "04_master_office_45.png"],
]
var failures: Array[String] = []

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Screenshots require a real renderer")
		get_tree().quit(1)
		return
	get_window().size = Vector2i(1920, 1440)
	get_viewport().scaling_3d_scale = 1.0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var packed := load("res://scenes/TowerDescent3D.tscn") as PackedScene
	var tower := packed.instantiate() as TowerDescent3D
	tower.test_mode = true
	tower.run_seed_override = 990098
	add_child(tower)
	await _settle()
	if not tower.generate_through_floor_for_test(98):
		get_tree().quit(1)
		return
	await _settle()
	var rooms: Dictionary = tower.get("_room_by_id")
	for shot in SHOTS:
		var room := rooms.get(str(shot[0])) as DungeonRoom3D
		tower.player.global_position = room.global_position + Vector3(0, 0.05, 0)
		tower.force_enter_room_for_test(room.room_id)
		room.set_stream_state(DungeonRoom3D.STREAM_ACTIVE)
		room.ensure_detail_built()
		room.apply_runtime_detail_state({"room_light_on": true})
		await _settle()
	tower.process_mode = Node.PROCESS_MODE_DISABLED
	for n in tower.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	tower.player.visible = false
	var env_node := tower.get_node("WorldEnvironment") as WorldEnvironment
	var env := env_node.environment.duplicate() as Environment
	env.fog_enabled = false
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.11, 0.14, 0.18)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.86, 1.0)
	env.ambient_light_energy = 0.6
	env_node.environment = env
	var camera := Camera3D.new()
	camera.name = "CaptureCamera45"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.05
	camera.far = 500.0
	add_child(camera)
	camera.make_current()
	# Hide unrelated world branches, preserving real room ancestors.
	for n in tower.find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).visible = false
	var records: Array = []
	for shot in SHOTS:
		var room := rooms.get(str(shot[0])) as DungeonRoom3D
		room.visible = true
		var dims := room.get_dimensions()
		var center := room.global_position
		var half := dims * 0.5
		var visible_geometry: Array[GeometryInstance3D] = []
		# Include shared boundary pieces owned by a neighbour, but no neighbour interior.
		for owner_shot in SHOTS:
			var owner := rooms.get(str(owner_shot[0])) as DungeonRoom3D
			owner.visible = true
			for n in owner.find_children("*", "GeometryInstance3D", true, false):
				var g := n as GeometryInstance3D
				var piece: Node = g
				while piece != owner and not piece.has_meta("tower_wall_direction") and not piece.has_meta("tower_wall_corner"):
					piece = piece.get_parent()
				var included := owner == room
				if piece != owner and piece is Node3D:
					var p := (piece as Node3D).global_position - center
					included = absf(p.x) <= half.x + 0.4 and absf(p.z) <= half.y + 0.4
					var side := str(piece.get_meta("tower_wall_direction", ""))
					if side in ["south", "east"] or p.x >= half.x - 0.4 or p.z >= half.y - 0.4:
						included = false
				if included:
					g.visible = true
					visible_geometry.append(g)
		for l in room.find_children("*", "WastelandLight3D", true, false):
			(l as WastelandLight3D).set_light_enabled(true)
		var box := _bounds(visible_geometry)
		var aim := box.get_center()
		# Horizontal direction south-east; y equals horizontal length => 45 degree pitch.
		var horizontal := Vector3(0.35, 0, 1).normalized()
		camera.global_position = aim + (horizontal + Vector3.UP) * 100.0
		camera.look_at(aim, Vector3.UP)
		var min_uv := Vector2(INF, INF)
		var max_uv := Vector2(-INF, -INF)
		for i in range(8):
			var local := camera.to_local(box.get_endpoint(i))
			min_uv = min_uv.min(Vector2(local.x, local.y))
			max_uv = max_uv.max(Vector2(local.x, local.y))
		camera.size = maxf(max_uv.y - min_uv.y, (max_uv.x - min_uv.x) / (1920.0 / 1440.0)) * 1.22
		await _settle()
		for i in range(8):
			var screen := camera.unproject_position(box.get_endpoint(i)) / Vector2(get_viewport().get_visible_rect().size)
			if screen.x < 0.04 or screen.x > 0.96 or screen.y < 0.04 or screen.y > 0.96:
				failures.append("Framing failed: " + room.room_id + str(screen))
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var buckets: Dictionary = {}
		for y in range(0, image.get_height(), 12):
			for x in range(0, image.get_width(), 12):
				var c := image.get_pixel(x, y)
				buckets[int((c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722) * 31)] = true
		if buckets.size() < 8:
			failures.append("Blank frame: " + room.room_id)
		var path := OUTPUT_DIR + "/" + str(shot[1])
		if image.save_png(path) != OK:
			failures.append("Save failed: " + path)
		var pitch := rad_to_deg(asin(absf((camera.global_position - aim).normalized().y)))
		records.append({"room_id": room.room_id, "png": path, "dimensions_m": str(dims), "pitch_degrees": pitch, "camera_position": str(camera.global_position), "visible_geometry": visible_geometry.size(), "luma_buckets": buckets.size(), "capture_only": "south/east foreground cutaway, HUD/player hidden, lights enabled, fog disabled, ambient fill"})
		print("CAPTURE ", room.room_id, " angle=", pitch, " size=", image.get_size(), " buckets=", buckets.size())
		for g in visible_geometry:
			g.visible = false
	var report := FileAccess.open(OUTPUT_DIR + "/capture_metadata.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"shots": records, "failures": failures}, "\t"))
	for failure in failures:
		push_error(failure)
	print("FLOOR98_CAPTURE_45_DONE images=4 failures=", failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

func _bounds(geometry: Array[GeometryInstance3D]) -> AABB:
	var result := AABB()
	var found := false
	for g in geometry:
		var aabb := g.get_aabb()
		for i in range(8):
			var p := g.global_transform * aabb.get_endpoint(i)
			if not found:
				result = AABB(p, Vector3.ZERO)
				found = true
			else:
				result = result.expand(p)
	return result

func _settle() -> void:
	for i in range(12):
		await get_tree().process_frame
		await get_tree().physics_frame
	await get_tree().create_timer(0.5).timeout
